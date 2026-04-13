[app]
title = VaultApp
package.name = vaultapp
package.domain = org.vaultapp.v5
source.dir = .
source.include_exts = py,png,jpg,kv,atlas,json

# 版本号
version = 1.0.0

# 修复 1：补全 httpx 完整依赖链（httpcore/h11/anyio/sniffio/idna/certifi）
# 修复 2：降级 cryptography 到 38.0.4，移除 setuptools-rust，完美兼容 p4a 的 C 交叉编译配方
requirements = python3,kivy==2.3.0,kivymd==1.2.0,openssl,libffi,cryptography==38.0.4,webdav4==0.9.8,pyjnius,httpx==0.27.0,httpcore==1.0.5,h11==0.14.0,anyio==4.3.0,sniffio==1.3.1,idna==3.7,certifi==2024.2.2

# Android 架构与 API 级别
android.api = 34
android.minapi = 28
android.ndk = 25b
android.archs = arm64-v8a

# 权限申请列表
android.permissions = READ_EXTERNAL_STORAGE,WRITE_EXTERNAL_STORAGE,MANAGE_EXTERNAL_STORAGE,READ_MEDIA_IMAGES,READ_MEDIA_VIDEO,READ_MEDIA_AUDIO,INTERNET,FOREGROUND_SERVICE,FOREGROUND_SERVICE_DATA_SYNC,WAKE_LOCK,POST_NOTIFICATIONS,USE_BIOMETRIC,REQUEST_IGNORE_BATTERY_OPTIMIZATIONS

# 后台保活服务
services = KeepAliveService:core/keepalive.py

# 自动接受 SDK 协议
android.accept_sdk_license = True

# 修复 3：锁定 p4a 到稳定的 release tag，避免 master 分支的潜在波动
p4a.branch = v2024.01.21

[buildozer]
log_level = 2
warn_on_root = 1
