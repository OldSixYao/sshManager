import Foundation
import Testing
@testable import SSHManager

struct APIKeyTests {

    @Test func storeRoundTrip() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sshm-apikeys-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = APIKeyStore(fileURL: directory.appendingPathComponent("apikeys.json"))

        // 首次读取：文件不存在 → 空
        #expect(try store.load().isEmpty)

        let key = APIKey(
            name: "智谱",
            provider: "国内",
            vendor: "zhipu",
            baseURL: "https://open.bigmodel.cn/api/paas/v4",
            apiKey: "sk-test-1234567890abcdef",
            website: "https://open.bigmodel.cn",
            models: ["glm-4.6", "glm-4.5-air"]
        )
        try store.save([key])
        let loaded = try store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == key.id)
        #expect(loaded[0].name == "智谱")
        #expect(loaded[0].provider == "国内")
        #expect(loaded[0].vendor == "zhipu")
        #expect(loaded[0].baseURL == key.baseURL)
        #expect(loaded[0].apiKey == key.apiKey)
        #expect(loaded[0].models == ["glm-4.6", "glm-4.5-air"])

        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.int16Value == 0o600, "密钥文件权限应为 600")
    }

    @Test func legacyJSONWithoutProviderDecodesAsUngrouped() throws {
        // 供应商字段加入前的旧格式应能正常读取，provider 视为未分组
        let legacy = #"{"name":"旧记录","baseURL":"https://api.example.com","apiKey":"sk-x","createdAt":"2026-01-02T03:04:05Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let key = try decoder.decode(APIKey.self, from: Data(legacy.utf8))
        #expect(key.name == "旧记录")
        #expect(key.provider.isEmpty)
        #expect(key.models.isEmpty)
    }

    @Test func normalizeBaseURL() {
        #expect(APIKeyTester.normalizeBaseURL("https://api.example.com/v1/")?.absoluteString == "https://api.example.com/v1")
        #expect(APIKeyTester.normalizeBaseURL("  api.example.com ")?.absoluteString == "https://api.example.com")
        #expect(APIKeyTester.normalizeBaseURL("http://localhost:8000/v1")?.absoluteString == "http://localhost:8000/v1")
        #expect(APIKeyTester.normalizeBaseURL("") == nil)
        #expect(APIKeyTester.normalizeBaseURL("ht tp://bad") == nil)
    }

    @Test func modelsURL() {
        #expect(
            APIKeyTester.modelsURL(forBaseURL: "https://api.example.com/v1")?.absoluteString
                == "https://api.example.com/v1/models"
        )
        #expect(
            APIKeyTester.modelsURL(forBaseURL: "https://api.example.com/v1/")?.absoluteString
                == "https://api.example.com/v1/models"
        )
        #expect(
            APIKeyTester.modelsURL(forBaseURL: "https://api.example.com")?.absoluteString
                == "https://api.example.com/v1/models"
        )
        #expect(
            APIKeyTester.modelsURL(forBaseURL: "https://api.example.com/api/paas/v4")?.absoluteString
                == "https://api.example.com/api/paas/v4/models"
        )
        #expect(
            APIKeyTester.modelsURL(forBaseURL: "https://api.example.com/v2")?.absoluteString
                == "https://api.example.com/v2/models"
        )
    }

    @Test func maskedKey() {
        #expect(APIKeyTester.masked("sk-abcdefghijklmnopqrstuvwxyz") == "sk-a…wxyz")
        #expect(APIKeyTester.masked("short") == "•••••")
        #expect(APIKeyTester.masked("12345678") == "••••••••")
        #expect(APIKeyTester.masked("123456789") == "1234…6789")
    }

    @Test func parseModelIDs() {
        // OpenAI 兼容形态，且自动去重保序
        let openAI = Data(#"{"data":[{"id":"gpt-4o"},{"id":"gpt-4o-mini"},{"id":"gpt-4o"}]}"#.utf8)
        #expect(APIKeyTester.parseModelIDs(from: openAI) == ["gpt-4o", "gpt-4o-mini"])

        // models[].name 形态（Gemini 风格），去掉 models/ 前缀
        let gemini = Data(#"{"models":[{"name":"models/gemini-2.0"},{"name":"models/gemini-1.5"}]}"#.utf8)
        #expect(APIKeyTester.parseModelIDs(from: gemini) == ["gemini-2.0", "gemini-1.5"])

        // 空列表与非法 JSON
        #expect(APIKeyTester.parseModelIDs(from: Data(#"{"data":[]}"#.utf8)).isEmpty)
        #expect(APIKeyTester.parseModelIDs(from: Data("not json".utf8)).isEmpty)
    }

    @Test func ccSwitchDeepLink() throws {
        let key = APIKey(
            name: "deepkey OpenAI",
            provider: "deepkey",
            vendor: "openai",
            baseURL: "https://deepkey.top/v1",
            apiKey: "sk-secret-123",
            website: "https://deepkey.top",
            models: ["gpt-5.6-sol", "gpt-5.5"]
        )
        let url = try #require(CCSwitchExporter.deepLink(for: key))
        #expect(url.scheme == "ccswitch")
        #expect(url.host == "v1")
        #expect(url.path == "/import")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            .queryItems!
        #expect(URLQueryItem(name: "resource", value: "provider") == items.first { $0.name == "resource" })
        #expect(items.first { $0.name == "app" }?.value == "codex")
        #expect(items.first { $0.name == "name" }?.value == "deepkey OpenAI")
        #expect(items.first { $0.name == "endpoint" }?.value == "https://deepkey.top/v1")
        #expect(items.first { $0.name == "apiKey" }?.value == "sk-secret-123")
        #expect(items.first { $0.name == "homepage" }?.value == "https://deepkey.top")
        #expect(items.first { $0.name == "model" }?.value == "gpt-5.6-sol")
        #expect(items.first { $0.name == "notes" }?.value?.contains("deepkey") == true)

        // Claude 厂商映射到 claude 应用
        let claudeKey = APIKey(name: "c", vendor: "claude", baseURL: "https://a.com", apiKey: "k")
        #expect(CCSwitchExporter.appType(for: claudeKey) == "claude")
        let geminiKey = APIKey(name: "g", vendor: "gemini", baseURL: "https://g.com", apiKey: "k")
        #expect(CCSwitchExporter.appType(for: geminiKey) == "gemini")
    }

    @Test func curlExample() {
        let key = APIKey(name: "t", baseURL: "https://api.example.com/v1", apiKey: "sk-secret")
        #expect(
            APIKeyTester.curlExample(for: key)
                == "curl -s https://api.example.com/v1/models -H \"Authorization: Bearer sk-secret\""
        )
    }

    @Test func validation() {
        #expect(APIKey.validate(name: "", baseURL: "https://a.com", apiKey: "k", models: []) != nil)
        #expect(APIKey.validate(name: "n", baseURL: "bad url", apiKey: "k", models: []) != nil)
        #expect(APIKey.validate(name: "n", baseURL: "https://a.com", apiKey: " ", models: []) != nil)
        #expect(APIKey.validate(name: "n", baseURL: "https://a.com", apiKey: "k", models: [""]) != nil)
        #expect(APIKey.validate(name: "n", baseURL: "a.com", apiKey: "k", models: ["glm-4"]) == nil)
    }
}
