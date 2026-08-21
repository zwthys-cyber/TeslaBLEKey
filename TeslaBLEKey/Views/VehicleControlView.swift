import SwiftUI

struct VehicleControlView: View {
    @Environment(VehicleController.self) private var vehicle
    @State private var confirmForget = false

    var body: some View {
        List {
            Section {
                HStack {
                    Label(vehicle.phase.title, systemImage: connected ? "bolt.horizontal.circle.fill" : "bolt.slash.circle")
                    Spacer()
                    if busy { ProgressView() }
                }
                Text(vehicle.normalizedVIN)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)

                if !connected {
                    Button("连接车辆") { Task { await vehicle.connectFromUI() } }
                        .disabled(busy)
                } else {
                    Button("断开连接") { Task { await vehicle.disconnect() } }
                }
            }

            Section("门锁") {
                ControlButton(title: "解锁", icon: "lock.open.fill", tint: .blue) {
                    await vehicle.unlock()
                }
                ControlButton(title: "上锁", icon: "lock.fill", tint: .green) {
                    await vehicle.lock()
                }
            }

            Section("车身") {
                ControlButton(title: "开启前备箱", icon: "car.side.front.open", tint: .orange) {
                    await vehicle.openFrunk()
                }
                ControlButton(title: "开启后备箱", icon: "car.side.rear.open", tint: .orange) {
                    await vehicle.openTrunk()
                }
                ControlButton(title: "闪灯", icon: "light.beacon.max.fill", tint: .yellow) {
                    await vehicle.flashLights()
                }
                ControlButton(title: "鸣笛", icon: "speaker.wave.3.fill", tint: .red) {
                    await vehicle.honk()
                }
            }

            Section {
                Button("忘记这辆车", role: .destructive) { confirmForget = true }
            } footer: {
                Text("忘记车辆会删除本机私钥，但不会自动删除车机钥匙列表中的记录。请同时在车机的锁设置中移除该钥匙。")
            }
        }
        .confirmationDialog("删除本机车辆密钥？", isPresented: $confirmForget) {
            Button("删除", role: .destructive) { Task { await vehicle.forgetVehicle() } }
            Button("取消", role: .cancel) {}
        }
    }

    private var connected: Bool { vehicle.phase == .connected || busyCommand }
    private var busyCommand: Bool { if case .executing = vehicle.phase { true } else { false } }
    private var busy: Bool {
        switch vehicle.phase {
        case .scanning, .connecting, .handshaking, .executing: true
        default: false
        }
    }
}

private struct ControlButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(tint)
    }
}

