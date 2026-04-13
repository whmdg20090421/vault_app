"""
core/updater.py — VaultApp V5 更新检查模块

设计规范（V5定稿）：
  · 检查机制：静默请求 GitHub Releases API
  · 更新策略：非强制更新，仅弹窗提示，点击后跳转系统浏览器下载
  · 多线程防卡死：网络请求放在独立线程执行
"""

import json
import urllib.request
import threading
import webbrowser
from typing import Optional, Callable, Dict, Any

class UpdaterError(Exception):
    pass

class UpdateManager:
    def __init__(self, current_version: str, repo_owner: str, repo_name: str):
        """
        初始化更新检查器
        
        Args:
            current_version: 当前 App 的版本号，例如 "v1.0.0"
            repo_owner: GitHub 仓库拥有者名称
            repo_name: GitHub 仓库名称
        """
        self.current_version = current_version
        self.api_url = f"https://api.github.com/repos/{repo_owner}/{repo_name}/releases/latest"
        
        # 缓存检查结果，避免单次启动中频繁发请求
        self._latest_release_info: Optional[Dict[str, Any]] = None

    def check_for_update_async(self, callback: Callable[[bool, Optional[Dict[str, Any]], str], None]):
        """
        异步检查更新（不阻塞 UI）
        
        Args:
            callback: 检查完成后的回调函数。
                      签名: callback(has_new_version: bool, release_info: dict, error_msg: str)
        """
        def _check_task():
            try:
                # 设置 5 秒超时，防止网络不佳时一直挂起
                req = urllib.request.Request(self.api_url, headers={'User-Agent': 'VaultApp-Updater'})
                with urllib.request.urlopen(req, timeout=5.0) as response:
                    data = json.loads(response.read().decode('utf-8'))
                
                latest_version = data.get("tag_name", "")
                
                # 简单字符串对比版本号（实际生产中可引入 packaging.version）
                # 假设版本号格式为 "vX.Y.Z"
                if latest_version and latest_version != self.current_version:
                    self._latest_release_info = {
                        "version": latest_version,
                        "release_notes": data.get("body", "无详细更新说明"),
                        "download_url": data.get("html_url", "")
                    }
                    callback(True, self._latest_release_info, "")
                else:
                    callback(False, None, "")
                    
            except Exception as e:
                callback(False, None, str(e))

        # 放入后台线程执行
        threading.Thread(target=_check_task, daemon=True).start()

    def open_download_page(self):
        """打开系统浏览器前往下载页面"""
        if self._latest_release_info and "download_url" in self._latest_release_info:
            url = self._latest_release_info["download_url"]
            try:
                webbrowser.open(url)
            except Exception as e:
                print(f"无法打开浏览器: {e}")

    def format_update_dialog_text(self) -> str:
        """格式化更新弹窗的文本内容（对应规范 14.2）"""
        if not self._latest_release_info:
            return ""
            
        new_v = self._latest_release_info['version']
        notes = self._latest_release_info['release_notes']
        
        # 限制更新日志长度，防止弹窗过长撑爆屏幕
        if len(notes) > 200:
            notes = notes[:197] + "..."
            
        return (
            f"发现新版本 {new_v}\n"
            f"当前版本：{self.current_version}\n\n"
            f"更新内容：\n{notes}"
        )
