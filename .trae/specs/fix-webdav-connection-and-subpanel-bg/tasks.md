# Tasks
- [ ] Task 1: 实现 WebDAV 错误日志记录：在 WebDAV 服务中添加全局异常捕获，将报错信息写入 `/storage/emulated/0/Android/data/com.tianyanmczj.vault/files/webdav_error_log.txt`。
- [ ] Task 2: 修复 WebDAV 具体文件连接问题：修正 WebDAV 客户端中对具体文件路径的处理和请求构造，确保能够正确发起请求。
- [ ] Task 3: 本地 401 验证：在本地执行测试代码，尝试连接 WebDAV 并验证是否成功返回 401 权限不足错误。
- [ ] Task 4: 修复子面板背景闪烁问题：排查并修改各子页面（如“关于”页面）的 Scaffold 背景色设置，确保其透明，并保证全局背景图在路由切换时不会被卸载或重绘。

# Task Dependencies
- [Task 3] depends on [Task 2]