import Foundation

/// API 密钥的连通性测试与展示辅助。
/// 测试约定为 OpenAI 兼容接口：GET {baseURL}/v1/models，Bearer 鉴权。
enum APIKeyTester {

    struct TestOutcome {
        var isValid: Bool
        var latencyMs: Int
        var message: String
    }

    // MARK: - URL 处理（纯函数，可测）

    /// 规范化 BaseURL：补 https:// 前缀、去首尾空白与末尾斜杠。无效返回 nil。
    static func normalizeBaseURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        guard let url = URL(string: text), url.host != nil else { return nil }
        return url
    }

    // swiftlint:disable:next force_try
    private static let versionedPathRegex = try! NSRegularExpression(pattern: #"/v\d+$"#)

    /// 模型列表请求地址：路径已以 /v1、/v4 等版本段结尾时接 /models，
    /// 否则拼 /v1/models（OpenAI 兼容约定）。
    static func modelsURL(forBaseURL raw: String) -> URL? {
        guard let base = normalizeBaseURL(raw),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        var path = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        let range = NSRange(path.startIndex..., in: path)
        if versionedPathRegex.firstMatch(in: path, range: range) != nil {
            path += "/models"
        } else {
            path += "/v1/models"
        }
        components.path = path
        return components.url
    }

    // MARK: - 展示辅助（纯函数，可测）

    /// 密钥打码：保留前 4 后 4，其余以 … 代替；过短则全打码。
    static func masked(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 8 else { return String(repeating: "•", count: max(trimmed.count, 4)) }
        return "\(trimmed.prefix(4))…\(trimmed.suffix(4))"
    }

    static func curlExample(for key: APIKey) -> String {
        let url = modelsURL(forBaseURL: key.baseURL)?.absoluteString ?? key.baseURL
        return "curl -s \(url) -H \"Authorization: Bearer \(key.apiKey)\""
    }

    // MARK: - 连通性测试与模型列表

    /// 按状态码给出可读的失败原因（测试与拉取模型共用）。
    static func httpFailureMessage(_ status: Int) -> String {
        switch status {
        case 401, 403:
            return "密钥无效或已被禁用（HTTP \(status)）"
        case 429:
            return "被限流（HTTP 429）"
        case 404:
            return "端点不存在（HTTP 404）——检查 BaseURL 是否需要包含 /v1"
        default:
            return "HTTP \(status)"
        }
    }

    private static func performModelListRequest(
        baseURL: String,
        apiKey: String,
        timeout: TimeInterval
    ) async throws -> (data: Data, status: Int, latencyMs: Int) {
        guard let url = modelsURL(forBaseURL: baseURL) else {
            throw NSError(domain: "APIKeyTester", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "BaseURL 无效"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let startedAt = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status, latencyMs)
    }

    /// 请求模型列表接口验证密钥。只会访问用户配置的 BaseURL。
    static func test(key: APIKey, timeout: TimeInterval = 10) async -> TestOutcome {
        do {
            let (data, status, latencyMs) = try await performModelListRequest(
                baseURL: key.baseURL,
                apiKey: key.apiKey,
                timeout: timeout
            )
            switch status {
            case 200:
                let count = parseModelIDs(from: data).count
                let suffix = count > 0 ? "，返回 \(count) 个模型" : ""
                return TestOutcome(isValid: true, latencyMs: latencyMs, message: "密钥有效（\(latencyMs)ms）\(suffix)")
            case 429:
                return TestOutcome(isValid: true, latencyMs: latencyMs, message: "密钥有效但被限流（HTTP 429）")
            default:
                return TestOutcome(isValid: false, latencyMs: latencyMs,
                                   message: "\(httpFailureMessage(status))（\(latencyMs)ms）")
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
                return TestOutcome(isValid: false, latencyMs: 0, message: "请求超时（\(Int(timeout))s）")
            }
            return TestOutcome(isValid: false, latencyMs: 0, message: "无法连接：\(error.localizedDescription)")
        }
    }

    /// 拉取该密钥可用的全部模型 id。失败抛错（信息可直接展示给用户）。
    static func fetchModelIDs(baseURL: String, apiKey: String, timeout: TimeInterval = 10) async throws -> [String] {
        let (data, status, _) = try await performModelListRequest(baseURL: baseURL, apiKey: apiKey, timeout: timeout)
        guard (200..<300).contains(status) else {
            throw NSError(domain: "APIKeyTester", code: status,
                          userInfo: [NSLocalizedDescriptionKey: httpFailureMessage(status)])
        }
        return parseModelIDs(from: data)
    }

    /// 解析模型列表响应：OpenAI 兼容 {"data":[{"id":…}]}；
    /// 兼容 {"models":[{"id"/"name":…}]}（name 形如 "models/xxx" 时去掉前缀）。
    /// 去重、保序；解析不出返回空数组。
    static func parseModelIDs(from data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        var ids: [String] = []
        func append(_ value: Any?) {
            guard let raw = value as? String else { return }
            let id = raw.hasPrefix("models/") ? String(raw.dropFirst("models/".count)) : raw
            if !id.isEmpty, !ids.contains(id) {
                ids.append(id)
            }
        }

        if let list = object["data"] as? [[String: Any]] {
            for entry in list {
                append(entry["id"])
            }
        }
        if ids.isEmpty, let list = object["models"] as? [[String: Any]] {
            for entry in list {
                append(entry["id"] ?? entry["name"])
            }
        }
        return ids
    }
}
