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

/// AI 厂商徽章：品牌色圆形 + 单字。不依赖外部图片素材。
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
            Text(vendor.monogram)
                .font(.system(size: size * (vendor.monogram.count > 1 ? 0.38 : 0.52), weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
