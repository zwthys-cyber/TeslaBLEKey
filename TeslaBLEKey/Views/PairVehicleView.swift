import SwiftUI

struct PairVehicleView: View {
    @Environment(VehicleController.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanner = NearbyTeslaScanner()
    @State private var selectedVehicle: NearbyTesla?

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 32)
            hero
            Spacer(minLength: 36)
            scanStatus
            pairButton.padding(.top, 16)
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
            if reduceMotion { selectedVehicle = vehicles.first }
            else {
                withAnimation(.spring(response: 0.36, dampingFraction: 1)) {
                    selectedVehicle = vehicles.first
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedVehicle?.id)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("车钥匙")
                .font(.system(size: 28, weight: .semibold, design: .default))
                .tracking(-0.5)
            Spacer()
            Text("本地蓝牙")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.muted)
        }
    }

    private var hero: some View {
        VStack(spacing: 20) {
            Image(systemName: selectedVehicle == nil ? "car.side" : "car.side.fill")
                .font(.system(size: 126, weight: .ultraLight))
                .symbolRenderingMode(.monochrome)
                .contentTransition(.symbolEffect(.replace))

            VStack(spacing: 7) {
                Text(selectedVehicle == nil ? "靠近车辆" : "发现车辆")
                    .font(.title2.weight(.semibold))
                Text(selectedVehicle == nil ? "将自动选择信号最强的兼容车辆" : "已选择离你最近的车辆")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var scanStatus: some View {
        HairlinePanel {
            HStack(spacing: 13) {
                Image(systemName: statusIcon)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle).font(.subheadline.weight(.semibold))
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                if selectedVehicle == nil && scanner.bluetoothMessage == nil {
                    ProgressView().controlSize(.small).tint(.white)
                }
            }
        }
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
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(.black)
        }
        .buttonStyle(PremiumPressStyle())
        .disabled(selectedVehicle == nil || isPairing)
        .opacity(selectedVehicle == nil || isPairing ? 0.38 : 1)
    }

    private var privacy: some View {
        Label("无账户 · 无网络 · 密钥仅存本机", systemImage: "lock")
            .font(.caption)
            .foregroundStyle(AppTheme.muted)
    }

    private var isPairing: Bool {
        switch vehicle.phase {
        case .connecting, .pairingAwaitingCard, .handshaking: true
        default: false
        }
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
        if vehicle.phase == .pairingAwaitingCard { return "creditcard" }
        return selectedVehicle == nil ? "antenna.radiowaves.left.and.right" : "checkmark.circle.fill"
    }

    private var statusTitle: String {
        if let message = scanner.bluetoothMessage { return message }
        if vehicle.phase == .pairingAwaitingCard { return "等待钥匙卡" }
        return selectedVehicle == nil ? "正在搜索附近车辆" : "车辆已就绪"
    }

    private var statusSubtitle: String {
        if vehicle.phase == .pairingAwaitingCard { return "将现有钥匙卡放在中控台感应区" }
        return selectedVehicle == nil ? "无需输入 VIN" : "点击下方按钮开始安全配对"
    }
}
