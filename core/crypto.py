"""
core/crypto.py — VaultApp V5 加密核心模块

设计规范（V5定稿）：
  · 分块流式加密（4 MB/块），最大内存占用 ≤ 4 MB，与文件总大小无关
  · 支持算法：AES-256-GCM（默认）/ XChaCha20-Poly1305
  · KDF：Argon2id（默认）/ scrypt（PBKDF2 已永久移除）
  · 文件名加密：AES-256-SIV（确定性，64 字节密钥）
  · 防 Chunk 重排攻击：每块 chunk_index 作为 AEAD Additional Data
  · 防截断攻击：文件头记录 chunk_count，解密时严格核对
  · 防 manifest 反查：HMAC-SHA256(manifest_key, plain_sha256_hex)
  · 防 KDF 参数降级攻击：强制安全参数阈值白名单校验

依赖（requirements.txt 中版本锁定）：
  cryptography==42.0.8
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import os
import struct
from typing import Callable, Optional

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives import hmac as crypto_hmac
from cryptography.hazmat.primitives.ciphers.aead import AESGCM, AESSIV, XChaCha20Poly1305
from cryptography.hazmat.primitives.kdf.argon2 import Argon2id
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt


# ═══════════════════════════════════════════════════════════════════════════════
# 常量
# ═══════════════════════════════════════════════════════════════════════════════

# 12 字节中文 UTF-8 编码 + 4 字节 \x00 填充，共 16 字节
MAGIC_HEADER: bytes = "艨艟战舰".encode("utf-8") + b"\x00\x00\x00\x00"
assert len(MAGIC_HEADER) == 16, "Magic Header 必须恰好为 16 字节"

# 算法 ID（写入文件头 1 字节）
ALGO_AES256GCM: int = 0x01    # AES-256-GCM，12 字节 Nonce
ALGO_XCHACHA20: int = 0x02    # XChaCha20-Poly1305，24 字节 Nonce（推荐）

CHUNK_SIZE: int = 4 * 1024 * 1024    # 4 MB，流式处理的基本单位


# ═══════════════════════════════════════════════════════════════════════════════
# 自定义异常
# ═══════════════════════════════════════════════════════════════════════════════

class CryptoError(Exception):
    """加密 / 解密操作通用错误基类"""


class TamperedError(CryptoError):
    """
    文件完整性校验失败：
      · Magic Header 不匹配（非本应用加密的文件）
      · AEAD Tag 校验失败（密文被篡改 / 密钥错误）
      · Chunk 数量不符（文件被截断）
      · Chunk 重排（AAD 校验失败）
    """


class UnsupportedAlgoError(CryptoError):
    """文件头中的算法 ID 未被本版本支持"""


class ParamsTamperedError(CryptoError):
    """
    .vault_meta 的 KDF 参数低于安全阈值。
    拒绝解锁以防止降级攻击。
    """


# ═══════════════════════════════════════════════════════════════════════════════
# 工具函数
# ═══════════════════════════════════════════════════════════════════════════════

def _b64_encode(data: bytes) -> str:
    """标准 Base64 编码（含 = 填充）"""
    return base64.b64encode(data).decode()


def _b64_decode(s: str) -> bytes:
    """安全 Base64 解码，自动补齐填充"""
    pad = (4 - len(s) % 4) % 4
    return base64.b64decode(s + "=" * pad)


def _safe_remove(path: str) -> None:
    """安全删除文件，忽略文件不存在的情况"""
    try:
        os.remove(path)
    except FileNotFoundError:
        pass


def _make_aead(algo: int, key: bytes):
    """根据算法 ID 创建对应的 AEAD 对象"""
    if algo == ALGO_AES256GCM:
        return AESGCM(key)
    elif algo == ALGO_XCHACHA20:
        return XChaCha20Poly1305(key)
    else:
        raise UnsupportedAlgoError(f"未知算法 ID: 0x{algo:02X}")


# ═══════════════════════════════════════════════════════════════════════════════
# KDF — 密钥派生函数
# ═══════════════════════════════════════════════════════════════════════════════

def derive_key_argon2id(
    password: bytes,
    salt: bytes,
    memory_kb: int,
    iterations: int,
    parallelism: int,
    length: int = 32,
) -> bytes:
    """
    Argon2id 密钥派生（默认推荐 KDF）。

    参数参考（来自 V5 设计文档）：
      档位    memory_kb   iterations  parallelism
      高端    65536        3           4
      中端    32768        2           2
      低端    16384        1           1

    Args:
        password    : 用户密码（bytes）
        salt        : 随机 32 字节盐（来自 .vault_meta）
        memory_kb   : 内存用量（KB），越大越难暴力破解
        iterations  : 计算迭代次数
        parallelism : 并行线程数（建议 = CPU 核心数 / 2）
        length      : 输出密钥长度（默认 32 字节 = 256 位）

    Returns:
        派生的密钥 bytes
    """
    kdf = Argon2id(
        salt=salt,
        length=length,
        iterations=iterations,
        lanes=parallelism,
        memory_cost=memory_kb,
        backend=default_backend(),
    )
    return kdf.derive(password)


def derive_key_scrypt(
    password: bytes,
    salt: bytes,
    n: int,
    r: int,
    p: int,
    length: int = 32,
) -> bytes:
    """
    scrypt 密钥派生（备选 KDF）。

    参数参考：
      档位    N       r   p
      高端    32768   8   1
      中端    16384   8   1
      低端    8192    8   1

    注意：N 必须为 2 的幂；r 固定 8，p 固定 1（scrypt 并行化收益极低）。
    """
    kdf = Scrypt(
        salt=salt,
        length=length,
        n=n,
        r=r,
        p=p,
        backend=default_backend(),
    )
    return kdf.derive(password)


def derive_subkey(master_key: bytes, info: str, length: int = 32) -> bytes:
    """
    HKDF-SHA256 子密钥派生。从主密钥安全分离出各功能密钥，互不影响。

    标准用途（info 字符串）：
      "content_key"         → 文件内容加密密钥（32 字节）
      "manifest_key"        → manifest HMAC 防反查密钥（32 字节）
      "log_key"             → 日志加密密钥（32 字节）
      "filename_siv_key"    → 文件名 SIV 加密密钥（64 字节，需指定 length=64）

    Args:
        master_key : 主密钥（由 KDF 派生）
        info       : 用途标识字符串（UTF-8 编码后作为 HKDF info）
        length     : 输出长度（字节）

    Returns:
        指定长度的子密钥 bytes
    """
    hkdf = HKDF(
        algorithm=hashes.SHA256(),
        length=length,
        salt=None,
        info=info.encode("utf-8"),
        backend=default_backend(),
    )
    return hkdf.derive(master_key)


# ═══════════════════════════════════════════════════════════════════════════════
# Nonce 管理
# ═══════════════════════════════════════════════════════════════════════════════

def generate_base_nonce() -> bytes:
    """
    生成 24 字节随机基础 Nonce。

    · AES-GCM 使用前 12 字节
    · XChaCha20 使用全部 24 字节

    XChaCha20 的 24 字节 Nonce 空间为 2¹⁹²，从数学层面消除随机碰撞可能。
    """
    return os.urandom(24)


def _derive_chunk_nonce(base_nonce: bytes, chunk_index: int, algo: int) -> bytes:
    """
    派生第 chunk_index 块的 Nonce：

      chunk_nonce = bytearray(base_nonce)
      chunk_nonce[:8] ^= little_endian_uint64(chunk_index)

    AES-GCM  → 返回前 12 字节
    XChaCha20 → 返回全 24 字节

    确保同一文件内每块 Nonce 唯一，且无需为每块单独存储 Nonce。
    """
    idx_bytes = struct.pack("<Q", chunk_index)   # 8 字节小端
    nonce = bytearray(base_nonce)
    for i in range(8):
        nonce[i] ^= idx_bytes[i]
    return bytes(nonce[:12]) if algo == ALGO_AES256GCM else bytes(nonce)


# ═══════════════════════════════════════════════════════════════════════════════
# 分块流式加密
# ═══════════════════════════════════════════════════════════════════════════════

def encrypt_file(
    src_path: str,
    dst_path: str,
    content_key: bytes,
    algo: int = ALGO_AES256GCM,
    progress_cb: Optional[Callable[[int, int], None]] = None,
) -> str:
    """
    流式分块加密文件，最大内存占用 ≤ 4 MB（与文件总大小无关）。

    ┌─ 输出文件格式 ─────────────────────────────────────────────────────────┐
    │  偏移       长度      内容                                             │
    │  0          16 B      Magic Header  （定制中文字符标头）                │
    │  16         1 B       AlgoID        0x01=AES-GCM / 0x02=XChaCha20   │
    │  17         4 B       ChunkCount    uint32 小端序                     │
    │  21         24 B      BaseNonce     随机 24 字节                      │
    │  ── 每个 Chunk 循环（共 ChunkCount 次）───────────────────────────── │
    │  +0         4 B       CipherLen     密文字节数 uint32 小端序          │
    │  +4         N B       Ciphertext    密文                              │
    │  +4+N       16 B      Tag           AEAD 认证 Tag                    │
    └────────────────────────────────────────────────────────────────────────┘

    安全性保证：
      · 每块 AAD = struct.pack('<I', chunk_index)，防重排 / 复制粘贴攻击
      · ChunkCount 记录在头部，解密时严格核对防截断
      · AEAD Tag 保证每块密文不可伪造

    Args:
        src_path    : 明文源文件路径（支持中文路径）
        dst_path    : 密文目标文件路径
        content_key : 32 字节内容加密密钥（由 derive_subkey 派生）
        algo        : ALGO_AES256GCM 或 ALGO_XCHACHA20
        progress_cb : 进度回调 (bytes_done: int, total_bytes: int) -> None

    Returns:
        明文文件的 SHA256（hex 字符串），用于 manifest 的 HMAC 计算。

    Raises:
        UnsupportedAlgoError : 无效的算法 ID
        OSError              : 文件读写错误
    """
    src_path = str(src_path)
    dst_path = str(dst_path)

    total_bytes = os.path.getsize(src_path)
    # 空文件也视为 1 块，避免 chunk_count=0 的边界情况
    chunk_count = max(1, (total_bytes + CHUNK_SIZE - 1) // CHUNK_SIZE)
    base_nonce = generate_base_nonce()
    aead = _make_aead(algo, content_key)
    plain_sha256 = hashlib.sha256()
    bytes_done = 0

    with open(src_path, "rb") as src_f, open(dst_path, "wb") as dst_f:
        # ── 写文件头 ────────────────────────────────────────────────────────
        dst_f.write(MAGIC_HEADER)
        dst_f.write(struct.pack("<B", algo))
        dst_f.write(struct.pack("<I", chunk_count))
        dst_f.write(base_nonce)

        # ── 逐块加密 ────────────────────────────────────────────────────────
        chunk_idx = 0
        while True:
            chunk = src_f.read(CHUNK_SIZE)
            
            # 允许 0 字节文件至少执行一次加密，生成合法的空密文块（修复空文件崩溃漏洞）
            if not chunk and chunk_idx > 0:
                break

            plain_sha256.update(chunk)
            chunk_nonce = _derive_chunk_nonce(base_nonce, chunk_idx, algo)
            aad = struct.pack("<I", chunk_idx)       # chunk 索引作为 AAD

            ct_with_tag = aead.encrypt(chunk_nonce, chunk, aad)
            ciphertext = ct_with_tag[:-16]           # cryptography 库：密文+Tag 拼接输出
            tag = ct_with_tag[-16:]

            dst_f.write(struct.pack("<I", len(ciphertext)))
            dst_f.write(ciphertext)
            dst_f.write(tag)

            bytes_done += len(chunk)
            chunk_idx += 1
            if progress_cb:
                progress_cb(bytes_done, total_bytes)

    return plain_sha256.hexdigest()


# ═══════════════════════════════════════════════════════════════════════════════
# 分块流式解密
# ═══════════════════════════════════════════════════════════════════════════════

def decrypt_file(
    src_path: str,
    dst_path: str,
    content_key: bytes,
    progress_cb: Optional[Callable[[int, int], None]] = None,
) -> str:
    """
    流式分块解密文件，最大内存占用 ≤ 4 MB。

    安全性保证：
      · Magic Header 校验：非本应用文件立即拒绝
      · 每块 AEAD 认证：密文篡改 / 密钥错误立即失败
      · chunk_index AAD：块重排 / 复制粘贴攻击立即失败
      · ChunkCount 核对：截断攻击立即失败
      · 解密失败时自动清理已写入的不完整目标文件

    Args:
        src_path    : 密文源文件路径
        dst_path    : 明文目标文件路径
        content_key : 32 字节内容加密密钥
        progress_cb : 进度回调 (bytes_done: int, estimated_total: int) -> None

    Returns:
        解密后明文的 SHA256（hex），供上层调用者二次校验。

    Raises:
        TamperedError        : 完整性 / 认证失败
        UnsupportedAlgoError : 未知算法 ID
        CryptoError          : 其他解密错误
    """
    src_path = str(src_path)
    dst_path = str(dst_path)

    plain_sha256 = hashlib.sha256()
    bytes_done = 0

    try:
        with open(src_path, "rb") as src_f, open(dst_path, "wb") as dst_f:
            # ── 验证 Magic Header ────────────────────────────────────────────
            magic = src_f.read(16)
            if magic != MAGIC_HEADER:
                raise TamperedError(
                    "Magic Header 不匹配：该文件不是 VaultApp 加密文件，或文件头已损坏"
                )

            algo = struct.unpack("<B", src_f.read(1))[0]
            expected_chunk_count = struct.unpack("<I", src_f.read(4))[0]
            base_nonce = src_f.read(24)

            if len(base_nonce) < 24:
                raise TamperedError("文件头不完整（BaseNonce 截断）")

            # ── 精准预估明文总大小（用于进度条计算）──────────────────────────────
            try:
                enc_size = os.path.getsize(src_path)
                header_overhead = 45  # Magic(16) + Algo(1) + ChunkCount(4) + BaseNonce(24)
                chunk_overhead = 20 * expected_chunk_count  # 每个 Chunk: CipherLen(4) + Tag(16)
                estimated_total = max(0, enc_size - header_overhead - chunk_overhead)
            except OSError:
                estimated_total = 0  # 兜底，防止文件系统异常导致崩溃

            aead = _make_aead(algo, content_key)

            # ── 逐块解密 ─────────────────────────────────────────────────────
            actual_chunk_count = 0

            for _ in range(expected_chunk_count):
                # 读 CipherLen
                len_raw = src_f.read(4)
                if len(len_raw) < 4:
                    break
                cipher_len = struct.unpack("<I", len_raw)[0]

                ciphertext = src_f.read(cipher_len)
                tag = src_f.read(16)

                if len(ciphertext) != cipher_len or len(tag) != 16:
                    raise TamperedError(
                        f"Chunk {actual_chunk_count} 数据不完整（文件可能被截断）"
                    )

                chunk_nonce = _derive_chunk_nonce(base_nonce, actual_chunk_count, algo)
                aad = struct.pack("<I", actual_chunk_count)

                try:
                    plaintext = aead.decrypt(chunk_nonce, ciphertext + tag, aad)
                except Exception:
                    raise TamperedError(
                        f"Chunk {actual_chunk_count} AEAD 认证失败：\n"
                        f"  · 可能原因：密钥错误 / 文件被篡改 / Chunk 顺序被破坏"
                    )

                dst_f.write(plaintext)
                plain_sha256.update(plaintext)
                bytes_done += len(plaintext)
                actual_chunk_count += 1

                if progress_cb:
                    progress_cb(bytes_done, estimated_total)

            # ── 验证 Chunk 总数（防截断攻击）────────────────────────────────
            if actual_chunk_count != expected_chunk_count:
                raise TamperedError(
                    f"Chunk 数量不匹配：期望 {expected_chunk_count} 块，"
                    f"实际读取 {actual_chunk_count} 块。文件可能被截断。"
                )

    except (TamperedError, UnsupportedAlgoError, CryptoError):
        _safe_remove(dst_path)    # 清理可能的不完整输出
        raise
    except Exception as e:
        _safe_remove(dst_path)
        raise CryptoError(f"解密时发生意外错误: {e}") from e

    return plain_sha256.hexdigest()


# ═══════════════════════════════════════════════════════════════════════════════
# 内存级加解密（用于日志条目、元数据等小块数据）
# ═══════════════════════════════════════════════════════════════════════════════

def encrypt_bytes(plaintext: bytes, key: bytes, algo: int = ALGO_AES256GCM) -> bytes:
    """
    加密小块数据（内存操作，不写文件）。

    输出格式：[AlgoID 1B][Nonce NB][Ciphertext+Tag]
      AES-GCM    : Nonce = 12 B，输出总开销 = 1 + 12 + 16 = 29 B
      XChaCha20  : Nonce = 24 B，输出总开销 = 1 + 24 + 16 = 41 B
    """
    nonce_len = 12 if algo == ALGO_AES256GCM else 24
    nonce = os.urandom(nonce_len)
    aead = _make_aead(algo, key)
    ct = aead.encrypt(nonce, plaintext, None)
    return struct.pack("<B", algo) + nonce + ct


def decrypt_bytes(data: bytes, key: bytes) -> bytes:
    """
    解密小块数据（内存操作）。

    Raises:
        TamperedError : AEAD 认证失败
    """
    if len(data) < 18:
        raise TamperedError("数据长度不足，无法解密")

    algo = struct.unpack("<B", data[:1])[0]
    nonce_len = 12 if algo == ALGO_AES256GCM else 24
    nonce = data[1:1 + nonce_len]
    ct = data[1 + nonce_len:]
    aead = _make_aead(algo, key)

    try:
        return aead.decrypt(nonce, ct, None)
    except Exception:
        raise TamperedError("小块数据 AEAD 认证失败（密钥错误或数据被篡改）")


# ═══════════════════════════════════════════════════════════════════════════════
# 文件名加密（AES-256-SIV，确定性）
# ═══════════════════════════════════════════════════════════════════════════════

def encrypt_filename(filename: str, filename_siv_key: bytes) -> str:
    """
    AES-SIV 确定性加密文件名。

    确定性的意义：
      · 相同 filename + 相同密钥 → 相同密文（文件系统可稳定寻址）
      · 不同 Vault 密钥不同 → 同名文件在不同 Vault 产生不同密文（无跨 Vault 冲突）

    Args:
        filename         : 原始文件名（支持中文）
        filename_siv_key : 64 字节 SIV 密钥
                           = derive_subkey(master_key, "filename_siv_key", length=64)

    Returns:
        Base64url 编码密文（无填充）+ ".enc"
        示例："YWVz1f3bQx8k.enc"
    """
    if len(filename_siv_key) != 64:
        raise ValueError("AES-SIV 密钥必须为 64 字节（两个 256 位密钥）")
    siv = AESSIV(filename_siv_key)
    ct = siv.encrypt(filename.encode("utf-8"), [])
    encoded = base64.urlsafe_b64encode(ct).rstrip(b"=").decode()
    return encoded + ".enc"


def decrypt_filename(enc_name: str, filename_siv_key: bytes) -> Optional[str]:
    """
    AES-SIV 解密文件名。

    Returns:
        原始文件名字符串，解密失败时返回 None。
    """
    try:
        name = enc_name[:-4] if enc_name.endswith(".enc") else enc_name
        pad = (4 - len(name) % 4) % 4
        ct = base64.urlsafe_b64decode(name + "=" * pad)
        siv = AESSIV(filename_siv_key)
        return siv.decrypt(ct, []).decode("utf-8")
    except Exception:
        return None


# ═══════════════════════════════════════════════════════════════════════════════
# manifest 防反查哈希
# ═══════════════════════════════════════════════════════════════════════════════

def compute_plain_hmac(plain_sha256_hex: str, manifest_key: bytes) -> str:
    """
    计算写入 manifest.db 的 plain_hash 字段（防反查设计）：
      HMAC-SHA256(manifest_key, bytes.fromhex(plain_sha256_hex))

    优势：
      · 攻击者拿到 manifest.db 但无主密钥时，无法通过彩虹表 / 哈希数据库反查文件内容
      · 相同文件 + 相同密钥 → 相同 HMAC，不影响增量对比逻辑

    Args:
        plain_sha256_hex : 明文文件的 SHA256（hex 字符串，由 encrypt_file 返回）
        manifest_key     : 32 字节，= derive_subkey(master_key, "manifest_key")

    Returns:
        HMAC 的 hex 字符串，写入 manifest.db 的 plain_hash 列。
    """
    h = crypto_hmac.HMAC(manifest_key, hashes.SHA256(), backend=default_backend())
    h.update(bytes.fromhex(plain_sha256_hex))
    return h.finalize().hex()


def verify_plain_hmac(
    plain_sha256_hex: str,
    stored_hmac: str,
    manifest_key: bytes,
) -> bool:
    """
    验证文件内容是否自上次同步后发生变更（constant-time 比较，防时序攻击）。

    Returns:
        True  : 文件未变更（HMAC 一致）
        False : 文件已变更或 manifest_key 错误
    """
    expected = compute_plain_hmac(plain_sha256_hex, manifest_key)
    return hmac.compare_digest(expected, stored_hmac)


# ═══════════════════════════════════════════════════════════════════════════════
# 便捷：完整主密钥派生流程
# ═══════════════════════════════════════════════════════════════════════════════

def derive_master_key_from_meta(password: bytes, meta: dict) -> bytes:
    """
    从 .vault_meta 字典派生主密钥（完整流程）：
      1. 验证 KDF 参数是否达到安全阈值（防降级攻击白名单）
      2. 执行重度 KDF（Argon2id 或 scrypt）
      3. 返回 256 位主密钥

    Args:
        password : 用户密码（bytes）
        meta     : 完整的 .vault_meta 字典（已从 JSON 解析）

    Returns:
        32 字节主密钥（bytearray 形式，调用方负责在不需要时清零）

    Raises:
        ParamsTamperedError  : KDF 参数低于安全阈值
        ValueError           : meta 字段缺失或 KDF 名称未知
    """
    kdf_params = meta.get("kdf_params", {})
    salt = _b64_decode(kdf_params["salt"])

    # ── 第一步：验证参数安全阈值（彻底切断离线爆破途径）───────────────────────────
    kdf_name = meta["kdf"]
    if kdf_name == "Argon2id":
        if kdf_params.get("memory_kb", 0) < 16384 or kdf_params.get("iterations", 0) < 1:
            raise ParamsTamperedError("Argon2id 参数低于安全阈值，拒绝执行（疑似被恶意降级）。")
    elif kdf_name == "scrypt":
        if kdf_params.get("n", 0) < 8192:
            raise ParamsTamperedError("scrypt 参数低于安全阈值，拒绝执行（疑似被恶意降级）。")
    else:
        raise ValueError(f"未知 KDF 类型: {kdf_name}（仅支持 Argon2id / scrypt）")

    # ── 第二步：执行重度 KDF（耗时 1-3 秒，正常现象）───────────────────────────────
    if kdf_name == "Argon2id":
        raw_key = derive_key_argon2id(
            password=password,
            salt=salt,
            memory_kb=kdf_params["memory_kb"],
            iterations=kdf_params["iterations"],
            parallelism=kdf_params["parallelism"],
        )
    elif kdf_name == "scrypt":
        raw_key = derive_key_scrypt(
            password=password,
            salt=salt,
            n=kdf_params["n"],
            r=kdf_params["r"],
            p=kdf_params["p"],
        )

    # 返回 bytearray，调用方可原地清零（安全清除）
    return bytearray(raw_key)

