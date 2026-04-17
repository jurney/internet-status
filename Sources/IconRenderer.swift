import AppKit

struct IconRenderer {
    static let menuBarHeight: CGFloat = 22.0
    static let maxDiameter: CGFloat = 16.0
    static let minDiameter: CGFloat = 5.0
    static let ringColor = NSColor(white: 0.65, alpha: 0.4)
    static let ringWidth: CGFloat = 1.0

    // Cache to avoid re-rendering identical frames
    private static var cachedImage: NSImage?
    private static var cachedKey: UInt64 = 0

    static func render(packetLoss: Double, avgLatencyMs: Double,
                       pingMin: Double, pingMax: Double,
                       dnsFailure: Bool = false) -> NSImage {
        if dnsFailure {
            let key = hashKey(packetLoss: -1, diameter: -1, dns: true)
            if key == cachedKey, let img = cachedImage { return img }
            let img = renderDnsFailure()
            cachedKey = key
            cachedImage = img
            return img
        }

        let color = sphereColor(packetLoss: packetLoss)
        let diameter = sphereDiameter(avgLatencyMs: avgLatencyMs,
                                       pingMin: pingMin, pingMax: pingMax)

        let key = hashKey(packetLoss: packetLoss, diameter: Double(diameter), dns: false)
        if key == cachedKey, let img = cachedImage { return img }

        let size = NSSize(width: menuBarHeight, height: menuBarHeight)
        let image = NSImage(size: size, flipped: false) { rect in
            let cx = rect.width / 2
            let cy = rect.height / 2

            drawRing(cx: cx, cy: cy)

            let x = (rect.width - diameter) / 2
            let y = (rect.height - diameter) / 2
            let sphereRect = NSRect(x: x, y: y, width: diameter, height: diameter)
            drawSphere(in: sphereRect, color: color)

            return true
        }
        image.isTemplate = false
        cachedKey = key
        cachedImage = image
        return image
    }

    static func renderDisabled() -> NSImage {
        let key = hashKey(packetLoss: -2, diameter: -2, dns: false)
        if key == cachedKey, let img = cachedImage { return img }

        let color = NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        let diameter = maxDiameter

        let size = NSSize(width: menuBarHeight, height: menuBarHeight)
        let image = NSImage(size: size, flipped: false) { rect in
            let x = (rect.width - diameter) / 2
            let y = (rect.height - diameter) / 2
            let sphereRect = NSRect(x: x, y: y, width: diameter, height: diameter)
            drawSphere(in: sphereRect, color: color)
            return true
        }
        image.isTemplate = false
        cachedKey = key
        cachedImage = image
        return image
    }

    private static func renderDnsFailure() -> NSImage {
        let color = NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        let diameter = maxDiameter

        let size = NSSize(width: menuBarHeight, height: menuBarHeight)
        let image = NSImage(size: size, flipped: false) { rect in
            let x = (rect.width - diameter) / 2
            let y = (rect.height - diameter) / 2
            let sphereRect = NSRect(x: x, y: y, width: diameter, height: diameter)
            drawSphere(in: sphereRect, color: color)

            // Draw red X over the sphere
            let xColor = NSColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 0.9)
            xColor.setStroke()

            let inset: CGFloat = diameter * 0.25
            let x1 = sphereRect.minX + inset
            let y1 = sphereRect.minY + inset
            let x2 = sphereRect.maxX - inset
            let y2 = sphereRect.maxY - inset

            let line1 = NSBezierPath()
            line1.lineWidth = 2.0
            line1.lineCapStyle = .round
            line1.move(to: NSPoint(x: x1, y: y1))
            line1.line(to: NSPoint(x: x2, y: y2))
            line1.stroke()

            let line2 = NSBezierPath()
            line2.lineWidth = 2.0
            line2.lineCapStyle = .round
            line2.move(to: NSPoint(x: x1, y: y2))
            line2.line(to: NSPoint(x: x2, y: y1))
            line2.stroke()

            return true
        }
        image.isTemplate = false
        return image
    }

    private static func hashKey(packetLoss: Double, diameter: Double, dns: Bool) -> UInt64 {
        // Quantize to avoid floating point churn — color changes at thresholds,
        // diameter changes in ~0.5pt steps
        let colorBucket: UInt64
        if dns { colorBucket = 99 }
        else if packetLoss < 0 { colorBucket = 98 }  // disabled
        else if packetLoss <= 0 { colorBucket = 0 }
        else if packetLoss <= 20 { colorBucket = 1 }
        else if packetLoss <= 80 { colorBucket = 2 }
        else { colorBucket = 3 }

        let diamBucket = diameter < 0 ? 999 : UInt64(diameter * 2)  // 0.5pt resolution
        return colorBucket * 1000 + diamBucket
    }

    private static func drawRing(cx: CGFloat, cy: CGFloat) {
        let ringRadius = (maxDiameter - ringWidth) / 2
        let ringRect = NSRect(x: cx - ringRadius, y: cy - ringRadius,
                              width: ringRadius * 2, height: ringRadius * 2)
        let path = NSBezierPath(ovalIn: ringRect)
        path.lineWidth = ringWidth
        ringColor.setStroke()
        path.stroke()
    }

    private static func sphereColor(packetLoss: Double) -> NSColor {
        if packetLoss <= 0 {
            return NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0)     // green: 0%
        } else if packetLoss <= 20 {
            return NSColor(red: 0.95, green: 0.85, blue: 0.1, alpha: 1.0)   // yellow: >0–20%
        } else if packetLoss <= 80 {
            return NSColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1.0)    // orange: >20–80%
        } else {
            return NSColor(red: 0.9, green: 0.15, blue: 0.15, alpha: 1.0)   // red: >80%
        }
    }

    private static func sphereDiameter(avgLatencyMs: Double,
                                        pingMin: Double, pingMax: Double) -> CGFloat {
        // t = 0.0 at pingMin (fast), 1.0 at pingMax (slow)
        let clamped = min(max(avgLatencyMs, pingMin), pingMax)
        let t = (clamped - pingMin) / (pingMax - pingMin)

        // Have more falloff from slight loss of ping vs min.
        let steepness = 1.4
        // curved describes degree of shrinkage
        // curved = 0.0 at pingMin, ~.85 at t=0.5, 1.0 at pingMax
        let curved = 1.0 - pow((-log10((t * 0.9) + 0.1)), steepness)

        // diameter goes from maxDiameter (fast) down to minDiameter (slow)
        return maxDiameter - CGFloat(curved) * (maxDiameter - minDiameter)
    }

    private static func drawSphere(in rect: NSRect, color: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let cx = rect.midX
        let cy = rect.midY
        let radius = rect.width / 2

        let highlightColor = color.blended(withFraction: 0.6, of: .white) ?? color
        let shadowColor = color.blended(withFraction: 0.5, of: .black) ?? color

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [highlightColor.cgColor, color.cgColor, shadowColor.cgColor] as CFArray
        let locations: [CGFloat] = [0.0, 0.5, 1.0]

        guard let gradient = CGGradient(colorsSpace: colorSpace,
                                         colors: colors,
                                         locations: locations) else { return }

        ctx.saveGState()

        let path = CGPath(ellipseIn: rect, transform: nil)
        ctx.addPath(path)
        ctx.clip()

        let highlightCenter = CGPoint(x: cx - radius * 0.3, y: cy + radius * 0.3)
        ctx.drawRadialGradient(gradient,
                                startCenter: highlightCenter,
                                startRadius: 0,
                                endCenter: CGPoint(x: cx, y: cy),
                                endRadius: radius,
                                options: [.drawsAfterEndLocation])

        ctx.restoreGState()
    }
}
