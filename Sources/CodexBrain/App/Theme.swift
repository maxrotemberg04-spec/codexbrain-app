import SwiftUI
import AppKit

/// Design tokens v2 — founder cockpit. Deep warm near-black base, ONE amber accent
/// (its gradient reserved for tiny elements: progress ring, dock icon), hairline
/// strokes over shadows, one radius system (10 cards / 6 controls). Dark-first.
enum Theme {
    static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    static let bg = dynamic(rgb(246, 245, 241), rgb(15, 16, 19))
    static let surface = dynamic(rgb(255, 255, 255), rgb(23, 24, 28))
    static let surfaceRaised = dynamic(rgb(251, 250, 247), rgb(29, 31, 36))
    static let surfaceHover = dynamic(rgb(240, 238, 233), rgb(36, 38, 44))
    static let textPrimary = dynamic(rgb(32, 31, 29), rgb(236, 234, 228))
    static let textSecondary = dynamic(rgb(115, 111, 104), rgb(142, 147, 155))
    static let stroke = dynamic(NSColor.black.withAlphaComponent(0.09), NSColor.white.withAlphaComponent(0.08))
    static let accent = dynamic(rgb(169, 118, 31), rgb(232, 169, 78))
    static let accentDeep = dynamic(rgb(140, 95, 22), rgb(199, 127, 42))
    static let accentSoft = dynamic(rgb(169, 118, 31).withAlphaComponent(0.10), rgb(232, 169, 78).withAlphaComponent(0.13))

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let radiusCard: CGFloat = 10
    static let radiusControl: CGFloat = 6

    static let mono = Font.system(size: 11, design: .monospaced)
    static let monoSmall = Font.system(size: 10, design: .monospaced)

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Runtime Dock icon: near-black rounded square, amber star. Real .icns is a named upgrade.
    static func dockIcon() -> NSImage {
        NSImage(size: NSSize(width: 512, height: 512), flipped: false) { rect in
            let inset = rect.insetBy(dx: 44, dy: 44)
            let path = NSBezierPath(roundedRect: inset, xRadius: 100, yRadius: 100)
            rgb(15, 16, 19).setFill()
            path.fill()
            let star = "✦" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 250, weight: .semibold),
                .foregroundColor: rgb(232, 169, 78),
            ]
            let size = star.size(withAttributes: attrs)
            star.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
            return true
        }
    }
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

/// Staggered entrance for the dashboard: one orchestrated moment, then stillness.
struct Rise: ViewModifier {
    let index: Int
    let shown: Bool
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .animation(
                Theme.reduceMotion ? nil
                    : .spring(response: 0.5, dampingFraction: 0.85).delay(Double(index) * 0.06),
                value: shown
            )
    }
}

/// Translucent sidebar material so the window feels native, not painted.
/// (Named to avoid clashing with SwiftUI's VisualEffect protocol.)
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// In-window glass: blurs the app content BEHIND the panel, not the desktop.
/// This is the honest macOS-15 build of the Liquid Glass look; on macOS 26 the
/// real .glassEffect() API takes over via glassBackground(radius:).
struct GlassPanel: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension View {
    /// Specular hairline: bright top edge fading down, like light catching glass.
    func specularBorder(radius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.05)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    func glassBackground(radius: CGFloat) -> some View {
        self
            .background(GlassPanel().clipShape(RoundedRectangle(cornerRadius: radius)))
            .specularBorder(radius: radius)
            .shadow(color: .black.opacity(0.35), radius: 34, y: 14)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardBackground(padding: padding)) }
    func rise(_ index: Int, _ shown: Bool) -> some View { modifier(Rise(index: index, shown: shown)) }
}
