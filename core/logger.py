"""
core/logger.py — VaultApp V5 内存级加密日志模块

设计规范（V5定稿）：
  · 日志密钥：HKDF(主密钥, info="log_key")
  · 存储：动态追加的 AES-256-GCM 密文块
  · 安全限制：仅记录指定字段（操作类型、时间、路径、大小、HMAC、错误代码），不记录文件内容与完整堆栈
  · App内查看：全内存解密，明文不落地
"""

import os
import json
import struct
import threading
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any

from core import crypto

class EncryptedLogger:
    def __init__(self, vault_id: str, master_key: bytearray, cache_dir: str = "cache"):
        """
        初始化加密日志记录器
        
        Args:
            vault_id: Vault 的唯一标识
            master_key: Session 中的主密钥
            cache_dir: 内部缓存目录
        """
        self.vault_id = vault_id
        
        # 严格遵守规范：派生专用的 log_key，互不影响
        self.log_key = crypto.derive_subkey(bytes(master_key), "log_key")
        
        # 日志存储路径
        self.log_dir = os.path.join(cache_dir, "log_tmp")
        os.makedirs(self.log_dir, exist_ok=True)
        self.log_file = os.path.join(self.log_dir, f"vault_{self.vault_id}.log.enc")
        
        # 线程安全锁，防止多线程 SyncEngine 竞争写入
        self._write_lock = threading.Lock()

    # ═════════════════════════════════════════════════════════════════════════
    # 核心接口：写入日志
    # ═════════════════════════════════════════════════════════════════════════

    def log_event(self, 
                  action: str, 
                  local_path: str, 
                  remote_path: str, 
                  size: int = 0, 
                  hmac_hash: str = "", 
                  error_code: str = ""):
        """
        记录一条操作日志（内存加密后追加写入）。
        
        Args:
            action: 操作类型，例如 "UPLOAD_SUCCESS", "SKIP", "ERROR"
            local_path: 本地相对路径
            remote_path: 云端相对路径
            size: 文件大小（字节）
            hmac_hash: 文件的 plain_hash (HMAC-SHA256)
            error_code: 错误简码（勿传入带有文件内容的堆栈信息）
        """
        # 1. 组装规范限定的字段
        log_entry = {
            "timestamp": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
            "action": action,
            "local_path": local_path,
            "remote_path": remote_path,
            "size": size,
            "hmac": hmac_hash,
            "error_code": str(error_code)[:100]  # 强制截断，防止泄露过长的异常堆栈
        }
        
        # 2. 序列化为 bytes
        plain_bytes = json.dumps(log_entry, separators=(',', ':')).encode('utf-8')
        
        # 3. 在内存中加密（使用 AES-256-GCM 小块加密模式）
        enc_bytes = crypto.encrypt_bytes(plain_bytes, self.log_key, crypto.ALGO_AES256GCM)
        
        # 4. 打包长度前缀（4字节无符号整数，小端序），方便日后逐条读取
        length_prefix = struct.pack("<I", len(enc_bytes))
        
        # 5. 追加写入文件
        with self._write_lock:
            with open(self.log_file, "ab") as f:
                f.write(length_prefix)
                f.write(enc_bytes)

    # ═════════════════════════════════════════════════════════════════════════
    # 核心接口：读取日志 (供设置页查看)
    # ═════════════════════════════════════════════════════════════════════════

    def read_all_logs(self) -> List[Dict[str, Any]]:
        """
        读取并解密所有日志内容（内存操作，明文不落地）。
        
        Returns:
            包含所有日志字典的列表
        """
        if not os.path.exists(self.log_file):
            return []

        logs = []
        with self._write_lock:
            with open(self.log_file, "rb") as f:
                while True:
                    # 1. 读取 4 字节长度前缀
                    length_bytes = f.read(4)
                    if not length_bytes or len(length_bytes) < 4:
                        break  # 文件结束
                        
                    enc_len = struct.unpack("<I", length_bytes)[0]
                    
                    # 2. 读取对应长度的密文块
                    enc_data = f.read(enc_len)
                    if len(enc_data) != enc_len:
                        break  # 文件损坏或截断
                        
                    # 3. 内存解密
                    try:
                        plain_bytes = crypto.decrypt_bytes(enc_data, self.log_key)
                        log_entry = json.loads(plain_bytes.decode('utf-8'))
                        logs.append(log_entry)
                    except crypto.TamperedError:
                        # 单条日志损坏（可能是掉电导致），追加一条提示并继续尝试解析后面的
                        logs.append({"action": "LOG_CORRUPT", "error_code": "日志块校验失败"})
                        continue
                    except Exception:
                        continue
        
        return logs

    # ═════════════════════════════════════════════════════════════════════════
    # 日志管理
    # ═════════════════════════════════════════════════════════════════════════

    def clear_logs(self):
        """清空日志文件"""
        with self._write_lock:
            crypto._safe_remove(self.log_file)

    def get_log_file_path(self) -> str:
        """获取日志密文文件路径（供 WebDAV 同步上传使用）"""
        return self.log_file
