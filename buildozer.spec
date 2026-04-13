[app]
title = VaultApp
package.name = vaultapp
package.domain = org.vaultapp.v5
source.dir = .
source.include_exts = py,png,jpg,kv,atlas,json

# 版本号
version = 1.0.0

# 明确应用需要的 Python 第三方库与打包工具版本 (设计文档 16 节)
requirements = python3,kivy==2.3.0,kivymd==1.2.0,cryptography==42.0.8,webdav4==0.9.8,pyjnius==1.6.1,httpx==0.27.0

# Android 架构与 API 级别 (设计文档 16 节与 11.3 节)
android.api = 34
android.minapi = 28
android.ndk = 25b
android.archs = arm64-v8a

# 极度重要的 Android 权限申请列表 (包含前台保活、通知、SAF 文件读写等)
android.permissions = READ_EXTERNAL_STORAGE,WRITE_EXTERNAL_STORAGE,MANAGE_EXTERNAL_STORAGE,READ_MEDIA_IMAGES,READ_MEDIA_VIDEO,READ_MEDIA_AUDIO,INTERNET,FOREGROUND_SERVICE,FOREGROUND_SERVICE_DATA_SYNC,WAKE_LOCK,POST_NOTIFICATIONS,USE_BIOMETRIC,REQUEST_IGNORE_BATTERY_OPTIMIZATIONS

# 防止应用休眠时被杀死的服务白名单
android.services = KeepAliveService:org.vaultapp.v5.KeepAliveService

# 告诉打包工具使用默认的 Python3
p4a.branch = master

[buildozer]
# 控制台输出日志级别
log_level = 2
warn_on_root = 1
