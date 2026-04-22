import sys

with open('CHANGELOG.md', 'r') as f:
    content = f.read()

new_entry = """# 版本 1.5.2 (2026-04-22)

### ✨ Features & Security
- **Hardware Crypto**: 引入 cryptography 底层硬件加密库并重构 ChunkCrypto，显著提升加密性能。
- **Adaptive Chunk Size**: 实现基于文件大小的自适应加密块大小算法及 V2 兼容头。
- **Zero-copy Stream**: 优化 EncryptedVfs 流读写，预分配内存以消除拷贝开销。
- **UI Enhancements**: 修复暂停状态恢复异常及在长按菜单中增加删除、重命名选项，并在打开文件夹时增加确认弹窗。
- **Benchmark Fix**: 修复硬件性能基准测试的假完成崩溃 Bug 及测速计算公式。

"""

with open('CHANGELOG.md', 'w') as f:
    f.write(new_entry + content)
