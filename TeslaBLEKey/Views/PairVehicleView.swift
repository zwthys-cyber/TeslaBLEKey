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
            if scanner.vehicles.count > 1, !isPairing {
                vehiclePicker.padding(.top, 18)
            }
            if let bluetoothMessage = scanner.bluetoothMessage {
                Label(bluetoothMessage, systemImage: "exclamationmark.circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.top, 20)
                    .transition(.opacity)
            }
            Spacer(minLength: 34)
            pairButton
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
            let selectionStillAvailable = vehicles.contains { $0.id == selectedVehicle?.id }
            guard !selectionStillAvailable else {
                if let selectedID = selectedVehicle?.id {
                    selectedVehicle = vehicles.first { $0.id == selectedID }
                }
                return
            }
            withAnimation(reduceMotion ? AppMotion.reduced : AppMotion.spatial) {
                selectedVehicle = vehicles.first
            }
        }
        .sensoryFeedback(.selection, trigger: selectedVehicle?.id)
    }

    private var vehiclePicker: some View {
        VStack(spacing: 0) {
            ForEach(Array(scanner.vehicles.enumerated()), id: \.element.id) { index, candidate in
                Button {
                    withAnimation(reduceMotion ? AppMotion.reduced : AppMotion.state) {
                        selectedVehicle = candidate
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedVehicle?.id == candidate.id ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("附近车辆 \(index + 1)")
                                .font(.subheadline.weight(.semibold))
                            Text("识别码 ·\(candidate.shortIdentifier)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Label(candidate.signalLabel, systemImage: signalSymbol(candidate.signalLevel))
                                .font(.caption.weight(.semibold))
                            Text("\(candidate.rssi) dBm")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)

                if index < scanner.vehicles.count - 1 {
                    Divider().overlay(.white.opacity(0.1))
                }
            }
        }
        .padding(.horizontal, 14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("发现多辆车辆，请选择距离最近的一辆")
    }

    private func signalSymbol(_ level: Int) -> String {
        switch level {
        case 3: "wifi"
        case 2: "wifi"
        default: "wifi.exclamationmark"
        }
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
        case .connecting: vehicle.phase == .connecting ? "正在连接车辆" : "建立安全连接"
        default: "车辆已就绪"
        }
    }

    private var stageSubtitle: String {
        switch stage {
        case .searching:
            if scanner.scanTimedOut { return "打开车门或轻踩刹车唤醒车辆，然后保持在驾驶位附近" }
            if scanner.nearbyDeviceCount > 0 { return "正在识别附近车辆 · 已收到 \(scanner.nearbyDeviceCount) 个蓝牙信号" }
            return "正在扫描附近兼容车辆"
        case .found:
            return scanner.vehicles.count > 1
                ? "发现多辆车辆，请选择信号最强且离你最近的一辆"
                : "无需 VIN，准备添加本机钥匙 · \(selectedVehicle?.rssi ?? 0) dBm"
        case .awaitingCard: return "将现有钥匙卡放在中控台感应区"
        case .connecting:
            if vehicle.phase == .connecting { return "正在连接所选车辆，最长等待 30 秒" }
            return "正在验证本机密钥，最长等待 20 秒"
        default: return ""
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

}
