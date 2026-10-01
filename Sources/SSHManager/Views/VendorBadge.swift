import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// AI 厂商徽章：品牌色圆形 + 厂商 logo（白色剪影）。
/// logo 来自 Resources/logos/ 下的 SVG / PNG 文件（首次运行时从
/// simpleicons.org 等公开源抓取，来源与许可见 README），缺失时回退到单字徽章。
struct VendorBadge: View {
    let vendor: AIVendor
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: vendor.colorHex))
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
            if let glyph = VendorLogoCache.whiteGlyph(for: vendor) {
                Image(nsImage: glyph)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .padding(size * 0.18)
            } else {
                Text(vendor.monogram)
                    .font(.system(size: size * (vendor.monogram.count > 1 ? 0.38 : 0.52), weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 厂商 logo 的加载与漂白缓存。
enum VendorLogoCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func whiteGlyph(for vendor: AIVendor) -> NSImage? {
        guard let file = vendor.logoFile else { return nil }
        if let cached = cache.object(forKey: file as NSString) {
            return cached
        }
        guard let source = loadLogo(named: file) else { return nil }
        let tinted = whiteSilhouette(of: source)
        cache.setObject(tinted, forKey: file as NSString)
        return tinted
    }

    private static func loadLogo(named file: String) -> NSImage? {
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        // logos 打包在 Resources/logos/ 子目录，Bundle 查找必须显式指定 subdirectory
        let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "logos")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        return image
    }

    /// 把任意颜色的 logo 转成白色剪影（保留 alpha 形状）。
    private static func whiteSilhouette(of image: NSImage) -> NSImage {
        let canvasSize = image.size
        let result = NSImage(size: canvasSize)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: canvasSize))
        NSColor.white.setFill()
        NSRect(origin: .zero, size: canvasSize).fill(using: .sourceAtop)
        result.unlockFocus()
        return result
    }
}
