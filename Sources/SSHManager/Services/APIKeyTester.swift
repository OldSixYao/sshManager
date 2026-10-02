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

    // MARK: - 余额查询

    struct BalanceOutcome {
        var succeeded: Bool
        var total: Double?
        var used: Double?
        var remaining: Double?
        var currency: String
        var message: String
    }

    /// new-api 系中转站的令牌级用量接口：{站点根}/api/usage/token/（Bearer 即 API key）。
    /// 响应单位为内部配额，500000 = 1 USD；new-api 变体会直接给 display{remaining,total,used,unit}。
    static func tokenUsageURL(forBaseURL raw: String) -> URL? {
        guard let base = normalizeBaseURL(raw),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        var path = components.path
        // 去掉结尾的 /v1、/v4 等版本段，回到站点根
        if let match = versionedPathRegex.firstMatch(
            in: path, range: NSRange(path.startIndex..., in: path)),
           let matchRange = Range(match.range, in: path) {
            path = String(path[..<matchRange.lowerBound])
        }
        components.path = path + "/api/usage/token/"
        return components.url
    }

    /// 令牌用量接口的三种返回形态。
    struct TokenUsage {
        enum Kind {
            /// new-api display 对象，自带金额与单位
            case display
            /// 不限量套餐：只有已用有意义
            case unlimited
            /// 有限额度：配额 ÷ 500000 = USD
            case quota
        }
        var kind: Kind
        var planName: String?
        var remaining: Double?
        var total: Double?
        var used: Double?
        var unit: String
    }

    /// 解析 /api/usage/token/ 响应；data 可能在顶层或 data 字段下。
    static func parseTokenUsage(from data: Data) -> TokenUsage? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let payload = (object["data"] as? [String: Any]) ?? object
        let name = payload["name"] as? String

        if let display = payload["display"] as? [String: Any],
           let remaining = display["remaining"] as? Double {
            return TokenUsage(
                kind: .display,
                planName: name,
                remaining: remaining,
                total: display["total"] as? Double,
                used: display["used"] as? Double,
                unit: (display["unit"] as? String) ?? "USD"
            )
        }
        func double(_ key: String) -> Double? {
            if let d = payload[key] as? Double { return d }
            if let s = payload[key] as? String { return Double(s) }
            return nil
        }
        if payload["unlimited_quota"] as? Bool == true {
            return TokenUsage(
                kind: .unlimited,
                planName: name,
                remaining: nil,
                total: nil,
                used: double("total_used").map { $0 / 500_000 },
                unit: "USD"
            )
        }
        if let available = double("total_available"), let used = double("total_used") {
            return TokenUsage(
                kind: .quota,
                planName: name,
                remaining: available / 500_000,
                total: double("total_granted").map { $0 / 500_000 },
                used: used / 500_000,
                unit: "USD"
            )
        }
        return nil
    }

    /// 计费端点（兜底用）：沿用版本路径规则（/v1 结尾接 dashboard/billing/…，否则补 /v1）。
    static func billingURL(forBaseURL raw: String, path: String) -> URL? {
        guard let base = normalizeBaseURL(raw),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        var base_ = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let range = NSRange(base_.startIndex..., in: base_)
        if versionedPathRegex.firstMatch(in: base_, range: range) == nil {
            base_ += "/v1"
        }
        components.path = "\(base_)/dashboard/billing/\(path)"
        return components.url
    }

    /// one-api 约定：subscription.hard_limit_usd 为总额度（美元）。
    static func parseSubscriptionTotal(from data: Data) -> Double? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limit = object["hard_limit_usd"]
        else { return nil }
        if let d = limit as? Double { return d }
        if let s = limit as? String { return Double(s) }
        return nil
    }

    /// one-api 约定：usage.total_usage 为已用金额（单位：美分）。
    static func parseUsageCents(from data: Data) -> Double? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = object["total_usage"]
        else { return nil }
        if let d = usage as? Double { return d }
        if let s = usage as? String { return Double(s) }
        return nil
    }

    /// DeepSeek 官方余额接口响应：balance_infos[].total_balance（字符串金额）。
    static func parseDeepSeekBalance(from data: Data) -> (remaining: Double, currency: String)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let infos = object["balance_infos"] as? [[String: Any]],
              let first = infos.first,
              let balance = first["total_balance"] as? String,
              let value = Double(balance)
        else { return nil }
        let currency = (first["currency"] as? String) ?? "CNY"
        return (value, currency)
    }

    private static func performGET(url: URL, apiKey: String, timeout: TimeInterval) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// 查询该密钥的余额。优先级：
    /// 1. 厂商专用接口（DeepSeek 官方）
    /// 2. new-api 系令牌用量接口 /api/usage/token/（真实额度来源）
    /// 3. one-api 计费约定（subscription/usage；占位值 1e8 视为不支持）
    static func fetchBalance(key: APIKey, timeout: TimeInterval = 10) async -> BalanceOutcome {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        let now = Date()
        let startDate = dayFormatter.string(from: now.addingTimeInterval(-100 * 86400))
        let endDate = dayFormatter.string(from: now.addingTimeInterval(86400))

        do {
            // 1) DeepSeek 官方：独立余额端点，直接返回剩余金额
            if key.vendor == "deepseek" {
                let url = URL(string: "https://api.deepseek.com/user/balance")!
                let (data, status) = try await performGET(url: url, apiKey: key.apiKey, timeout: timeout)
                if (200..<300).contains(status), let parsed = parseDeepSeekBalance(from: data) {
                    return BalanceOutcome(
                        succeeded: true, total: nil, used: nil,
                        remaining: parsed.remaining, currency: parsed.currency,
                        message: String(format: "剩余 %.2f %@", parsed.remaining, parsed.currency)
                    )
                }
            }

            // 2) new-api 令牌用量接口
            if let tokenURL = tokenUsageURL(forBaseURL: key.baseURL) {
                let (data, status) = try await performGET(url: tokenURL, apiKey: key.apiKey, timeout: timeout)
                switch status {
                case 200..<300:
                    if let usage = parseTokenUsage(from: data) {
                        return balanceOutcome(for: usage)
                    }
                case 401, 403:
                    return BalanceOutcome(succeeded: false, total: nil, used: nil, remaining: nil, currency: "USD",
                                          message: "该密钥无权查询余额（HTTP \(status)）")
                default:
                    break // 404 等 → 继续尝试兜底
                }
            }

            // 3) one-api 计费约定兜底
            if let subURL = billingURL(forBaseURL: key.baseURL, path: "subscription") {
                let (subData, subStatus) = try await performGET(url: subURL, apiKey: key.apiKey, timeout: timeout)
                if (200..<300).contains(subStatus), let total = parseSubscriptionTotal(from: subData) {
                    // 部分站点返回 1e8 之类的占位值，不是真实额度
                    guard total < 1_000_000 else {
                        return BalanceOutcome(succeeded: false, total: nil, used: nil, remaining: nil, currency: "USD",
                                              message: "该供应商未开放真实额度查询（计费接口返回占位值）")
                    }
                    var used: Double?
                    if let usageURL = billingURL(forBaseURL: key.baseURL, path: "usage")?
                        .appending(queryItems: [
                            URLQueryItem(name: "start_date", value: startDate),
                            URLQueryItem(name: "end_date", value: endDate),
                        ]),
                       let components = URLComponents(url: usageURL, resolvingAgainstBaseURL: false),
                       let finalURL = components.url {
                        let (usageData, usageStatus) = try await performGET(url: finalURL, apiKey: key.apiKey, timeout: timeout)
                        if (200..<300).contains(usageStatus) {
                            used = parseUsageCents(from: usageData).map { $0 / 100 }
                        }
                    }
                    let remaining = total - (used ?? 0)
                    var message = String(format: "剩余 %.2f / 总额度 %.2f USD", remaining, total)
                    if let used {
                        message += String(format: "（已用 %.2f）", used)
                    }
                    return BalanceOutcome(succeeded: true, total: total, used: used,
                                          remaining: remaining, currency: "USD", message: message)
                }
            }

            return BalanceOutcome(succeeded: false, total: nil, used: nil, remaining: nil, currency: "USD",
                                  message: "该供应商未提供可用的余额查询接口")
        } catch {
            return BalanceOutcome(succeeded: false, total: nil, used: nil, remaining: nil, currency: "USD",
                                  message: "查询失败：\(error.localizedDescription)")
        }
    }

    private static func balanceOutcome(for usage: TokenUsage) -> BalanceOutcome {
        switch usage.kind {
        case .display:
            var message = ""
            if let name = usage.planName { message += "套餐「\(name)」：" }
            message += String(format: "剩余 %.2f %@", usage.remaining ?? 0, usage.unit)
            if let total = usage.total {
                message += String(format: " / 总额度 %.2f", total)
            }
            if let used = usage.used {
                message += String(format: "（已用 %.2f）", used)
            }
            return BalanceOutcome(succeeded: true, total: usage.total, used: usage.used,
                                  remaining: usage.remaining, currency: usage.unit, message: message)
        case .unlimited:
            var message = "不限量套餐"
            if let name = usage.planName { message = "套餐「\(name)」（不限量）" }
            if let used = usage.used {
                message += String(format: "：已用 %.2f USD", used)
            }
            return BalanceOutcome(succeeded: true, total: nil, used: usage.used,
                                  remaining: nil, currency: "USD", message: message)
        case .quota:
            var message = String(format: "剩余 %.2f / 总额度 %.2f USD（已用 %.2f）",
                                 usage.remaining ?? 0, usage.total ?? 0, usage.used ?? 0)
            if let name = usage.planName { message = "套餐「\(name)」" + message }
            return BalanceOutcome(succeeded: true, total: usage.total, used: usage.used,
                                  remaining: usage.remaining, currency: "USD", message: message)
        }
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
