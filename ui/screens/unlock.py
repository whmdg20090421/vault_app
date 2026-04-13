"""
ui/screens/unlock.py — VaultApp V5 解锁页面

设计规范（V5定稿）：
  · UI 结构：锁图标 + 密码框 + 记住密码选项 + 设备保护状态横幅
  · 逻辑要求：
      - 根据 session.py 中的三级降级状态，显示不同颜色横幅
      - 若为第三级（不可用），强制置灰禁用“记住密码”
      - 解密过程需放在独立线程，防 UI 卡死
"""

import threading
from kivy.metrics import dp
from kivy.clock import Clock
from kivy.uix.screenmanager import Screen
from kivymd.app import MDApp
from kivymd.uix.boxlayout import MDBoxLayout
from kivymd.uix.textfield import MDTextField
from kivymd.uix.button import MDRaisedButton
from kivymd.uix.label import MDLabel
from kivymd.uix.selectioncontrol import MDCheckbox
from kivymd.uix.snackbar import MDSnackbar
from kivymd.uix.card import MDCard

from core.session import PROTECTION_LEVEL_HARDWARE, PROTECTION_LEVEL_SOFTWARE, PROTECTION_LEVEL_UNAVAILABLE


class UnlockScreen(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.name = "unlock"
        self.app = MDApp.get_running_app()
        self.build_ui()

    def build_ui(self):
        """使用纯 Python 构建 UI 树（不使用 KV 语言，方便逻辑控制）"""
        # 主容器：垂直居中布局
        main_layout = MDBoxLayout(
            orientation="vertical",
            padding=dp(24),
            spacing=dp(20),
            pos_hint={"center_x": 0.5, "center_y": 0.5},
            size_hint_x=None,
            width=dp(360) # 限制最大宽度，适配平板单列居中
        )

        # 1. 锁图标与大标题
        title_icon = MDLabel(
            text="🔒",
            font_style="H2",
            halign="center",
            size_hint_y=None,
            height=dp(80)
        )
        title_label = MDLabel(
            text="解锁您的 Vault",
            font_style="H5",
            halign="center",
            theme_text_color="Primary",
            size_hint_y=None,
            height=dp(40)
        )

        # 2. 动态生成的设备保护状态横幅 (设计文档 4.2 节)
        self.banner_card = MDCard(
            size_hint_y=None,
            height=dp(60),
            padding=dp(8),
            md_bg_color=self._get_banner_color(),
            radius=[dp(8)]
        )
        banner_text = MDLabel(
            text=self._get_banner_text(),
            theme_text_color="Custom",
            text_color=(1, 1, 1, 1),  # 白色文字
            font_style="Caption",
            halign="center"
        )
        self.banner_card.add_widget(banner_text)

        # 3. 密码输入框
        self.pwd_field = MDTextField(
            hint_text="请输入 Vault 密码",
            password=True,
            icon_left="key-variant",
            size_hint_x=1
        )

        # 4. 记住密码区块
        remember_layout = MDBoxLayout(
            orientation="horizontal",
            size_hint_y=None,
            height=dp(48),
            spacing=dp(8)
        )
        self.remember_chk = MDCheckbox(
            size_hint=(None, None),
            size=(dp(48), dp(48))
        )
        remember_lbl = MDLabel(
            text="记住密码 (24小时)",
            theme_text_color="Secondary",
            valign="center"
        )
        remember_layout.add_widget(self.remember_chk)
        remember_layout.add_widget(remember_lbl)

        # 第三级降级：禁用记住密码
        if self.app.session_manager.protection_level == PROTECTION_LEVEL_UNAVAILABLE:
            self.remember_chk.disabled = True
            remember_lbl.text = "不可用 (当前设备不支持密钥保护)"

        # 5. 解锁按钮
        self.unlock_btn = MDRaisedButton(
            text="解 锁",
            size_hint_x=1,
            height=dp(48),
            font_style="Button",
            on_release=self.on_unlock_click
        )

        # 组装 UI
        main_layout.add_widget(title_icon)
        main_layout.add_widget(title_label)
        main_layout.add_widget(self.banner_card)
        main_layout.add_widget(self.pwd_field)
        main_layout.add_widget(remember_layout)
        main_layout.add_widget(self.unlock_btn)
        
        self.add_widget(main_layout)

    # ═════════════════════════════════════════════════════════════════════════
    # 横幅降级状态判定
    # ═════════════════════════════════════════════════════════════════════════

    def _get_banner_text(self) -> str:
        level = self.app.session_manager.protection_level
        if level == PROTECTION_LEVEL_HARDWARE:
            return "✓ 硬件级密钥保护已启用\n主密钥安全储存于 TEE 芯片中"
        elif level == PROTECTION_LEVEL_SOFTWARE:
            return "⚠️ 软件密钥保护，安全性较低\n若长期开启 USB 调试，建议勿勾选记住密码"
        else:
            return "❌ 当前设备不支持密钥保护\n每次使用需重新输入密码"

    def _get_banner_color(self):
        """返回不同状态的底色 (RGBA)"""
        level = self.app.session_manager.protection_level
        if level == PROTECTION_LEVEL_HARDWARE:
            return (0.2, 0.6, 0.3, 1)  # 绿色
        elif level == PROTECTION_LEVEL_SOFTWARE:
            return (0.8, 0.6, 0.1, 1)  # 黄色
        else:
            return (0.8, 0.2, 0.2, 1)  # 红色

    # ═════════════════════════════════════════════════════════════════════════
    # 解锁操作与防卡死多线程
    # ═════════════════════════════════════════════════════════════════════════

    def on_unlock_click(self, instance):
        """点击解锁按钮"""
        password = self.pwd_field.text.strip()
        if not password:
            MDSnackbar(text="密码不能为空").open()
            return

        # 禁用 UI，防止重复点击
        self.unlock_btn.disabled = True
        self.unlock_btn.text = "解密中，请稍候..."
        self.pwd_field.disabled = True
        self.remember_chk.disabled = True

        # 启动后台线程执行耗时的 KDF (Argon2id)
        threading.Thread(target=self._async_unlock, args=(password,), daemon=True).start()

    def _async_unlock(self, password: str):
        """在后台线程执行底层解密"""
        try:
            # 确定记住密码的时间（规范中默认选项可设为 1440 分钟 = 24小时）
            remember_mins = 1440 if self.remember_chk.active else 0
            
            # 调用我们在 core/vault.py 中写好的核心逻辑
            success = self.app.vault_manager.unlock_vault(password, remember_minutes=remember_mins)
            
            # 使用 Clock.schedule_once 切回主线程更新 UI
            if success:
                Clock.schedule_once(lambda dt: self._unlock_success())
        except Exception as e:
            # 捕获我们在 vault.py 中抛出的 MetaTamperedError 或密码错误
            Clock.schedule_once(lambda dt, err=str(e): self._unlock_failure(err))

    def _unlock_success(self):
        """解锁成功，恢复 UI 并跳转主页"""
        self._reset_ui_state()
        self.pwd_field.text = "" # 清空密码框防泄露
        
        MDSnackbar(text="解锁成功").open()
        
        # 切换到下一步要写的主界面
        # self.manager.current = "home" 

    def _unlock_failure(self, error_msg: str):
        """解锁失败，弹窗提示并恢复 UI"""
        self._reset_ui_state()
        MDSnackbar(text=f"解锁失败: {error_msg}").open()

    def _reset_ui_state(self):
        """恢复按钮和输入框的可用状态"""
        self.unlock_btn.disabled = False
        self.unlock_btn.text = "解 锁"
        self.pwd_field.disabled = False
        if self.app.session_manager.protection_level != PROTECTION_LEVEL_UNAVAILABLE:
            self.remember_chk.disabled = False
