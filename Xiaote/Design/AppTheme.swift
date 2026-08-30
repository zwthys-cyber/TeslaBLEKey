import SwiftUI

enum AppTheme {
    static let background = Color.black
    static let surface = Color.white.opacity(0.06)
    static let raised = Color.white.opacity(0.10)
    static let hairline = Color.white.opacity(0.16)
    static let muted = Color.white.opacity(0.55)
}

enum AppMotion {
    /// Immediate feedback for controls used repeatedly.
    static let press = Animation.easeOut(duration: 0.14)
    /// Cross-fades between semantic icon and label states.
    static let state = Animation.easeOut(duration: 0.22)
    /// Rare spatial continuity, deliberately critically damped.
    static let spatial = Animation.spring(response: 0.36, dampingFraction: 1)
    static let reduced = Animation.easeOut(duration: 0.20)
}

struct PrimaryPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(AppMotion.press, value: configuration.isPressed)
    }
}

struct UtilityPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(AppMotion.press, value: configuration.isPressed)
    }
}

struct ActionPressStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? (primary ? 0.97 : 0.98) : 1)
            .opacity(configuration.isPressed ? (primary ? 0.84 : 0.82) : 1)
            .animation(AppMotion.press, value: configuration.isPressed)
    }
}

struct HairlinePanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 0.5)
            }
    }
}

private struct DestinationPageModifier: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .background(AppTheme.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
}

extension View {
    /// Restores the navigation bar hidden by a root page. NavigationStack owns
    /// the opaque push/pop animation so the previous page never shows through.
    func appDestinationPage(title: String) -> some View {
        modifier(DestinationPageModifier(title: title))
    }
}
