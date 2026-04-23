# 计划：优化数据存储格式与云盘同步目录选择

## 摘要
本计划旨在解决以下三个核心问题：
1. **确认与兼容 `local_index.json` 树状结构**：确保刚刚对 `local_index.json` 的修改（将其转换为格式化并带换行的嵌套树结构）能被全局读取和兼容。
2. **将 `.vault_manifest` 升级为带换行的树状结构并加密**：将保险箱中的关键记录文件 `.vault_manifest` 解除隐藏，使其以加密形式存储在物理磁盘中。并且保证当在客户端中点击该文件时，能够在内存中自动解密并使用第三方应用预览，其内部 JSON 格式必须同样为带缩进、每个文件或文件夹独占一行的树状结构，以便人类阅读。
3. **复用云盘文件浏览作为同步目录选择器**：弃用底部弹出的简陋 `VfsFolderPickerDialog` 目录选择器，改为直接调用现有的 `WebDavBrowserPage`（云盘文件浏览页），通过传入参数使其变身为与原版完全一致的“全屏目录选择器”，从而解决“浏览文件正常但选择目录却异常/不一致”的问题。

## 当前状态分析
- **`local_index.json`**：在之前的修改中已应用 `JsonEncoder.withIndent('  ')` 及自研的 `_flatToTree` / `_treeToFlat`，已经完全实现了树状层级和提行（每项一行）的需求。目前的解析代码兼容旧版与新版 V2 格式。
- **`.vault_manifest`**：目前被隐藏于 `EncryptedVfs.list` 的黑名单中，且物理磁盘上存储的是一段未加密的扁平化 JSON 字节流。这导致它不支持安全存储且不具备人类可读性。
- **同步目录选择器**：目前在 `sync_config_page.dart` 中使用的是一个弹窗对话框 `VfsFolderPickerDialog`。由于它通过 `StandardVfs.list` 拉取数据并过滤了文件点击事件，体验与完整的 `WebDavBrowserPage` 割裂，容易引发路径斜杠导致的读取异常或认知困惑。

## 拟议变更

### 1. 提取树状格式化工具类
**文件**：`lib/utils/tree_format_utils.dart` (新建)
**操作**：
- 将 `local_index_service.dart` 中私有的 `_flatToTree` 与 `_treeToFlat` 提取为公共静态方法 `TreeFormatUtils.flatToTree` 和 `treeToFlat`。
- 修改 `treeToFlat`，使其能够正确识别 `isDirectory`、`chunkSize` 等属于 `.vault_manifest` 的叶子节点属性。

### 2. 兼容 `local_index.json`
**文件**：`lib/encryption/services/local_index_service.dart`
**操作**：
- 引入并使用新提取的 `TreeFormatUtils` 替代原有的私有方法。
- 确认 `JsonEncoder.withIndent('  ')` 逻辑完好，它原生支持提行和标准的 JSON 大括号换行包裹，符合用户“每一个都要提行”的期望。

### 3. 重构 `.vault_manifest` 存储与加解密流程
**文件**：`lib/vfs/encrypted_vfs.dart`
**操作**：
- **取消隐藏**：在 `list()` 方法的过滤条件中移除 `realNode.name == '.vault_manifest'`，让用户在保险箱中能直接看到该文件。
- **保存时格式化并加密**：在 `_saveManifest()` 方法中，将平铺的 `_manifestEntries` 使用 `TreeFormatUtils.flatToTree` 转换为树状，标记 `version: 2`，然后用 `JsonEncoder.withIndent('  ')` 转为带提行的可读字符串。随后使用 `_encryptStream` 手动加密这些字节流再写入物理磁盘。
- **读取时兼容解密**：在 `_loadManifest()` 方法中，先读取物理文件前 25 个字节，若匹配到魔数 `T_VAULT`，则调用内部的 `this.open(_manifestPath)` 进行内存流式解密；若未匹配到，则按旧版本明文读取，并在读取成功后立即触发升级覆盖（保存为加密版）。
- **解决循环依赖**：在 `open()` 方法的头部添加 `if (path != _manifestPath) await _loadManifest();`，防止 `_loadManifest` 在调用 `this.open` 时陷入死循环。

### 4. 升级同步目录选择器 UI
**文件**：`lib/cloud_drive/webdav_browser_page.dart`
**操作**：
- 在构造函数中新增 `final bool isPickingFolder;` 参数（默认为 `false`）。
- 在构建 UI 时，如果 `isPickingFolder` 为 `true`，则在文件列表的右侧隐藏长按/点击的操作菜单（`PopupMenuButton`）。
- 底部新增悬浮按钮 `FloatingActionButton.extended`，文案为“选择此文件夹”，点击时触发 `Navigator.pop(context, _currentPath)` 返回当前选中的路径。

**文件**：`lib/cloud_drive/sync_config_page.dart`
**操作**：
- 在 `_selectRemoteFolder()` 方法中，废弃原来的 `showDialog<String>(builder: (_) => VfsFolderPickerDialog(...))`。
- 替换为全屏路由跳转 `Navigator.push<String>(..., MaterialPageRoute(builder: (_) => WebDavBrowserPage(config: _selectedWebDav!, isPickingFolder: true)))`。

## 假设与决策
- **假设**：用户所指的“其他应用打开”是基于已经实现的 `VaultExplorerPage` 中的 `_previewFile` 逻辑（它会将 `vfs.open()` 流式解密的数据写入系统临时缓存目录，然后调用系统 API `OpenFilex.open` 唤起外部应用）。由于该逻辑已十分成熟，因此只要我们让 `vfs.open()` 能够解密并吐出 `.vault_manifest` 的明文，外部打开需求就自然达成了。
- **决策**：为了不破坏现有的旧版明文 `.vault_manifest`，在加载解析时加入了无缝平滑升级（Migration）机制，一旦检测到老版文件，读取后会自动将其重写为新的加密树状格式。

## 验证步骤
1. 打开云盘的“同步配置”页，点击选择目录，验证是否全屏弹出了与云盘文件浏览一致的页面，且底部带有“选择此文件夹”的确认按钮。
2. 观察加密保险箱首页，验证原本被隐藏的 `.vault_manifest` 文件是否已出现在列表中。
3. 点击 `.vault_manifest` 文件，验证系统是否能够自动在内存中解密，并弹出第三方文本编辑器供你阅读。
4. 在文本编辑器中查看该文件，确认其 JSON 格式是否呈树状结构、并且“大括号换行，每个文件独占一行（提行）”。
5. 检查本地日志与运行状态，确认 `local_index.json` 是否也完全保持了提行的格式兼容性，没有发生解析崩溃。