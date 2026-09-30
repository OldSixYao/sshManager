import Foundation

/// 一条端口转发配置。`raw` 为 config 中的原始写法，
/// 如 "8080:localhost:80" 或 "127.0.0.1:8080:10.0.0.5:80"。
struct PortForward: Equatable, Identifiable {
    let id: UUID
    var raw: String

    init(id: UUID = UUID(), raw: String) {
        self.id = id
        self.raw = raw.trimmingCharacters(in: .whitespaces)
    }

    var isValid: Bool {
        !raw.isEmpty && raw.contains(":")
    }

    /// 尽力解析为 (绑定端点, 目标端点) 便于展示，无法识别时返回 nil。
    var displayParts: (bind: String, target: String)? {
        let tokens = raw.split(separator: " ").map(String.init)
        let normalized = tokens.count == 2 ? tokens.joined(separator: ":") : raw
        let parts = normalized.split(separator: ":").map(String.init)
        switch parts.count {
        case 3:
            return (parts[0], "\(parts[1]):\(parts[2])")
        case 4:
            return ("\(parts[0]):\(parts[1])", "\(parts[2]):\(parts[3])")
        default:
            return nil
        }
    }
}

/// 表单未覆盖的自定义指令（如 ProxyCommand），原样保留。
struct RawOption: Equatable, Identifiable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

/// 从 ~/.ssh/config 解析出的一个 Host 块。
/// blockStart/blockEnd 是该块在 sourceFile 中的行区间（end 为 exclusive）。
struct SSHHost: Equatable, Identifiable {
    var primaryAlias: String
    var aliases: [String]
    var hostName: String?
    var user: String?
    var port: String?
    var identityFiles: [String]
    var identitiesOnly: Bool?
    var serverAliveInterval: String?
    var proxyJump: String?
    var proxyCommand: String?
    var localForwards: [PortForward]
    var remoteForwards: [PortForward]
    var otherOptions: [RawOption]
    var isPattern: Bool
    var isReadOnly: Bool
    var sourceFile: String
    var blockStart: Int
    var blockEnd: Int

    var id: String { "\(sourceFile)#\(blockStart)|\(primaryAlias)" }

    var displayName: String { primaryAlias }

    var targetDescription: String {
        let target = hostName ?? primaryAlias
        return "\(user ?? "当前用户")@\(target):\(port ?? "22")"
    }

    /// 是否允许在应用内编辑（Include 文件中的主机首版只读）。
    var isEditable: Bool { !isReadOnly }

    func withReadOnly(_ value: Bool) -> SSHHost {
        var copy = self
        copy.isReadOnly = value
        return copy
    }
}

/// 分组/标签等 SSH config 之外的元信息，按主别名存储在侧车 JSON 中。
struct HostMetadata: Codable, Equatable {
    var group: String?
    var tags: [String] = []

    init(group: String? = nil, tags: [String] = []) {
        self.group = group
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        group = try container.decodeIfPresent(String.self, forKey: .group)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    var isEmpty: Bool { (group ?? "").isEmpty && tags.isEmpty }
}
