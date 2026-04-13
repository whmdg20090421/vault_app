"""
ui/screens/sync.py — VaultApp V5 同步进度页面

设计规范（V5定稿）：
  · 分阶段进度显示：扫描 -> 传输 -> 清理
  · 实时数据：网速、已完成数/总数、预计剩余时间
  · 交互：暂停 (释放 WakeLock) / 继续 (重新申请 WakeLock)
  · 系统联动：同步期间调用 keepalive 更新通知栏
"""

import time
from kivy.metrics import dp
from kivy.clock import Clock
from kivy.uix.screenmanager import Screen
from kivymd.app import MDApp
from kivymd.uix.boxlayout import MDBoxLayout
from kivymd.uix.label import MDLabel
from kivymd.uix.progressbar import MDProgressBar
from kivymd.uix.button import MDFillRoundFlatButton, MDFlatButton
from kivymd.uix.card import MDCard

from core.keepalive import KeepAliveManager

class SyncScreen(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.name = "sync"
        self.app = MDApp.get_running_app()
        self.keepalive = KeepAliveManager()
        
        # 统计数据
        self.start_time = 0
        self.total_files = 0
        self.done_files = 0
        
        self.build_ui()

    def build_ui(self):
        # 主布局
        self.main_layout = MDBoxLayout(
            orientation="vertical",
            padding=dp(16),
            spacing=dp(20)
        )

        # 1. 核心进度卡片
        self.progress_card = MDCard(
            orientation="vertical",
            padding=dp(16),
            size_hint=(1, None),
            height=dp(220),
            radius=[dp(12)],
            elevation=2
        )
        
        self.status_label = MDLabel(
            text="正在扫描文件...",
            font_style="H6",
            size_hint_y=None,
            height=dp(40)
        )
        
        self.progress_bar = MDProgressBar(
            value=0,
            max=100,
            size_hint_y=None,
            height=dp(8)
        )
        
        self.stats_label = MDLabel(
            text="进度: 0 / 0 | 速度: 0 KB/s",
            theme_text_color="Secondary",
            font_style="Body2"
        )

        self.time_label = MDLabel(
            text="剩余时间: --:--",
            theme_text_color="Hint",
            font_style="Caption"
        )

        self.progress_card.add_widget(self.status_label)
        self.progress_card.add_widget(self.progress_bar)
        self.progress_card.add_widget(self.stats_label)
        self.progress_card.add_widget(self.time_label)

        # 2. 控制按钮区
        btn_layout = MDBoxLayout(
            spacing=dp(20),
            size_hint=(1, None),
            height=dp(60),
            padding=[0, dp(10)]
        )
        
        self.pause_btn = MDFillRoundFlatButton(
            text="暂停同步",
            size_hint_x=0.5,
            on_release=self.toggle_sync
        )
        
        stop_btn = MDFlatButton(
            text="取消",
            size_hint_x=0.5,
            on_release=self.stop_sync
        )
        
        btn_layout.add_widget(self.pause_btn)
        btn_layout.add_widget(stop_btn)

        self.main_layout.add_widget(self.progress_card)
        self.main_layout.add_widget(btn_layout)
        self.add_widget(self.main_layout)

    # ═════════════════════════════════════════════════════════════════════════
    # 状态更新逻辑
    # ═════════════════════════════════════════════════════════════════════════

    def update_progress(self, done, total, speed_kb):
        """由 SyncEngine 通过 Clock 调度调用此方法"""
        self.done_files = done
        self.total_files = total
        
        # 更新 UI
        if total > 0:
            pct = (done / total) * 100
            self.progress_bar.value = pct
            
        self.stats_label.text = f"进度: {done} / {total} | 速度: {speed_kb:.1f} KB/s"
        
        # 计算剩余时间 (ETA)
        if speed_kb > 0 and (total - done) > 0:
            # 这是一个简化的估算：假设平均文件大小为 1MB
            remaining_sec = (total - done) * 1024 / speed_kb
            mins, secs = divmod(int(remaining_sec), 60)
            self.time_label.text = f"预计剩余: {mins:02d}:{secs:02d}"
        
        # 更新 Android 通知栏 (第 12 节)
        self.keepalive.update_notification(
            "VaultApp 同步中", 
            f"{done}/{total} 文件 | {speed_kb:.1f} KB/s"
        )

    def toggle_sync(self, instance):
        """暂停/继续 切换"""
        # 获取 SyncEngine 实例 (假设已在 App 类中初始化)
        engine = self.app.sync_engine 
        
        if self.pause_btn.text == "暂停同步":
            engine.pause()
            self.keepalive.stop_sync_keepalive() # 暂停时释放 WakeLock 省电
            self.pause_btn.text = "继续同步"
            self.status_label.text = "同步已暂停"
        else:
            engine.resume()
            self.keepalive.start_sync_keepalive() # 恢复时重新持有 WakeLock
            self.pause_btn.text = "暂停同步"
            self.status_label.text = "正在同步..."

    def stop_sync(self, instance):
        """停止同步并返回主页"""
        self.app.sync_engine.stop()
        self.keepalive.stop_sync_keepalive()
        self.manager.current = "home"
