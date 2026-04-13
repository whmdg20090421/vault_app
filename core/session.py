"""
core/session.py — VaultApp V5 会话与密钥保护模块

设计规范（V5定稿）：
  · 密码时限计时（使用 time.monotonic 防篡改）
  · Android Keystore 三级降级保护（Pyjnius 跨语言调用）
    - 第一级：硬件 TEE/StrongBox 保护
    - 第二级：软件 Keystore 保护
    - 第三级：不可用（禁用“记住密码”）
  · 主密钥内存安全：使用 bytearray，支持快速清零
"""

import time
import json
import os
from typing import Optional, Tuple
import struct as _struct

# 尝试导入 pyjnius (如果运行在非 Android 环境，自动降级到第三级)
try:
    from jnius import autoclass
    HAS_PYJNIUS = True
except ImportError:
    HAS_PYJNIUS = False

# ═══════════════════════════════════════════════════════════════════════════════
# 常量与配置
# ═══════════════════════════════════════════════════════════════════════════════

KEYSTORE_ALIAS = "vaultapp_master_key_wrapper_v1"
PROTECTION_LEVEL_HARDWARE = 1
PROTECTION_LEVEL_SOFTWARE = 2
PROTECTION_LEVEL_UNAVAILABLE = 3

class SessionManager:
    def __init__(self, cache_dir: str):
        """
        Args:
            cache_dir: 应用的内部缓存目录，用于存放加密后的主密钥Blob（如果不清零的话）
        """
        self.cache_dir = cache_dir
        self.blob_path = os.path.join(self.cache_dir, "session_blob.enc")
        
        # 内存状态
        self._active_key: Optional[bytearray] = None
        self._expire_time: float = 0.0
        
        # 检查设备 Keystore 支持层级
        self.protection_level = self._evaluate_protection_level()

    # ═════════════════════════════════════════════════════════════════════════
    # 核心会话生命周期
    # ═════════════════════════════════════════════════════════════════════════

    def activate_session(self, master_key: bytearray, duration_minutes: float):
        """
        激活会话，将主密钥放入内存，并设定过期时间。
        如果 duration_minutes > 0 且设备支持 Keystore，则加密密钥并保存到本地。
        """
        self._active_key = bytearray(master_key)
        
        if duration_minutes <= 0:
            self._expire_time = 0.0
            self._safe_remove_blob()
            return

        # 计算过期时间 (monotonic 免疫系统时间修改)
        self._expire_time = time.monotonic() + (duration_minutes * 60)
        
        # 持久化加密保存（仅当支持 Keystore 时）
        if self.protection_level != PROTECTION_LEVEL_UNAVAILABLE:
            try:
                expire_unix = time.time() + (duration_minutes * 60)
                # 将 expire unix 时间戳（8字节 double）拼在密钥前面一起加密
                payload = _struct.pack('<d', expire_unix) + bytes(master_key)
                encrypted_blob = self._encrypt_with_keystore(payload)
                with open(self.blob_path, "wb") as f:
                    f.write(encrypted_blob)
            except Exception as e:
                # 写入失败不影响内存会话，但无法"记住密码"
                self._safe_remove_blob()

    def get_master_key(self) -> Optional[bytearray]:
        """
        获取当前活动的主密钥。如果超时或不存在，尝试从 Keystore 恢复。
        """
        current_time = time.monotonic()

        # 1. 检查内存中是否还有效
        if self._active_key is not None:
            if self._expire_time > 0 and current_time > self._expire_time:
                self.clear_session()
                return None
            return self._active_key

        # 2. 内存没有，但时限未过（可能是 App 重启或被系统回收）
        # 这里为了安全，只有在持久化 Blob 存在时才尝试恢复
        if not os.path.exists(self.blob_path):
            return None

        # 3. 尝试从 Keystore 解密恢复
        if self.protection_level != PROTECTION_LEVEL_UNAVAILABLE:
            try:
                with open(self.blob_path, "rb") as f:
                    encrypted_blob = f.read()
                
                decrypted_bytes = self._decrypt_with_keystore(encrypted_blob)
                # Blob 格式：前8字节为过期的 wall-clock unix 时间戳（float，小端）
                # 其余字节为主密钥
                expire_unix = _struct.unpack_from('<d', decrypted_bytes, 0)[0]
                raw_key = decrypted_bytes[8:]
                
                # 检查 wall-clock 时间是否仍在有效期内
                if time.time() > expire_unix:
                    self.clear_session()
                    return None
                
                self._active_key = bytearray(raw_key)
                # 将剩余有效时间换算回 monotonic 轴
                remaining_sec = expire_unix - time.time()
                self._expire_time = time.monotonic() + remaining_sec
                return self._active_key
            except Exception:
                # 解密失败（密钥损坏或 Keystore 重置）
                self.clear_session()
                return None

        return None

    def clear_session(self):
        """
        彻底清除会话（触发：点击立即清除、超时、解密失败）
        """
        if self._active_key is not None:
            # 原地覆盖清零 bytearray 防内存读取
            for i in range(len(self._active_key)):
                self._active_key[i] = 0
            self._active_key = None
            
        self._expire_time = 0.0
        self._safe_remove_blob()
        self._delete_keystore_entry()

    def is_active(self) -> bool:
        """检查会话当前是否可用且未超时"""
        return self.get_master_key() is not None

    def _safe_remove_blob(self):
        try:
            os.remove(self.blob_path)
        except OSError:
            pass

    # ═════════════════════════════════════════════════════════════════════════
    # Android Keystore 三级降级判定与加密核心 (Pyjnius)
    # ═════════════════════════════════════════════════════════════════════════

    def _evaluate_protection_level(self) -> int:
        """
        评估当前设备的 Keystore 保护层级（应用启动时调用一次）
        """
        if not HAS_PYJNIUS:
            return PROTECTION_LEVEL_UNAVAILABLE

        try:
            KeyStore = autoclass('java.security.KeyStore')
            KeyProperties = autoclass('android.security.keystore.KeyProperties')
            KeyGenParameterSpecBuilder = autoclass('android.security.keystore.KeyGenParameterSpec$Builder')
            KeyGenerator = autoclass('javax.crypto.KeyGenerator')
            SecretKeyFactory = autoclass('javax.crypto.SecretKeyFactory')
            KeyInfo = autoclass('android.security.keystore.KeyInfo')

            # 确保 Keystore 实例可用
            ks = KeyStore.getInstance("AndroidKeyStore")
            ks.load(None)

            # 尝试生成一个测试密钥以检查硬件支持
            test_alias = "vaultapp_hardware_test"
            if ks.containsAlias(test_alias):
                ks.deleteEntry(test_alias)

            purposes = KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT
            builder = KeyGenParameterSpecBuilder(test_alias, purposes)
            builder.setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            builder.setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            builder.setKeySize(256)
            
            kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            kg.init(builder.build())
            secret_key = kg.generateKey()

            # 检查是否在 TEE (Trusted Execution Environment) 内
            factory = SecretKeyFactory.getInstance(secret_key.getAlgorithm(), "AndroidKeyStore")
            key_info = factory.getKeySpec(secret_key, KeyInfo)
            
            is_hardware = key_info.isInsideSecureHardware()
            ks.deleteEntry(test_alias) # 测试完毕删除

            if is_hardware:
                return PROTECTION_LEVEL_HARDWARE
            else:
                return PROTECTION_LEVEL_SOFTWARE

        except Exception as e:
            print(f"Keystore 评估失败，降级为不可用: {e}")
            return PROTECTION_LEVEL_UNAVAILABLE

    def _get_or_create_key(self):
        """获取或在 Keystore 中生成包装用的 AES-GCM 密钥"""
        KeyStore = autoclass('java.security.KeyStore')
        ks = KeyStore.getInstance("AndroidKeyStore")
        ks.load(None)

        if not ks.containsAlias(KEYSTORE_ALIAS):
            KeyProperties = autoclass('android.security.keystore.KeyProperties')
            KeyGenParameterSpecBuilder = autoclass('android.security.keystore.KeyGenParameterSpec$Builder')
            KeyGenerator = autoclass('javax.crypto.KeyGenerator')

            purposes = KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT
            builder = KeyGenParameterSpecBuilder(KEYSTORE_ALIAS, purposes)
            builder.setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            builder.setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            builder.setKeySize(256)     # 明确要求 AES-256，不依赖设备默认值
            
            kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            kg.init(builder.build())
            kg.generateKey()

        return ks.getKey(KEYSTORE_ALIAS, None)

    def _encrypt_with_keystore(self, plaintext: bytes) -> bytes:
        """使用 Android Keystore 加密主密钥"""
        Cipher = autoclass('javax.crypto.Cipher')
        secret_key = self._get_or_create_key()
        
        cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secret_key)
        
        iv = cipher.getIV()
        # JNI 需要传递 byte[]，Pyjnius 可以自动转换 python 的 bytes
        ciphertext = cipher.doFinal(plaintext)
        
        # 组装返回格式：[IV长度 1字节][IV数据][密文数据]
        iv_len = len(iv)
        return bytes([iv_len]) + bytes(iv) + bytes(ciphertext)

    def _decrypt_with_keystore(self, encrypted_blob: bytes) -> bytes:
        """使用 Android Keystore 解密主密钥"""
        Cipher = autoclass('javax.crypto.Cipher')
        GCMParameterSpec = autoclass('javax.crypto.spec.GCMParameterSpec')
        
        iv_len = encrypted_blob[0]
        iv = encrypted_blob[1:1+iv_len]
        ciphertext = encrypted_blob[1+iv_len:]

        secret_key = self._get_or_create_key()
        cipher = Cipher.getInstance("AES/GCM/NoPadding")
        
        # 128 位 = 16 字节的 GCM Authentication Tag
        spec = GCMParameterSpec(128, iv) 
        cipher.init(Cipher.DECRYPT_MODE, secret_key, spec)
        
        return bytes(cipher.doFinal(ciphertext))

    def _delete_keystore_entry(self):
        """彻底从系统中抹除此 Vault 的自动解锁能力"""
        if self.protection_level == PROTECTION_LEVEL_UNAVAILABLE:
            return
        try:
            KeyStore = autoclass('java.security.KeyStore')
            ks = KeyStore.getInstance("AndroidKeyStore")
            ks.load(None)
            if ks.containsAlias(KEYSTORE_ALIAS):
                ks.deleteEntry(KEYSTORE_ALIAS)
        except Exception:
            pass
