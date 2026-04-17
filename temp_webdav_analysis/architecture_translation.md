# WebDAV 架构解析与 Flutter 重构思路 (基于 webdav-js)

## 1. 整体架构分析 (Architecture Overview)

`webdav-js` (作者 dom111 / perry-mitchell) 是一个非常成熟的基于 Node.js/Browser 的 WebDAV 客户端。通过分析其源码（主要位于 `source/` 目录），其核心架构可以划分为以下几个层次，这为我们使用 Dart/Flutter 重构提供了极好的参考模板：

### 1.1 Context / Configuration (上下文与配置层)
- **实现机制**：在 `factory.ts` 中，`createClient` 函数并没有实例化一个复杂的庞大 Class，而是创建了一个 `WebDAVClientContext` 对象（包含了 `remoteURL`, `headers`, `authType`, `username`, `password`, `parsing` 等）。
- **设计思路**：将所有状态（如当前请求头、认证信息、URL基路径）内聚在一个轻量级的 Context 对象中。
- **Dart 映射**：我们可以定义一个 `WebDavContext` 类，或者直接让 `WebDavClient` 内部持有一个不可变的配置对象。

### 1.2 Authentication Layer (认证层)
- **实现机制**：在 `auth/` 目录下，主要支持 Basic Auth、Digest Auth 以及 OAuth2 Token。
- **请求拦截**：在 `request.ts` 中，`requestAuto` 函数会先尝试普通请求，如果遇到 `401` 并且是 Digest Auth，会自动进行质询响应。
- **Dart 映射**：使用 `Dio` 拦截器 (`Interceptor`)。我们可以编写一个 `BasicAuthInterceptor`（因为绝大多数国内网盘如 123pan、坚果云都只使用 Basic Auth），在 `onRequest` 中自动添加 `Authorization: Basic XXX`。

### 1.3 Request Transport Layer (请求传输层)
- **实现机制**：`request.ts` 封装了底层的 `fetch`，统一处理 Headers 的合并、Data 到 Body 的转换以及 Agent 的挂载。
- **Dart 映射**：直接使用 `Dio` 的实例。我们将所有底层的 HTTP 动词 (`PROPFIND`, `MKCOL`, `PUT`, `GET`, `MOVE`, `COPY`, `DELETE`) 封装在 `WebDavClient` (或 `WebDavTransport`) 中。

### 1.4 Operations / Business Logic (业务操作层)
- **实现机制**：在 `operations/` 目录下，每个 HTTP 动词都被拆分成了独立的函数（例如 `directoryContents.ts`, `createDirectory.ts`, `putFileContents.ts`）。它们接收 `Context`，发起 `request`，然后处理响应。
- **Dart 映射**：在我们的项目中，可以将这些映射为 `WebDavService` 里的独立异步方法，如 `readDir(String path)`, `mkdir(String path)`, `upload(...)`, `download(...)`。

### 1.5 XML Parsing & Data Mapping (协议解析与数据映射层)
- **实现机制**：`tools/dav.ts` 使用了 `fast-xml-parser`。WebDAV 的核心在于解析 `PROPFIND` 返回的 `<D:multistatus>` 和 `<D:response>`。
- **核心提取**：
  - `href`: 文件的相对路径
  - `getlastmodified`: 修改时间
  - `getcontentlength`: 文件大小
  - `resourcetype`: 如果包含 `<D:collection/>` 则为目录，否则为文件
  - `getetag`: 文件指纹
- **Dart 映射**：我们将使用 `xml` 包（`package:xml/xml.dart`）。创建一个 `WebDavParser` 类，专门负责将 XML 字符串映射为我们的 `WebDavFile` 实体类。

---

## 2. 针对 Dart/Flutter 的重构设计 (Refactoring Design for Dart)

根据以上分析，结合 Flutter 和 Dio 的最佳实践，我们应该采用**Service / Parser / Client 三层架构**：

### 2.1 核心数据结构 (`WebDavFile`)
对应 `webdav-js` 中的 `FileStat`。
```dart
class WebDavFile {
  final String path;       // href (需 URL decode)
  final String name;       // basename
  final bool isDirectory;  // 根据 resourcetype 判定
  final int size;          // getcontentlength
  final DateTime? lastModified; // getlastmodified
  final String? eTag;      // getetag
}
```

### 2.2 协议解析器 (`WebDavParser`)
对应 `tools/dav.ts`。
```dart
class WebDavParser {
  static List<WebDavFile> parsePropFindResponse(String xmlStr) {
    // 1. 解析 <D:multistatus>
    // 2. 遍历 <D:response>
    // 3. 提取 <D:href>
    // 4. 进入 <D:propstat> -> <D:prop> 提取元数据
    // 5. 过滤掉自身 (请求的目录本身也会在结果中)
  }
}
```

### 2.3 底层通信客户端 (`WebDavClient`)
对应 `request.ts`。
封装 Dio，处理特殊的 HTTP 方法。
```dart
class WebDavClient {
  final Dio _dio;
  
  // 提供通用的 request 接口，支持自定义 method (如 PROPFIND, MKCOL)
  Future<Response> request(String path, {
    required String method,
    dynamic data,
    Map<String, dynamic>? headers,
  });
}
```

### 2.4 高级业务服务 (`WebDavService`)
对应 `operations/` 目录。
供 UI 调用的最高层接口。
```dart
class WebDavService {
  final WebDavClient _client;

  Future<List<WebDavFile>> readDir(String path);
  Future<void> mkdir(String path);
  Future<void> upload(String localPath, String remotePath);
  Future<void> download(String remotePath, String localPath);
  Future<void> remove(String path);
}
```

## 3. 同步机制的建议 (Sync Engine Suggestion)

在 `webdav-js` 的基础上，如果我们要实现高效的“增量同步”（Sync），应该利用 WebDAV 提供的 `ETag` 和 `Last-Modified`：

1. **差异对比 (Diffing)**：获取云端目录 (`PROPFIND`) 和本地目录的列表。
2. **基于 ETag/时间戳的覆盖策略**：
   - 云端有，本地无 -> 下载。
   - 本地有，云端无 -> 上传。
   - 都有 -> 对比修改时间或 ETag，保留最新的进行覆盖。
3. **并发控制**：在 Flutter 中同步大量小文件时，不要一次性发起所有的 `Dio.download`，这会造成 Socket 耗尽或内存溢出。建议使用包 `pool` 或者手写一个基于 `Future.wait` 的信号量机制，限制最大并发数为 3-5 个。

---
*此文档为内部架构分析与翻译草稿，专门为后续的 Dart 重构提供 Spec 参考。*