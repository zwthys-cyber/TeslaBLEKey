import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.035, green: 0.039, blue: 0.05)
    static let surface = Color.white.opacity(0.075)
    static let hairline = Color.white.opacity(0.11)
    static let accent = Color(red: 0.3, green: 0.66, blue: 1)
    static let muted = Color.white.opacity(0.58)
}

struct PremiumPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 1), value: configuration.isPressed)
    }
}

struct GlassPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 0.7)
            }
    }
}

