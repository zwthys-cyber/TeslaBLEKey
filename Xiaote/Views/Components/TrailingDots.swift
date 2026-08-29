import SwiftUI

struct TrailingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var size: CGFloat = 40
    var color: Color = .white

    private let dotCount = 5
    private let cycleDuration = 1.5
    private let delay = 0.1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            ZStack {
                ForEach(0..<dotCount, id: \.self) { index in
                    dot(index)
                        .rotationEffect(.degrees(angle(for: index, at: timeline.date)))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func dot(_ index: Int) -> some View {
        Circle()
            .fill(color)
            .frame(width: dotSize, height: dotSize)
            .opacity(1 - Double(index) * 0.18)
            .frame(width: size, height: size, alignment: .top)
    }

    private func angle(for index: Int, at date: Date) -> Double {
        if reduceMotion {
            return Double(index) * (360 / Double(dotCount))
        }

        let delayedTime = date.timeIntervalSinceReferenceDate - Double(index) * delay
        let progress = delayedTime.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        let normalized = progress < 0 ? progress + 1 : progress
        let eased = 0.5 - cos(.pi * normalized) / 2
        return eased * 360
    }

    private var dotSize: CGFloat {
        max(3, size * 0.2)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        TrailingDots()
    }
}
