import AppKit

/// 通过 CC Switch 的 ccswitch://v1/import 深度链接一键导入供应商。
/// app 类型映射：vendor=claude → claude；vendor=gemini → gemini；其余（OpenAI 兼容）→ codex。
/// 链接由 CC Switch 接管后弹出确认框完成合并，本应用不直接改写它的数据库。
enum CCSwitchExporter {

    static func appType(for key: APIKey) -> String {
        switch key.vendor {
        case "claude": return "claude"
        case "gemini": return "gemini"
        default: return "codex"
        }
    }

    static func deepLink(for key: APIKey) -> URL? {
        guard var components = URLComponents(string: "ccswitch://v1/import") else { return nil }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "resource", value: "provider"),
            URLQueryItem(name: "app", value: appType(for: key)),
            URLQueryItem(name: "name", value: key.name),
        ]
        if !key.baseURL.isEmpty {
            items.append(URLQueryItem(name: "endpoint", value: key.baseURL))
        }
        if !key.apiKey.isEmpty {
            items.append(URLQueryItem(name: "apiKey", value: key.apiKey))
        }
        if !key.website.isEmpty {
            items.append(URLQueryItem(name: "homepage", value: key.website))
        }
        if let model = key.models.first, !model.isEmpty {
            items.append(URLQueryItem(name: "model", value: model))
        }
        var notes = "来自 SSH Manager"
        if !key.provider.isEmpty {
            notes += " · \(key.provider)"
        }
        items.append(URLQueryItem(name: "notes", value: notes))
        components.queryItems = items
        return components.url
    }

    /// 本机是否注册了 ccswitch:// 协议（装过并启动过一次 CC Switch 即可）。
    static func isAvailable() -> Bool {
        guard let probe = URL(string: "ccswitch://v1/import") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
    }

    /// 打开深度链接，交给 CC Switch 弹确认导入。返回是否成功唤起。
    @discardableResult
    static func importKey(_ key: APIKey) -> Bool {
        guard let url = deepLink(for: key) else { return false }
        return NSWorkspace.shared.open(url)
    }
}
