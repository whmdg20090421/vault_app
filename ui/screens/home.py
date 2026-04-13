"""
ui/screens/home.py — VaultApp V5 手机端主页

设计规范（V5定稿）：
  · UI 结构：顶部导航栏 + Vault 卡片列表 + 悬浮添加按钮 (FAB)
  · 交互设计：适配手机端拇指操作，长按拖拽（预留接口）
  · Android SAF 整合：点击“+”号唤起原生的系统文件夹选取器
"""

from kivy.metrics import dp
from kivy.uix.screenmanager import Screen
from kivy.uix.scrollview import ScrollView
from kivymd.app import MDApp
from kivymd.uix.boxlayout import MDBoxLayout
from kivymd.uix.toolbar import MDTopAppBar
from kivymd.uix.button import MDFloatingActionButton
from kivymd.uix.list import MDList, TwoLineAvatarIconListItem, IconLeftWidget
from kivymd.uix.snackbar import MDSnackbar

try:
    from jnius import autoclass, cast
    HAS_PYJNIUS = True
except ImportError:
    HAS_PYJNIUS = False


class VaultListItem(TwoLineAvatarIconListItem):
    """自定义的 Vault 列表项卡片"""
    def __init__(self, vault_name, vault_status, on_click_callback, **kwargs):
        super().__init__(**kwargs)
        self.text = vault_name
        self.secondary_text = vault_status
        self.on_click_callback = on_click_callback
        
        # 左侧图标
        icon = IconLeftWidget(icon="folder-lock")
        self.add_widget(icon)

    def on_release(self):
        """点击列表项进入 Vault 浏览器"""
        if self.on_click_callback:
            self.on_click_callback(self.text)


class HomeScreen(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.name = "home"
        self.app = MDApp.get_running_app()
        self.build_ui()

    def build_ui(self):
        # 主布局
        self.layout = MDBoxLayout(orientation="vertical")

        # 1. 顶部应用栏 (App Bar)
        self.top_bar = MDTopAppBar(
            title="我的 Vault",
            anchor_title="left",
            elevation=2,
            right_action_items=[
                ["sync", lambda x: self.go_to_sync(), "查看同步队列"],
                ["cog", lambda x: self.go_to_settings(), "设置"]
            ]
        )
        self.layout.add_widget(self.top_bar)

        # 2. 滑动列表容器 (存放所有的 Vault)
        self.scroll = ScrollView()
        self.vault_list = MDList()
        self.scroll.add_widget(self.vault_list)
        self.layout.add_widget(self.scroll)

        # 3. 悬浮添加按钮 (FAB) - 放在屏幕右下角，最适合手机拇指操作
        self.fab = MDFloatingActionButton(
            icon="plus",
            pos_hint={"right": 0.95, "y": 0.05},
            elevation=3,
            on_release=self.on_fab_click
        )

        # 这里使用一个特殊的技巧：由于 Kivy 的 MDBoxLayout 会自动排列，
        # 为了让 FAB 悬浮在列表之上，我们不用 add_widget 添加到垂直布局，
        # 而是添加一个浮动布局包裹体，或者直接添加到 Screen 本身。
        self.add_widget(self.layout)
        self.add_widget(self.fab)

    def on_enter(self, *args):
        """每次进入主页时刷新列表"""
        self.refresh_vault_list()

    def refresh_vault_list(self):
        """刷新并显示本地已存在的 Vault 列表"""
        self.vault_list.clear_widgets()
        
        # TODO: 实际上这里应从本地数据库/配置读取已保存的 Vault 路径列表。
        # 为了演示切片流程，我们先模拟渲染一个。
        dummy_vault = VaultListItem(
            vault_name="私密文档",
            vault_status="已同步 (今天 14:30)",
            on_click_callback=self.open_vault
        )
        self.vault_list.add_widget(dummy_vault)

    # ═════════════════════════════════════════════════════════════════════════
    # 手机端交互：Android SAF 文件夹选取器
    # ═════════════════════════════════════════════════════════════════════════

    def on_fab_click(self, instance):
        """点击添加按钮，拉起 Android 系统文件夹选取器"""
        if not HAS_PYJNIUS:
            MDSnackbar(text="[PC测试环境] 模拟触发选择文件夹").open()
            # 在电脑上调试时，假装选好了一个目录，跳转去新建向导
            return

        # 在 Android 上，拉起 SAF 框架 (ACTION_OPEN_DOCUMENT_TREE)
        try:
            PythonActivity = autoclass('org.kivy.android.PythonActivity')
            Intent = autoclass('android.content.Intent')
            
            intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            # 允许系统显示高级存储选项
            intent.addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION |
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION |
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
            
            # 使用 REQUEST_CODE_SAF_PICKER = 1001 发起请求
            # 真实环境中，我们需要在 main.py 监听 on_activity_result 接收回调
            PythonActivity.mActivity.startActivityForResult(intent, 1001)
            
            MDSnackbar(text="请在系统中选择一个空文件夹作为 Vault").open()
        except Exception as e:
            MDSnackbar(text=f"无法拉起系统文件管理器: {e}").open()

    # ═════════════════════════════════════════════════════════════════════════
    # 页面路由跳转
    # ═════════════════════════════════════════════════════════════════════════

    def open_vault(self, vault_name):
        """点击卡片，进入该 Vault 的内部文件浏览器"""
        MDSnackbar(text=f"正在打开 {vault_name}...").open()
        # self.manager.current = "vault_browser"

    def go_to_sync(self):
        """跳转到全局同步队列"""
        # self.manager.current = "sync"
        pass

    def go_to_settings(self):
        """跳转到设置"""
        # self.manager.current = "settings"
        pass
