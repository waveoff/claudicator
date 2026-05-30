import AppKit
import SwiftUI

@main
struct ClaudicatorApp: App {
    @StateObject private var usageStore = UsageStore()
    @StateObject private var updater = UpdaterService()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(usageStore)
                .environmentObject(updater)
                .frame(width: 280)
        } label: {
            MenuBarLabel(usage: usageStore)
        }
        // .window style renders a floating panel and — unlike the default
        // .menu style — does NOT dismiss when a button inside is tapped, so
        // "Refresh now" can spin in place instead of closing the popover.
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar item itself: a half-ring gauge that fills with the 5-hour
/// session's *used* level, with the used % tucked just under the arc. Drawn
/// as one ImageRenderer-rasterized NSImage — a separate live Text below the
/// arc would be clipped by the menu bar's height limit. Normal usage renders
/// as a template (native white/black menu bar tint); at the warning threshold
/// it becomes a fixed amber, and at the danger threshold a fixed red (both
/// non-template, to keep their color).
private struct MenuBarLabel: View {
    @ObservedObject var usage: UsageStore

    // Tweak these if proportions need nudging after a build.
    private static let arcWidth:    CGFloat = 22
    private static let arcHeight:   CGFloat = 12
    private static let lineWidth:   CGFloat = 2.5
    private static let numberSize:  CGFloat = 9    // ~30% smaller than the old inline text
    private static let maxHeight:   CGFloat = 20   // keep the composite within the menu bar slot

    var body: some View {
        Image(nsImage: glyph)
    }

    private var glyph: NSImage {
        let used: Double = usage.sessionUsed ?? 0
        // Tiers mirror the popover, but the *normal* tier stays a native
        // template (white/black menu bar tint) rather than blue — so the icon
        // is unobtrusive until usage climbs, then turns amber at 80% and red at
        // 90%. Amber/red must be non-template to keep their color; the template
        // tint is irrelevant (template rendering uses only the alpha channel).
        let colored: Bool = usage.sessionUsed != nil && used >= UsageStore.warningThreshold
        let tint: Color = used >= UsageStore.dangerThreshold  ? .claudeDanger
                        : used >= UsageStore.warningThreshold ? .claudeWarning
                        : .primary

        // When the arc is colored (amber/red) the image is non-template, so we
        // bake the number in the native menu bar label color instead of the
        // tint — only the arc changes color, the number stays unchanged. In the
        // normal tier the whole image is a template, so this color is moot.
        let isDark = NSApplication.shared.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let numberColor: Color = colored ? (isDark ? .white : .black) : tint

        let content = VStack(spacing: 1) {
            ZStack {
                HalfRing(fraction: 1)                  // faint track
                    .stroke(Color.gray.opacity(0.4),
                            style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                HalfRing(fraction: used / 100)         // colored fill
                    .stroke(tint,
                            style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
            }
            .frame(width: Self.arcWidth, height: Self.arcHeight)

            if usage.sessionUsed != nil {
                Text("\(Int(used.rounded()))%")
                    .font(.system(size: Self.numberSize, weight: .semibold))
                    .foregroundStyle(numberColor)
                    .fixedSize()
            }
        }

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        guard let image = renderer.nsImage, image.size.height > 0 else {
            let fallback = NSImage(
                systemSymbolName: "gauge.medium",
                accessibilityDescription: "Claude Quota"
            ) ?? NSImage()
            fallback.isTemplate = true
            return fallback
        }

        // Clamp to the menu bar height, preserving aspect ratio.
        if image.size.height > Self.maxHeight {
            let ratio = Self.maxHeight / image.size.height
            image.size = NSSize(width: image.size.width * ratio, height: Self.maxHeight)
        }
        // Normal: template → native menu bar tint. Warning/danger: keep color.
        image.isTemplate = !colored
        return image
    }
}

/// A 180° arc filling from the left end, over the top, to the right end.
/// `fraction` (0…1) is how much of that sweep is drawn. Built by sampling
/// points so the geometry is unambiguous regardless of arc-angle conventions.
private struct HalfRing: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clamped = max(0, min(1, fraction))
        guard clamped > 0 else { return path }

        // Inset for the stroke so round caps aren't clipped. The top needs a
        // full inset of headroom (radius leaves `inset` below the top edge),
        // the bottom needs `inset` below the diameter line — hence height-2·inset.
        let inset: CGFloat = 2
        let radius = min(rect.width / 2 - inset, rect.height - 2 * inset)
        guard radius > 0 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.maxY - inset)

        let steps = 60
        for i in 0...steps {
            let t = Double(i) / Double(steps) * clamped          // 0 … clamped
            let theta = (180.0 - 180.0 * t) * .pi / 180.0        // 180°(left) → 0°(right)
            let point = CGPoint(
                x: center.x + radius * cos(theta),
                y: center.y - radius * sin(theta)                // −sin: y grows downward
            )
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}
