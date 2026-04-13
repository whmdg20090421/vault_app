"""
core/vault.py — VaultApp V5 Vault 生命周期与配置管理模块

设计规范（V5定稿）：
  · 负责 .vault_meta 的读写与解析
  · params_mac 防篡改验证（轻量级 PBKDF2 绑定参数）
  · 串接 crypto.py (派生密钥) 和 session.py (存储会话)
  · 创建新 Vault / 导入明文向导的底层支撑
"""

import json
import os
import uuid
import base64
import hmac
import hashlib
from datetime import datetime, timezone
from typing import Dict, Any, Tuple, Optional

#  cryptography 依赖（用于轻量级 PBKDF2 和随机盐生成）
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.backends import default_backend

# 导入我们已经写好的底层模块
from core import crypto
from core.session import SessionManager


class VaultError(Exception):
    """Vault 操作相关的通用异常"""

class MetaTamperedError(VaultError):
    """.vault_meta 文件被篡改或损坏"""


class VaultManager:
    def __init__(self, session_manager: SessionManager):
        """
        Args:
            session_manager: 我们在 session.py 中创建的会话管理器实例
        """
        self.session = session_manager
        self.current_vault_dir: Optional[str] = None
        self.meta_path: Optional[str] = None
        self.vault_id: Optional[str] = None

    def set_vault_directory(self, root_dir: str):
        """
        设置当前操作的根目录（从 SAF 选择器获取）
        """
        self.current_vault_dir = root_dir
        self.meta_path = os.path.join(root_dir, ".vault_meta")

    def is_vault_exists(self) -> bool:
        """检查当前目录下是否已存在 Vault (即是否存在 .vault_meta)"""
        if not self.meta_path:
            raise VaultError("尚未设置 Vault 目录")
        return os.path.exists(self.meta_path)

    # ═════════════════════════════════════════════════════════════════════════
    # 防篡改 MAC 生成与验证 (设计文档 3.4 节)
    # ═════════════════════════════════════════════════════════════════════════

    def _generate_params_mac(self, password: bytes, meta_dict: Dict[str, Any]) -> str:
        """
        生成 params_mac 以防止降级攻击。
        使用 PBKDF2(iter=1) 进行极轻量计算，既不影响启动速度，又能与密码绑定。
        """
        # 提取需要保护的关键字段
        protected_data = {
            "vault_id": meta_dict["vault_id"],
            "cipher": meta_dict["cipher"],
            "kdf": meta_dict["kdf"],
            "kdf_params": meta_dict["kdf_params"]
        }
        
        # 将其转化为稳定的 JSON 字符串作为被签名的 msg
        msg = json.dumps(protected_data, sort_keys=True).encode('utf-8')
        
        # 提取盐值
        salt = base64.b64decode(meta_dict["kdf_params"]["salt"])
        
        # 轻量级密钥派生 (仅用于验证配置文件，不用于文件加密)
        kdf = PBKDF2HMAC(
            algorithm=hashes.SHA256(),
            length=32,
            salt=salt,
            iterations=1,
            backend=default_backend()
        )
        light_key = kdf.derive(password)
        
        # 计算 HMAC-SHA256
        h = hmac.new(light_key, msg, hashlib.sha256)
        return base64.b64encode(h.digest()).decode('utf-8')

    # ═════════════════════════════════════════════════════════════════════════
    # 核心生命周期：解锁与创建
    # ═════════════════════════════════════════════════════════════════════════

    def unlock_vault(self, password: str, remember_minutes: float = 0) -> bool:
        """
        解锁 Vault。
        流程：读 Meta -> 验证 params_mac -> 执行重度 KDF 派生主密钥 -> 存入 Session
        
        Args:
            password: 用户输入的密码
            remember_minutes: 记住密码的时长（分钟）
            
        Returns:
            bool: 解锁是否成功
        """
        if not self.is_vault_exists():
            raise VaultError("Vault 不存在，请先创建")

        pwd_bytes = password.encode('utf-8')

        # 1. 读取并解析 .vault_meta
        try:
            with open(self.meta_path, 'r', encoding='utf-8') as f:
                meta = json.load(f)
        except json.JSONDecodeError:
            raise MetaTamperedError("配置文件格式损坏，请使用修复模式")

        # 2. 验证 params_mac（防篡改验证，速度极快）
        expected_mac = self._generate_params_mac(pwd_bytes, meta)
        if not hmac.compare_digest(expected_mac, meta.get("params_mac", "")):
            # MAC 校验失败：密码错误 或 配置文件被恶意降级
            raise MetaTamperedError("Vault 配置验证失败（密码错误或文件被篡改）")

        self.vault_id = meta["vault_id"]

        # 3. 执行重度 KDF 派生主密钥（耗时操作，调用我们写的 crypto.py）
        # 这里还会二次校验 KDF 参数的安全阈值
        try:
            master_key_bytearray = crypto.derive_master_key_from_meta(pwd_bytes, meta)
        except crypto.ParamsTamperedError as e:
            raise MetaTamperedError(str(e))

        # 4. 激活会话（存入 session.py 进行保护）
        self.session.activate_session(master_key_bytearray, remember_minutes)
        
        # 安全清零临时主密钥（session.py 内部已经复制了一份）
        for i in range(len(master_key_bytearray)):
            master_key_bytearray[i] = 0
            
        return True

    def create_vault(self, 
                     password: str, 
                     cipher: str = "XChaCha20-Poly1305", 
                     kdf_type: str = "Argon2id",
                     kdf_params: Dict[str, int] = None,
                     filename_encryption: str = "full") -> str:
        """
        创建新的 Vault（写入 .vault_meta）。
        
        Args:
            password: 用户设置的密码
            cipher: 算法，默认 XChaCha20-Poly1305
            kdf_type: KDF 类型，默认 Argon2id
            kdf_params: 包含 memory_kb, iterations, parallelism 的字典
            filename_encryption: 文件名加密方式
        """
        if self.is_vault_exists():
            raise VaultError("该目录下已存在 Vault")

        # 采用安全默认参数（如果用户没有指定）
        if kdf_params is None:
            if kdf_type == "Argon2id":
                kdf_params = {"memory_kb": 32768, "iterations": 2, "parallelism": 2}
            else:
                kdf_params = {"n": 16384, "r": 8, "p": 1}

        # 生成 32 字节随机盐
        salt = os.urandom(32)
        kdf_params["salt"] = base64.b64encode(salt).decode('utf-8')

        # 构建基础 Meta 字典
        meta = {
            "vault_version": 1,     # 文件格式版本，与 App 版本无关
            "vault_id": str(uuid.uuid4()),
            "cipher": cipher,
            "kdf": kdf_type,
            "kdf_params": kdf_params,
            "filename_encryption": filename_encryption,
            "created_at": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        }

        # 生成防篡改 MAC 并加入字典
        meta["params_mac"] = self._generate_params_mac(password.encode('utf-8'), meta)

        # 写入文件
        os.makedirs(self.current_vault_dir, exist_ok=True)
        with open(self.meta_path, 'w', encoding='utf-8') as f:
            json.dump(meta, f, indent=2)

        self.vault_id = meta["vault_id"]
        return self.vault_id
