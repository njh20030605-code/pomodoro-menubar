import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}

// 背景圆角方块（squircle）+ 阴影
let margin = size * 0.09
let bgRect = NSRect(x: margin, y: margin, width: size - 2*margin, height: size - 2*margin)
let corner = bgRect.width * 0.2237
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: corner, yRadius: corner)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40,
              color: rgb(0, 0, 0, 0.22).cgColor)
let bgGrad = NSGradient(colors: [rgb(255, 244, 232), rgb(255, 214, 178)])!
bgGrad.draw(in: bgPath, angle: -90)
ctx.restoreGState()

// 内高光描边
rgb(255, 255, 255, 0.35).setStroke()
let stroke = NSBezierPath(roundedRect: bgRect.insetBy(dx: 3, dy: 3), xRadius: corner, yRadius: corner)
stroke.lineWidth = 5
stroke.stroke()

// 番茄本体
let cx = bgRect.midX
let cy = bgRect.midY - bgRect.height * 0.03
let bodyW = bgRect.width * 0.66
let bodyH = bodyW * 0.90
let bodyRect = NSRect(x: cx - bodyW/2, y: cy - bodyH/2, width: bodyW, height: bodyH)
let bodyPath = NSBezierPath(ovalIn: bodyRect)

// 番茄阴影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(180, 30, 20, 0.35).cgColor)
rgb(230, 57, 46).setFill()
bodyPath.fill()
ctx.restoreGState()

// 径向渐变（左上高光 -> 深红）
let bodyGrad = NSGradient(colors: [rgb(255, 120, 95), rgb(233, 60, 48), rgb(190, 32, 28)])!
bodyGrad.draw(in: bodyPath, relativeCenterPosition: NSPoint(x: -0.28, y: 0.32))

// 顶部柔和高光
let hl = NSBezierPath(ovalIn: NSRect(x: cx - bodyW*0.30, y: cy + bodyH*0.05,
                                     width: bodyW*0.42, height: bodyH*0.30))
rgb(255, 255, 255, 0.28).setFill()
hl.fill()

// 绿色蒂/叶片（星形）
let leafCX = cx
let leafCY = cy + bodyH * 0.40
let outerR = bodyW * 0.26
let innerR = outerR * 0.40
let star = NSBezierPath()
let points = 5
for i in 0..<(points * 2) {
    let r = (i % 2 == 0) ? outerR : innerR
    let angle = CGFloat.pi/2 + CGFloat(i) * CGFloat.pi / CGFloat(points)
    let px = leafCX + cos(angle) * r
    let py = leafCY + sin(angle) * r
    if i == 0 { star.move(to: NSPoint(x: px, y: py)) }
    else { star.line(to: NSPoint(x: px, y: py)) }
}
star.close()
let leafGrad = NSGradient(colors: [rgb(126, 200, 92), rgb(74, 156, 62)])!
leafGrad.draw(in: star, angle: -90)

// 叶片中心小圆
let core = NSBezierPath(ovalIn: NSRect(x: leafCX - outerR*0.22, y: leafCY - outerR*0.22,
                                       width: outerR*0.44, height: outerR*0.44))
rgb(90, 170, 70).setFill()
core.fill()

// 短茎
let stem = NSBezierPath(roundedRect: NSRect(x: leafCX - bodyW*0.028, y: leafCY + outerR*0.15,
                                            width: bodyW*0.056, height: bodyH*0.14),
                        xRadius: bodyW*0.028, yRadius: bodyW*0.028)
rgb(88, 150, 66).setFill()
stem.fill()

NSGraphicsContext.restoreGraphicsState()

let outURL = URL(fileURLWithPath: CommandLine.arguments[1])
if let data = rep.representation(using: .png, properties: [:]) {
    try! data.write(to: outURL)
    print("icon written: \(outURL.path)")
}
