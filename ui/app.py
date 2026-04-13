"""
ui/app.py — VaultApp V5 UI 总控与应用程序入口

设计规范（V5定稿）：
  · KivyMD 1.2.0 + Material Design 3 深色主题
  · 强调色：#6750A4 (在 KivyMD 中通过 custom color 或最相近的 DeepPurple 实现)
  · 响应式布局：监听屏幕尺寸，< 600dp 为单列，>= 600dp 为双列
  · 充当 Core 模块的依赖注入容器 (DI Container)
"""

import os
from kivy.core.window import Window
from kivy.metrics import dp
from kivy.properties import BooleanProperty, ObjectProperty
from kivy.uix.screenmanager import ScreenManager, FadeTransition
from kivymd.app import MDApp
from kivymd.color_definitions import colors

# 导入我们的核心依赖
from core.session import SessionManager
from core.vault import VaultManager


class VaultScreenManager(ScreenManager):
    """自定义屏幕管理器，用于管理所有的页面路由"""
    pass


class MainApp(MDApp):
    """
    KivyMD 应用程序主类。
    全局单例，包含所有 UI 共享的逻辑和 Core 层的实例。
    """
    
    # 响应式布局状态：是否为宽屏（>= 600dp）
    is_tablet_mode = BooleanProperty(False)
    
    # 核心后端的全局实例
    session_manager = ObjectProperty(None)
    vault_manager = ObjectProperty(None)
    
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.init_core_modules()

    def init_core_modules(self):
        """初始化 Core 层的依赖"""
        # 设置 App 私有缓存目录
        self.cache_dir = os.path.join(self.user_data_dir, "cache")
        os.makedirs(self.cache_dir, exist_ok=True)
        
        # 实例化我们在 Core 层写好的大骨架
        self.session_manager = SessionManager(cache_dir=self.cache_dir)
        self.vault_manager = VaultManager(session_manager=self.session_manager)
        
        # 注意：SyncEngine, WebDAV, Manifest 等依赖 Vault ID 的模块，
        # 会在 Vault 解锁成功后，再在相应的逻辑中初始化。

    def build(self):
        """应用构建：设置主题并返回根 Widget"""
        
        # ── 1. 设置 Material Design 3 视觉规范 (设计文档 15.1 节) ──
        self.theme_cls.material_style = "M3"
        self.theme_cls.theme_style = "Dark"
        
        # V5 规范强调色：#6750A4。在 KivyMD 中可以通过自定义调色板设置，
        # 这里为了兼容性，我们直接应用 MD 的深紫色系。
        self.theme_cls.primary_palette = "DeepPurple"
        self.theme_cls.primary_hue = "400"
        
        # ── 2. 设置响应式监听 (设计文档 15.2 节) ──
        # 监听窗口尺寸变化，以支持折叠屏和设备旋转
        Window.bind(size=self.on_window_resize)
        # 初始化调用一次以确定当前设备类型
        self.on_window_resize(Window, Window.size)

        # ── 3. 初始化页面路由 (Screen Manager) ──
        self.sm = VaultScreenManager(transition=FadeTransition(duration=0.2))
        
        # TODO: 下一步将在这里把各个屏幕 (Screens) 添加进 self.sm
        
        return self.sm

    def on_window_resize(self, window, size):
        """
        屏幕尺寸变化回调。
        动态计算 dp 宽度，判定是否应切换为平板/折叠屏布局。
        """
        width_px, height_px = size
        # 将像素转换为密度无关像素 (dp)
        width_dp = width_px / getattr(Window, 'dpi', 160) * 160 
        
        # >= 600dp 认为是宽屏 (Tablet/Foldable)
        is_wide = width_dp >= 600
        
        if self.is_tablet_mode != is_wide:
            self.is_tablet_mode = is_wide
            # 我们可以在这里抛出自定义事件或让各页面监听 is_tablet_mode
            print(f"[UI 布局] 切换至 {'双列 (平板)' if is_wide else '单列 (手机)'} 模式")

    def on_start(self):
        """应用启动后的钩子"""
        # 检查降级状态 (从 session_manager 获取)，如果是最高级，打印日志
        print(f"当前密钥保护层级: {self.session_manager.protection_level}")

    def on_pause(self):
        """
        Android 压入后台时触发。
        返回 True 表示允许应用在后台挂起而不被立即杀死。
        """
        return True

    def on_resume(self):
        """从后台恢复到前台时触发"""
        pass
