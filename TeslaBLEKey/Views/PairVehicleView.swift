import SwiftUI

struct PairVehicleView: View {
    @Environment(VehicleController.self) private var vehicle
    @State private var scanner = NearbyTeslaScanner()
    @State private var selectedVehicle: NearbyTesla?

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            Circle()
                .fill(AppTheme.accent.opacity(0.16))
                .frame(width: 380, height: 380)
                .blur(radius: 120)
                .offset(y: -220)

            VStack(spacing: 0) {
                header
                Spacer(minLength: 20)
                vehicleHero
                Spacer(minLength: 24)
                statusPanel
                action
                    .padding(.top, 18)
                privacy
                    .padding(.top, 16)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
        }
        .preferredColorScheme(.dark)
        .task { scanner.start() }
        .onDisappear { scanner.stop() }
        .onChange(of: scanner.vehicles) { _, vehicles in
            guard vehicle.phase != .pairingAwaitingCard else { return }
            selectedVehicle = vehicles.first
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: selectedVehicle)
        .sensoryFeedback(.selection, trigger: selectedVehicle?.id)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("添加车钥匙")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text("坐进车内，保持蓝牙开启")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(AppTheme.surface, in: Circle())
                .overlay(Circle().stroke(AppTheme.hairline, lineWidth: 0.7))
        }
    }

    private var vehicleHero: some View {
        ZStack {
            ForEach(0 ..< 2, id: \.self) { index in
                Circle()
                    .stroke(AppTheme.accent.opacity(0.12 - Double(index) * 0.035), lineWidth: 1)
                    .frame(width: CGFloat(215 + index * 54), height: CGFloat(215 + index * 54))
            }
            Circle()
                .fill(AppTheme.accent.opacity(selectedVehicle == nil ? 0.05 : 0.12))
                .frame(width: 210, height: 210)
            Image(systemName: selectedVehicle == nil ? "car.side" : "car.side.fill")
                .font(.system(size: 112, weight: .ultraLight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selectedVehicle == nil ? AppTheme.muted : .white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(height: 285)
        .accessibilityHidden(true)
    }

    private var statusPanel: some View {
        GlassPanel {
            HStack(spacing: 14) {
                Circle()
                    .fill(statusColor.opacity(0.16))
                    .overlay {
                        Image(systemName: statusIcon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(statusColor)
                    }
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle).font(.headline)
                    Text(statusSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                if selectedVehicle == nil && scanner.bluetoothMessage == nil { ProgressView() }
            }
        }
    }

    private var action: some View {
        Button {
            guard let selectedVehicle else { return }
            scanner.stop()
            Task { await vehicle.pair(with: selectedVehicle) }
        } label: {
            Text(actionTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .foregroundStyle(.black)
        }
        .buttonStyle(PremiumPressStyle())
        .disabled(selectedVehicle == nil || isPairing)
        .opacity(selectedVehicle == nil || isPairing ? 0.48 : 1)
    }

    private var privacy: some View {
        Label("无需账户或网络，私钥仅保存在本机", systemImage: "lock.shield")
            .font(.footnote)
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
        case .pairingAwaitingCard: "请刷钥匙卡并在车机确认"
        case .connecting, .handshaking: "正在安全配对…"
        default: selectedVehicle == nil ? "正在寻找车辆…" : "添加这辆车"
        }
    }

    private var statusColor: Color {
        if scanner.bluetoothMessage != nil { return .orange }
        return selectedVehicle == nil ? AppTheme.accent : .green
    }

    private var statusIcon: String {
        if scanner.bluetoothMessage != nil { return "exclamationmark.triangle.fill" }
        return selectedVehicle == nil ? "antenna.radiowaves.left.and.right" : "checkmark"
    }

    private var statusTitle: String {
        if let message = scanner.bluetoothMessage { return message }
        if vehicle.phase == .pairingAwaitingCard { return "等待车辆确认" }
        return selectedVehicle == nil ? "正在自动识别车辆" : "车辆已就绪"
    }

    private var statusSubtitle: String {
        if vehicle.phase == .pairingAwaitingCard { return "将已有钥匙卡放在中控台感应区" }
        guard let selectedVehicle else { return "最靠近的车辆会自动出现" }
        return selectedVehicle.signalLabel == "很近" ? "已锁定你身边的车辆" : "靠近驾驶位可提高识别准确度"
    }
}
