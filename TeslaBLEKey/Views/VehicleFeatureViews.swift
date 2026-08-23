import SwiftUI

struct ChargingControlView: View {
    @Environment(VehicleController.self) private var vehicle
    @State private var limit = 80.0
    @State private var amps = 16.0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                FeatureStatusCard(icon: "bolt.fill", title: vehicle.chargingStatus ?? "充电状态读取中",
                                  value: vehicle.batteryLevel.map { "\($0)%" } ?? "—",
                                  detail: rangeDetail)
                controlCard("充电控制") {
                    Button { Task { await vehicle.toggleCharging() } } label: {
                        Label(vehicle.isCharging ? "停止充电" : "开始充电",
                              systemImage: vehicle.isCharging ? "stop.fill" : "bolt.fill")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                    .disabled(!connected || vehicle.executingAction != nil)
                }
                controlCard("充电上限") {
                    valueHeader("目标电量", "\(Int(limit))%")
                    Slider(value: $limit, in: 50...100, step: 5)
                        .tint(.white)
                    Button("应用充电上限") { Task { await vehicle.setChargeLimit(Int(limit)) } }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity, alignment: .trailing)
                        .disabled(!connected || vehicle.executingAction != nil)
                }
                controlCard("充电电流") {
                    valueHeader("车辆允许范围内", "\(Int(amps)) A")
                    Slider(value: $amps, in: 5...48, step: 1).tint(.white)
                    Button("应用充电电流") { Task { await vehicle.setChargingCurrent(Int(amps)) } }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity, alignment: .trailing)
                        .disabled(!connected || vehicle.executingAction != nil)
                }
                if vehicle.chargeCableStatus != nil || vehicle.chargePortLatchStatus != nil {
                    controlCard("连接状态") {
                        statusRow("充电枪", vehicle.chargeCableStatus ?? "—")
                        statusRow("充电口锁止", vehicle.chargePortLatchStatus ?? "—")
                        statusRow("当前功率", vehicle.chargerPowerKilowatts.map { "\($0) kW" } ?? "—")
                        statusRow("剩余时间", vehicle.minutesToChargeLimit.map { "\($0) 分钟" } ?? "—")
                    }
                }
            }.padding(20)
        }
        .featurePage(title: "充电")
        .onAppear {
            limit = Double(vehicle.chargeLimit ?? 80)
            amps = Double(vehicle.chargerCurrentAmps ?? 16)
        }
    }

    private var rangeDetail: String { vehicle.estimatedRangeKilometers.map { String(format: "预计续航 %.0f km", $0) } ?? "等待车辆数据" }
    private var connected: Bool { vehicle.phase == .connected || vehicle.executingAction != nil }
}

struct CabinControlView: View {
    @Environment(VehicleController.self) private var vehicle

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                FeatureStatusCard(icon: "fan.fill", title: vehicle.isClimateOn ? "空调运行中" : "空调已关闭",
                                  value: String(format: "%.1f°", vehicle.targetTemperature),
                                  detail: temperatureDetail)
                controlCard("温度") {
                    HStack {
                        cabinButton("minus") { await vehicle.setCabinTemperature(vehicle.targetTemperature - 0.5) }
                        Spacer()
                        Text(String(format: "%.1f°", vehicle.targetTemperature)).font(.title2.weight(.semibold)).monospacedDigit()
                        Spacer()
                        cabinButton("plus") { await vehicle.setCabinTemperature(vehicle.targetTemperature + 0.5) }
                    }
                    Button { Task { await vehicle.toggleClimate() } } label: {
                        Label(vehicle.isClimateOn ? "关闭空调" : "开启空调", systemImage: "fan.fill")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                }
                controlCard("座舱模式") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        toggleTile("最大除霜", "windshield.front.and.heat.waves", vehicle.isDefrostOn) { await vehicle.toggleDefrost() }
                        toggleTile("方向盘加热", "steeringwheel.and.heat.waves", vehicle.isSteeringWheelHeaterOn) { await vehicle.toggleSteeringWheelHeater() }
                        toggleTile("生化防御", "aqi.high", vehicle.isBioweaponModeOn) { await vehicle.toggleBioweaponMode() }
                        toggleTile("过热保护", "thermometer.sun.fill", vehicle.isCabinOverheatProtectionOn) { await vehicle.toggleCabinOverheatProtection() }
                    }
                }
                controlCard("保持空调") {
                    Picker("保持空调", selection: Binding(get: { vehicle.climateKeeperMode }, set: { mode in Task { await vehicle.setClimateKeeper(mode) } })) {
                        ForEach(["关闭", "保持", "爱犬", "露营"], id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.segmented)
                    Text("爱犬和露营模式会持续消耗电量，请确认车辆环境安全。")
                        .font(.caption).foregroundStyle(AppTheme.muted)
                }
            }.padding(20)
        }.featurePage(title: "座舱")
    }

    private var temperatureDetail: String {
        [vehicle.cabinTemperature.map { String(format: "车内 %.1f°", $0) }, vehicle.outsideTemperature.map { String(format: "车外 %.1f°", $0) }]
            .compactMap { $0 }.joined(separator: " · ")
    }
    private func cabinButton(_ icon: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: { Image(systemName: icon).frame(width: 52, height: 44) }
            .buttonStyle(.bordered).disabled(vehicle.executingAction != nil)
    }
    private func toggleTile(_ title: String, _ icon: String, _ active: Bool, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.subheadline.weight(.medium))
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(active ? Color.white : AppTheme.raised, in: RoundedRectangle(cornerRadius: 15))
                .foregroundStyle(active ? .black : .white)
        }.buttonStyle(UtilityPressStyle()).disabled(vehicle.executingAction != nil)
    }
}

struct SentryControlView: View {
    @Environment(VehicleController.self) private var vehicle
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: vehicle.isSentryOn ? "eye.fill" : "eye.slash")
                .font(.system(size: 52, weight: .light)).frame(width: 104, height: 104)
                .background(AppTheme.surface, in: Circle())
            Text(vehicle.isSentryAvailable ? (vehicle.isSentryOn ? "哨兵模式已开启" : "哨兵模式已关闭") : "车辆未提供哨兵模式")
                .font(.title2.weight(.semibold))
            Text("哨兵模式会监控车辆周围环境并增加驻车耗电。视频内容仍保存在车辆本地存储中。")
                .font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
            Button { Task { await vehicle.toggleSentryMode() } } label: {
                Text(vehicle.isSentryOn ? "关闭哨兵模式" : "开启哨兵模式").frame(maxWidth: .infinity, minHeight: 54)
            }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                .disabled(!vehicle.isSentryAvailable || vehicle.executingAction != nil)
            Spacer()
        }.padding(24).featurePage(title: "哨兵模式")
    }
}

struct VehicleDiagnosticsView: View {
    @Environment(VehicleController.self) private var vehicle
    var body: some View {
        List {
            Section("连接") {
                LabeledContent("状态", value: vehicle.phase.title)
                LabeledContent("车辆", value: vehicle.displayVehicleName)
                LabeledContent("被动钥匙", value: vehicle.passiveEntryEnabled
                               ? (vehicle.passiveKeyOnline ? "在线" : "恢复中")
                               : "已关闭")
                LabeledContent("最后更新", value: freshness)
            }
            Section("最近操作") {
                if vehicle.commandHistory.isEmpty { Text("暂无操作记录").foregroundStyle(.secondary) }
                ForEach(vehicle.commandHistory) { item in
                    HStack {
                        Image(systemName: item.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(item.succeeded ? .green : .red)
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section { Text("记录仅保存在本机，最多保留最近 20 条，不包含 VIN 或位置。") }
        }.scrollContentBackground(.hidden).featurePage(title: "状态与诊断")
    }
    private var freshness: String {
        guard let date = vehicle.lastStateUpdate else { return "尚未获取" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "刚刚" }
        return "\(Int(seconds / 60)) 分钟前"
    }
}

private struct FeatureStatusCard: View {
    let icon: String; let title: String; let value: String; let detail: String
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.title2).frame(width: 48, height: 48).background(.white, in: Circle()).foregroundStyle(.black)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(AppTheme.muted) }
            Spacer(); Text(value).font(.title2.weight(.semibold)).monospacedDigit()
        }.padding(18).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

private func controlCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 14) { Text(title).font(.headline); content() }
        .padding(16).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.hairline, lineWidth: 0.5))
}
private func valueHeader(_ title: String, _ value: String) -> some View { HStack { Text(title).foregroundStyle(AppTheme.muted); Spacer(); Text(value).monospacedDigit() }.font(.subheadline) }
private func statusRow(_ title: String, _ value: String) -> some View { HStack { Text(title).foregroundStyle(AppTheme.muted); Spacer(); Text(value).monospacedDigit() }.font(.subheadline) }

private extension View {
    func featurePage(title: String) -> some View {
        background(AppTheme.background.ignoresSafeArea()).preferredColorScheme(.dark)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}
