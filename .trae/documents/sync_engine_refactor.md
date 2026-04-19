# WebDAV 同步引擎重构计划 (Sync Engine Refactor Plan)

## 1. 摘要 (Summary)
重构现有的 WebDAV 同步引擎，彻底移除原先基于 `remote_index.json`（云端索引）与 `local_index.json`（本地索引）强绑定的识别标识机制。
新的同步机制将：
1. **拥抱云盘原生能力**：每次检查同步时，直接使用 WebDAV 原生的 `PROPFIND` 命令获取云端文件夹及其子文件的最新信息（修改时间和大小）。
2. **精简本地索引**：本地索引文件 (`local_index.json`) 将严格且规范地仅记录本地文件的 **大小 (size)**、**修改时间 (updatedAt)** 以及 **哈希值 (hash)**。
3. **精准的差异比对 (Diffing) 算法**：
   - 若本地文件与云端文件**大小不同**，则一定判定为文件已被修改。
   - 若大小相同但**时间不同**，则进行哈希值运算。若哈希匹配，则视为同一文件；否则视为不同文件。
4. **智能的移动/复制检测**：当同时发现本地文件有新增和删除时，优先处理新增文件，通过其哈希值在原本的库（本地索引）中查找。若找到相同的哈希，则判定为**复制**或**移动**，并直接调用 WebDAV 原生的 `COPY` 或 `MOVE` 命令在云端完成操作，避免重新上传。随后再处理剩余的删除操作。
5. **灵活的同步方向**：在配置页面新增“双向同步”选项，允许用户自由选择“本地到云端”、“云端到本地”或“双向同步”，并支持精确到具体的文件夹。

## 2. 当前状态分析 (Current State Analysis)
- **过度依赖云端缓存**：`lib/cloud_drive/webdav_new/sync_engine.dart` 中的 `_syncRecursive` 方法强依赖下载和上传 `remote_index.json`，这不仅不符合 WebDAV 的常规使用方式，还极易引发多设备同步时的冲突和一致性问题。
- **本地索引结构有待规范**：`LocalIndexService` 存在，但未充分利用其来记录历史状态以辅助推断“移动/复制”操作。
- **缺乏移动/复制优化**：目前本地移动一个文件，会被当作“删除旧文件”和“上传新文件”处理，造成严重的带宽和时间浪费。
- **比对逻辑简陋**：现有的比对逻辑仅简单比较时间戳和大小，未根据“时间不同则进行哈希校验”的精准策略进行优化。
- **方向限制**：`SyncDirection` 枚举和 UI 仅支持 `cloudToLocal` 和 `localToCloud`，缺少 `twoWay`（双向同步）。

## 3. 具体修改方案 (Proposed Changes)

### 3.1 修改同步模型与 UI 配置
**文件**: `lib/models/sync_task.dart`
- **操作**: 在 `SyncDirection` 枚举中新增 `twoWay`（双向同步）。

**文件**: `lib/cloud_drive/sync_config_page.dart`
- **操作**: 在步骤 4（同步选项）的“同步方向”中，添加一个 `RadioListTile`，提供“双向同步 (Two-Way)”选项，让用户可以自由选择具体的本地文件夹与云盘文件夹进行双向同步。

### 3.2 规范化本地索引服务
**文件**: `lib/encryption/services/local_index_service.dart`
- **操作**:
  - 确保 `local_index.json` 的记录极其规范。每条记录的 Key 为文件相对路径，Value 仅包含：`size`（大小）、`updatedAt`（修改时间，必须是准确的 Last-Modified），以及 `hash`（SHA-256）。
  - 提供方法用于查询某哈希值是否存在于历史记录中，以辅助 `SyncEngine` 判断复制或移动。

### 3.3 扩展 WebDAV Service API
**文件**: `lib/cloud_drive/webdav_new/webdav_service.dart`
- **操作**: 增加 `move(String source, String destination)` 和 `copy(String source, String destination)` 方法，底层调用 `client.request` 发送 `MOVE` 和 `COPY` HTTP 方法，并附带 `Destination` Header。

### 3.4 彻底重构 Sync Engine (核心核心)
**文件**: `lib/cloud_drive/webdav_new/sync_engine.dart`
- **操作**:
  1. **移除旧索引逻辑**: 删掉所有关于 `remote_index_cache.json` 的下载、解析、比对、上传和冲突校验代码。
  2. **读取本地历史状态**: 在同步开始前，通过 `LocalIndexService` 加载上一时刻的 `local_index.json`。
  3. **扫描当前本地文件**: 遍历本地目录，获取当前的实际文件列表。与 `local_index.json` 比对，计算出本地的 **新增集 (Added)** 和 **删除集 (Deleted)**。
  4. **处理移动与复制 (WebDAV 原生优化)**:
     - 遍历**新增集**中的文件，计算其哈希值。
     - 在 `local_index.json` (原本的库) 中寻找是否具有相同哈希的记录。
     - 若找到匹配项，且该匹配项在**删除集**中，判定为 **移动 (MOVE)**。执行 WebDAV `MOVE` 命令，并将该文件从新增集和删除集中剔除。
     - 若找到匹配项，但该匹配项不在删除集中（即原文件仍在），判定为 **复制 (COPY)**。执行 WebDAV `COPY` 命令，并将该文件从新增集中剔除。
  5. **PROPFIND 获取云端状态**: 调用 `service.readDir` (PROPFIND) 获取云端当前的文件树、大小及修改时间。
  6. **精准差异比对**:
     - 比较云端文件与本地剩余文件。
     - **判定规则**: 若大小不同 -> 不同文件（一定修改）。若大小相同但时间不同 -> 进行哈希值运算匹配，哈希不同 -> 不同文件，哈希相同 -> 相同文件（忽略时间差异或仅更新本地索引时间）。
  7. **执行最终的同步方向逻辑**:
     - 根据用户选择的同步方向（本地到云端、云端到本地、双向同步），以及文件的最新修改时间，将剩余的上传、下载、删除任务加入并发队列 (`_executeConcurrently`)。
  8. **更新并保存规范的本地索引**: 同步结束后，重新扫描本地目录，将最新的 `size`、`updatedAt` 和 `hash` 规范地保存回 `local_index.json`。

## 4. 假设与决策 (Assumptions & Decisions)
- **WebDAV 服务器支持**: 假设用户连接的 WebDAV 服务器（如 Aliyun, Nutstore, Nextcloud）均标准支持 `MOVE` 和 `COPY` 动词。若不支持，需在网络请求抛出异常时回退到先下载/再上传的兜底策略（本阶段优先保证原生命令调用）。
- **哈希算法**: 继续沿用 SHA-256 作为文件哈希比对的标准。
- **废弃数据的处理**: 云端如果残留了以前版本的 `remote_index.json`，在新的逻辑中会被当成普通文件或直接忽略，不再产生副作用。

## 5. 验证步骤 (Verification Steps)
1. **新建任务**: 进入 App 新建同步任务，确认可以选择“双向同步”。
2. **纯净同步**: 执行一次同步，检查云端是否**不再生成** `remote_index.json`。检查本地保险箱目录下是否规范生成了包含 size、updatedAt、hash 的 `local_index.json`。
3. **差异比对测试**: 在本地修改一个文件的大小，执行同步，验证其被判定为修改并重新上传。将一个文件的修改时间篡改（例如使用 `touch` 命令）但不改变内容，执行同步，验证系统会进行哈希计算并最终判定为相同文件，跳过上传。
4. **移动优化测试**: 在本地新建文件夹，将某个大文件移动进去。执行同步，通过抓包或日志观察到调用了 `MOVE` 命令而非 `PUT`。验证同步瞬间完成，且旧文件被正确移除。