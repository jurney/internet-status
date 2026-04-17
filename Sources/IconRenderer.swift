import AppKit

struct IconRenderer {
    static let menuBarHeight: CGFloat = 22.0
    static let maxDiameter: CGFloat = 16.0
    static let minDiameter: CGFloat = 10.0
    static let ringColor = NSColor(white: 0.65, alpha: 0.4)
    static let ringWidth: CGFloat = 1.0

    static func render(packetLoss: Double, avgLatencyMs: Double,
                       pingMin: Double, pingMax: Double) -> NSImage {
        let color = sphereColor(packetLoss: packetLoss)
        let diameter = sphereDiameter(avgLatencyMs: avgLatencyMs,
                                       pingMin: pingMin, pingMax: pingMax)

        let size = NSSize(width: menuBarHeight, height: menuBarHeight)
        let image = NSImage(size: size, flipped: false) { rect in
            let cx = rect.width / 2
            let cy = rect.height / 2

            // Background ring at full size
            drawRing(cx: cx, cy: cy)

            // Foreground sphere at current size
            let x = (rect.width - diameter) / 2
            let y = (rect.height - diameter) / 2
            let sphereRect = NSRect(x: x, y: y, width: diameter, height: diameter)
            drawSphere(in: sphereRect, color: color)

            return true
        }
        image.isTemplate = false
        return image
    }

    static func renderDisabled() -> NSImage {
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
        return image
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
        let clamped = min(max(avgLatencyMs, pingMin), pingMax)
        let t = (clamped - pingMin) / (pingMax - pingMin)
        return maxDiameter - CGFloat(t) * (maxDiameter - minDiameter)
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

        // Highlight center offset up-left for 3D look
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
