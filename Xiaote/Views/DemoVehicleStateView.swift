import SwiftUI

struct DemoVehicleStateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isConnected = true
    @State private var isLocked = true
    @State private var isFrunkOpen = false
    @State private var isTrunkOpen = false
    @State private var isCharging = false
    @State private var doorStates: [String: Bool] = [:]
    @State private var sequenceTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                StatefulModel3Artwork(
                    isConnected: isConnected,
                    isLocked: isLocked,
                    isFrunkOpen: isFrunkOpen,
                    isTrunkOpen: isTrunkOpen,
                    doorStates: doorStates,
                    isCharging: isCharging,
                    reduceMotion: reduceMotion
                )
                .frame(maxWidth: 430)
                .padding(.top, 8)

                Text("Model 3")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    Circle().fill(isConnected ? Color.green : AppTheme.muted).frame(width: 7, height: 7)
                    Text(isConnected ? "演示车辆在线" : "演示车辆离线")
                }
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .padding(.top, 5)

                controls.padding(.top, 34)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("状态动画测试")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
        }
        .onDisappear { sequenceTask?.cancel() }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            demoRow("车辆连接", value: isConnected ? "在线" : "离线", icon: "antenna.radiowaves.left.and.right") {
                isConnected.toggle()
            }
            divider
            demoRow("车辆锁定", value: isLocked ? "已锁定" : "已解锁", icon: isLocked ? "lock.fill" : "lock.open.fill") {
                isLocked.toggle()
            }
            divider
            demoRow("左前门", value: doorStates["左前门"] == true ? "已开启" : "已关闭", icon: "door.left.hand.open") {
                doorStates["左前门", default: false].toggle()
            }
            divider
            demoRow("前备箱", value: isFrunkOpen ? "已开启" : "已关闭", icon: "car.side.front.open") {
                isFrunkOpen.toggle()
            }
            divider
            demoRow("后备箱", value: isTrunkOpen ? "已开启" : "已关闭", icon: "car.side.rear.open") {
                isTrunkOpen.toggle()
            }
            divider
            demoRow("车辆充电", value: isCharging ? "充电中" : "未充电", icon: "bolt.fill") {
                isCharging.toggle()
            }

            Button {
                playSequence()
            } label: {
                Label("自动演示全部状态", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.black)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PrimaryPressStyle())
            .padding(.top, 26)
        }
    }

    private func demoRow(_ title: String, value: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 28)
                Text(title).font(.subheadline)
                Spacer()
                Text(value).font(.subheadline).foregroundStyle(AppTheme.muted)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(UtilityPressStyle())
    }

    private var divider: some View {
        Divider().overlay(AppTheme.hairline).padding(.leading, 41)
    }

    private func playSequence() {
        sequenceTask?.cancel()
        sequenceTask = Task { @MainActor in
            reset()
            guard await pause() else { return }
            isConnected = false
            guard await pause() else { return }
            isConnected = true
            guard await pause() else { return }
            isLocked = false
            guard await pause() else { return }
            doorStates["左前门"] = true
            guard await pause() else { return }
            doorStates["左前门"] = false
            isFrunkOpen = true
            guard await pause() else { return }
            isFrunkOpen = false
            isTrunkOpen = true
            guard await pause() else { return }
            isTrunkOpen = false
            isCharging = true
            guard await pause(seconds: 2.4) else { return }
            isCharging = false
            isLocked = true
        }
    }

    @MainActor
    private func reset() {
        isConnected = true
        isLocked = true
        isFrunkOpen = false
        isTrunkOpen = false
        isCharging = false
        doorStates = [:]
    }

    private func pause(seconds: Double = 0.8) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(seconds))
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}
