import SwiftUI

struct TrailingDotsRefreshScrollView<Content: View>: View {
    private let threshold: CGFloat = 72
    private let isEnabled: Bool
    private let action: @MainActor () async -> Void
    private let content: Content

    @State private var pullDistance: CGFloat = 0
    @State private var previousPullDistance: CGFloat = 0
    @State private var isArmed = false
    @State private var isRefreshing = false

    init(
        isEnabled: Bool = true,
        action: @escaping @MainActor () async -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isEnabled = isEnabled
        self.action = action
        self.content = content()
    }

    var body: some View {
        ScrollView {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: PullDistancePreferenceKey.self,
                        value: max(0, proxy.frame(in: .named("trailing-dots-refresh")).minY)
                    )
            }
            .frame(height: 0)

            content
        }
        .coordinateSpace(name: "trailing-dots-refresh")
        .scrollIndicators(.hidden)
        .onPreferenceChange(PullDistancePreferenceKey.self, perform: updatePullDistance)
        .overlay(alignment: .top) {
            if isEnabled && (pullDistance > 2 || isRefreshing) {
                TrailingDots(size: 28)
                    .padding(8)
                    .background(.black.opacity(0.72), in: Circle())
                    .opacity(isRefreshing ? 1 : pullProgress)
                    .scaleEffect(isRefreshing ? 1 : 0.72 + pullProgress * 0.28)
                    .offset(y: isRefreshing ? 8 : max(8, pullDistance - 44))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAction(named: Text("刷新")) {
            beginRefresh()
        }
    }

    private var pullProgress: CGFloat {
        min(1, pullDistance / threshold)
    }

    private func updatePullDistance(_ distance: CGFloat) {
        guard isEnabled else {
            pullDistance = 0
            previousPullDistance = 0
            isArmed = false
            return
        }

        pullDistance = distance
        if distance >= threshold { isArmed = true }

        let isReturning = distance < previousPullDistance
        if isArmed && isReturning && distance <= threshold * 0.72 {
            isArmed = false
            beginRefresh()
        } else if distance <= 1 {
            isArmed = false
        }
        previousPullDistance = distance
    }

    private func beginRefresh() {
        guard isEnabled, !isRefreshing else { return }
        isRefreshing = true
        Task { @MainActor in
            await action()
            isRefreshing = false
        }
    }
}

private struct PullDistancePreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
