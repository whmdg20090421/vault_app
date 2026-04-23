# 计划：优化数据存储格式与云盘同步目录选择

## 摘要
本计划旨在解决以下三个核心问题：
1. **重构 `local_index.json` 的 JSON 格式与遍历顺序**：废弃此前的嵌套树结构，改用带有深度优先（DFS）严格排序的**平铺路径键值对**结构。保证顶部为其他信息，新增 `目录` 字段；在 `目录` 中，键为完整绝对路径，值为对应信息。**必须实现自定义 JSON 编码器，以保证每个文件和每个文件夹对应的键值对独占一行，不产生多行换行**。
2. **将 `.vault_manifest` 升级为相同的格式并加密**：取消对该文件的隐藏，将其格式与 `local_index.json` 保持完全一致（包含 `目录` 与单行键值对），并以加密流写入磁盘。用户在客户端点击它时，能在内存中解密并调用第三方应用查看。
3. **复用云盘文件浏览作为同步目录选择器**：弃用 `VfsFolderPickerDialog`，直接复用 `WebDavBrowserPage` 及其文件浏览体系，以全屏路由的模式作为目录选择器。

## 拟议变更

### 1. 提取自定义 DFS 排序与单行 JSON 编码器
**文件**：`lib/utils/dfs_format_utils.dart` (新建)
**操作**：
- **`sortAndFillDFS(Map<String, dynamic> flatMap)`**：
  - 将平铺的 Map 解析为内存树，然后进行 DFS 遍历。
  - **遍历规则**：在同级目录下，先输出所有文件夹，再输出所有文件；按字母顺序排序。
  - **输出结果**：返回一个 `LinkedHashMap<String, dynamic>`，其键的插入顺序严格等于上述遍历顺序。即使原始数据中没有记录文件夹，该算法也会自动补齐并生成文件夹对应的路径键（值为 `{"isDirectory": true}`）。
- **`customJsonEncode(Map<String, dynamic> otherContent, Map<String, dynamic> directoryContent)`**：
  - 手动拼接 JSON 字符串。
  - 将 `otherContent` 写入顶层。
  - 写入 `"目录": {`。
  - 遍历 `directoryContent` 的 `LinkedHashMap`，使用 `jsonEncode(value)` 将值压缩为单行字符串，并与键拼接：`"  \"/A/a\": {\"size\": 123},"`。
  - **确保绝对的“每个文件/文件夹独占一行”**，极大提高人类可读性。

### 2. 应用新格式至 `local_index.json`
**文件**：`lib/encryption/services/local_index_service.dart`
**操作**：
- 在 `saveLocalIndex` 中，调用 `DfsFormatUtils.sortAndFillDFS` 处理传入的数据。
- 构建 `otherContent` 包含 metadata 等，调用 `DfsFormatUtils.customJsonEncode` 生成最终的单行格式 JSON 并写入。
- 在 `getLocalIndex` 中，兼容读取。若发现顶层存在 `目录` 键，则解析其内容，并过滤掉仅含 `isDirectory` 的补齐文件夹条目，返回真实的平铺数据。

### 3. 应用新格式至 `.vault_manifest` 及其加密解密
**文件**：`lib/vfs/encrypted_vfs.dart`
**操作**：
- **取消隐藏**：在 `list()` 的过滤条件中移除 `realNode.name == '.vault_manifest'`。
- **格式化并加密**：在 `_saveManifest()` 中，同样使用 `DfsFormatUtils` 生成新格式的单行 JSON。判断如果根目录被加密，则对该 JSON 字节流进行 `_encryptStream` 加密后再写入；否则明文写入。
- **兼容加载**：在 `_loadManifest()` 中，先读取物理文件头部 25 字节。若检测到 `T_VAULT` 魔数，调用 `this.open(_manifestPath)` 在内存中解密流；否则按旧版明文读取。读取成功后若为旧版，则立即触发异步 `_saveManifest()` 将其转换为加密版。解析时兼容 `"目录"` 键。
- **防止死循环**：在 `open()` 头部加入 `if (path == _manifestPath && !_manifestLoaded) await _loadManifest();`。

### 4. 升级同步目录选择器 UI
**文件**：`lib/cloud_drive/webdav_browser_page.dart`
**操作**：
- 新增 `final bool isPickingFolder;` 参数。
- 若 `isPickingFolder == true`，隐藏列表右侧的操作菜单（`PopupMenuButton`）。
- 底部显示 `FloatingActionButton.extended`，文案为“选择此文件夹”，点击时执行 `Navigator.pop(context, _currentPath)`。

**文件**：`lib/cloud_drive/sync_config_page.dart`
**操作**：
- `_selectRemoteFolder()` 改为 `Navigator.push` 唤起 `WebDavBrowserPage(config: _selectedWebDav!, isPickingFolder: true)`。

## 验证步骤
1. 打开云盘的“同步配置”页，点击选择目录，验证是否全屏弹出与云盘文件浏览完全一致的页面，且能正常点击浏览，底部有确认按钮。
2. 观察加密保险箱首页，验证 `.vault_manifest` 已出现。点击它，验证能被解密并在外部文本编辑器中打开。
3. 检查打开的 `.vault_manifest` 和 `local_index.json`，确认顶层有 `目录` 对象，且其内部**严格按照 DFS 顺序（文件夹在前，文件在后），并且每一条路径独占一行（没有多行换行）**。
