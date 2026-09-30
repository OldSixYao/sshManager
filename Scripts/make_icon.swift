// 生成 SSH Manager 应用图标（1024×1024 母版 PNG）
// 用法: swift Scripts/make_icon.swift Resources/icon_1024.png
import CoreGraphics
import CoreText
import ImageIO
import Foundation

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/icon_1024.png"

let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// MARK: - 背景圆角方块（macOS 图标网格：824×824，圆角 185）

let inset: CGFloat = 100
let side: CGFloat = CGFloat(size) - 2 * inset
let cornerRadius: CGFloat = 185
let backgroundRect = CGRect(x: inset, y: inset, width: side, height: side)
let backgroundPath = CGPath(roundedRect: backgroundRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

ctx.addPath(backgroundPath)
ctx.clip()

// 深海军蓝纵向渐变
let backgroundGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [color(0x33415E), color(0x0D1524)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    backgroundGradient,
    start: CGPoint(x: 512, y: 924),
    end: CGPoint(x: 512, y: 100),
    options: []
)

// 左上角蓝色光晕
let glow = CGGradient(
    colorsSpace: colorSpace,
    colors: [color(0x4C6FFF, 0.32), color(0x4C6FFF, 0)] as CFArray,
    locations: [0, 1]
)!
ctx.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: 300, y: 830), startRadius: 0,
    endCenter: CGPoint(x: 300, y: 830), endRadius: 640,
    options: []
)

// MARK: - 终端窗口（浅色窗体 + 投影，深底上很跳）

let windowRect = CGRect(x: 192, y: 318, width: 640, height: 452)
let windowPath = CGPath(roundedRect: windowRect, cornerWidth: 40, cornerHeight: 40, transform: nil)

ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 48, color: color(0x000000, 0.45))
ctx.addPath(windowPath)
ctx.setFillColor(color(0xF7FAFD))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// 标题栏与窗体内容（裁剪在窗口内）
ctx.saveGState()
ctx.addPath(windowPath)
ctx.clip()

let titleBarHeight: CGFloat = 84
let titleBarTop = windowRect.maxY
ctx.setFillColor(color(0xE8EEF6))
ctx.fill(CGRect(x: windowRect.minX, y: titleBarTop - titleBarHeight, width: windowRect.width, height: titleBarHeight))
ctx.setFillColor(color(0xD5DEE9))
ctx.fill(CGRect(x: windowRect.minX, y: titleBarTop - titleBarHeight - 2, width: windowRect.width, height: 2))

// 红绿灯
let trafficLights: [(UInt32, CGFloat)] = [(0xFF5F57, 264), (0xFEBC2E, 324), (0x28C840, 384)]
for (hex, centerX) in trafficLights {
    ctx.setFillColor(color(hex))
    ctx.fillEllipse(in: CGRect(x: centerX - 16, y: titleBarTop - 58, width: 32, height: 32))
}

//MARK: 提示符：几何绘制的 ">" + "ssh" 文本 + 光标块

// ">" 形箭头（纯几何，小尺寸下依旧锐利）
ctx.setStrokeColor(color(0x22314A))
ctx.setLineWidth(34)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: 296, y: 566))
ctx.addLine(to: CGPoint(x: 380, y: 478))
ctx.addLine(to: CGPoint(x: 296, y: 390))
ctx.strokePath()

// "ssh" 文本（Menlo 等宽字体）
let font = CTFontCreateWithName("Menlo-Bold" as CFString, 112, nil)
let attributes = [
    kCTFontAttributeName: font,
    kCTForegroundColorAttributeName: color(0x22314A)
] as CFDictionary
if let attributed = CFAttributedStringCreate(nil, "ssh" as CFString, attributes) {
    let line = CTLineCreateWithAttributedString(attributed)
    ctx.textPosition = CGPoint(x: 424, y: 402)
    CTLineDraw(line, ctx)
}

// 绿色光标块（在命令之后，符合终端习惯）
let cursorRect = CGRect(x: 656, y: 382, width: 72, height: 192)
ctx.setFillColor(color(0x2BC79A))
ctx.addPath(CGPath(roundedRect: cursorRect, cornerWidth: 14, cornerHeight: 14, transform: nil))
ctx.fillPath()

ctx.restoreGState()

// 窗口描边（增加边缘立体感）
ctx.addPath(windowPath)
ctx.setStrokeColor(color(0xFFFFFF, 0.45))
ctx.setLineWidth(3)
ctx.strokePath()

// MARK: - 导出

let image = ctx.makeImage()!
let outputURL = URL(fileURLWithPath: outPath) as CFURL
let destination = CGImageDestinationCreateWithURL(outputURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("已生成: \(outPath)")
