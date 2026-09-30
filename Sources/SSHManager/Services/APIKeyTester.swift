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

    // MARK: - 连通性测试

    /// 请求模型列表验证密钥。只会访问用户配置的 BaseURL。
    static func test(key: APIKey, timeout: TimeInterval = 10) async -> TestOutcome {
        guard let url = modelsURL(forBaseURL: key.baseURL) else {
            return TestOutcome(isValid: false, latencyMs: 0, message: "BaseURL 无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(key.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let startedAt = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            switch status {
            case 200:
                let modelCount = modelCount(from: data)
                let suffix = modelCount > 0 ? "，返回 \(modelCount) 个模型" : ""
                return TestOutcome(isValid: true, latencyMs: latencyMs, message: "密钥有效（\(latencyMs)ms）\(suffix)")
            case 401, 403:
                return TestOutcome(isValid: false, latencyMs: latencyMs, message: "密钥无效或已被禁用（HTTP \(status)，\(latencyMs)ms）")
            case 429:
                return TestOutcome(isValid: true, latencyMs: latencyMs, message: "密钥有效但被限流（HTTP 429）")
            case 404:
                return TestOutcome(isValid: false, latencyMs: latencyMs, message: "端点不存在（HTTP 404）——检查 BaseURL 是否需要包含 /v1")
            default:
                return TestOutcome(isValid: false, latencyMs: latencyMs, message: "HTTP \(status)（\(latencyMs)ms）")
            }
        } catch {
            let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let nsError = error as NSError
            let reason: String
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
                reason = "请求超时（\(Int(timeout))s）"
            } else {
                reason = nsError.localizedDescription
            }
            return TestOutcome(isValid: false, latencyMs: latencyMs, message: "无法连接：\(reason)")
        }
    }

    /// 从 OpenAI 兼容的 {"data":[{"id":...}]} 响应里数模型个数，解析失败返回 0。
    private static func modelCount(from data: Data) -> Int {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["data"] as? [[String: Any]]
        else { return 0 }
        return list.count
    }
}
