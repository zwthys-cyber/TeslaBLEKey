import SwiftUI

struct PairVehicleView: View {
    @Environment(VehicleController.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanner = NearbyTeslaScanner()
    @State private var selectedVehicle: NearbyTesla?

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 28)
            VehicleStage(state: stage)
                .frame(maxWidth: 430)
            stageCopy.padding(.top, 22)
            Spacer(minLength: 30)
            status
            pairButton.padding(.top, 14)
            privacy.padding(.top, 18)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { scanner.start() }
        .onDisappear { scanner.stop() }
        .onChange(of: scanner.vehicles) { _, vehicles in
            guard vehicle.phase != .pairingAwaitingCard else { return }
            withAnimation(reduceMotion ? AppMotion.reduced : AppMotion.spatial) {
                selectedVehicle = vehicles.first
            }
        }
        .sensoryFeedback(.selection, trigger: selectedVehicle?.id)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("车钥匙").font(.system(size: 28, weight: .semibold)).tracking(-0.5)
            Spacer()
            Text("本地蓝牙").font(.caption.weight(.medium)).foregroundStyle(AppTheme.muted)
        }
    }

    private var stageCopy: some View {
        VStack(spacing: 7) {
            Text(stageTitle).font(.title2.weight(.semibold))
            Text(stageSubtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
        }
        .id(stage)
        .transition(.opacity)
        .animation(AppMotion.state, value: stage)
    }

    private var status: some View {
        HairlinePanel {
            HStack(spacing: 13) {
                Image(systemName: statusIcon).font(.system(size: 17, weight: .medium)).frame(width: 24)
                    .contentTransition(.opacity)
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle).font(.subheadline.weight(.semibold))
                    Text(statusSubtitle).font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                if stage == .searching { ProgressView().controlSize(.small).tint(.white) }
            }
        }
        .animation(AppMotion.state, value: stage)
    }

    private var pairButton: some View {
        Button {
            guard let selectedVehicle else { return }
            scanner.stop()
            Task { await vehicle.pair(with: selectedVehicle) }
        } label: {
            HStack(spacing: 8) {
                if isPairing { ProgressView().controlSize(.small).tint(.black) }
                Text(actionTitle).font(.headline)
            }
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(.black)
        }
        .buttonStyle(PrimaryPressStyle())
        .disabled(selectedVehicle == nil || isPairing)
        .opacity(selectedVehicle == nil || isPairing ? 0.38 : 1)
    }

    private var privacy: some View {
        Label("无账户 · 无网络 · 密钥仅存本机", systemImage: "lock")
            .font(.caption).foregroundStyle(AppTheme.muted)
    }

    private var stage: VehicleStageState {
        switch vehicle.phase {
        case .pairingAwaitingCard: .awaitingCard
        case .connecting, .handshaking: .connecting
        default: selectedVehicle == nil ? .searching : .found
        }
    }

    private var stageTitle: String {
        switch stage {
        case .searching: "靠近车辆"
        case .found: "车辆就在附近"
        case .awaitingCard: "用钥匙卡确认"
        case .connecting: "建立安全连接"
        default: "车辆已就绪"
        }
    }

    private var stageSubtitle: String {
        switch stage {
        case .searching: "自动识别并选择信号最强的兼容车辆"
        case .found: "无需 VIN，准备添加本机钥匙"
        case .awaitingCard: "将现有钥匙卡放在中控台感应区"
        case .connecting: "密钥仅保存在这台 iPhone"
        default: ""
        }
    }

    private var isPairing: Bool {
        switch vehicle.phase { case .connecting, .pairingAwaitingCard, .handshaking: true; default: false }
    }

    private var actionTitle: String {
        switch vehicle.phase {
        case .pairingAwaitingCard: "刷卡并在车机确认"
        case .connecting, .handshaking: "正在配对"
        default: selectedVehicle == nil ? "正在搜索" : "添加车钥匙"
        }
    }

    private var statusIcon: String {
        if scanner.bluetoothMessage != nil { return "exclamationmark.circle" }
        switch stage {
        case .searching: "antenna.radiowaves.left.and.right"
        case .awaitingCard: "creditcard"
        case .connecting: "lock"
        default: "checkmark.circle.fill"
        }
    }

    private var statusTitle: String {
        scanner.bluetoothMessage ?? stageTitle
    }

    private var statusSubtitle: String {
        stageSubtitle
    }
}
