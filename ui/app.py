"""
ui/app.py — VaultApp V5 UI 总控与应用程序入口
"""

import os
import traceback
from kivy.core.window import Window
from kivy.metrics import dp
from kivy.properties import BooleanProperty, ObjectProperty
from kivy.uix.screenmanager import ScreenManager, FadeTransition
from kivymd.app import MDApp
from kivymd.uix.screen import MDScreen
from kivymd.uix.label import MDLabel

class VaultScreenManager(ScreenManager):
    """自定义屏幕管理器，用于管理所有的页面路由"""
    pass

class MainApp(MDApp):
    """KivyMD 应用程序主类"""
    
    is_tablet_mode = BooleanProperty(False)
    session_manager = ObjectProperty(None)
    vault_manager = ObjectProperty(None)
    
    # 删除了 __init__ 中的初始化，延迟到 on_start 中进行

    def build(self):
        """应用构建：设置主题并返回根 Widget"""
        try:
            self.theme_cls.material_style = "M3"
            self.theme_cls.theme_style = "Dark"
            self.theme_cls.primary_palette = "DeepPurple"
            self.theme_cls.primary_hue = "400"
            
            Window.bind(size=self.on_window_resize)
            self.sm = VaultScreenManager(transition=FadeTransition(duration=0.2))
            
            # 【修复 1】：必须添加一个初始页面，否则 ScreenManager 为空会导致闪退
            splash_screen = MDScreen(name="splash")
            splash_screen.add_widget(MDLabel(
                text="VaultApp 正在初始化...\n如果卡在此界面，请检查日志。",
                halign="center",
                theme_text_color="Primary"
            ))
            self.sm.add_widget(splash_screen)
            
            return self.sm

        except Exception as e:
            # 【终极防闪退神器】：如果界面构建报错，直接把错误显示在屏幕上
            return self.create_error_screen("UI 构建失败:\n" + traceback.format_exc())

    def create_error_screen(self, error_msg):
        """生成一个专门显示红字报错的屏幕，防止应用闪退"""
        error_screen = MDScreen(name="error")
        error_screen.add_widget(MDLabel(
            text=error_msg,
            halign="left",
            valign="top",
            font_style="Caption",
            theme_text_color="Error"
        ))
        return error_screen

    def on_start(self):
        """应用启动后的钩子，在这里加载耗时的后台逻辑最安全"""
        try:
            # 【修复 2】：延迟导入核心模块，确保安卓 JVM 环境已完全就绪
            from core.session import SessionManager
            from core.vault import VaultManager

            self.cache_dir = os.path.join(self.user_data_dir, "cache")
            os.makedirs(self.cache_dir, exist_ok=True)
            
            self.session_manager = SessionManager(cache_dir=self.cache_dir)
            self.vault_manager = VaultManager(session_manager=self.session_manager)
            
            print(f"当前密钥保护层级: {self.session_manager.protection_level}")
            
            # 如果初始化成功，可以在这里把 splash_screen 替换成你真正的 home 页面
            # self.sm.current = 'home'
            
        except Exception as e:
            # 如果后台逻辑报错，抓取报错信息并展示在屏幕上
            err_text = "核心逻辑加载失败:\n" + traceback.format_exc()
            err_screen = self.create_error_screen(err_text)
            self.sm.add_widget(err_screen)
            self.sm.current = "error"

    def on_window_resize(self, window, size):
        """屏幕尺寸变化回调"""
        width_px, height_px = size
        # 【修复 3】：更安全的 dp 转换方式，防止由于设备尚未准备好导致除以 0 报错
        scale = dp(1)
        if scale == 0: scale = 1 
        width_dp = width_px / scale
        
        is_wide = width_dp >= 600
        if self.is_tablet_mode != is_wide:
            self.is_tablet_mode = is_wide
            print(f"[UI 布局] 切换至 {'双列 (平板)' if is_wide else '单列 (手机)'} 模式")

    def on_pause(self):
        return True
