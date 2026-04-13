"""
core/sync_engine.py — VaultApp V5 增量同步引擎

设计规范（V5定稿）：
  · 快速预检（7.3节）：size + mtime 对比，一致则跳过，不读文件内容
  · 变更确认：若 size 相同但 mtime 不同，执行 HMAC-SHA256 确认
  · 上传流水线（9.1节）：分块加密至 cache/webdav_tmp/ → 入队 UPLOADING → 上传 → DONE/FAILED
  · 检查点机制（9.2节）：每完成20个文件或60秒触发 manifest 备份
  · 并发与生命周期：支持多线程并发、暂停、恢复、彻底停止
"""

import os
import time
import hashlib
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Optional, Callable

from core import crypto
from core.manifest import ManifestDB
from core.webdav import WebDAVManager

class SyncEngine:
    def __init__(
        self,
        vault_root: str,
        vault_id: str,
        manifest: ManifestDB,
        webdav: WebDAVManager,
        master_key: bytearray,
        vault_meta: dict,           # 新增：传入已解析的 .vault_meta 字典
        max_workers: int = 4,
        cache_dir: str = "cache"
    ):
        self.vault_root = vault_root
        self.vault_id = vault_id
        self.manifest = manifest
        self.webdav = webdav
        self.max_workers = max_workers
        self.tmp_dir = os.path.join(cache_dir, "webdav_tmp")
        os.makedirs(self.tmp_dir, exist_ok=True)
        
        # 派生专用的子密钥
        self.content_key = crypto.derive_subkey(bytes(master_key), "content_key")
        self.manifest_key = crypto.derive_subkey(bytes(master_key), "manifest_key")
        self.filename_siv_key = crypto.derive_subkey(bytes(master_key), "filename_siv_key", length=64)
        
        # 从 vault_meta 读取算法配置，不硬编码
        cipher_str = vault_meta.get("cipher", "XChaCha20-Poly1305")
        self.algo = crypto.ALGO_XCHACHA20 if "XChaCha20" in cipher_str else crypto.ALGO_AES256GCM
        
        # 线程与状态控制
        self._pause_event = threading.Event()
        self._pause_event.set()  # 初始为未暂停 (set 状态表示允许通行)
        self._stop_event = threading.Event()
        
        # 统计回调
        self.on_progress: Optional[Callable[[int, int], None]] = None
        self.processed_count = 0
        self.last_checkpoint_time = time.time()
        self._lock = threading.Lock()

    # ═════════════════════════════════════════════════════════════════════════
    # 辅助方法：计算文件 SHA256 (用于变更确认)
    # ═════════════════════════════════════════════════════════════════════════

    def _hash_file(self, file_path: str) -> str:
        """纯读取计算 SHA256"""
        sha256 = hashlib.sha256()
        with open(file_path, 'rb') as f:
            while chunk := f.read(crypto.CHUNK_SIZE):
                sha256.update(chunk)
        return sha256.hexdigest()

    # ═════════════════════════════════════════════════════════════════════════
    # 核心流水线：处理单个文件 (在线程池中并发执行)
    # ═════════════════════════════════════════════════════════════════════════

    def _process_file(self, rel_path: str, local_path: str):
        """执行 9.1 节定义的上传流水线"""
        
        # 检查是否暂停或停止
        self._pause_event.wait()
        if self._stop_event.is_set():
            return

        # 1. 获取本地文件状态
        try:
            stat = os.stat(local_path)
            current_size = stat.st_size
            current_mtime = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(stat.st_mtime))
        except OSError:
            return  # 文件可能已被删除，跳过

        path_hash = hashlib.sha256(rel_path.encode('utf-8')).hexdigest()
        db_record = self.manifest.get_file_meta(path_hash)

        # 2. 快速预检机制 (7.3 节)
        if db_record and db_record['status'] == 'DONE':
            if db_record['file_size'] == current_size and db_record['last_modified'] == current_mtime:
                # 完全一致，跳过（不读文件内容）
                return
            elif db_record['file_size'] == current_size:
                # 大小没变，可能只是属性被修改。执行 HMAC 校验确认是否真的变了
                plain_sha256 = self._hash_file(local_path)
                plain_hmac = crypto.compute_plain_hmac(plain_sha256, self.manifest_key)
                if plain_hmac == db_record['plain_hash']:
                    # 内容没变，仅更新 mtime
                    self.manifest.enqueue_write({
                        'path_hash': path_hash,
                        'last_modified': current_mtime
                    })
                    return

        # 3. 确认需要上传，开始加密至临时文件夹
        enc_filename = crypto.encrypt_filename(rel_path, self.filename_siv_key)
        tmp_enc_path = os.path.join(self.tmp_dir, f"{path_hash}.enc")
        remote_path = f"/vaults/{self.vault_id}/{enc_filename}"

        try:
            # 记录状态为 UPLOADING
            self.manifest.enqueue_write({
                'path_hash': path_hash,
                'rel_path': rel_path,
                'enc_filename': enc_filename,
                'status': 'UPLOADING'
            })

            # 分块流式加密 (最大内存 <= 4MB)
            plain_sha256 = crypto.encrypt_file(
                src_path=local_path,
                dst_path=tmp_enc_path,
                content_key=self.content_key,
                algo=self.algo          # 使用从 vault_meta 读取的算法
            )
            plain_hmac = crypto.compute_plain_hmac(plain_sha256, self.manifest_key)

            # 检查是否要求停止（加密大文件耗时，期间可能被中断）
            if self._stop_event.is_set():
                crypto._safe_remove(tmp_enc_path)
                return

            # 4. WebDAV 上传
            self.webdav.upload_file(tmp_enc_path, remote_path)

            # 5. 上传成功，写入 DONE 状态
            self.manifest.enqueue_write({
                'path_hash': path_hash,
                'plain_hash': plain_hmac,
                'file_size': current_size,
                'last_modified': current_mtime,
                'status': 'DONE',
                'retry_count': 0,
                'fail_reason': None
            })

        except Exception as e:
            # 上传失败处理
            retry_count = (db_record['retry_count'] if db_record else 0) + 1
            status = 'PENDING' if retry_count <= 3 else 'FAILED'
            self.manifest.enqueue_write({
                'path_hash': path_hash,
                'status': status,
                'retry_count': retry_count,
                'fail_reason': str(e)[:200]  # 截断错误信息防止过长
            })
        finally:
            # 6. 清理临时密文文件
            crypto._safe_remove(tmp_enc_path)
            self._trigger_checkpoint()

    # ═════════════════════════════════════════════════════════════════════════
    # 检查点机制 (9.2 节)
    # ═════════════════════════════════════════════════════════════════════════

    def _trigger_checkpoint(self):
        """每完成 20 个文件或超过 60 秒触发一次备份"""
        with self._lock:
            self.processed_count += 1
            current_time = time.time()
            if self.processed_count >= 20 or (current_time - self.last_checkpoint_time) >= 60:
                self.processed_count = 0
                self.last_checkpoint_time = current_time
                self.manifest.backup()
                # TODO: 可以在这里加上传加密日志的逻辑 (logger.py)

    # ═════════════════════════════════════════════════════════════════════════
    # 引擎生命周期控制
    # ═════════════════════════════════════════════════════════════════════════

    def start_sync(self):
        """启动同步（使用线程池遍历本地文件）"""
        self._stop_event.clear()
        self._pause_event.set()
        
        # 收集需要扫描的文件列表
        tasks = []
        for root, dirs, files in os.walk(self.vault_root):
            # 就地修改 dirs 防止 os.walk 下探到缓存和缩略图子目录
            dirs[:] = [d for d in dirs if d not in ("cache", ".thumbnails", "benchmark")]

            for file in files:
                if file == ".vault_meta" or file.endswith(".bak"):
                    continue
                local_path = os.path.join(root, file)
                rel_path = os.path.relpath(local_path, self.vault_root)
                tasks.append((rel_path, local_path))

        # 使用线程池并发执行
        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            futures = []
            for rel_path, local_path in tasks:
                if self._stop_event.is_set():
                    break
                futures.append(executor.submit(self._process_file, rel_path, local_path))

            # 等待所有任务完成
            for future in as_completed(futures):
                try:
                    future.result()
                except Exception as e:
                    print(f"工作线程发生未捕获异常: {e}")

        # 最终执行一次检查点备份
        self.manifest.backup()

    def pause(self):
        """暂停同步 (利用 Event 阻塞所有工作线程的 _process_file 入口)"""
        self._pause_event.clear()

    def resume(self):
        """恢复同步"""
        self._pause_event.set()

    def stop(self):
        """彻底停止同步"""
        self._stop_event.set()
        self._pause_event.set()  # 放行被 pause 阻塞的线程，让它们看到 stop_event 并退出
