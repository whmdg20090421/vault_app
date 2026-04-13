"""
ui/screens/vault_browser.py — VaultApp V5 文件浏览器页面

设计规范（V5定稿）：
  · UI 结构：面包屑导航 + 文件/文件夹列表 + 底部操作栏
  · 文件名解密：调用 crypto.decrypt_filename 实时显示明文
  · SAF 优化：仅显示当前层级，点击文件夹进入下级
  · 交互：右上方 ⋮ 菜单包含“立即清除记住的密码”功能
"""

import os
from kivy.metrics import dp
from kivy.uix.screenmanager import Screen
from kivy.uix.scrollview import ScrollView
from kivymd.app import MDApp
from kivymd.uix.boxlayout import MDBoxLayout
from kivymd.uix.toolbar import MDTopAppBar
from kivymd.uix.list import MDList, OneLineAvatarIconListItem, IconLeftWidget, IconRightWidget
from kivymd.uix.snackbar import MDSnackbar

from core import crypto

class FileListItem(OneLineAvatarIconListItem):
    """单个文件或文件夹的行显示"""
    def __init__(self, name, is_dir=False, on_click=None, **kwargs):
        super().__init__(**kwargs)
        self.text = name
        self.is_dir = is_dir
        
        # 左侧图标：文件夹或文件
        icon_name = "folder" if is_dir else "file-lock"
        self.add_widget(IconLeftWidget(icon=icon_name))
        
        # 右侧菜单图标
        self.add_widget(IconRightWidget(icon="dots-vertical"))
        
        self.on_click_callback = on_click

    def on_release(self):
        if self.on_click_callback:
            self.on_click_callback(self.text, self.is_dir)


class VaultBrowserScreen(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.name = "vault_browser"
        self.app = MDApp.get_running_app()
        self.current_path = "/" # 虚拟相对路径
        self.build_ui()

    def build_ui(self):
        self.layout = MDBoxLayout(orientation="vertical")

        # 1. 顶部工具栏（含面包屑显示）
        self.top_bar = MDTopAppBar(
            title="文件浏览: /",
            anchor_title="left",
            elevation=2,
            left_action_items=[["arrow-left", lambda x: self.go_back()]],
            right_action_items=[
                ["magnify", lambda x: None], # 搜索预留
                ["dots-vertical", lambda x: self.open_menu()] # 包含清除密码
            ]
        )
        self.layout.add_widget(self.top_bar)

        # 2. 文件列表滚动区域
        self.scroll = ScrollView()
        self.file_list = MDList()
        self.scroll.add_widget(self.file_list)
        self.layout.add_widget(self.scroll)

        self.add_widget(self.layout)

    def on_enter(self):
        """进入页面时加载文件"""
        self.refresh_list()

    def refresh_list(self):
        """
        加载并解密当前路径下的文件列表。
        注意：实际开发中，这里会读取 .vault_meta 所在的目录。
        """
        self.file_list.clear_widgets()
        self.top_bar.title = f"浏览: {self.current_path}"
        
        # 模拟从存储读取到的加密文件名（实际会通过 os.listdir 或 SAF 接口）
        # 假设我们从 SyncEngine 获取到了 filename_siv_key
        # 这里仅作逻辑展示：
        # decoded_name = crypto.decrypt_filename(enc_name, siv_key)
        
        # 演示数据
        demo_items = [
            ("我的文档", True),
            ("财务报表.pdf", False),
            ("项目说明.docx", False)
        ]

        for name, is_dir in demo_items:
            item = FileListItem(
                name=name, 
                is_dir=is_dir, 
                on_click=self.handle_item_click
            )
            self.file_list.add_widget(item)

    def handle_item_click(self, name, is_dir):
        """处理点击事件：进入文件夹或查看文件详情"""
        if is_dir:
            self.current_path = os.path.join(self.current_path, name)
            self.refresh_list()
        else:
            MDSnackbar(text=f"选中文件: {name} (准备解密查看)").open()

    def go_back(self):
        """回退到上一级目录，若在根目录则返回主页"""
        if self.current_path == "/":
            self.manager.current = "home"
        else:
            self.current_path = os.path.dirname(self.current_path)
            if not self.current_path.startswith("/"): self.current_path = "/"
            self.refresh_list()

    def open_menu(self):
        """弹出右上角 ⋮ 菜单"""
        # 设计规范 6.3 节：清除密码入口
        # 实现逻辑：调用 app.session_manager.clear_session() 并返回解锁页
        MDSnackbar(text="提示：点击此处可立即清除记住的密码并锁定").open()
        # self.app.session_manager.clear_session()
        # self.manager.current = "unlock"
