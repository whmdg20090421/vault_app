[app]
title = VaultApp
package.name = vaultapp
package.domain = org.vaultapp.v5
source.dir = .
source.include_exts = py,png,jpg,kv,atlas,json

version = 1.0.0

requirements = python3,\
    kivy==2.3.0,\
    kivymd==1.2.0,\
    openssl,\
    libffi,\
    cryptography==38.0.4,\
    webdav4==0.9.8,\
    pyjnius,\
    httpx==0.27.0,\
    httpcore==1.0.5,\
    h11==0.14.0,\
    anyio==4.3.0,\
    sniffio==1.3.1,\
    idna==3.7,\
    certifi==2024.2.2

android.api = 34
android.minapi = 28
android.ndk = 27.3
android.archs = arm64-v8a

# 核心修复：直接指向 Runner 预装路径，完全跳过 Buildozer 的 NDK/SDK 下载逻辑
# Runner 上 NDK 27.3 和 SDK 已预装，无需重复下载
android.ndk_path = /usr/local/lib/android/sdk/ndk/27.3.13750724
android.sdk_path = /usr/local/lib/android/sdk

android.permissions = READ_EXTERNAL_STORAGE,WRITE_EXTERNAL_STORAGE,MANAGE_EXTERNAL_STORAGE,\
    READ_MEDIA_IMAGES,READ_MEDIA_VIDEO,READ_MEDIA_AUDIO,\
    INTERNET,FOREGROUND_SERVICE,FOREGROUND_SERVICE_DATA_SYNC,\
    WAKE_LOCK,POST_NOTIFICATIONS,USE_BIOMETRIC,REQUEST_IGNORE_BATTERY_OPTIMIZATIONS

services = KeepAliveService:core/keepalive.py

android.accept_sdk_license = True

p4a.branch = v2024.01.21


[buildozer]
log_level = 2
warn_on_root = 1