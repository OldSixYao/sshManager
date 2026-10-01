// 渲染厂商徽章预览条到 /tmp/vendor_badges.png，用于人工核验 logo 加载与漂白效果
// 用法: swift Scripts/render_vendor_preview.swift
import AppKit

let logosDir = "Resources/logos"
let vendors: [(name: String, monogram: String, colorHex: UInt32, file: String?)] = [
    ("OpenAI", "O", 0x10A37F, "openai.svg"),
    ("Claude", "C", 0xD97757, "anthropic.svg"),
    ("DeepSeek", "D", 0x4D6BFE, "deepseek.svg"),
    ("Gemini", "G", 0x4285F4, "googlegemini.svg"),
    ("智谱", "智", 0x3859FF, "zhipu_favicon.png"),
    ("Kimi", "K", 0x1F2937, "kimi.svg"),
    ("通义", "通", 0x615CED, "qwen.svg"),
    ("Grok", "X", 0x1A1A1A, "x.svg"),
    ("Mistral", "M", 0xFF7000, "mistralai.svg"),
    ("通用", "?", 0x8E8E93, nil),
]

func whiteSilhouette(of image: NSImage) -> NSImage {
    let size = image.size
    let result = NSImage(size: size)
    result.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: size))
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
    result.unlockFocus()
    return result
}

let cell = 88
let badge: CGFloat = 64
let canvas = NSImage(size: NSSize(width: cell * vendors.count, height: cell))
canvas.lockFocus()
NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
NSRect(origin: .zero, size: canvas.size).fill()

for (index, vendor) in vendors.enumerated() {
    let origin = CGPoint(x: CGFloat(index * cell) + (CGFloat(cell) - badge) / 2,
                         y: (CGFloat(cell) - badge) / 2)
    let rect = NSRect(origin: origin, size: CGSize(width: badge, height: badge))

    let color = NSColor(srgbRed: CGFloat((vendor.colorHex >> 16) & 0xFF) / 255,
                        green: CGFloat((vendor.colorHex >> 8) & 0xFF) / 255,
                        blue: CGFloat(vendor.colorHex & 0xFF) / 255, alpha: 1)
    color.setFill()
    NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()

    var drewGlyph = false
    if let file = vendor.file,
       let image = NSImage(contentsOf: URL(fileURLWithPath: "\(logosDir)/\(file)")) {
        let tinted = whiteSilhouette(of: image)
        let inset = badge * 0.2
        let glyphRect = rect.insetBy(dx: inset, dy: inset)
        tinted.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1)
        drewGlyph = true
    }
    if !drewGlyph {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: badge * 0.45, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: vendor.monogram, attributes: attributes)
        let textSize = text.size()
        text.draw(at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
    }

    let label = NSAttributedString(string: vendor.name, attributes: [
        .font: NSFont.systemFont(ofSize: 10),
        .foregroundColor: NSColor.white,
    ])
    let labelSize = label.size()
    label.draw(at: CGPoint(x: rect.midX - labelSize.width / 2, y: origin.y - 14))
}
canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else { fatalError("导出失败") }
try! png.write(to: URL(fileURLWithPath: "/tmp/vendor_badges.png"))
print("已输出 /tmp/vendor_badges.png")
