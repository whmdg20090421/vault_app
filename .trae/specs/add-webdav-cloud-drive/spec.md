# 云盘 WebDAV 配置管理 Spec

## Why
当前“云盘”界面仅展示占位内容，无法接入实际网盘服务。需要在云盘页增加 WebDAV 配置管理能力，便于用户保存并选择自己的 WebDAV 连接信息。

## What Changes
- 在“云盘”界面新增 WebDAV 配置管理 UI：支持新增、列表、编辑、删除。
- 新增 WebDAV 配置持久化：非敏感字段落盘；授权密码使用系统安全存储保存。
- 新增“安全等级检测”与图形化提示：首次绑定/保存时检测当前设备密钥存储能力，并在无法使用硬件后端时以黄色警告提示用户。

## Impact
- Affected specs: 云盘页 UI、设置/主题不受影响、错误记录逻辑不受影响
- Affected code: lib/main.dart（云盘页替换占位页）、新增数据模型与存储模块（lib/ 下）、测试用例更新（test/）

## ADDED Requirements

### Requirement: WebDAV 配置 CRUD
系统 SHALL 在“云盘”页面提供 WebDAV 配置的新增、查看列表、编辑、删除能力。

#### 数据字段
每个 WebDAV 配置 SHALL 包含：
- 配置命名（用户自定义显示名）
- 连接网站（WebDAV 服务 URL）
- 账户名（username）
- 授权密码（password）

#### Scenario: 新增配置（成功）
- **WHEN** 用户进入“云盘”页面并点击“新增 WebDAV”
- **AND** 填写“命名 / URL / 账户名 / 授权密码”并保存
- **THEN** 新配置出现在列表中
- **AND** 重新打开 App 后仍可在列表中看到该配置

#### Scenario: 编辑配置（成功）
- **WHEN** 用户在列表中选择某一配置并进入编辑
- **AND** 修改命名、URL 或账户名并保存
- **THEN** 列表展示更新后的字段
- **AND** 授权密码保持不变，除非用户明确修改

#### Scenario: 删除配置（成功）
- **WHEN** 用户在列表中删除某一配置
- **THEN** 该配置从列表中消失
- **AND** 该配置对应的授权密码也会从安全存储中删除

### Requirement: 本地持久化与敏感信息隔离
系统 SHALL 将 WebDAV 配置拆分存储：
- **非敏感字段**（命名、URL、账户名、内部 ID）存储在应用数据目录的 JSON 文件中。
- **授权密码** SHALL 使用系统安全存储保存，并通过配置 ID 进行索引。

#### Scenario: 数据恢复（成功）
- **WHEN** App 重新启动
- **THEN** 系统从 JSON 文件加载配置列表
- **AND** 在需要展示/使用密码时，通过配置 ID 从安全存储读取对应密码

### Requirement: 两级安全能力检测与图形化提示
系统 SHALL 在用户首次保存 WebDAV 配置时执行“安全能力检测”，并将检测结果用于 UI 图形化提示。

#### 安全等级定义
- **Level 1（强）**：检测到安全存储具备硬件后端能力（例如 TEE/StrongBox 等硬件支持的 Keystore 形态）。
- **Level 2（弱）**：只能使用软件后端的安全存储（无硬件保护）。

#### Scenario: Level 1（成功）
- **WHEN** 用户首次保存配置且检测到 Level 1
- **THEN** 保存成功
- **AND** 在“云盘”页面以“绿色/正常”图形化标识展示 Level 1

#### Scenario: Level 2（降级但允许）
- **WHEN** 用户首次保存配置且检测到 Level 2
- **THEN** 保存成功
- **AND** 在“云盘”页面顶部展示黄色警告横幅
- **AND** 在配置列表或详情处展示“黄色/警告”图形化标识

## MODIFIED Requirements

### Requirement: 云盘页面内容
系统 SHALL 将“云盘”页面从仅展示标题的占位页，替换为可交互的 WebDAV 配置管理页面。

## REMOVED Requirements
无

