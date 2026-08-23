import SwiftUI

private enum HomeCard: String, CaseIterable, Identifiable {
    case vehicle, features, media, climate, controls, drive
    var id: String { rawValue }
    var title: String { switch self { case .vehicle: "车辆状态"; case .features: "功能入口"; case .media: "正在播放"; case .climate: "座舱温度"; case .controls: "快捷控制"; case .drive: "驾驶授权" } }
    var icon: String { switch self { case .vehicle: "car.side.fill"; case .features: "square.grid.2x2"; case .media: "music.note"; case .climate: "fan.fill"; case .controls: "switch.2"; case .drive: "power" } }
}

struct VehicleControlView: View {
    @Environment(VehicleController.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmForget = false
    @State private var confirmDrive = false
    @State private var showingAddVehicle = false
    @State private var showingRenameVehicle = false
    @State private var showingSecuritySettings = false
    @State private var showingHomeLayout = false
    @State private var showingAlerts = false
    @State private var homeCardOrder = HomeCard.allCases
    @State private var hiddenHomeCards: Set<HomeCard> = []
    @State private var pressFeedback = 0
    @SceneStorage("controlRailHasAppeared") private var railHasAppeared = false
    @State private var revealRail = false
    @State private var animateRailEntrance = false

    var body: some View {
        VStack(spacing: 0) {
            fixedHeader
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(homeCardOrder) { card in
                        if !hiddenHomeCards.contains(card) {
                            homeCard(card)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await vehicle.refreshVehicleState()
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if vehicle.phase == .idle { await vehicle.connectFromUI() }
            animateRailEntrance = !railHasAppeared && !reduceMotion
            revealRail = true
            railHasAppeared = true
            loadHomeLayout()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
                await vehicle.refreshMediaState()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await vehicle.refreshAfterReturningToForeground() }
            } else if newPhase == .background {
                vehicle.noteAppMovedToBackground()
            }
        }
        .onChange(of: vehicle.vehicleID) { _, _ in loadHomeLayout() }
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
        .sheet(isPresented: $showingAddVehicle) {
            NavigationStack { AddVehicleView() }
                .environment(vehicle)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingRenameVehicle) {
            RenameVehicleView().environment(vehicle).presentationDetents([.height(250)])
        }
        .sheet(isPresented: $showingSecuritySettings) {
            SecuritySettingsView().environment(vehicle).presentationDetents([.height(310)])
        }
        .sheet(isPresented: $showingHomeLayout) {
            HomeLayoutView(order: $homeCardOrder, hidden: $hiddenHomeCards) {
                saveHomeLayout()
            }.presentationDetents([.large])
        }
        .sheet(isPresented: $showingAlerts) {
            VehicleAlertsView().environment(vehicle).presentationDetents([.large])
        }
    }

    private var fixedHeader: some View {
        topBar
            .padding(.horizontal, 22)
            .padding(.bottom, 12)
            .background(AppTheme.background)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppTheme.hairline.opacity(0.55))
                    .frame(height: 0.5)
            }
            .zIndex(1)
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
                if vehicle.pairedVehicleIDs.count > 1 {
                    Section("切换车辆") {
                        ForEach(vehicle.pairedVehicleIDs, id: \.self) { identifier in
                            Button {
                                Task { await vehicle.switchVehicle(to: identifier) }
                            } label: {
                                Label(vehicle.vehicleDisplayName(for: identifier),
                                      systemImage: identifier == vehicle.vehicleID ? "checkmark.circle.fill" : "car.side")
                            }
                        }
                    }
                }
                Button { vehicle.disconnect(); showingAddVehicle = true } label: {
                    Label("添加车辆", systemImage: "plus.circle")
                }
                Button { showingRenameVehicle = true } label: {
                    Label("自定义车辆名称", systemImage: "pencil")
                }
                Button { showingSecuritySettings = true } label: {
                    Label("Face ID 保护", systemImage: "faceid")
                }
                Button { showingHomeLayout = true } label: {
                    Label("编辑主页", systemImage: "rectangle.3.group")
                }
                Button { showingAlerts = true } label: {
                    Label("车辆提醒", systemImage: "bell.badge")
                }
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
        VStack(spacing: 13) {
            NavigationLink {
                VehicleDetailView()
            } label: {
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
                            if connected {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(passiveKeyStatusColor)
                                        .frame(width: 6, height: 6)
                                    Text(passiveKeyCompactStatus)
                                }
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.muted)
                                .padding(.leading, 2)
                                .accessibilityElement(children: .combine)
                            }
                        }
                        Text(statusSummary).font(.caption).foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    if busy { ProgressView().controlSize(.small).tint(.white) }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(UtilityPressStyle())
            .accessibilityHint("查看车辆详情")
            Divider().overlay(AppTheme.hairline)
            HStack(spacing: 20) {
                if let battery = vehicle.batteryLevel {
                    Label("\(battery)%", systemImage: "battery.75percent")
                        .accessibilityLabel("电池电量百分之 \(battery)")
                }
                if let range = vehicle.estimatedRangeKilometers {
                    Label(String(format: "%.0f km", range), systemImage: "road.lanes")
                        .accessibilityLabel("预计续航 \(Int(range)) 公里")
                }
                Spacer(minLength: 8)
                compactLockButton
            }
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.hairline, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func homeCard(_ card: HomeCard) -> some View {
        switch card {
        case .vehicle: vehicleSummary.padding(.top, 18)
        case .features: featureRail.padding(.top, 14)
        case .media:
            if showsNowPlaying {
                nowPlayingCard.padding(.top, 14).transition(.opacity.combined(with: .move(edge: .top)))
            }
        case .climate: climateControl.padding(.top, 22)
        case .controls: utilityGrid.padding(.top, 22)
        case .drive: driveControl.padding(.top, 12)
        }
    }

    private func loadHomeLayout() {
        let defaults = UserDefaults.standard
        let orderKey = AppStorageKeys.homeCardOrderPrefix + vehicle.vehicleID
        let hiddenKey = AppStorageKeys.hiddenHomeCardsPrefix + vehicle.vehicleID
        let stored = defaults.stringArray(forKey: orderKey)?.compactMap(HomeCard.init(rawValue:)) ?? []
        homeCardOrder = stored.count == HomeCard.allCases.count ? stored : HomeCard.allCases
        hiddenHomeCards = Set((defaults.stringArray(forKey: hiddenKey) ?? []).compactMap(HomeCard.init(rawValue:)))
    }

    private func saveHomeLayout() {
        UserDefaults.standard.set(homeCardOrder.map(\.rawValue), forKey: AppStorageKeys.homeCardOrderPrefix + vehicle.vehicleID)
        UserDefaults.standard.set(hiddenHomeCards.map(\.rawValue), forKey: AppStorageKeys.hiddenHomeCardsPrefix + vehicle.vehicleID)
    }

    private var compactLockButton: some View {
        let action: VehicleController.VehicleAction = vehicle.isLocked == true ? .unlock : .lock
        let label = vehicle.isLocked == true ? "解锁车辆" : "锁定车辆"
        return Button {
            if action == .unlock { submit(.unlock) { await secureUnlock() } }
            else { submit(.lock) { await vehicle.lock() } }
        } label: {
            Group {
                if vehicle.executingAction == action {
                    ProgressView().controlSize(.mini).tint(.black)
                } else {
                    Image(systemName: action == .unlock ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .frame(width: 40, height: 40)
            .foregroundStyle(.black)
            .background(.white, in: Circle())
        }
        .buttonStyle(UtilityPressStyle())
        .disabled(!connected || vehicle.executingAction != nil)
        .accessibilityLabel(label)
        .accessibilityHint("立即向车辆发送\(label)命令")
    }

    private var featureRail: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                featureLink("充电", "bolt.fill", ChargingControlView())
                featureLink("座舱", "fan.fill", CabinControlView())
                featureLink("哨兵", "eye.fill", SentryControlView())
                featureLink("诊断", "waveform.path.ecg", VehicleDiagnosticsView())
                featureLink("场景", "sparkles", AutomationScenesView())
                featureLink("预约", "calendar.badge.clock", VehicleSchedulesView())
                featureLink("充电站", "bolt.car.fill", NearbyChargingSitesView())
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .accessibilityLabel("车辆功能")
    }

    private func featureLink<Destination: View>(_ title: String, _ icon: String, _ destination: Destination) -> some View {
        NavigationLink { destination } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.subheadline.weight(.semibold))
                Text(title).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 15).frame(height: 44)
            .background(AppTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(AppTheme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(UtilityPressStyle())
    }

    private var nowPlayingCard: some View {
        HStack(spacing: 13) {
            HStack(spacing: 13) {
                AsyncImage(url: vehicle.mediaArtworkURL) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(AppTheme.raised)
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private var passiveKeyCompactStatus: String {
        guard vehicle.passiveEntryEnabled else { return "钥匙关闭" }
        return vehicle.passiveKeyOnline ? "钥匙在线" : "钥匙恢复中"
    }

    private var passiveKeyStatusColor: Color {
        guard vehicle.passiveEntryEnabled else { return AppTheme.muted }
        return vehicle.passiveKeyOnline ? .green : .orange
    }

    private func submit(_ id: VehicleController.VehicleAction, haptic: Bool = true,
                        operation: @escaping () async -> Void) {
        guard vehicle.executingAction == nil else { return }
        if haptic { pressFeedback += 1 }
        Task {
            await operation()
        }
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
        await vehicle.openFrunk()
    }

    private func secureUnlock() async {
        await vehicle.unlock()
    }

    private func secureDrive() async {
        await vehicle.authorizeDrive()
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

private struct AddVehicleView: View {
    @Environment(VehicleController.self) private var vehicle
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        PairVehicleView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                        Task { await vehicle.connectFromUI() }
                    }
                }
            }
            .onChange(of: vehicle.phase) { _, phase in
                if phase == .connected { dismiss() }
            }
    }
}

private struct RenameVehicleView: View {
    @Environment(VehicleController.self) private var vehicle
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("例如：我的 Model 3", text: $name).textInputAutocapitalization(.words)
                Text("名称只保存在本机，留空会恢复显示真实车型。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("车辆名称").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { vehicle.saveCustomVehicleName(name); dismiss() }
                }
            }
            .onAppear { name = vehicle.customVehicleName ?? "" }
        }
    }
}

private struct SecuritySettingsView: View {
    @Environment(VehicleController.self) private var vehicle
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Picker("操作保护", selection: Binding(get: { vehicle.faceIDProtection }, set: { vehicle.setFaceIDProtection($0) })) {
                    ForEach(VehicleController.FaceIDProtection.allCases) { Text($0.title).tag($0) }
                }
                Section { Text("“仅敏感操作”保护解锁、前备箱和驾驶授权；“全部控制”会在每次发送车辆命令前验证。") }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Face ID 保护").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

private struct HomeLayoutView: View {
    @Binding var order: [HomeCard]
    @Binding var hidden: Set<HomeCard>
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("拖动排序") {
                    ForEach(order) { card in
                        HStack {
                            Label(card.title, systemImage: card.icon)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { !hidden.contains(card) },
                                set: { visible in
                                    if visible { hidden.remove(card) } else { hidden.insert(card) }
                                    save()
                                }
                            )).labelsHidden()
                        }
                    }
                    .onMove { source, destination in
                        order.move(fromOffsets: source, toOffset: destination)
                        save()
                    }
                }
                Section {
                    Button("恢复默认布局") {
                        order = HomeCard.allCases
                        hidden = []
                        save()
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("编辑主页").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { save(); dismiss() } } }
        }
        .preferredColorScheme(.dark)
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
