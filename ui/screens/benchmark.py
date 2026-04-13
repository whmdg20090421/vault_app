"""
ui/screens/benchmark.py — VaultApp V5 加密性能测试页面

设计规范（V5定稿）：
  · 自动预估：首次进入运行极速测试，判断设备属于高端/中端/低端
  · 深度测试：调用 core/benchmark.py，带有实时更新的进度条
  · 结果展示：直观显示 KDF 解锁耗时、流式加密吞吐量及大文件耗时预估
"""

import threading
from kivy.metrics import dp
from kivy.clock import Clock
from kivy.uix.screenmanager import Screen
from kivymd.app import MDApp
from kivymd.uix.boxlayout import MDBoxLayout
from kivymd.uix.toolbar import MDTopAppBar
from kivymd.uix.label import MDLabel
from kivymd.uix.button import MDRaisedButton
from kivymd.uix.progressbar import MDProgressBar
from kivymd.uix.card import MDCard
from kivymd.uix.snackbar import MDSnackbar

from core.benchmark import BenchmarkManager
from core import crypto


class BenchmarkScreen(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.name = "benchmark"
        self.app = MDApp.get_running_app()
        # 实例化我们在 Core 层写好的测试引擎
        self.bench_manager = BenchmarkManager(cache_dir=self.app.cache_dir)
        self.build_ui()

    def build_ui(self):
        self.layout = MDBoxLayout(orientation="vertical")
        
        # 1. 顶部工具栏
        self.top_bar = MDTopAppBar(
            title="设备性能与档位测定",
            anchor_title="left",
            elevation=2,
            left_action_items=[["arrow-left", lambda x: self.go_back()]]
        )
        self.layout.add_widget(self.top_bar)

        # 2. 内容区 (居中卡片布局)
        content_layout = MDBoxLayout(
            orientation="vertical",
            padding=dp(24),
            spacing=dp(20),
            pos_hint={"center_x": 0.5},
            size_hint_x=None,
            width=dp(360)  # 适配平板的限制宽度
        )

        # 设备预估建议文本
        self.tier_label = MDLabel(
            text="正在检测设备算力...",
            theme_text_color="Primary",
            font_style="Subtitle1",
            halign="center",
            size_hint_y=None,
            height=dp(60)
        )
        content_layout.add_widget(self.tier_label)

        # 进度指示器
        self.status_label = MDLabel(
            text="点击下方按钮开始 500MB 深度测试",
            theme_text_color="Secondary",
            halign="center",
            size_hint_y=None,
            height=dp(30)
        )
        self.progress_bar = MDProgressBar(
            value=0, max=100, size_hint_y=None, height=dp(8)
        )
        content_layout.add_widget(self.status_label)
        content_layout.add_widget(self.progress_bar)

        # 结果展示面板
        self.result_card = MDCard(
            orientation="vertical",
            padding=dp(16),
            size_hint_y=None,
            height=dp(180),
            radius=[dp(12)]
        )
        self.result_text = MDLabel(
            text="测试尚未运行\n\n• KDF 解锁耗时：--\n• 加密吞吐量：-- MB/s\n• 预估 10GB：--\n• 预估 50GB：--",
            theme_text_color="Primary",
            font_style="Body2"
        )
        self.result_card.add_widget(self.result_text)
        content_layout.add_widget(self.result_card)

        # 操作按钮
        self.start_btn = MDRaisedButton(
            text="运行完整性能测试",
            size_hint_x=1,
            height=dp(48),
            on_release=self.start_benchmark
        )
        content_layout.add_widget(self.start_btn)

        self.layout.add_widget(content_layout)
        self.add_widget(self.layout)

    def on_enter(self):
        """进入页面时，静默运行 1 秒的极速测试 (设计文档 13.1)"""
        self.tier_label.text = "正在极速预估设备算力..."
        threading.Thread(target=self._run_quick_estimate, daemon=True).start()

    def _run_quick_estimate(self):
        tier, msg = self.bench_manager.estimate_device_tier()
        Clock.schedule_once(lambda dt: self._update_tier_ui(tier, msg))

    def _update_tier_ui(self, tier, msg):
        self.tier_label.text = f"评级：【{tier}】\n{msg}"

    # ═════════════════════════════════════════════════════════════════════════
    # 深度综合测试逻辑 (防 UI 卡死的多线程结构)
    # ═════════════════════════════════════════════════════════════════════════

    def start_benchmark(self, instance):
        """点击开始深度测试"""
        self.start_btn.disabled = True
        self.result_text.text = "测试运行中，请勿退出..."
        
        # 使用高端参数作为基准进行测试
        test_params = {
            "memory_kb": 65536,
            "iterations": 3,
            "parallelism": 4
        }
        
        threading.Thread(target=self._run_full_test_thread, args=(test_params,), daemon=True).start()

    def _run_full_test_thread(self, kdf_params):
        """后台线程中执行耗时的生成、加密操作"""
        
        # 定义一个回调闭包，用于把进度推回主线程
        def progress_callback(status_text: str, percent: float):
            Clock.schedule_once(lambda dt: self._update_progress_ui(status_text, percent))

        try:
            results = self.bench_manager.run_full_benchmark(
                kdf_name="Argon2id",
                kdf_params=kdf_params,
                algo=crypto.ALGO_XCHACHA20,
                file_size_mb=500,
                ui_callback=progress_callback
            )
            Clock.schedule_once(lambda dt: self._show_results(results))
        except Exception as e:
            Clock.schedule_once(lambda dt, err=str(e): self._show_error(err))

    def _update_progress_ui(self, status_text: str, percent: float):
        """主线程更新进度条"""
        self.status_label.text = status_text
        self.progress_bar.value = percent

    def _show_results(self, results):
        """测试完成，展示数据"""
        self.start_btn.disabled = False
        self.status_label.text = "测试完成！"
        self.progress_bar.value = 100
        
        kdf_time = results.get("kdf_time", 0)
        speed = results.get("speed_mb_s", 0)
        est_10g = results.get("est_10gb", 0)
        est_50g = results.get("est_50gb", 0)

        # 格式化展示结果
        res_text = (
            f"✅ 测试成功完成\n\n"
            f"• Argon2id 解锁耗时：{kdf_time:.2f} 秒\n"
            f"• 流式加密吞吐量：{speed:.1f} MB/s\n"
            f"• 同步 10GB 约需：{est_10g:.1f} 分钟\n"
            f"• 同步 50GB 约需：{est_50g:.1f} 分钟"
        )
        self.result_text.text = res_text

    def _show_error(self, error_msg):
        self.start_btn.disabled = False
        self.status_label.text = "测试失败"
        self.progress_bar.value = 0
        self.result_text.text = f"❌ 发生错误：\n{error_msg}"
        MDSnackbar(text="测试过程被中断或发生异常").open()

    def go_back(self):
        self.manager.current = "settings"
