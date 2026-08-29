import SwiftUI

struct VehicleDetailView: View {
    @Environment(VehicleController.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var refreshing = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                vehicleHero
                primaryMetrics
                    .padding(.top, 10)
                    .padding(.bottom, 34)

                if hasClosureData { detailSection("车辆", summary: closureSummary, rows: closureRows) }
                if hasClimateData { detailSection("座舱", summary: climateSummary, rows: climateRows) }
                if hasChargingData { detailSection("电池与充电", summary: chargingSummary, rows: secondaryChargingRows) }
                if hasTireData { tireSection }
                if hasVehicleData { detailSection("系统", summary: vehicleSummary, rows: vehicleRows) }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 44)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationTitle("车辆详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await refresh() } } label: {
                    if refreshing { ProgressView().controlSize(.small).tint(.white) }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(refreshing)
                .accessibilityLabel("刷新车辆信息")
            }
        }
        .task { await refresh() }
    }

    private var vehicleHero: some View {
        VStack(spacing: 4) {
            Group {
                if showsModel3Artwork {
                    StatefulModel3Artwork(
                        isConnected: connected,
                        isLocked: vehicle.isLocked,
                        isFrunkOpen: vehicle.isFrunkOpen == true,
                        isTrunkOpen: vehicle.isTrunkOpen,
                        doorStates: vehicle.doorStates,
                        isCharging: vehicle.isCharging,
                        reduceMotion: reduceMotion
                    )
                } else {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 82, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, minHeight: 160)
                }
            }
            .frame(maxWidth: 430)
            .accessibilityHidden(true)

            Text(vehicle.displayVehicleName)
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.4)

            HStack(spacing: 7) {
                Circle()
                    .fill(connected ? Color.green : AppTheme.muted)
                    .frame(width: 7, height: 7)
                Text(vehicle.phase.title)
                Text("·")
                Text(updateLabel)
            }
            .font(.caption)
            .foregroundStyle(AppTheme.muted)
        }
        .padding(.top, 6)
    }

    private var primaryMetrics: some View {
        HStack(spacing: 0) {
            metric(value: vehicle.batteryLevel.map { "\($0)%" } ?? "—", label: "电量")
            Rectangle().fill(AppTheme.hairline).frame(width: 0.5, height: 35)
            metric(value: vehicle.estimatedRangeKilometers.map { String(format: "%.0f km", $0) } ?? "—", label: "预计续航")
        }
        .padding(.top, 18)
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private func detailSection(_ title: String, summary: String?, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if let summary {
                    Text(summary).font(.subheadline).foregroundStyle(AppTheme.muted)
                }
            }
            .padding(.bottom, 9)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 16) {
                    Text(row.0).foregroundStyle(AppTheme.muted)
                    Spacer()
                    Text(row.1).monospacedDigit().multilineTextAlignment(.trailing)
                }
                .font(.subheadline)
                .padding(.vertical, 11)
                if index < rows.count - 1 { Divider().overlay(AppTheme.hairline) }
            }
        }
        .padding(.bottom, 30)
    }

    private var tireSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("轮胎").font(.headline)
                Spacer()
                if vehicle.hasTirePressureWarning {
                    Text("请检查").font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                } else {
                    Text("胎压正常").font(.subheadline).foregroundStyle(AppTheme.muted)
                }
            }
            .padding(.bottom, 9)

            HStack(spacing: 0) {
                tire("左前", vehicle.tirePressureFL)
                tire("右前", vehicle.tirePressureFR)
                tire("左后", vehicle.tirePressureRL)
                tire("右后", vehicle.tirePressureRR)
            }
        }
        .padding(.bottom, 30)
    }


    private func tire(_ title: String, _ pressure: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(AppTheme.muted)
            Text(pressure.map { String(format: "%.1f", $0) } ?? "—")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
            Text("bar").font(.caption2).foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        await vehicle.refreshVehicleState()
        refreshing = false
    }

    private var chargingRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let value = vehicle.batteryLevel { rows.append(("电池电量", "\(value)%")) }
        if let value = vehicle.estimatedRangeKilometers { rows.append(("预计续航", String(format: "%.0f km", value))) }
        if let value = vehicle.chargingStatus { rows.append(("充电状态", value)) }
        if let value = vehicle.chargeLimit { rows.append(("充电上限", "\(value)%")) }
        if let value = vehicle.chargerPowerKilowatts { rows.append(("充电功率", "\(value) kW")) }
        if let value = vehicle.chargerCurrentAmps { rows.append(("充电电流", "\(value) A")) }
        if let value = vehicle.chargerVoltage { rows.append(("充电电压", "\(value) V")) }
        if let value = vehicle.minutesToChargeLimit { rows.append(("距目标电量", "\(value) 分钟")) }
        if let value = vehicle.chargeCableStatus { rows.append(("充电枪", value)) }
        if let value = vehicle.chargePortLatchStatus { rows.append(("充电口锁止", value)) }
        return rows
    }

    private var secondaryChargingRows: [(String, String)] {
        chargingRows.filter { $0.0 != "电池电量" && $0.0 != "预计续航" }
    }

    private var climateRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let value = vehicle.cabinTemperature { rows.append(("车内温度", String(format: "%.1f°", value))) }
        if let value = vehicle.outsideTemperature { rows.append(("车外温度", String(format: "%.1f°", value))) }
        rows.append(("空调", vehicle.isClimateOn ? "已开启" : "已关闭"))
        rows.append(("设定温度", String(format: "%.1f°", vehicle.targetTemperature)))
        return rows
    }

    private var closureRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let value = vehicle.isLocked { rows.append(("车辆", value ? "已上锁" : "已解锁")) }
        if let value = vehicle.openDoorCount {
            rows.append(("车门", value == 0 ? "全部关闭" : openNames(in: vehicle.doorStates, fallback: "\(value) 个开启")))
        }
        if let value = vehicle.openWindowCount {
            rows.append(("车窗", value == 0 ? "全部关闭" : openNames(in: vehicle.windowStates, fallback: "\(value) 个开启")))
        }
        let storage = [vehicle.isFrunkOpen == true ? "前备箱" : nil, vehicle.isTrunkOpen ? "后备箱" : nil].compactMap { $0 }
        rows.append(("储物箱", storage.isEmpty ? "均已关闭" : storage.joined(separator: "、") + "已开启"))
        rows.append(("充电口", vehicle.isChargePortOpen ? "已开启" : "已关闭"))
        return rows
    }

    private func openNames(in states: [String: Bool], fallback: String) -> String {
        let names = states.filter(\.value).map(\.key).sorted()
        return names.isEmpty ? fallback : names.joined(separator: "、")
    }

    private var vehicleRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let value = vehicle.odometerKilometers { rows.append(("累计里程", String(format: "%.0f km", value))) }
        if let value = vehicle.availableSoftwareVersion { rows.append(("待安装版本", value)) }
        if let value = vehicle.softwareUpdateStatus { rows.append(("更新状态", value)) }
        if let value = vehicle.vehicleSleepStatus { rows.append(("车辆电源", value)) }
        if let value = vehicle.currentGear { rows.append(("当前挡位", value)) }
        return rows
    }


    private var hasChargingData: Bool { !secondaryChargingRows.isEmpty }
    private var hasClimateData: Bool { vehicle.cabinTemperature != nil || vehicle.outsideTemperature != nil }
    private var hasClosureData: Bool { vehicle.isLocked != nil || vehicle.openDoorCount != nil || vehicle.openWindowCount != nil }
    private var hasTireData: Bool { [vehicle.tirePressureFL, vehicle.tirePressureFR, vehicle.tirePressureRL, vehicle.tirePressureRR].contains { $0 != nil } }
    private var hasVehicleData: Bool { !vehicleRows.isEmpty }
    private var connected: Bool {
        if vehicle.phase == .connected { return true }
        if case .executing = vehicle.phase { return true }
        return false
    }
    private var closureSummary: String? {
        if let doors = vehicle.openDoorCount, doors > 0 { return "\(doors) 个车门开启" }
        if let windows = vehicle.openWindowCount, windows > 0 { return "\(windows) 个车窗开启" }
        if vehicle.isFrunkOpen == true || vehicle.isTrunkOpen { return "储物箱开启" }
        return "门窗均已关闭"
    }
    private var climateSummary: String? {
        if let temperature = vehicle.cabinTemperature { return String(format: "车内 %.1f°", temperature) }
        return vehicle.isClimateOn ? "空调已开启" : "空调已关闭"
    }
    private var chargingSummary: String? { vehicle.chargingStatus ?? vehicle.batteryLevel.map { "\($0)%" } }
    private var vehicleSummary: String? {
        if let odometer = vehicle.odometerKilometers { return String(format: "%.0f km", odometer) }
        return vehicle.vehicleSleepStatus
    }
    private var showsModel3Artwork: Bool {
        let model = vehicle.vehicleModelName ?? vehicle.displayVehicleName
        return model.lowercased().replacingOccurrences(of: " ", with: "").contains("model3")
    }
    private var updateLabel: String {
        guard let date = vehicle.lastStateUpdate else { return refreshing ? "正在读取车辆状态" : "尚未刷新" }
        return "更新于 \(date.formatted(date: .omitted, time: .shortened))"
    }
}

struct StatefulModel3Artwork: View {
    let isConnected: Bool
    let isLocked: Bool?
    let isFrunkOpen: Bool
    let isTrunkOpen: Bool
    let doorStates: [String: Bool]
    let isCharging: Bool
    let reduceMotion: Bool
    @State private var artworkOpacity = 1.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("Model3HighlandDetail")
                    .resizable()
                    .scaledToFit()
                    .opacity(isLocked == true ? 0 : 1)
                Image("Model3HighlandLocked")
                    .resizable()
                    .scaledToFit()
                    .opacity(isLocked == true ? 1 : 0)

                if isFrunkOpen {
                    statePoint(at: CGPoint(x: 0.31, y: 0.60), in: proxy.size, label: "前备箱已开启")
                }
                if isTrunkOpen {
                    statePoint(at: CGPoint(x: 0.88, y: 0.43), in: proxy.size, label: "后备箱已开启")
                }
                if doorStates["左前门"] == true {
                    statePoint(at: CGPoint(x: 0.63, y: 0.52), in: proxy.size, label: "左前门已开启")
                }
                if doorStates["左后门"] == true {
                    statePoint(at: CGPoint(x: 0.75, y: 0.48), in: proxy.size, label: "左后门已开启")
                }
                if doorStates["右前门"] == true || doorStates["右后门"] == true {
                    statePoint(at: CGPoint(x: 0.54, y: 0.43), in: proxy.size, label: "右侧车门已开启")
                }
                if isCharging {
                    ChargingPulse(reduceMotion: reduceMotion)
                        .position(x: proxy.size.width * 0.89, y: proxy.size.height * 0.44)
                        .accessibilityLabel("车辆正在充电")
                }
            }
        }
        .aspectRatio(1.5, contentMode: .fit)
        .opacity(isConnected ? artworkOpacity : 0.58)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: isLocked)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isFrunkOpen)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isTrunkOpen)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: doorStates)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isConnected)
        .onChange(of: isConnected) { wasConnected, connected in
            guard !wasConnected, connected, !reduceMotion else { return }
            artworkOpacity = 0.72
            withAnimation(.easeOut(duration: 0.24)) {
                artworkOpacity = 1
            }
        }
    }

    private func statePoint(at point: CGPoint, in size: CGSize, label: String) -> some View {
        ZStack {
            Circle().fill(.black.opacity(0.55)).frame(width: 19, height: 19)
            Circle().stroke(.white.opacity(0.92), lineWidth: 1.5).frame(width: 12, height: 12)
            Circle().fill(.white).frame(width: 4, height: 4)
        }
        .position(x: size.width * point.x, y: size.height * point.y)
        .transition(.opacity.combined(with: .scale(scale: 0.75)))
        .accessibilityLabel(label)
    }
}

private struct ChargingPulse: View {
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
            let phase = reduceMotion ? 0.5 : (sin(context.date.timeIntervalSinceReferenceDate * .pi / 1.6) + 1) / 2
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12 + phase * 0.14))
                    .frame(width: 30, height: 30)
                    .scaleEffect(0.84 + phase * 0.16)
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 5, weight: .bold))
                    .foregroundStyle(.black)
            }
        }
        .frame(width: 30, height: 30)
    }
}
