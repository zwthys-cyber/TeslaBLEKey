import SwiftUI

struct VehicleControlView: View {
    @Environment(VehicleController.self) private var vehicle
    @State private var confirmForget = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBar
                vehicleSummary.padding(.top, 44)
                lockControls.padding(.top, 36)
                Divider().overlay(AppTheme.hairline).padding(.vertical, 28)
                quickControls
                safetyNote.padding(.top, 28)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 36)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if vehicle.phase == .idle { await vehicle.connectFromUI() }
        }
        .confirmationDialog("移除本机车钥匙？", isPresented: $confirmForget) {
            Button("移除", role: .destructive) { vehicle.forgetVehicle() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("还需要在车机的钥匙管理中删除对应记录。")
        }
        .sensoryFeedback(.success, trigger: vehicle.phase == .connected)
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("我的车辆")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.5)
                Text("蓝牙车钥匙")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
            Menu {
                Button {
                    if connected { vehicle.disconnect() }
                    else { Task { await vehicle.connectFromUI() } }
                } label: {
                    Label(connected ? "断开连接" : "重新连接", systemImage: connected ? "bolt.slash" : "arrow.clockwise")
                }
                Button("移除车辆", systemImage: "trash", role: .destructive) { confirmForget = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .overlay(Circle().stroke(AppTheme.hairline, lineWidth: 0.5))
            }
            .buttonStyle(PremiumPressStyle())
            .accessibilityLabel("车辆选项")
        }
        .padding(.top, 10)
    }

    private var vehicleSummary: some View {
        VStack(spacing: 24) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 132, weight: .ultraLight))
                .symbolRenderingMode(.monochrome)
                .accessibilityLabel("已配对车辆")

            HStack(spacing: 7) {
                Circle()
                    .fill(connected ? Color.white : AppTheme.muted)
                    .frame(width: 6, height: 6)
                Text(vehicle.phase.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(connected ? .white : AppTheme.muted)
                if busy { ProgressView().controlSize(.mini).tint(.white) }
            }
            .animation(.easeOut(duration: 0.18), value: vehicle.phase)
        }
    }

    private var lockControls: some View {
        HStack(spacing: 10) {
            MainAction(title: "解锁", icon: "lock.open", filled: false, disabled: !connected) {
                await vehicle.unlock()
            }
            MainAction(title: "上锁", icon: "lock.fill", filled: true, disabled: !connected) {
                await vehicle.lock()
            }
        }
    }

    private var quickControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("快捷控制")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
                .textCase(.uppercase)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                QuickAction(title: "前备箱", icon: "car.side.front.open", disabled: !connected) { await vehicle.openFrunk() }
                QuickAction(title: "后备箱", icon: "car.side.rear.open", disabled: !connected) { await vehicle.openTrunk() }
                QuickAction(title: "启动车辆", icon: "power", disabled: !connected) { await vehicle.authorizeDrive() }
                QuickAction(title: "闪灯", icon: "light.beacon.max", disabled: !connected) { await vehicle.flashLights() }
                QuickAction(title: "鸣笛", icon: "speaker.wave.2", disabled: !connected) { await vehicle.honk() }
                QuickAction(title: "重新连接", icon: "arrow.clockwise", disabled: busy) { await vehicle.connectFromUI() }
            }
        }
    }

    private var safetyNote: some View {
        Text("离车前确认车辆已上锁，并随身携带实体钥匙卡。")
            .font(.caption)
            .foregroundStyle(AppTheme.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var connected: Bool {
        if vehicle.phase == .connected { return true }
        if case .executing = vehicle.phase { return true }
        return false
    }

    private var busy: Bool {
        switch vehicle.phase {
        case .scanning, .connecting, .handshaking, .executing: true
        default: false
        }
    }
}

private struct MainAction: View {
    let title: String
    let icon: String
    let filled: Bool
    let disabled: Bool
    let action: () async -> Void

    var body: some View {
        Button { Task { await action() } } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(filled ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(filled ? .black : .white)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(filled ? .clear : AppTheme.hairline, lineWidth: 0.5)
            }
        }
        .buttonStyle(PremiumPressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.32 : 1)
    }
}

private struct QuickAction: View {
    let title: String
    let icon: String
    let disabled: Bool
    let action: () async -> Void

    var body: some View {
        Button { Task { await action() } } label: {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .frame(height: 96)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 0.5)
            }
        }
        .buttonStyle(PremiumPressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.32 : 1)
    }
}
