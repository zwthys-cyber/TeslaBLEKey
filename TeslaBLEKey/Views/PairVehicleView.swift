import SwiftUI

struct PairVehicleView: View {
    @Environment(VehicleController.self) private var vehicle

    var body: some View {
        @Bindable var vehicle = vehicle

        Form {
            Section("车辆") {
                TextField("17 位 VIN", text: $vehicle.vin)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .fontDesign(.monospaced)
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
                    .disabled(!vehicle.hasValidVIN || isBusy)
                }
            } footer: {
                Text("本应用不使用 Tesla 账号或网络。私钥只保存在这台设备的 Keychain；卸载后需要重新刷卡配对。")
            }
        }
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

