import Foundation

/// 对解析后的行数组做「块级文本手术」：编辑/新增/删除主机时
/// 只触碰目标 Host 块，文件其余部分（注释、全局配置、Match 块）原样保留。
enum ConfigWriter {

    /// 编辑器表单的数据模型。
    struct Draft {
        var aliases: [String] = []
        var hostName: String = ""
        var user: String = ""
        var port: String = ""
        var identityFiles: [String] = []
        var identitiesOnly: Bool = false
        var serverAliveInterval: String = ""
        var proxyJump: String = ""
        var proxyCommand: String = ""
        var localForwards: [PortForward] = []
        var remoteForwards: [PortForward] = []
        var otherOptions: [RawOption] = []

        static func from(_ host: SSHHost) -> Draft {
            var draft = Draft()
            draft.aliases = host.aliases
            draft.hostName = host.hostName ?? ""
            draft.user = host.user ?? ""
            draft.port = host.port ?? ""
            draft.identityFiles = host.identityFiles
            draft.identitiesOnly = host.identitiesOnly ?? false
            draft.serverAliveInterval = host.serverAliveInterval ?? ""
            draft.proxyJump = host.proxyJump ?? ""
            draft.proxyCommand = host.proxyCommand ?? ""
            draft.localForwards = host.localForwards
            draft.remoteForwards = host.remoteForwards
            draft.otherOptions = host.otherOptions
            return draft
        }
    }

    /// 返回 nil 表示校验通过，否则为错误信息。
    static func validate(_ draft: Draft) -> String? {
        guard !draft.aliases.isEmpty else { return "至少需要一个主机别名" }
        for alias in draft.aliases where alias.contains(where: { $0.isWhitespace }) {
            return "别名不能包含空格：\(alias)"
        }
        if !draft.port.isEmpty {
            guard let port = Int(draft.port), (1...65535).contains(port) else {
                return "端口必须是 1–65535 的数字"
            }
            _ = port
        }
        if !draft.serverAliveInterval.isEmpty {
            guard let interval = Int(draft.serverAliveInterval), interval > 0 else {
                return "ServerAliveInterval 必须是正整数"
            }
            _ = interval
        }
        for forward in draft.localForwards + draft.remoteForwards where !forward.isValid {
            return "转发格式无效：\"\(forward.raw)\"（示例：8080:localhost:80）"
        }
        for option in draft.otherOptions where option.key.trimmingCharacters(in: .whitespaces).isEmpty {
            return "其他选项存在空键名"
        }
        return nil
    }

    /// 检查首别名是否与其他主机重复（允许保存，仅用于 UI 提示）。
    static func duplicateAlias(of draft: Draft, excludingPrimary primary: String?, in hosts: [SSHHost]) -> String? {
        guard let first = draft.aliases.first else { return nil }
        return hosts.first { $0.primaryAlias == first && $0.primaryAlias != primary }?.primaryAlias
    }

    static func blockLines(_ draft: Draft) -> [String] {
        var out = ["Host " + draft.aliases.map { quoteIfNeeded($0) }.joined(separator: " ")]

        func add(_ key: String, _ value: String) {
            guard !value.isEmpty else { return }
            out.append("    \(key) \(quoteValue(value))")
        }

        add("HostName", draft.hostName)
        add("User", draft.user)
        add("Port", draft.port)
        for file in draft.identityFiles where !file.isEmpty {
            add("IdentityFile", file)
        }
        if draft.identitiesOnly {
            out.append("    IdentitiesOnly yes")
        }
        add("ServerAliveInterval", draft.serverAliveInterval)
        add("ProxyJump", draft.proxyJump)
        add("ProxyCommand", draft.proxyCommand)
        for forward in draft.localForwards where forward.isValid {
            out.append("    LocalForward \(forward.raw)")
        }
        for forward in draft.remoteForwards where forward.isValid {
            out.append("    RemoteForward \(forward.raw)")
        }
        for option in draft.otherOptions {
            let key = option.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            add(key, option.value)
        }
        return out
    }

    static func replacing(host: SSHHost, draft: Draft, in lines: [String]) -> [String] {
        var newLines = lines
        let upper = min(host.blockEnd, newLines.count)
        let lower = min(host.blockStart, upper)
        newLines.replaceSubrange(lower..<upper, with: blockLines(draft))
        return newLines
    }

    static func appending(draft: Draft, to lines: [String]) -> [String] {
        var out = lines
        while let last = out.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            out.removeLast()
        }
        out.append("")
        out.append(contentsOf: blockLines(draft))
        return out
    }

    static func removing(host: SSHHost, from lines: [String]) -> [String] {
        let upper = min(host.blockEnd, lines.count)
        let lower = min(host.blockStart, upper)
        var out = Array(lines[0..<lower]) + Array(lines[upper...])
        // 块删除后若产生连续空行，收敛为一行
        var cleaned: [String] = []
        var blankRun = 0
        for line in out {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blankRun += 1
                if blankRun > 1 { continue }
            } else {
                blankRun = 0
            }
            cleaned.append(line)
        }
        return cleaned
    }

    static func text(of lines: [String]) -> String {
        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: "\n") + "\n"
    }

    static func quoteIfNeeded(_ alias: String) -> String {
        alias.contains(where: { $0.isWhitespace }) ? "\"\(alias)\"" : alias
    }

    static func quoteValue(_ value: String) -> String {
        value.contains(where: { $0.isWhitespace }) ? "\"\(value)\"" : value
    }
}
