import SwiftUI

struct VehicleControlView: View {
    @Environment(VehicleController.self) private var vehicle
    @State private var confirmForget = false

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ambientGlow

            ScrollView {
                VStack(spacing: 0) {
                    topBar
                    carHero.padding(.top, 20)
                    connectionStatus.padding(.top, 14)
                    lockControls.padding(.top, 24)
                    quickControls.padding(.top, 18)
                    safetyNote.padding(.top, 18)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
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
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text("本地蓝牙钥匙")
                    .font(.subheadline)
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
                    .frame(width: 42, height: 42)
                    .background(AppTheme.surface, in: Circle())
                    .overlay(Circle().stroke(AppTheme.hairline, lineWidth: 0.7))
            }
            .buttonStyle(PremiumPressStyle())
        }
        .padding(.top, 10)
    }

    private var carHero: some View {
        ZStack {
            Ellipse()
                .fill(AppTheme.accent.opacity(0.13))
                .frame(width: 290, height: 115)
                .blur(radius: 38)
                .offset(y: 34)
            Image(systemName: "car.side.fill")
                .font(.system(size: 132, weight: .ultraLight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .shadow(color: AppTheme.accent.opacity(0.26), radius: 22, y: 10)
        }
        .frame(height: 225)
        .accessibilityLabel("已配对车辆")
    }

    private var connectionStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .shadow(color: statusColor.opacity(0.7), radius: 5)
            Text(vehicle.phase.title)
                .font(.subheadline.weight(.medium))
                .contentTransition(.numericText())
            if busy { ProgressView().controlSize(.small).padding(.leading, 3) }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .background(AppTheme.surface, in: Capsule())
        .overlay(Capsule().stroke(AppTheme.hairline, lineWidth: 0.7))
    }

    private var lockControls: some View {
        HStack(spacing: 12) {
            PrimaryControl(title: "解锁", icon: "lock.open.fill", emphasized: true, disabled: !connected) {
                await vehicle.unlock()
            }
            PrimaryControl(title: "上锁", icon: "lock.fill", emphasized: false, disabled: !connected) {
                await vehicle.lock()
            }
        }
    }

    private var quickControls: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            QuickControl(title: "前备箱", icon: "car.side.front.open", disabled: !connected) { await vehicle.openFrunk() }
            QuickControl(title: "后备箱", icon: "car.side.rear.open", disabled: !connected) { await vehicle.openTrunk() }
            QuickControl(title: "启动车辆", icon: "power", disabled: !connected) { await vehicle.authorizeDrive() }
            QuickControl(title: "闪灯", icon: "light.beacon.max.fill", disabled: !connected) { await vehicle.flashLights() }
            QuickControl(title: "鸣笛", icon: "speaker.wave.2.fill", disabled: !connected) { await vehicle.honk() }
            QuickControl(title: "重新连接", icon: "arrow.clockwise", disabled: busy) { await vehicle.connectFromUI() }
        }
    }

    private var safetyNote: some View {
        Label("离车前请确认车辆已上锁，并随身携带实体钥匙卡。", systemImage: "shield.checkered")
            .font(.footnote)
            .foregroundStyle(AppTheme.muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
    }

    private var ambientGlow: some View {
        Circle()
            .fill(AppTheme.accent.opacity(0.13))
            .frame(width: 400, height: 400)
            .blur(radius: 130)
            .offset(y: -250)
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

    private var statusColor: Color {
        switch vehicle.phase {
        case .connected, .executing: .green
        case .failed: .orange
        default: AppTheme.accent
        }
    }
}

private struct PrimaryControl: View {
    let title: String
    let icon: String
    let emphasized: Bool
    let disabled: Bool
    let action: () async -> Void

    var body: some View {
        Button { Task { await action() } } label: {
            VStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 25, weight: .semibold))
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .background(emphasized ? Color.white : AppTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .foregroundStyle(emphasized ? .black : .white)
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(emphasized ? .clear : AppTheme.hairline, lineWidth: 0.7))
        }
        .buttonStyle(PremiumPressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
    }
}

private struct QuickControl: View {
    let title: String
    let icon: String
    let disabled: Bool
    let action: () async -> Void

    var body: some View {
        Button { Task { await action() } } label: {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.08), in: Circle())
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            .padding(13)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 19).stroke(AppTheme.hairline, lineWidth: 0.7))
        }
        .buttonStyle(PremiumPressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
    }
}
