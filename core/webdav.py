"""
core/webdav.py — VaultApp V5 WebDAV 传输与兼容性管理模块

设计规范（V5定稿）：
  · 封装 webdav4 客户端操作（上传、下载、删除、目录创建）
  · 并发连接数配置与 HTTP 客户端连接池管理
  · 严格的中文及特殊字符兼容性测试流水线 (8.2 节)
  · 网络请求的异常捕获与统一抛出
"""

import io
from typing import Tuple, Optional
from webdav4.client import Client
from httpx import Limits, Timeout

class WebDAVError(Exception):
    """WebDAV 传输相关的通用错误"""
    pass

class WebDAVManager:
    def __init__(self, base_url: str, username: str = "", password: str = "", max_connections: int = 4):
        """
        初始化 WebDAV 客户端。
        
        Args:
            base_url: WebDAV 服务器地址 (如 https://dav.jianguoyun.com/dav/)
            username: 账号
            password: 密码/应用专用密码
            max_connections: 并发 HTTP 连接数限制（设计文档 8.1 节）
        """
        self.base_url = base_url.rstrip('/')
        self.max_connections = max_connections
        
        # httpx 底层连接池与超时配置
        # Limits 用于控制并发连接数，防止过度占用网络资源
        limits = Limits(max_keepalive_connections=max_connections, max_connections=max_connections)
        # 设置合理的超时时间，防网络假死（连接10秒，读取30秒）
        timeout_config = Timeout(10.0, read=30.0)

        auth = (username, password) if username and password else None
        
        self.client = Client(
            self.base_url, 
            auth=auth,
            timeout=timeout_config,
            http2=True,  # 尽可能开启 HTTP/2 以复用连接
            limits=limits
        )

    # ═════════════════════════════════════════════════════════════════════════
    # 服务器兼容性检测流水线 (设计文档 8.2 节)
    # ═════════════════════════════════════════════════════════════════════════

    def check_compatibility(self) -> Tuple[bool, str]:
        """
        检测服务器对中文路径及特殊字符的支持程度。
        
        Returns:
            (是否建议继续使用, 提示信息字符串)
        """
        test_dir = "vault_compat_中文测试"
        test_file_normal = f"{test_dir}/测试文件.bin"
        test_file_special = f"{test_dir}/special_!'()*.bin"
        
        dummy_data = b"\x01" # 1字节测试数据

        # 测试 1 & 测试 2：创建中文目录并上传中文文件
        try:
            if self.client.exists(test_dir):
                self.client.remove(test_dir)
            
            self.client.mkdir(test_dir)
            self.client.upload_fileobj(io.BytesIO(dummy_data), test_file_normal)
            
            # 测试 4（部分）：读取校验内容
            downloaded_bytes = io.BytesIO()
            self.client.download_fileobj(test_file_normal, downloaded_bytes)
            if downloaded_bytes.getvalue() != dummy_data:
                raise ValueError("读写数据不一致")
                
        except Exception as e:
            self._cleanup_test_dir(test_dir)
            return False, "❌ 服务器不兼容中文路径，建议使用纯英文Vault路径"

        # 测试 3：上传包含 RFC 3986 保留字符的文件
        try:
            self.client.upload_fileobj(io.BytesIO(dummy_data), test_file_special)
        except Exception as e:
            self._cleanup_test_dir(test_dir)
            return True, "⚠️ 服务器不支持部分特殊字符，避免在路径中使用 ! ' ( ) * & % # + 等字符"

        # 测试 5：删除测试目录及善后
        cleanup_success = self._cleanup_test_dir(test_dir)
        if not cleanup_success:
            # 有些弱鸡 WebDAV 服务器允许创建但删除报错，这也算一种兼容性瑕疵
            return True, "⚠️ 服务器已通过读写测试，但删除文件夹时遇到异常，请留意。"

        return True, "✓ 服务器完全兼容"

    def _cleanup_test_dir(self, dir_name: str) -> bool:
        """静默清理测试用的目录"""
        try:
            if self.client.exists(dir_name):
                self.client.remove(dir_name)
            return True
        except Exception:
            return False

    # ═════════════════════════════════════════════════════════════════════════
    # 核心传输接口 (供 Sync Engine 调用)
    # ═════════════════════════════════════════════════════════════════════════

    def ensure_dir(self, remote_dir: str):
        """
        确保远程目录存在。如果父目录也不存在，会级联创建。
        （webdav4 的 mkdir 默认不级联，所以我们需要自己实现一层层创建）
        """
        if not remote_dir or remote_dir == "/":
            return
            
        parts = remote_dir.strip("/").split("/")
        current_path = ""
        
        for part in parts:
            current_path = f"{current_path}/{part}" if current_path else part
            if not self.client.exists(current_path):
                try:
                    self.client.mkdir(current_path)
                except Exception as e:
                    raise WebDAVError(f"创建远程目录 {current_path} 失败: {e}")

    def upload_file(self, local_path: str, remote_path: str):
        """
        上传文件至云端 (标准 PUT，不支持断点续传)。
        成功后，按 V5 规范我们需要进行第二阶段校验：云端文件大小是否与本地一致。
        """
        try:
            import os
            local_size = os.path.getsize(local_path)
            
            # 自动处理远端父目录的创建
            remote_parent = remote_path.rsplit('/', 1)[0]
            if remote_parent != remote_path:
                self.ensure_dir(remote_parent)
            
            # 执行传输
            self.client.upload_file(local_path, remote_path, overwrite=True)
            
            # 两阶段校验：比对大小
            info = self.client.info(remote_path)
            remote_size = int(info.get('size', -1))
            
            if remote_size != local_size:
                raise WebDAVError(f"大小校验失败：本地 {local_size} 字节，云端 {remote_size} 字节")
                
        except Exception as e:
            raise WebDAVError(f"上传文件 {remote_path} 失败: {e}")

    def download_file(self, remote_path: str, local_path: str):
        """从云端下载文件"""
        try:
            self.client.download_file(remote_path, local_path)
        except Exception as e:
            raise WebDAVError(f"下载文件 {remote_path} 失败: {e}")

    def delete(self, remote_path: str):
        """删除云端文件或目录"""
        try:
            if self.client.exists(remote_path):
                self.client.remove(remote_path)
        except Exception as e:
            raise WebDAVError(f"删除远端资源 {remote_path} 失败: {e}")
