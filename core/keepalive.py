"""
core/keepalive.py — VaultApp V5 Android 前台服务与保活模块

设计规范（V5定稿）：
  · 申请并持有 WakeLock，防止设备休眠导致同步中断
  · 弹出并维护持久通知栏（前台服务标识）
  · 引导用户将电池优化设置为“无限制”
  · 优雅降级：在非 Android 系统（PC 调试）时静默放行
"""

import os

try:
    from jnius import autoclass, cast
    HAS_PYJNIUS = True
except ImportError:
    HAS_PYJNIUS = False

class KeepAliveManager:
    def __init__(self):
        self._wake_lock = None
        self._is_active = False
        
        # Android 常量
        self.NOTIFICATION_ID = 550  # 随意的唯一ID
        self.CHANNEL_ID = "vault_sync_channel"
        self.CHANNEL_NAME = "VaultApp 同步服务"
        
        # 缓存 Android 类引用
        if HAS_PYJNIUS:
            self.PythonActivity = autoclass('org.kivy.android.PythonActivity')
            self.Context = autoclass('android.content.Context')
            self.PowerManager = autoclass('android.os.PowerManager')
            self.Intent = autoclass('android.content.Intent')
            self.Uri = autoclass('android.net.Uri')
            self.Settings = autoclass('android.provider.Settings')
            self.NotificationManager = autoclass('android.app.NotificationManager')
            self.NotificationChannel = autoclass('android.app.NotificationChannel')
            # 兼容 AndroidX
            self.NotificationCompatBuilder = autoclass('androidx.core.app.NotificationCompat$Builder')

    # ═════════════════════════════════════════════════════════════════════════
    # 电池优化管理
    # ═════════════════════════════════════════════════════════════════════════

    def is_ignoring_battery_optimizations(self) -> bool:
        """检查用户是否已经允许 App 忽略电池优化（无限制）"""
        if not HAS_PYJNIUS:
            return True # PC 环境默认返回 True
            
        context = self.PythonActivity.mActivity
        if not context:
            return True
            
        pm = cast('android.os.PowerManager', context.getSystemService(self.Context.POWER_SERVICE))
        # Android 6.0 (API 23) 引入的 API
        return pm.isIgnoringBatteryOptimizations(context.getPackageName())

    def request_ignore_battery_optimizations(self):
        """跳转到系统设置，引导用户关闭电池优化"""
        if not HAS_PYJNIUS:
            return
            
        context = self.PythonActivity.mActivity
        if not context:
            return
            
        intent = self.Intent()
        intent.setAction(self.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
        intent.setData(self.Uri.parse(f"package:{context.getPackageName()}"))
        context.startActivity(intent)

    # ═════════════════════════════════════════════════════════════════════════
    # WakeLock 与 通知栏保活生命周期
    # ═════════════════════════════════════════════════════════════════════════

    def start_sync_keepalive(self, title: str = "VaultApp 同步中", text: str = "准备扫描文件..."):
        """
        开始同步时调用：获取 WakeLock 并显示通知。
        （配合 Buildozer 中的 FOREGROUND_SERVICE_DATA_SYNC 权限）
        """
        if not HAS_PYJNIUS or self._is_active:
            return
            
        context = self.PythonActivity.mActivity
        if not context:
            return

        try:
            # 1. 申请 WakeLock 防休眠
            pm = cast('android.os.PowerManager', context.getSystemService(self.Context.POWER_SERVICE))
            # PARTIAL_WAKE_LOCK 允许息屏，但保持 CPU 运转
            self._wake_lock = pm.newWakeLock(self.PowerManager.PARTIAL_WAKE_LOCK, "VaultApp::SyncWakeLock")
            self._wake_lock.acquire()

            # 2. 创建通知渠道 (Android 8.0+)
            notification_manager = cast('android.app.NotificationManager', context.getSystemService(self.Context.NOTIFICATION_SERVICE))
            channel = self.NotificationChannel(self.CHANNEL_ID, self.CHANNEL_NAME, self.NotificationManager.IMPORTANCE_LOW)
            notification_manager.createNotificationChannel(channel)

            # 3. 创建并发送持久通知
            # 注意：在真实的 Kivy Service 中，我们会调用 startForeground()，
            # 但作为轻量级唤醒，在主 Activity 中推送一个 Ongoing(不可滑动删除) 的通知配合 WakeLock 同样有效
            builder = self.NotificationCompatBuilder(context, self.CHANNEL_ID)
            # android.R.drawable.stat_notify_sync 是系统自带的同步图标
            icon_id = context.getResources().getIdentifier("stat_notify_sync", "drawable", "android")
            
            builder.setContentTitle(title)
            builder.setContentText(text)
            builder.setSmallIcon(icon_id)
            builder.setOngoing(True) # 持久化，禁止用户手动划掉
            
            notification_manager.notify(self.NOTIFICATION_ID, builder.build())
            
            self._is_active = True
        except Exception as e:
            print(f"启动 Android 保活失败: {e}")

    def update_notification(self, title: str, text: str):
        """
        更新通知栏上的进度文本，例如：
        "VaultApp 同步中 | 45/200 文件 | 2.3 MB/s"
        """
        if not HAS_PYJNIUS or not self._is_active:
            return
            
        context = self.PythonActivity.mActivity
        if not context:
            return

        try:
            notification_manager = cast('android.app.NotificationManager', context.getSystemService(self.Context.NOTIFICATION_SERVICE))
            builder = self.NotificationCompatBuilder(context, self.CHANNEL_ID)
            icon_id = context.getResources().getIdentifier("stat_notify_sync", "drawable", "android")
            
            builder.setContentTitle(title)
            builder.setContentText(text)
            builder.setSmallIcon(icon_id)
            builder.setOngoing(True)
            
            # 使用同一个 NOTIFICATION_ID，实现原地刷新，不会叮咚响
            notification_manager.notify(self.NOTIFICATION_ID, builder.build())
        except Exception as e:
            pass

    def stop_sync_keepalive(self):
        """
        同步完成或暂停时调用：释放 WakeLock 并取消通知。
        """
        if not HAS_PYJNIUS or not self._is_active:
            return
            
        context = self.PythonActivity.mActivity
        if not context:
            return

        try:
            # 1. 释放 WakeLock 让设备可以正常休眠，省电
            if self._wake_lock and self._wake_lock.isHeld():
                self._wake_lock.release()
                self._wake_lock = None

            # 2. 取消通知栏
            notification_manager = cast('android.app.NotificationManager', context.getSystemService(self.Context.NOTIFICATION_SERVICE))
            notification_manager.cancel(self.NOTIFICATION_ID)
            
            self._is_active = False
        except Exception as e:
            print(f"停止 Android 保活失败: {e}")
