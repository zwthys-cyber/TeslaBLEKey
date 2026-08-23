import SwiftUI

struct VehicleControlView: View {
    @Environment(VehicleController.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmForget = false
    @State private var confirmDrive = false
    @State private var nextDoorAction: VehicleController.VehicleAction = .lock
    @State private var pressFeedback = 0
    @SceneStorage("controlRailHasAppeared") private var railHasAppeared = false
    @State private var revealRail = false
    @State private var animateRailEntrance = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBar
                VehicleStage(state: stage)
                    .frame(maxWidth: 440)
                    .padding(.top, 26)
                connectionButton.padding(.top, 12)
                primaryControl.padding(.top, 30)
                utilityRail.padding(.top, 28)
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
            animateRailEntrance = !railHasAppeared && !reduceMotion
            revealRail = true
            railHasAppeared = true
        }
        .onChange(of: vehicle.lastSuccessAction) { _, action in
            if action == .lock { nextDoorAction = .unlock }
            if action == .unlock { nextDoorAction = .lock }
        }
        .confirmationDialog("移除本机车钥匙？", isPresented: $confirmForget) {
            Button("移除", role: .destructive) { vehicle.forgetVehicle() }
            Button("取消", role: .cancel) {}
        } message: { Text("还需要在车机的钥匙管理中删除对应记录。") }
        .confirmationDialog("授权启动车辆？", isPresented: $confirmDrive) {
            Button("授权启动") { submit(.drive, haptic: false) { await vehicle.authorizeDrive() } }
            Button("取消", role: .cancel) {}
        } message: { Text("授权后车辆可在没有实体钥匙卡的情况下行驶。请确认车辆处于你的控制范围内。") }
        .sensoryFeedback(.impact(weight: .light), trigger: pressFeedback)
        .sensoryFeedback(.success, trigger: vehicle.lastSuccessAction)
        .sensoryFeedback(.error, trigger: vehicle.showingError)
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(vehicle.vehicleModelName.map { "我的 \($0)" } ?? "我的车辆")
                    .font(.system(size: 28, weight: .semibold)).tracking(-0.5)
                Text("蓝牙车钥匙").font(.caption).foregroundStyle(AppTheme.muted)
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
            .buttonStyle(UtilityPressStyle())
            .accessibilityLabel("车辆选项")
        }
        .padding(.top, 10)
    }

    private var connectionButton: some View {
        Button {
            guard !busy else { return }
            if !connected { Task { await vehicle.connectFromUI() } }
        } label: {
            HStack(spacing: 7) {
                Circle().fill(connected ? Color.white : AppTheme.muted).frame(width: 6, height: 6)
                Text(vehicle.phase.title).font(.caption.weight(.medium))
                if busy { ProgressView().controlSize(.mini).tint(.white) }
                if !connected && !busy { Image(systemName: "arrow.clockwise").font(.caption2.weight(.bold)) }
            }
            .foregroundStyle(connected ? .white : AppTheme.muted)
            .frame(minHeight: 44)
            .padding(.horizontal, 14)
            .background(AppTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(AppTheme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(UtilityPressStyle())
        .accessibilityHint(connected ? "车辆连接正常" : "轻点重新连接")
    }

    private var primaryControl: some View {
        ActionButton(
            title: nextDoorAction == .lock ? "上锁" : "解锁",
            icon: nextDoorAction == .lock ? "lock.fill" : "lock.open",
            actionID: nextDoorAction,
            appearance: .primary,
            enabled: connected,
            executing: vehicle.executingAction,
            success: vehicle.lastSuccessAction
        ) {
            if nextDoorAction == .lock { submit(.lock) { await vehicle.lock() } }
            else { submit(.unlock) { await vehicle.unlock() } }
        }
    }

    private var utilityRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("车辆控制").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    utility("前备箱", "car.side.front.open", .frunk, index: 0) { await vehicle.openFrunk() }
                    utility(
                        vehicle.isTrunkOpen ? "关闭后备箱" : "打开后备箱",
                        vehicle.isTrunkOpen ? "door.garage.closed" : "car.side.rear.open",
                        .trunk,
                        index: 1
                    ) {
                        if vehicle.isTrunkOpen { await vehicle.closeTrunk() }
                        else { await vehicle.openTrunk() }
                    }
                    utility("闪灯", "light.beacon.max", .flash, index: 2) { await vehicle.flashLights() }
                    utility("鸣笛", "speaker.wave.2", .horn, index: 3) { await vehicle.honk() }
                    ActionButton(title: "启动", icon: "power", actionID: .drive, appearance: .safety,
                                 enabled: connected, executing: vehicle.executingAction,
                                 success: vehicle.lastSuccessAction) {
                        pressFeedback += 1
                        confirmDrive = true
                    }
                    .reveal(index: 4, active: revealRail, skip: !animateRailEntrance)
                }
            }
            .contentMargins(.horizontal, 1, for: .scrollContent)
        }
    }

    private func utility(_ title: String, _ icon: String, _ id: VehicleController.VehicleAction, index: Int,
                         operation: @escaping () async -> Void) -> some View {
        ActionButton(title: title, icon: icon, actionID: id, appearance: .utility,
                     enabled: connected, executing: vehicle.executingAction,
                     success: vehicle.lastSuccessAction) {
            submit(id, operation: operation)
        }
        .reveal(index: index, active: revealRail, skip: !animateRailEntrance)
    }

    private var safetyNote: some View {
        Text("离车前确认车辆已上锁，并随身携带实体钥匙卡。")
            .font(.caption).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func submit(_ id: VehicleController.VehicleAction, haptic: Bool = true,
                        operation: @escaping () async -> Void) {
        guard vehicle.executingAction == nil else { return }
        if haptic { pressFeedback += 1 }
        Task { await operation() }
    }

    private var stage: VehicleStageState {
        if vehicle.lastSuccessAction != nil { return .success }
        if vehicle.executingAction != nil { return .executing }
        switch vehicle.phase {
        case .connecting, .handshaking: return .connecting
        case .connected: return .ready
        default: return .found
        }
    }

    private var connected: Bool {
        if vehicle.phase == .connected { return true }
        if case .executing = vehicle.phase { return true }
        return false
    }

    private var busy: Bool {
        switch vehicle.phase { case .scanning, .connecting, .handshaking: true; default: false }
    }
}

private enum ActionAppearance: Equatable { case primary, utility, safety }

private struct ActionButton: View {
    let title: String
    let icon: String
    let actionID: VehicleController.VehicleAction
    let appearance: ActionAppearance
    let enabled: Bool
    let executing: VehicleController.VehicleAction?
    let success: VehicleController.VehicleAction?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if appearance == .primary {
                    HStack(spacing: 10) {
                        ActionGlyph(icon: icon, state: glyphState)
                        Text(title).font(.headline)
                    }
                    .frame(maxWidth: .infinity).frame(height: 60)
                } else {
                    VStack(spacing: 10) {
                        ActionGlyph(icon: icon, state: glyphState)
                        Text(title).font(.caption.weight(.medium)).lineLimit(1)
                    }
                    .frame(width: 76, height: 76)
                }
            }
            .foregroundStyle(appearance == .primary ? Color.black : Color.white)
            .background(background, in: RoundedRectangle(cornerRadius: appearance == .primary ? 20 : 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: appearance == .primary ? 20 : 18, style: .continuous)
                    .stroke(appearance == .safety ? Color.white.opacity(0.34) : AppTheme.hairline, lineWidth: 0.5)
            }
        }
        .buttonStyle(ActionPressStyle(primary: appearance == .primary))
        // Keep unaffected commands visually legible while serializing interaction.
        // The active command alone owns the local progress glyph.
        .disabled(!enabled || executing != nil)
        .opacity(enabled ? 1 : 0.34)
        .accessibilityLabel(title)
        .accessibilityValue(glyphState.accessibilityValue)
    }

    private var glyphState: ActionGlyph.State {
        if executing == actionID { return .executing }
        if success == actionID { return .success }
        return .idle
    }

    private var background: Color {
        if appearance == .primary { return .white }
        return appearance == .safety ? AppTheme.raised : AppTheme.surface
    }
}

private struct ActionGlyph: View {
    enum State: Hashable { case idle, executing, success
        var accessibilityValue: String {
            switch self { case .idle: "可执行"; case .executing: "执行中"; case .success: "已完成" }
        }
    }
    let icon: String
    let state: State

    var body: some View {
        ZStack {
            switch state {
            case .idle: Image(systemName: icon)
            case .executing: ProgressView().controlSize(.small).tint(.gray)
            case .success: Image(systemName: "checkmark").fontWeight(.bold)
            }
        }
        .font(.system(size: 18, weight: .semibold))
        .frame(width: 24, height: 24)
        .id(state)
        .transition(.opacity)
        .animation(AppMotion.state, value: state)
    }
}

private extension View {
    func reveal(index: Int, active: Bool, skip: Bool) -> some View {
        opacity(skip || active ? 1 : 0)
            .offset(y: skip || active ? 0 : 4)
            .animation(skip ? nil : AppMotion.state.delay(Double(index) * 0.04), value: active)
    }
}
