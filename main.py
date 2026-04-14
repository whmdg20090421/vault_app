"""
main.py — VaultApp V5 应用程序主入口 (含全局异常与日志捕获)
"""

import os
import sys
import traceback
from datetime import datetime

# 确保能正确导入当前目录下的 core 和 ui 模块
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

def get_android_external_dir():
    """获取 Android/data/org.vaultapp.v5/files 目录"""
    from kivy.utils import platform
    if platform == 'android':
        try:
            # 使用 jnius 调用安卓原生 API 获取外部私有目录
            from jnius import autoclass
            PythonActivity = autoclass('org.kivy.android.PythonActivity')
            # getExternalFilesDir(None) 会返回类似 /storage/emulated/0/Android/data/org.vaultapp.v5/files 的路径
            file_obj = PythonActivity.mActivity.getExternalFilesDir(None)
            if file_obj:
                return file_obj.getAbsolutePath()
        except Exception as e:
            print(f"获取 Android 目录失败: {e}")
            
        # 如果 jnius 获取失败，提供一个基于你包名的硬编码备用路径
        return "/storage/emulated/0/Android/data/org.vaultapp.v5/files"
    
    # 如果在电脑上运行测试，就保存在当前目录下
    return os.path.dirname(os.path.abspath(__file__))

def main():
    # 1. 确定日志保存目录和文件名
    log_dir = get_android_external_dir()
    
    # 确保目录存在 (虽然 Android 系统通常会自动创建)
    if not os.path.exists(log_dir):
        try:
            os.makedirs(log_dir, exist_ok=True)
        except:
            pass

    log_file = os.path.join(log_dir, "vaultapp_crash.log")

    try:
        # 2. 记录应用开始启动
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(f"\n\n{'='*40}\n")
            f.write(f"🚀 [App Started] {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"{'='*40}\n")

        # 3. 正常启动应用
        from ui.app import MainApp
        MainApp().run()
        
    except Exception as e:
        # 4. 如果遇到任何致命闪退，将错误信息写入文本
        error_msg = traceback.format_exc()
        
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(f"\n❌ [CRASH OCCURRED] {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(error_msg)
            f.write("\n")
            
        # 同时也在控制台打印一份，防止电脑调试时漏看
        print("====== 严重致命错误 ======")
        print(error_msg)
        print(f"日志已保存至: {log_file}")
        print("==========================")

if __name__ == "__main__":
    main()
