"""
core/benchmark.py — VaultApp V5 加密性能测试与设备档位预估模块

设计规范（V5定稿）：
  · 13.1 档位预估：极速 KDF 测试（<0.5s高端，0.5-1.5s中端，>1.5s低端）
  · 13.2 深度测试：生成 500MB 测试文件，流式分块加密，测试吞吐率并预估 10GB/50GB 耗时
  · 安全清理：finally 块强制删除庞大的测试文件
"""

import os
import time
from typing import Dict, Any, Tuple, Optional, Callable

from core import crypto

class BenchmarkError(Exception):
    pass

class BenchmarkManager:
    def __init__(self, cache_dir: str = "cache"):
        self.bench_dir = os.path.join(cache_dir, "benchmark")
        self.test_file_path = os.path.join(self.bench_dir, "benchmark_tmp.bin")
        self.test_enc_path = os.path.join(self.bench_dir, "benchmark_tmp.enc")
        
        # 启动时双重清理（防上次异常退出残留）
        self.cleanup_test_files()

    def cleanup_test_files(self):
        """无论发生什么，绝对不能让无用的 500MB 文件常驻占用用户空间"""
        if os.path.exists(self.bench_dir):
            for file in os.listdir(self.bench_dir):
                if file.startswith("benchmark_tmp"):
                    crypto._safe_remove(os.path.join(self.bench_dir, file))
        os.makedirs(self.bench_dir, exist_ok=True)

    # ═════════════════════════════════════════════════════════════════════════
    # 极速档位预估 (设计文档 13.1 节)
    # ═════════════════════════════════════════════════════════════════════════

    def estimate_device_tier(self) -> Tuple[str, str]:
        """
        极速测试设备 CPU 算力，用于向新手推荐合理的 KDF 安全档位。
        执行约 1 秒钟的最低限度 Argon2id 测试。
        
        Returns:
            (tier_name, 附加提示信息)
        """
        # 使用低于“低端标准”的极低参数，仅用于探底计时
        salt = os.urandom(32)
        pwd = b"benchmark_test_password"
        
        start_time = time.monotonic()
        
        try:
            # 8MB 内存, 1次迭代, 1线程（探底线）
            crypto.derive_key_argon2id(pwd, salt, memory_kb=8192, iterations=1, parallelism=1)
        except Exception as e:
            return "低端", f"测试失败，建议使用低端参数 ({e})"
            
        elapsed = time.monotonic() - start_time
        
        if elapsed < 0.5:
            return "高端", "您的设备性能强劲，推荐使用【高端】安全参数。"
        elif elapsed <= 1.5:
            return "中端", "您的设备性能良好，推荐使用【中端】安全参数。"
        else:
            return "低端", "⚠️ 热节流或算力受限，推荐使用【低端】参数。多次解锁后速度可能略有下降，属正常现象。"

    # ═════════════════════════════════════════════════════════════════════════
    # 深度综合性能测试 (设计文档 13.2 节)
    # ═════════════════════════════════════════════════════════════════════════

    def _generate_dummy_file(self, size_mb: int, progress_cb: Optional[Callable[[int], None]] = None):
        """快速生成指定大小的随机垃圾文件（用于模拟待加密文件）"""
        target_bytes = size_mb * 1024 * 1024
        chunk_size = 4 * 1024 * 1024 # 4MB 每次写入
        written = 0
        
        with open(self.test_file_path, "wb") as f:
            while written < target_bytes:
                # 不用全随机，urandom(4MB) 较慢，用少量随机+大块重复以保证磁盘IO速度测试不受生成速度拖累
                chunk = os.urandom(1024) * 4096 
                f.write(chunk)
                written += len(chunk)
                if progress_cb:
                    progress_cb(int((written / target_bytes) * 100))

    def run_full_benchmark(
        self,
        kdf_name: str,
        kdf_params: Dict[str, int],
        algo: int = crypto.ALGO_XCHACHA20,
        file_size_mb: int = 500,
        ui_callback: Optional[Callable[[str, float], None]] = None
    ) -> Dict[str, Any]:
        """
        运行完整链路测试：KDF 解锁时间 + 流式大文件加密吞吐量
        
        Args:
            kdf_name: "Argon2id" 或 "scrypt"
            kdf_params: 对应的参数字典
            algo: 测试的对称加密算法
            file_size_mb: 默认测试 500MB
            ui_callback: 供 UI 刷新进度的回调，如 (status_text, progress_percent)
        """
        results = {}
        salt = os.urandom(32)
        pwd = b"full_benchmark_password"
        
        try:
            # 阶段 1：准备测试文件
            if ui_callback:
                ui_callback("正在生成测试文件...", 0.0)
            self._generate_dummy_file(file_size_mb)
            
            # 阶段 2：KDF 派生密钥计时 (模拟解锁)
            if ui_callback:
                ui_callback(f"正在测试 {kdf_name} 解锁耗时...", 10.0)
                
            start_kdf = time.monotonic()
            if kdf_name == "Argon2id":
                master_key = crypto.derive_key_argon2id(
                    pwd, salt, 
                    kdf_params["memory_kb"], kdf_params["iterations"], kdf_params["parallelism"]
                )
            else:
                master_key = crypto.derive_key_scrypt(
                    pwd, salt, 
                    kdf_params["n"], kdf_params["r"], kdf_params["p"]
                )
            kdf_elapsed = time.monotonic() - start_kdf
            results["kdf_time"] = kdf_elapsed
            
            content_key = crypto.derive_subkey(master_key, "content_key")
            
            # 阶段 3：流式分块加密计时
            if ui_callback:
                ui_callback("正在测试 4MB 分块流式加密吞吐量...", 20.0)
                
            start_enc = time.monotonic()
            
            def enc_progress(done: int, total: int):
                if ui_callback:
                    # 进度区间 20% ~ 100%
                    pct = 20.0 + (done / total) * 80.0
                    ui_callback(f"加密中... ({done/1024/1024:.1f} MB)", pct)
                    
            crypto.encrypt_file(
                src_path=self.test_file_path,
                dst_path=self.test_enc_path,
                content_key=content_key,
                algo=algo,
                progress_cb=enc_progress
            )
            
            enc_elapsed = time.monotonic() - start_enc
            results["enc_time"] = enc_elapsed
            
            # 计算吞吐量与预估
            speed_mb_s = file_size_mb / enc_elapsed if enc_elapsed > 0 else 0
            results["speed_mb_s"] = speed_mb_s
            results["est_10gb"] = (10240 / speed_mb_s) / 60 if speed_mb_s > 0 else 0
            results["est_50gb"] = (51200 / speed_mb_s) / 60 if speed_mb_s > 0 else 0
            
            return results
            
        except Exception as e:
            raise BenchmarkError(f"测试过程中发生错误: {e}")
        finally:
            # 绝对不能留下几百 MB 的测试垃圾！
            if ui_callback:
                ui_callback("清理测试缓存...", 100.0)
            self.cleanup_test_files()
