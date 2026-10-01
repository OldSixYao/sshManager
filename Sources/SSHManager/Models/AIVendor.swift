import Foundation

/// 主流 AI 厂商注册表。vendor 以 id 形式存在 APIKey.vendor 中，
/// 空字符串表示「通用 / 其他」。
struct AIVendor: Identifiable, Hashable {
    let id: String
    let name: String
    let monogram: String
    let colorHex: UInt32

    static let custom = AIVendor(id: "", name: "通用 / 其他", monogram: "?", colorHex: 0x8E8E93)

    static let all: [AIVendor] = [
        AIVendor(id: "openai", name: "OpenAI", monogram: "O", colorHex: 0x10A37F),
        AIVendor(id: "claude", name: "Claude", monogram: "C", colorHex: 0xD97757),
        AIVendor(id: "deepseek", name: "DeepSeek", monogram: "D", colorHex: 0x4D6BFE),
        AIVendor(id: "gemini", name: "Gemini", monogram: "G", colorHex: 0x4285F4),
        AIVendor(id: "zhipu", name: "智谱 GLM", monogram: "智", colorHex: 0x3859FF),
        AIVendor(id: "kimi", name: "Kimi", monogram: "K", colorHex: 0x1F2937),
        AIVendor(id: "qwen", name: "通义千问", monogram: "通", colorHex: 0x615CED),
        AIVendor(id: "grok", name: "Grok", monogram: "X", colorHex: 0x1A1A1A),
        AIVendor(id: "mistral", name: "Mistral", monogram: "M", colorHex: 0xFF7000),
        custom,
    ]

    /// 按 id 查找；未知 id（历史数据）回退为通用。
    static func matching(id: String) -> AIVendor {
        all.first { $0.id == id } ?? custom
    }
}
