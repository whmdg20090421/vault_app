# WebDAV 架构解析与 Flutter 重构思路 (基于 webdav-js)

*基于 dom111/webdav-js 源码深入分析，为 Dart/Flutter WebDAV 库的重构提供 Spec 参考。特别强化了对网络连接底层实现和错误处理流程的解析。*

## 1. 整体架构与网络连接底层分析 (Architecture & Network Deep Dive)

`webdav-js` 是基于 TypeScript 编写的 WebDAV 客户端，支持 Node.js 和浏览器。通过深度阅读 `source/` 目录中的代码（特别是 `request.ts`, `response.ts`, `auth/` 和 `operations/`），其网络通信与错误处理机制如下：

### 1.1 请求传输与代理控制 (Transport & DNS/TCP Control)
- **实现机制**：在 `request.ts` 的 `getFetchOptions` 中，如果环境是 Node.js，它允许开发者通过 `WebDAVClientOptions` 传入自定义的 `httpAgent` 和 `httpsAgent`。
  ```typescript
  if (requestOptions.httpAgent || requestOptions.httpsAgent) {
      opts.agent = (parsedURL: URL) => {
          if (parsedURL.protocol === "http:") return requestOptions.httpAgent || new HTTPAgent();
          return requestOptions.httpsAgent || new HTTPSAgent();
      };
  }
  ```
- **核心作用**：在 Node.js 中，`http.Agent` 负责管理连接池、Socket 行为、Keep-Alive 以及**自定义 DNS 解析或代理**。这也是解决网络连接异常（如 DNS 污染、代理转发、TLS 握手失败）的核心入口。
- **Dart/Flutter 映射**：
  - 在 Dart 中，我们不使用 `Agent`，而是使用 `Dio` 配合 `HttpClientAdapter`（如 `IOHttpClientAdapter`）。
  - 若要处理底层 DNS 或证书校验问题（如避免 401 或拦截），可以在 `IOHttpClientAdapter.createHttpClient` 中：
    1. 自定义 `SecurityContext`（允许自签名证书或特定 CA）。
    2. 设置代理 `client.findProxy = (uri) => "PROXY x.x.x.x:8080";`。
    3. 如果需要绕过系统 DNS 直接使用 IP 直连并带上 Host 头，可通过 `Dio` 拦截器修改 Host。

### 1.2 认证自动升级机制 (Auto Authentication)
- **实现机制**：`auth/` 目录支持 Basic, Digest 和 OAuth。在 `request.ts` 的 `requestAuto` 方法中，客户端会先发送无认证或默认认证的请求。
- **流程**：如果服务器返回 `401 Unauthorized` 并且响应头 `www-authenticate` 包含 `Digest`（见 `digest.ts`），客户端会自动计算 `nonce`, `qop`, `nc` 并生成哈希，重新发起第二次请求。
- **Dart/Flutter 映射**：
  - 我们需要实现一个**拦截器驱动的认证层**。在 `Dio` 的 `Interceptor.onError` 中：
    - 如果捕获到 `DioException` 且状态码为 `401`。
    - 读取 `e.response?.headers.value('www-authenticate')`。
    - 如果是 `Basic`，使用 Base64 编码账户密码重新请求；如果是 `Digest`，则解析 Challenge 并重新生成 Auth Header 后重试。

### 1.3 异常捕获与响应处理 (Error Handling & Logging)
- **实现机制**：`response.ts` 包含 `handleResponseCode` 和 `createErrorFromResponse`。所有 >= 400 的 HTTP 状态都会抛出携带完整上下文的 `WebDAVClientError`。
- **Dart/Flutter 映射与增强**：
  - 必须建立一套完整的**请求生命周期日志机制**。
  - 创建一个专门的 `WebDavLogger` 拦截器，捕获：
    - `onRequest`: 记录目标 URL、Headers、方法。
    - `onResponse`: 记录状态码、内容大小。
    - `onError`: 区分 `SocketException`（DNS 解析失败、TCP 连接超时）、`TlsException`（证书错误）、`HttpException`（代理或服务器关闭连接）以及常规 HTTP 错误（401/404/502）。
  - 所有这些细节必须写入 `/storage/emulated/0/Android/data/com.tianyanmczj.vault/files/webdav_error_log.txt`。

### 1.4 XML 解析与业务操作 (XML Parsing & Operations)
- **实现机制**：`operations/directoryContents.ts` 发送带 `Depth: 1` 头的 `PROPFIND` 请求。接收到 XML 后，调用 `tools/dav.ts` 的 `parseXML`（基于 `fast-xml-parser`）转换为 JS 对象。
- **Dart/Flutter 映射**：
  - 使用 `package:xml/xml.dart`。
  - 发送 `PROPFIND`，获取 `207 Multi-Status`。
  - 遍历 `<D:response>`，提取 `href`（务必 `Uri.decodeFull`）、`getcontentlength`、`resourcetype` 和 `getetag`。

---

## 2. 详细重构方案 (Detailed Refactoring Plan)

### 2.1 底层网络连接与日志追踪 (Network Transport & Error Logging)
构建一个专门的 `Dio` 实例，挂载以下机制：

```dart
class WebDavClient {
  late final Dio dio;

  WebDavClient({required String url, required String username, required String password}) {
    dio = Dio(BaseOptions(
      baseUrl: url,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));

    // 1. 认证拦截器 (处理 Basic/Digest)
    dio.interceptors.add(WebDavAuthInterceptor(username, password));
    
    // 2. 错误与日志持久化拦截器
    dio.interceptors.add(WebDavErrorLoggerInterceptor());
  }

  // 统一的请求入口，支持 PROPFIND, MKCOL 等自定义 Method
  Future<Response<String>> request(String path, {required String method, Map<String, dynamic>? headers, dynamic data}) async {
    return await dio.request<String>(
      path,
      data: data,
      options: Options(method: method, headers: headers, responseType: ResponseType.plain),
    );
  }
}
```

**WebDavErrorLoggerInterceptor 设计**：
该拦截器负责捕获全流程并写出到日志文件：
```dart
void onError(DioException err, ErrorInterceptorHandler handler) {
  final logBuffer = StringBuffer();
  logBuffer.writeln('=== [WebDAV Error] ${DateTime.now().toIso8601String()} ===');
  logBuffer.writeln('URL: ${err.requestOptions.method} ${err.requestOptions.uri}');
  
  if (err.error is SocketException) {
    logBuffer.writeln('底层 Socket 异常 (通常为 DNS 解析或 TCP 无法建连): ${err.error}');
  } else if (err.error is TlsException) {
    logBuffer.writeln('SSL/TLS 握手失败 (可能被中间人或代理拦截): ${err.error}');
  } else if (err.response != null) {
    logBuffer.writeln('HTTP 错误: 状态码 ${err.response?.statusCode}');
    logBuffer.writeln('响应体: ${err.response?.data}');
  }
  
  // 写入 /storage/.../webdav_error_log.txt
  _writeToLogFile(logBuffer.toString());
  super.onError(err, handler);
}
```

### 2.2 协议解析与实体 (Parser & Entities)
定义标准的 `WebDavFile` 和解析逻辑，完全脱离 UI。
```dart
class WebDavFile {
  final String path;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime? lastModified;
  final String? eTag;
}

class WebDavParser {
  static List<WebDavFile> parsePropFind(String xmlString) {
    // 使用 xml 包解析，提取属性，屏蔽父目录自身的返回项
  }
}
```

### 2.3 业务服务与同步逻辑 (Business Service & Sync Logic)
提供高层 API 供应用调用。
```dart
class WebDavService {
  final WebDavClient _client;

  // 读取目录
  Future<List<WebDavFile>> readDir(String path) async {
    final response = await _client.request(path, method: 'PROPFIND', headers: {'Depth': '1'});
    return WebDavParser.parsePropFind(response.data!);
  }

  // 并发受限的增量同步逻辑 (基于 ETag)
  // 参考 webdav-js 的操作逻辑
}
```

## 3. 结论 (Conclusion)

通过剖析 `dom111/webdav-js`，我们明确了其网络核心在于对 Fetch/Agent 的灵活运用以及健全的错误传递机制。对于 Flutter 的重构，我们的首要任务是**建立稳固的 Dio 实例**，实现基于拦截器的认证与详细的文件级错误日志记录机制（从 DNS 到 HTTP），然后再在上层封装 XML 解析和增量同步引擎。