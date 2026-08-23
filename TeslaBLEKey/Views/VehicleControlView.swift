import SwiftUI
import LocalAuthentication

struct VehicleControlView: View {
    @Environment(VehicleController.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmForget = false
    @State private var confirmDrive = false
    @State private var pressFeedback = 0
    @SceneStorage("controlRailHasAppeared") private var railHasAppeared = false
    @State private var revealRail = false
    @State private var animateRailEntrance = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBar
                vehicleSummary.padding(.top, 18)
                primaryControl.padding(.top, 18)
                if showsNowPlaying {
                    nowPlayingCard.padding(.top, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                climateControl.padding(.top, 22)
                utilityGrid.padding(.top, 22)
                driveControl.padding(.top, 12)
                safetyNote.padding(.top, 24)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 36)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .refreshable {
            await vehicle.refreshVehicleState()
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if vehicle.phase == .idle { await vehicle.connectFromUI() }
            animateRailEntrance = !railHasAppeared && !reduceMotion
            revealRail = true
            railHasAppeared = true
        }
        .confirmationDialog("移除本机车钥匙？", isPresented: $confirmForget) {
            Button("移除", role: .destructive) { vehicle.forgetVehicle() }
            Button("取消", role: .cancel) {}
        } message: { Text("还需要在车机的钥匙管理中删除对应记录。") }
        .confirmationDialog("授权启动车辆？", isPresented: $confirmDrive) {
            Button("授权启动") { submit(.drive, haptic: false) { await secureDrive() } }
            Button("取消", role: .cancel) {}
        } message: { Text("授权后车辆可在没有实体钥匙卡的情况下行驶。请确认车辆处于你的控制范围内。") }
        .sensoryFeedback(.impact(weight: .light), trigger: pressFeedback)
        .sensoryFeedback(.success, trigger: vehicle.lastSuccessAction)
        .sensoryFeedback(.error, trigger: vehicle.showingError)
        .animation(reduceMotion ? AppMotion.reduced : AppMotion.state, value: vehicle.mediaPlaybackStatus)
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(vehicle.displayVehicleName)
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
                Toggle(isOn: Binding(
                    get: { vehicle.passiveEntryEnabled },
                    set: { enabled in Task { await vehicle.setPassiveEntryEnabled(enabled) } }
                )) {
                    Label("被动钥匙", systemImage: "figure.walk.arrival")
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

    private var vehicleSummary: some View {
        NavigationLink {
            VehicleDetailView()
        } label: {
            VStack(spacing: 13) {
                HStack(spacing: 14) {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 28, weight: .light))
                        .frame(width: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(connected ? Color.green : AppTheme.muted)
                                .frame(width: 7, height: 7)
                            Text(vehicle.phase.title).font(.subheadline.weight(.semibold))
                        }
                        Text(statusSummary).font(.caption).foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    if busy { ProgressView().controlSize(.small).tint(.white) }
                    else { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.muted) }
                }
                if vehicle.batteryLevel != nil || vehicle.estimatedRangeKilometers != nil {
                    Divider().overlay(AppTheme.hairline)
                    HStack(spacing: 24) {
                        if let battery = vehicle.batteryLevel {
                            Label("\(battery)%", systemImage: "battery.75percent")
                                .accessibilityLabel("电池电量百分之 \(battery)")
                        }
                        if let range = vehicle.estimatedRangeKilometers {
                            Label(String(format: "%.0f km", range), systemImage: "road.lanes")
                                .accessibilityLabel("预计续航 \(Int(range)) 公里")
                        }
                        Spacer()
                    }
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(UtilityPressStyle())
        .accessibilityValue(connected ? "绿色状态，车辆已连接" : "灰色状态，车辆未连接")
        .accessibilityHint("轻点查看车辆详情")
    }

    private var primaryControl: some View {
        ActionButton(
            title: vehicle.isLocked == true ? "解锁车辆" : "锁定车辆",
            icon: vehicle.isLocked == true ? "lock.open" : "lock.fill",
            actionID: vehicle.isLocked == true ? .unlock : .lock,
            appearance: .primary,
            enabled: connected,
            executing: vehicle.executingAction,
            success: vehicle.lastSuccessAction
        ) {
            if vehicle.isLocked == true { submit(.unlock) { await vehicle.unlock() } }
            else { submit(.lock) { await vehicle.lock() } }
        }
    }

    private var nowPlayingCard: some View {
        HStack(spacing: 13) {
            Image(systemName: "music.note")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 46, height: 46)
                .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(vehicle.mediaTitle ?? "正在播放")
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(vehicle.mediaArtist ?? vehicle.mediaSource ?? "车载媒体")
                    .font(.caption).foregroundStyle(AppTheme.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            compactMediaButton("backward.end.fill", label: "上一首", action: .mediaPrevious) {
                await vehicle.previousMediaTrack()
            }
            compactMediaButton(vehicle.mediaPlaybackStatus == "播放中" ? "pause.fill" : "play.fill",
                               label: vehicle.mediaPlaybackStatus == "播放中" ? "暂停" : "继续播放",
                               action: .mediaPlayPause, emphasized: true) {
                await vehicle.toggleMediaPlayback()
            }
            compactMediaButton("forward.end.fill", label: "下一首", action: .mediaNext) {
                await vehicle.nextMediaTrack()
            }
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.hairline, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
    }

    private func compactMediaButton(
        _ symbol: String,
        label: String,
        action: VehicleController.VehicleAction,
        emphasized: Bool = false,
        operation: @escaping () async -> Void
    ) -> some View {
        Button { submit(action) { await operation() } } label: {
            Group {
                if vehicle.executingAction == action { ProgressView().controlSize(.mini).tint(emphasized ? .black : .white) }
                else { Image(systemName: symbol).font(.caption.weight(.semibold)) }
            }
            .frame(width: 36, height: 36)
            .background(emphasized ? Color.white : AppTheme.raised, in: Circle())
            .foregroundStyle(emphasized ? .black : .white)
        }
        .buttonStyle(UtilityPressStyle())
        .disabled(vehicle.executingAction != nil)
        .accessibilityLabel(label)
    }

    private var climateControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("座舱温度").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.muted)
                    Text(vehicle.cabinTemperature.map { String(format: "车内 %.1f°", $0) } ?? "车内温度读取中")
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                Button { submit(.climate) { await vehicle.toggleClimate() } } label: {
                    Label(vehicle.isClimateOn ? "关闭" : "开启", systemImage: vehicle.isClimateOn ? "fan.fill" : "fan")
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 44)
                        .padding(.horizontal, 12)
                        .background(vehicle.isClimateOn ? Color.white : AppTheme.raised, in: Capsule())
                        .foregroundStyle(vehicle.isClimateOn ? .black : .white)
                }
                .buttonStyle(UtilityPressStyle())
                .disabled(!connected || vehicle.executingAction != nil)
            }
            HStack {
                temperatureButton("minus") { vehicle.targetTemperature - 0.5 }
                Spacer()
                Text(String(format: "%.1f°", vehicle.targetTemperature))
                    .font(.title2.weight(.semibold)).monospacedDigit()
                Spacer()
                temperatureButton("plus") { vehicle.targetTemperature + 0.5 }
            }
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.hairline, lineWidth: 0.5))
    }

    private var utilityGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷控制")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                utility("前备箱", "car.side.front.open", .frunk, index: 0) { await secureFrunk() }
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
                utility(vehicle.isChargePortOpen ? "关闭充电口" : "打开充电口", "bolt.circle", .chargePort, index: 4) { await vehicle.toggleChargePort() }
                utility(vehicle.areWindowsVented ? "关闭车窗" : "车窗通风", "rectangle.split.3x1", .windows, index: 5) { await vehicle.toggleWindows() }
            }
        }
    }

    private var driveControl: some View {
        ActionButton(title: "授权启动车辆", icon: "power", actionID: .drive, appearance: .safety,
                     enabled: connected, executing: vehicle.executingAction,
                     success: vehicle.lastSuccessAction) {
            pressFeedback += 1
            confirmDrive = true
        }
        .reveal(index: 4, active: revealRail, skip: !animateRailEntrance)
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
        Text(vehicle.passiveEntryEnabled
             ? "被动钥匙已开启。请在车机启用「离车后自动上锁」，并随身携带实体钥匙卡。"
             : "离车前确认车辆已上锁，并随身携带实体钥匙卡。")
            .font(.caption).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func submit(_ id: VehicleController.VehicleAction, haptic: Bool = true,
                        operation: @escaping () async -> Void) {
        guard vehicle.executingAction == nil else { return }
        if haptic { pressFeedback += 1 }
        Task { await operation() }
    }

    private func temperatureButton(_ symbol: String, value: @escaping () -> Double) -> some View {
        Button {
            submit(.climate) { await vehicle.setCabinTemperature(value()) }
        } label: {
            Image(systemName: symbol).font(.body.weight(.semibold)).frame(width: 48, height: 44)
                .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(UtilityPressStyle())
        .disabled(!connected || vehicle.executingAction != nil)
        .accessibilityLabel(symbol == "minus" ? "降低温度" : "升高温度")
    }

    private func secureFrunk() async {
        guard await authenticate(reason: "确认打开车辆前备箱") else { return }
        await vehicle.openFrunk()
    }

    private func secureDrive() async {
        guard await authenticate(reason: "确认授权车辆启动") else { return }
        await vehicle.authorizeDrive()
    }

    private func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            vehicle.presentUserError("请先在系统设置中启用 Face ID、Touch ID 或设备密码。")
            return false
        }
        do { return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
        catch { return false }
    }

    private var statusSummary: String {
        guard connected else { return "轻点重新连接" }
        let lock = vehicle.isLocked.map { $0 ? "已上锁" : "已解锁" } ?? "锁车状态读取中"
        let trunk = vehicle.isTrunkOpen ? "尾门已开" : "尾门已关"
        return "\(lock) · \(trunk)"
    }

    private var connected: Bool {
        if vehicle.phase == .connected { return true }
        if case .executing = vehicle.phase { return true }
        return false
    }

    private var showsNowPlaying: Bool {
        guard vehicle.mediaTitle != nil else { return false }
        return vehicle.mediaPlaybackStatus == "播放中" || vehicle.mediaPlaybackStatus == "已暂停"
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
                    HStack(spacing: 12) {
                        ActionGlyph(icon: icon, state: glyphState)
                        Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 68)
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
