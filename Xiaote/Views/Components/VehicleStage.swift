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
        VStack(spacing: 18) {
            Capsule()
                .fill(.white.opacity(isActive ? 0.16 : 0.07))
                .frame(width: 220, height: 1)
                .frame(height: 30, alignment: .bottom)

            stateMark
                .frame(height: 22)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? AppMotion.reduced : AppMotion.spatial, value: state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("车辆")
        .accessibilityValue(state.accessibilityValue)
    }

    @ViewBuilder
    private var stateMark: some View {
        if state == .searching || state == .connecting || state == .executing {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
                .transition(.opacity)
        } else if state == .awaitingCard {
            Image(systemName: "creditcard")
                .font(.system(size: 17, weight: .medium))
                .transition(markTransition)
        } else if state == .success {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .transition(markTransition)
        } else {
            Circle()
                .fill(.white)
                .frame(width: 5, height: 5)
                .transition(.opacity)
        }
    }

    private var markTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
    }

    private var isActive: Bool {
        state == .ready || state == .success
    }

}
