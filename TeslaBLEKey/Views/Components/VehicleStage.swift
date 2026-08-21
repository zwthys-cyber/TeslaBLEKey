import SwiftUI

enum VehicleStageState: Equatable {
    case searching, found, awaitingCard, connecting, ready
    case executing, success

    var accessibilityValue: String {
        switch self {
        case .searching: "正在搜索车辆"
        case .found: "已发现附近车辆"
        case .awaitingCard: "等待钥匙卡确认"
        case .connecting: "正在安全连接"
        case .ready: "车辆已连接"
        case .executing: "正在执行车辆操作"
        case .success: "车辆操作完成"
        }
    }
}

struct VehicleStage: View {
    let state: VehicleStageState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ground
            VehicleSilhouette()
                .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .opacity(state == .searching ? 0.38 : 1)
                .scaleEffect(reduceMotion ? 1 : scale)
                .offset(y: reduceMotion ? 0 : offset)

            if state == .searching || state == .connecting || state == .executing {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .offset(y: 54)
                    .transition(.opacity)
            } else if state == .awaitingCard {
                Image(systemName: "creditcard")
                    .font(.system(size: 18, weight: .medium))
                    .offset(y: 54)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            } else if state == .success {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .offset(y: 54)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(2.25, contentMode: .fit)
        .animation(reduceMotion ? AppMotion.reduced : AppMotion.spatial, value: state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("车辆")
        .accessibilityValue(state.accessibilityValue)
    }

    private var scale: CGFloat {
        switch state {
        case .searching: 0.96
        case .success: 1.015
        default: 1
        }
    }

    private var offset: CGFloat { state == .searching ? 3 : 0 }

    private var ground: some View {
        Capsule()
            .fill(Color.white.opacity(state == .ready || state == .success ? 0.18 : 0.08))
            .frame(width: 208, height: 1)
            .offset(y: 38)
    }
}

private struct VehicleSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
        var path = Path()
        path.move(to: p(0.10, 0.61))
        path.addCurve(to: p(0.24, 0.52), control1: p(0.14, 0.57), control2: p(0.19, 0.54))
        path.addCurve(to: p(0.38, 0.32), control1: p(0.29, 0.43), control2: p(0.33, 0.35))
        path.addCurve(to: p(0.61, 0.30), control1: p(0.45, 0.29), control2: p(0.55, 0.28))
        path.addCurve(to: p(0.75, 0.49), control1: p(0.67, 0.34), control2: p(0.71, 0.42))
        path.addCurve(to: p(0.89, 0.56), control1: p(0.81, 0.51), control2: p(0.86, 0.53))
        path.addCurve(to: p(0.91, 0.68), control1: p(0.91, 0.59), control2: p(0.92, 0.64))
        path.addLine(to: p(0.84, 0.70))
        path.move(to: p(0.16, 0.70))
        path.addLine(to: p(0.10, 0.67))
        path.addLine(to: p(0.10, 0.61))
        path.move(to: p(0.31, 0.69))
        path.addLine(to: p(0.69, 0.69))
        path.move(to: p(0.38, 0.34))
        path.addLine(to: p(0.43, 0.51))
        path.addLine(to: p(0.72, 0.50))
        path.move(to: p(0.50, 0.32))
        path.addLine(to: p(0.50, 0.51))
        path.addEllipse(in: CGRect(x: 0.18 * w, y: 0.60 * h, width: 0.13 * w, height: 0.20 * h))
        path.addEllipse(in: CGRect(x: 0.69 * w, y: 0.60 * h, width: 0.13 * w, height: 0.20 * h))
        return path
    }
}
