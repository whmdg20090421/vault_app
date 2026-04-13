"""
main.py — VaultApp V5 应用程序主入口

这里非常简洁，主要负责实例化 ui.app.MainApp 并启动 Kivy 事件循环。
"""

import os
import sys

# 确保能正确导入当前目录下的 core 和 ui 模块
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from ui.app import MainApp

if __name__ == "__main__":
    # 启动 Material Design 3 风格的 Vault 应用程序
    MainApp().run()
