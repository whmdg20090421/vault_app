"""
ui/components/progress_card.py — 独立封装的进度条卡片组件
"""
from kivy.metrics import dp
from kivymd.uix.card import MDCard
from kivymd.uix.label import MDLabel
from kivymd.uix.progressbar import MDProgressBar

class ProgressCard(MDCard):
    """
    可复用的进度条卡片，适用于性能测试页和同步页。
    """
    def __init__(self, title_text="进度", **kwargs):
        super().__init__(**kwargs)
        self.orientation = "vertical"
        self.padding = dp(16)
        self.size_hint_y = None
        self.height = dp(120)
        self.radius = [dp(12)]
        self.elevation = 2

        self.title_label = MDLabel(
            text=title_text,
            font_style="Subtitle1",
            size_hint_y=None,
            height=dp(30)
        )
        self.progress_bar = MDProgressBar(
            value=0, max=100, size_hint_y=None, height=dp(10)
        )
        self.status_label = MDLabel(
            text="等待中...",
            theme_text_color="Secondary",
            font_style="Caption",
            size_hint_y=None,
            height=dp(30)
        )

        self.add_widget(self.title_label)
        self.add_widget(self.progress_bar)
        self.add_widget(self.status_label)

    def update(self, percent: float, status_text: str):
        """更新进度与文本"""
        self.progress_bar.value = percent
        self.status_label.text = status_text
