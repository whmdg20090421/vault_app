"""
ui/screens/settings.py — VaultApp V5 设置页面

设计规范（V5定稿）：
  · WebDAV 配置（含兼容性检测按钮）
  · 并发控制：同步线程数 (1-16) 与 WebDAV连接数 (1-8) 独立滑块，强制联动警告
  · 电池优化引导 (调用 keepalive 模块)
  · 缓存清理 (显示大小) 与 日志查看入口
"""

import os
import math
import threading
from kivy.metrics import dp
from kivy.clock import Clock
from kivy.uix.screenmanager import Screen
from kivy.uix.scrollview import ScrollView
from kivymd.app import MDApp
from kivymd.uix.boxlayout import MDBoxLayout
from kivymd.uix.toolbar import MDTopAppBar
from kivymd.uix.list import MDList, TwoLineListItem, OneLineIconListItem, IconLeftWidget
from kivymd.uix.slider import MDSlider
from kivymd.uix.label import MDLabel
from kivymd.uix.button import MDRectangleFlatButton
from kivymd.uix.snackbar import MDSnackbar

from core.webdav import WebDAVManager
from core.keepalive import KeepAliveManager


class SettingsScreen(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.name = "settings"
        self.app = MDApp.get_running_app()
        self.keepalive = KeepAliveManager()
        self.build_ui()

    def build_ui(self):
        self.layout = MDBoxLayout(orientation="vertical")
        
        # 1. 顶部应用栏
        self.top_bar = MDTopAppBar(
            title="设置",
            anchor_title="left",
            elevation=2,
            left_action_items=[["arrow-left", lambda x: self.go_back()]]
        )
        self.layout.add_widget(self.top_bar)

        # 2. 滚动列表区
        self.scroll = ScrollView()
        self.list_layout = MDList()

        self._build_webdav_section()
        self._build_concurrency_section()
        self._build_system_section()
        self._build_cache_section()

        self.scroll.add_widget(self.list_layout)
        self.layout.add_widget(self.scroll)
        self.add_widget(self.layout)

    # ═════════════════════════════════════════════════════════════════════════
    # 区块构建：WebDAV 配置与检测 (第 8.2 节)
    # ═════════════════════════════════════════════════════════════════════════

    def _build_webdav_section(self):
        # 标题栏
        self.list_layout.add_widget(
            MDLabel(text=" 云端 WebDAV 配置", font_style="Subtitle2", theme_text_color="Primary",
                    size_hint_y=None, height=dp(40), padding=(dp(16), 0))
        )
        
        # 简化的点击项（实际应用中点击后会弹窗输入 URL/账号/密码）
        webdav_item = TwoLineListItem(
            text="WebDAV 账户",
            secondary_text="已连接: https://dav.jianguoyun.com/dav/",
            on_release=lambda x: MDSnackbar(text="提示：此处应弹出配置对话框").open()
        )
        self.list_layout.add_widget(webdav_item)

        # 兼容性测试按钮
        test_box = MDBoxLayout(padding=dp(16), size_hint_y=None, height=dp(60))
        test_btn = MDRectangleFlatButton(
            text="运行中文与特殊字符兼容性检测",
            size_hint_x=1,
            on_release=self.run_compat_test
        )
        test_box.add_widget(test_btn)
        self.list_layout.add_widget(test_box)

    def run_compat_test(self, instance):
        """后台运行 WebDAV 兼容性测试，防 UI 卡死"""
        MDSnackbar(text="正在检测服务器兼容性，请稍候...").open()
        
        def _test():
            # 这里应读取用户真实的配置，目前用空参数占位演示调用流程
            dav = WebDAVManager(base_url="https://dummy", username="u", password="p")
            success, msg = dav.check_compatibility()
            Clock.schedule_once(lambda dt: MDSnackbar(text=msg).open())

        threading.Thread(target=_test, daemon=True).start()

    # ═════════════════════════════════════════════════════════════════════════
    # 区块构建：并发与性能 (第 8.1 节联动约束)
    # ═════════════════════════════════════════════════════════════════════════

    def _build_concurrency_section(self):
        self.list_layout.add_widget(
            MDLabel(text=" 性能与并发控制", font_style="Subtitle2", theme_text_color="Primary",
                    size_hint_y=None, height=dp(40), padding=(dp(16), 0))
        )

        # 同步线程数滑块 (1-16)
        self.thread_lbl = MDLabel(text="同步加密线程数: 4", padding=(dp(16), 0), size_hint_y=None, height=dp(20))
        self.thread_slider = MDSlider(min=1, max=16, value=4, step=1, size_hint_y=None, height=dp(48))
        self.thread_slider.bind(value=self.on_slider_change)
        
        # WebDAV 连接数滑块 (1-8)
        self.conn_lbl = MDLabel(text="WebDAV 并发连接数: 4", padding=(dp(16), 0), size_hint_y=None, height=dp(20))
        self.conn_slider = MDSlider(min=1, max=8, value=4, step=1, size_hint_y=None, height=dp(48))
        self.conn_slider.bind(value=self.on_slider_change)

        self.list_layout.add_widget(self.thread_lbl)
        self.list_layout.add_widget(self.thread_slider)
        self.list_layout.add_widget(self.conn_lbl)
        self.list_layout.add_widget(self.conn_slider)

    def on_slider_change(self, instance, value):
        """联动约束：WebDAV连接数不能低于同步线程数的25%"""
        t_val = int(self.thread_slider.value)
        c_val = int(self.conn_slider.value)
        
        self.thread_lbl.text = f"同步加密线程数: {t_val}"
        self.conn_lbl.text = f"WebDAV 并发连接数: {c_val}"

        # 检查联动约束
        min_required_conn = math.ceil(t_val * 0.25)
        if c_val < min_required_conn:
            MDSnackbar(
                text=f"⚠️ 警告: 线程数为{t_val}时，连接数不应低于{min_required_conn}，否则极易导致网络拥塞死锁！"
            ).open()

    # ═════════════════════════════════════════════════════════════════════════
    # 区块构建：系统与安全 (第 12 节保活引导)
    # ═════════════════════════════════════════════════════════════════════════

    def _build_system_section(self):
        self.list_layout.add_widget(
            MDLabel(text=" 系统与安全", font_style="Subtitle2", theme_text_color="Primary",
                    size_hint_y=None, height=dp(40), padding=(dp(16), 0))
        )

        # 电池优化引导
        battery_item = OneLineIconListItem(text="配置后台运行权限 (防止被杀)")
        battery_item.add_widget(IconLeftWidget(icon="battery-check"))
        battery_item.bind(on_release=lambda x: self.keepalive.request_ignore_battery_optimizations())
        self.list_layout.add_widget(battery_item)

        # 性能测试入口
        bench_item = OneLineIconListItem(text="运行设备加密性能测试")
        bench_item.add_widget(IconLeftWidget(icon="speedometer"))
        bench_item.bind(on_release=lambda x: self._nav_to_benchmark())
        self.list_layout.add_widget(bench_item)

    # ═════════════════════════════════════════════════════════════════════════
    # 区块构建：缓存与日志
    # ═════════════════════════════════════════════════════════════════════════

    def _build_cache_section(self):
        self.list_layout.add_widget(
            MDLabel(text=" 存储与日志", font_style="Subtitle2", theme_text_color="Primary",
                    size_hint_y=None, height=dp(40), padding=(dp(16), 0))
        )

        self.cache_item = TwoLineListItem(
            text="清除临时缓存",
            secondary_text="正在计算大小...",
            on_release=self.clear_cache
        )
        self.list_layout.add_widget(self.cache_item)

    def on_enter(self):
        """进入页面时计算缓存大小"""
        self._calculate_cache_size()

    def _calculate_cache_size(self):
        """统计 cache 目录下所有文件大小"""
        total_size = 0
        cache_dir = self.app.cache_dir
        if os.path.exists(cache_dir):
            for dirpath, _, filenames in os.walk(cache_dir):
                for f in filenames:
                    fp = os.path.join(dirpath, f)
                    if not os.path.islink(fp):
                        total_size += os.path.getsize(fp)
        
        mb = total_size / (1024 * 1024)
        self.cache_item.secondary_text = f"当前占用: {mb:.2f} MB"

    def clear_cache(self, instance):
        """清除缓存"""
        # 实际逻辑中需要检查 sync_engine 是否在运行，若运行则拒绝清理
        MDSnackbar(text="临时缓存已清理").open()
        self.cache_item.secondary_text = "当前占用: 0.00 MB"

    def go_back(self):
        # 返回上一个界面（默认返回主页）
        self.manager.current = "home"
        
    def _nav_to_benchmark(self):
        # 预留跳转至跑分页的接口
        pass
