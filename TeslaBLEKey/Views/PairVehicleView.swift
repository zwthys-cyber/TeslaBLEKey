import SwiftUI

struct PairVehicleView: View {
    @Environment(VehicleController.self) private var vehicle
    @State private var scanner = NearbyTeslaScanner()
    @State private var selectedVehicle: NearbyTesla?

    var body: some View {
        @Bindable var vehicle = vehicle

        Form {
            Section {
                if let message = scanner.bluetoothMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if scanner.vehicles.isEmpty {
                    HStack {
                        Label("正在扫描附近 Tesla", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        if scanner.isScanning { ProgressView() }
                    }
                } else {
                    ForEach(scanner.vehicles) { nearby in
                        Button {
                            selectedVehicle = nearby
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedVehicle?.id == nearby.id ? "checkmark.circle.fill" : "car.side.fill")
                                    .foregroundStyle(selectedVehicle?.id == nearby.id ? .blue : .primary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("附近的 Tesla")
                                        .foregroundStyle(.primary)
                                    Text("\(nearby.signalLabel) · \(nearby.peripheralName)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(nearby.rssi) dBm")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Button {
                    scanner.start()
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
            } header: {
                Text("附近车辆")
            } footer: {
                Text("Tesla 蓝牙广播只包含 VIN 的单向哈希，不会广播可读取的完整 VIN。信号强度只能辅助判断距离。")
            }

            Section("确认 VIN（仅首次）") {
                TextField("17 位 VIN", text: $vehicle.vin)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .fontDesign(.monospaced)

                if let selectedVehicle, vehicle.hasValidVIN {
                    Label(
                        vehicle.matches(selectedVehicle) ? "VIN 与所选车辆匹配" : "VIN 与所选车辆不匹配",
                        systemImage: vehicle.matches(selectedVehicle) ? "checkmark.shield.fill" : "xmark.shield.fill"
                    )
                    .foregroundStyle(vehicle.matches(selectedVehicle) ? .green : .red)
                }
            }

            Section {
                Label(vehicle.phase.title, systemImage: statusIcon)

                if vehicle.phase == .pairingAwaitingCard {
                    Text("将已授权的 Tesla NFC 钥匙卡放在中控台读卡位置，然后在车辆屏幕确认添加钥匙。车机显示成功后再点下方按钮。")
                        .foregroundStyle(.secondary)

                    Button("车机已确认，验证连接") {
                        Task { await vehicle.confirmPairing() }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("连接并添加本机钥匙") {
                        Task { await vehicle.pair() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canPair || isBusy)
                }
            } footer: {
                Text("本应用不使用 Tesla 账号或网络。私钥只保存在这台设备的 Keychain；卸载后需要重新刷卡配对。")
            }
        }
        .task { scanner.start() }
        .onDisappear { scanner.stop() }
    }

    private var canPair: Bool {
        guard let selectedVehicle else { return false }
        return vehicle.hasValidVIN && vehicle.matches(selectedVehicle)
    }

    private var isBusy: Bool {
        switch vehicle.phase {
        case .preparingKey, .scanning, .connecting, .handshaking, .executing: true
        default: false
        }
    }

    private var statusIcon: String {
        switch vehicle.phase {
        case .connected: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .pairingAwaitingCard: "key.viewfinder"
        default: "antenna.radiowaves.left.and.right"
        }
    }
}
