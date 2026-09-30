import Testing
import Foundation
@testable import SSHManager

struct SSHConfigTests {

    let fixture = """
    # 我的配置
    Host alpha
        HostName 10.0.0.1
        User root
        Port 22
        IdentityFile ~/.ssh/id_alpha
        IdentitiesOnly yes

    Host beta
        HostName example.com
        User ubuntu
        ServerAliveInterval 60
        ProxyCommand nc -X connect -x 127.0.0.1:7890 %h %p

    Host *
        Compression yes
    """

    @Test func parseBasic() {
        let parsed = ConfigParser.parse(text: fixture, sourceFile: "/tmp/config")
        #expect(parsed.hosts.count == 3)
        #expect(parsed.matchBlockCount == 0)

        let alpha = parsed.hosts[0]
        #expect(alpha.primaryAlias == "alpha")
        #expect(alpha.hostName == "10.0.0.1")
        #expect(alpha.user == "root")
        #expect(alpha.port == "22")
        #expect(alpha.identityFiles == ["~/.ssh/id_alpha"])
        #expect(alpha.identitiesOnly == true)
        #expect(alpha.blockStart == 1)
        #expect(alpha.blockEnd == 8, "块尾 exclusive，包含块后的空行")
        #expect(!alpha.isPattern)

        #expect(!parsed.hosts[1].isPattern)
        #expect(parsed.hosts[2].isPattern)
    }

    @Test func proxyCommandParsedIntoKnownField() {
        let parsed = ConfigParser.parse(text: fixture, sourceFile: "/tmp/config")
        let beta = parsed.hosts[1]
        #expect(beta.proxyCommand == "nc -X connect -x 127.0.0.1:7890 %h %p")
        #expect(beta.serverAliveInterval == "60")
        #expect(beta.otherOptions.isEmpty, "fixture 中没有真正的未知指令")
    }

    @Test func updateOnlyTouchesTargetBlock() {
        let parsed = ConfigParser.parse(text: fixture, sourceFile: "/tmp/config")
        let beta = parsed.hosts[1]

        var draft = ConfigWriter.Draft.from(beta)
        draft.user = "deploy"
        draft.port = "2222"
        let newLines = ConfigWriter.replacing(host: beta, draft: draft, in: parsed.lines)
        let newText = ConfigWriter.text(of: newLines)

        // 其他块原样保留
        #expect(newText.contains("# 我的配置"))
        #expect(newText.contains("    IdentityFile ~/.ssh/id_alpha"))
        #expect(newText.contains("    Compression yes"))
        #expect(!newText.contains("User ubuntu"))
        #expect(newText.contains("User deploy"))
        #expect(newText.contains("Port 2222"))

        // 重新解析后整体一致
        let reparsed = ConfigParser.parse(text: newText, sourceFile: "/tmp/config")
        #expect(reparsed.hosts.count == 3)
        #expect(reparsed.hosts[0].user == "root")
        #expect(reparsed.hosts[1].user == "deploy")
        #expect(reparsed.hosts[1].port == "2222")
        #expect(reparsed.hosts[1].otherOptions.isEmpty)
        #expect(reparsed.hosts[1].proxyCommand == "nc -X connect -x 127.0.0.1:7890 %h %p")
        #expect(reparsed.hosts[2].primaryAlias == "*")
    }

    @Test func roundTripWithoutChangesIsSemanticallyEqual() {
        let parsed = ConfigParser.parse(text: fixture, sourceFile: "/tmp/config")
        let beta = parsed.hosts[1]
        let draft = ConfigWriter.Draft.from(beta)
        let newText = ConfigWriter.text(of: ConfigWriter.replacing(host: beta, draft: draft, in: parsed.lines))
        let reparsed = ConfigParser.parse(text: newText, sourceFile: "/tmp/config")
        let reparsedBeta = reparsed.hosts[1]
        #expect(reparsedBeta.primaryAlias == beta.primaryAlias)
        #expect(reparsedBeta.hostName == beta.hostName)
        #expect(reparsedBeta.user == beta.user)
        #expect(reparsedBeta.proxyCommand == beta.proxyCommand)
        #expect(reparsedBeta.serverAliveInterval == beta.serverAliveInterval)
    }

    @Test func addAndRemoveHost() {
        let parsed = ConfigParser.parse(text: fixture, sourceFile: "/tmp/config")

        var draft = ConfigWriter.Draft()
        draft.aliases = ["gamma"]
        draft.hostName = "g.example.com"
        draft.user = "ops"
        draft.localForwards = [PortForward(raw: "8080:localhost:80")]
        let added = ConfigWriter.appending(draft: draft, to: parsed.lines)
        let addedText = ConfigWriter.text(of: added)

        let reparsed = ConfigParser.parse(text: addedText, sourceFile: "/tmp/config")
        #expect(reparsed.hosts.count == 4)
        #expect(reparsed.hosts.last?.primaryAlias == "gamma")
        #expect(reparsed.hosts.last?.localForwards.first?.raw == "8080:localhost:80")
        #expect(reparsed.hosts[2].primaryAlias == "*", "新增块不应影响原有模式块")

        let removed = ConfigWriter.removing(host: reparsed.hosts[0], from: reparsed.lines)
        let removedText = ConfigWriter.text(of: removed)
        #expect(!removedText.contains("Host alpha"))
        #expect(removedText.contains("Host beta"))
        #expect(removedText.contains("Host gamma"))
    }

    @Test func equalsSyntaxAndQuotedValues() {
        let text = "Host eq\nUser=root\nIdentityFile \"/path/with space/k\"\n"
        let parsed = ConfigParser.parse(text: text, sourceFile: "x")
        #expect(parsed.hosts.count == 1)
        #expect(parsed.hosts[0].user == "root")
        #expect(parsed.hosts[0].identityFiles == ["/path/with space/k"])
    }

    @Test func matchBlockIsNotAHost() {
        let text = """
        Match host *.corp
            User corpuser

        Host a
            HostName a.example.com
        """
        let parsed = ConfigParser.parse(text: text, sourceFile: "x")
        #expect(parsed.hosts.count == 1)
        #expect(parsed.matchBlockCount == 1)

        // 编辑 Host a 时 Match 块原样保留
        let draft = ConfigWriter.Draft.from(parsed.hosts[0])
        let newText = ConfigWriter.text(of: ConfigWriter.replacing(host: parsed.hosts[0], draft: draft, in: parsed.lines))
        #expect(newText.contains("Match host *.corp"))
        #expect(newText.contains("User corpuser"))
    }

    @Test func multipleAliasesAndForwards() {
        let text = """
        Host web web01 web.example.com
            HostName 1.2.3.4
            LocalForward 8080 localhost:80
            LocalForward 127.0.0.1:9090 10.0.0.5:80
            RemoteForward 8000:127.0.0.1:80
        """
        let parsed = ConfigParser.parse(text: text, sourceFile: "x")
        let host = parsed.hosts[0]
        #expect(host.aliases == ["web", "web01", "web.example.com"])
        #expect(host.primaryAlias == "web")
        #expect(host.localForwards.count == 2)
        #expect(host.remoteForwards.count == 1)
        #expect(host.localForwards[0].displayParts?.bind == "8080")
        #expect(host.localForwards[1].displayParts?.bind == "127.0.0.1:9090")
    }

    @Test func validation() {
        var draft = ConfigWriter.Draft()
        draft.aliases = []
        #expect(ConfigWriter.validate(draft) != nil)

        draft.aliases = ["a b"]
        #expect(ConfigWriter.validate(draft) != nil)

        draft.aliases = ["ok"]
        draft.port = "70000"
        #expect(ConfigWriter.validate(draft) != nil)

        draft.port = "22"
        draft.localForwards = [PortForward(raw: "no-colon")]
        #expect(ConfigWriter.validate(draft) != nil)

        draft.localForwards = [PortForward(raw: "8080:localhost:80")]
        #expect(ConfigWriter.validate(draft) == nil)
    }

    @Test func storeAtomicWriteAndBackup() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sshm-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("config")
        let store = ConfigStore(configURL: url)

        try store.save("Host a\n")
        try store.save("Host a\nHost b\n")
        #expect(try store.loadText() == "Host a\nHost b\n")

        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("config.sshm-backup-") }
        #expect(backups.count == 1, "第二次写入应产生一份备份")

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.int16Value
        #expect(permissions == 0o600, "config 文件权限应为 600")
    }

    @Test func backupPruning() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sshm-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("config")
        let store = ConfigStore(configURL: url)
        try store.save("v0\n")
        for index in 0..<15 {
            try store.save("v\(index)\n")
        }
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("config.sshm-backup-") }
        #expect(backups.count == ConfigStore.maxBackups, "备份应只保留最近 10 份")
    }

    @Test func includeParsingMarksReadOnly() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sshm-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let main = directory.appendingPathComponent("config")
        let included = directory.appendingPathComponent("work_hosts")
        try "Host main\n    HostName main.example.com\n\nInclude work_hosts\n".write(to: main, atomically: true, encoding: .utf8)
        try "Host work\n    HostName work.example.com\n".write(to: included, atomically: true, encoding: .utf8)

        let parsed = try ConfigParser.parseFile(at: main)
        #expect(parsed.hosts.count == 2)
        #expect(parsed.hosts[0].primaryAlias == "main")
        #expect(!parsed.hosts[0].isReadOnly)
        #expect(parsed.hosts[1].primaryAlias == "work")
        #expect(parsed.hosts[1].isReadOnly)
        #expect(parsed.hosts[1].sourceFile == included.path)
    }
}
