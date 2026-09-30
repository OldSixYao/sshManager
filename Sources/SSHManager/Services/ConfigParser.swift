import Foundation

/// OpenSSH config 解析器。
///
/// 解析目标是「块级」的：文件被拆为若干 Host / Match 块，每个 Host 块记录
/// 自己在文件中的行区间，供 ConfigWriter 做局部替换（其余行原样保留）。
enum ConfigParser {

    static let directiveRegex = try! NSRegularExpression(pattern: #"^([^\s=]+)(?:\s*=\s*|\s+)(.*)$"#)

    struct Directive {
        let key: String
        let value: String
    }

    struct ParsedConfig {
        var lines: [String]
        var hosts: [SSHHost]
        var matchBlockCount: Int
        var includeDirectives: [String]
    }

    /// 统一换行后按行拆分；末尾换行不产生空元素。
    static func normalizeLines(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if normalized.hasSuffix("\n"), let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        return lines
    }

    /// 把一行拆成 key/value，支持 `Key value` 与 `Key=value`。
    /// 注释行、空行、无参数行返回 nil。
    static func directive(in line: String) -> Directive? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = directiveRegex.firstMatch(in: trimmed, range: range),
              let keyRange = Range(match.range(at: 1), in: trimmed),
              let valueRange = Range(match.range(at: 2), in: trimmed)
        else { return nil }
        return Directive(key: String(trimmed[keyRange]), value: String(trimmed[valueRange]))
    }

    static func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    /// 解析配置文件。Include 会递归展开（深度 ≤ 3），引入的主机标记为只读。
    static func parseFile(at url: URL, depth: Int = 0) throws -> ParsedConfig {
        let text = try String(contentsOf: url, encoding: .utf8)
        let parsed = parse(text: text, sourceFile: url.path)
        guard depth < 3, !parsed.includeDirectives.isEmpty else { return parsed }

        let sshDir = url.deletingLastPathComponent()
        var all = parsed
        var matchCount = parsed.matchBlockCount
        for arg in parsed.includeDirectives {
            let pattern: String
            if arg.hasPrefix("/") {
                pattern = arg
            } else {
                pattern = sshDir.appendingPathComponent(arg).path
            }
            for file in Glob.expand(pattern) where file != url.path {
                guard let sub = try? parseFile(at: URL(fileURLWithPath: file), depth: depth + 1) else { continue }
                all.hosts += sub.hosts.map { $0.withReadOnly(true) }
                matchCount += sub.matchBlockCount
            }
        }
        all.matchBlockCount = matchCount
        return all
    }

    static func parse(text: String, sourceFile: String) -> ParsedConfig {
        let lines = normalizeLines(text)
        var hosts: [SSHHost] = []
        var includeDirectives: [String] = []
        var matchCount = 0

        var blockStarts: [(offset: Int, isMatch: Bool)] = []
        for (index, line) in lines.enumerated() {
            guard let d = directive(in: line) else { continue }
            let key = d.key.lowercased()
            if key == "host" {
                blockStarts.append((index, false))
            } else if key == "match" {
                blockStarts.append((index, true))
            }
        }

        // 首个块之前的全局区
        let firstBlockOffset = blockStarts.first?.offset ?? lines.count
        for line in lines[0..<firstBlockOffset] {
            if let d = directive(in: line), d.key.lowercased() == "include" {
                includeDirectives.append(contentsOf: splitIncludeArgs(d.value))
            }
        }

        for (bi, start) in blockStarts.enumerated() {
            let end = bi + 1 < blockStarts.count ? blockStarts[bi + 1].offset : lines.count
            if start.isMatch {
                matchCount += 1
                continue
            }
            let blockLines = Array(lines[start.offset..<end])
            if let host = hostBlock(blockLines: blockLines, start: start.offset, sourceFile: sourceFile,
                                    includeOut: &includeDirectives) {
                hosts.append(host)
            }
        }

        return ParsedConfig(lines: lines, hosts: hosts, matchBlockCount: matchCount,
                            includeDirectives: includeDirectives)
    }

    static func splitIncludeArgs(_ value: String) -> [String] {
        value.split(separator: " ").map { unquote(String($0)) }.filter { !$0.isEmpty }
    }

    static func hostBlock(blockLines: [String], start: Int, sourceFile: String,
                          includeOut: inout [String]) -> SSHHost? {
        guard let hostLine = blockLines.first,
              let header = directive(in: hostLine),
              header.key.lowercased() == "host"
        else { return nil }
        let aliases = header.value.split(separator: " ")
            .map { unquote(String($0)) }
            .filter { !$0.isEmpty }
        guard !aliases.isEmpty else { return nil }

        var host = SSHHost(
            primaryAlias: aliases[0],
            aliases: aliases,
            hostName: nil,
            user: nil,
            port: nil,
            identityFiles: [],
            identitiesOnly: nil,
            serverAliveInterval: nil,
            proxyJump: nil,
            proxyCommand: nil,
            localForwards: [],
            remoteForwards: [],
            otherOptions: [],
            isPattern: aliases.contains { $0.contains("*") || $0.contains("?") },
            isReadOnly: false,
            sourceFile: sourceFile,
            blockStart: start,
            blockEnd: start + blockLines.count
        )

        for line in blockLines.dropFirst() {
            guard let d = directive(in: line) else { continue }
            if d.key.lowercased() == "include" {
                includeOut.append(contentsOf: splitIncludeArgs(d.value))
                continue
            }
            let value = unquote(d.value)

            // 标量指令只取第一次出现的值，重复出现时进 otherOptions 以免丢数据
            func setOnce(_ current: String?, assign: (String) -> Void) {
                if current == nil {
                    assign(value)
                } else {
                    host.otherOptions.append(RawOption(key: d.key, value: value))
                }
            }

            switch d.key.lowercased() {
            case "hostname":
                setOnce(host.hostName) { host.hostName = $0 }
            case "user":
                setOnce(host.user) { host.user = $0 }
            case "port":
                setOnce(host.port) { host.port = $0 }
            case "identityfile":
                host.identityFiles.append(value)
            case "identitiesonly":
                if host.identitiesOnly == nil {
                    host.identitiesOnly = value.lowercased() == "yes"
                } else {
                    host.otherOptions.append(RawOption(key: d.key, value: value))
                }
            case "serveraliveinterval":
                setOnce(host.serverAliveInterval) { host.serverAliveInterval = $0 }
            case "proxyjump":
                setOnce(host.proxyJump) { host.proxyJump = $0 }
            case "proxycommand":
                setOnce(host.proxyCommand) { host.proxyCommand = $0 }
            case "localforward":
                host.localForwards.append(PortForward(raw: d.value))
            case "remoteforward":
                host.remoteForwards.append(PortForward(raw: d.value))
            default:
                host.otherOptions.append(RawOption(key: d.key, value: value))
            }
        }
        return host
    }
}
