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

    func edgeSwipeToDismiss(enabled: Bool = true) -> some View {
        modifier(EdgeSwipeDismissModifier(isEnabled: enabled))
    }
}

private struct EdgeSwipeDismissModifier: ViewModifier {
    let isEnabled: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var isTracking = false

    func body(content: Content) -> some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            content.offset(x: offset)
        }
        .simultaneousGesture(isEnabled ? edgeDrag : nil)
    }

    private var edgeDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                if !isTracking {
                    guard value.startLocation.x <= 24,
                          value.translation.width > 0,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    isTracking = true
                }
                offset = max(0, value.translation.width)
            }
            .onEnded { value in
                guard isTracking else { return }
                isTracking = false
                let shouldDismiss = value.translation.width > 88 || value.predictedEndTranslation.width > 180
                guard shouldDismiss else {
                    withAnimation(reduceMotion ? AppMotion.reduced : AppMotion.spatial) { offset = 0 }
                    return
                }
                let width = max(UIScreen.main.bounds.width, 320)
                withAnimation(reduceMotion ? AppMotion.reduced : .easeOut(duration: 0.18)) { offset = width }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(reduceMotion ? 30 : 180))
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { dismiss() }
                }
            }
    }
}
