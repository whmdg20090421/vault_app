"""
ui/components/file_item.py — 独立封装的文件列表项组件
"""
from kivymd.uix.list import OneLineAvatarIconListItem, IconLeftWidget, IconRightWidget

class FileItem(OneLineAvatarIconListItem):
    """
    可复用的文件浏览器列表项。
    包含左侧的类型图标（文件/文件夹）和右侧的操作菜单。
    """
    def __init__(self, filename: str, is_dir: bool, on_click_callback=None, **kwargs):
        super().__init__(**kwargs)
        self.text = filename
        self.is_dir = is_dir
        self.on_click_callback = on_click_callback
        
        # 左侧图标判定
        icon_name = "folder-outline" if is_dir else "file-lock-outline"
        self.add_widget(IconLeftWidget(icon=icon_name))
        
        # 右侧菜单触发器
        self.add_widget(IconRightWidget(icon="dots-vertical"))

    def on_release(self):
        if self.on_click_callback:
            self.on_click_callback(self.text, self.is_dir)
