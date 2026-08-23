import SwiftUI

struct VehicleDetailView: View {
    @Environment(VehicleController.self) private var vehicle
    @State private var refreshing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                identityCard
                if hasChargingData { detailSection("电池与充电", icon: "bolt.fill", rows: chargingRows) }
                if hasClimateData { detailSection("座舱", icon: "fan.fill", rows: climateRows) }
                if hasClosureData { detailSection("车辆状态", icon: "car.side.fill", rows: closureRows) }
                if hasTireData { tireSection }
                if hasVehicleData { detailSection("车辆信息", icon: "info.circle", rows: vehicleRows) }
                if hasMediaData { detailSection("正在播放", icon: "play.fill", rows: mediaRows) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
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

    private var identityCard: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vehicle.displayVehicleName).font(.title2.weight(.semibold))
                    Text(updateLabel).font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                if let battery = vehicle.batteryLevel {
                    Text("\(battery)%").font(.title2.weight(.semibold)).monospacedDigit()
                }
            }
            if let battery = vehicle.batteryLevel {
                ProgressView(value: Double(battery), total: 100)
                    .tint(.white)
                    .background(.white.opacity(0.12))
            }
        }
        .padding(18)
        .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(AppTheme.hairline, lineWidth: 0.5))
    }

    private func detailSection(_ title: String, icon: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: icon).font(.headline).padding(.bottom, 12)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack { Text(row.0).foregroundStyle(AppTheme.muted); Spacer(); Text(row.1).monospacedDigit() }
                    .font(.subheadline).padding(.vertical, 11)
                if index < rows.count - 1 { Divider().overlay(AppTheme.hairline) }
            }
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.hairline, lineWidth: 0.5))
    }

    private var tireSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("轮胎压力", systemImage: "gauge.with.dots.needle.67percent").font(.headline)
                Spacer()
                if vehicle.hasTirePressureWarning {
                    Label("请检查", systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.semibold))
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                tire("左前", vehicle.tirePressureFL)
                tire("右前", vehicle.tirePressureFR)
                tire("左后", vehicle.tirePressureRL)
                tire("右后", vehicle.tirePressureRR)
            }
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.hairline, lineWidth: 0.5))
    }

    private func tire(_ title: String, _ pressure: Double?) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(AppTheme.muted)
            Text(pressure.map { String(format: "%.2f bar", $0) } ?? "—").font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        if let value = vehicle.openDoorCount { rows.append(("车门", value == 0 ? "全部关闭" : "\(value) 个开启")) }
        if let value = vehicle.openWindowCount { rows.append(("车窗", value == 0 ? "全部关闭" : "\(value) 个开启")) }
        if let value = vehicle.isFrunkOpen { rows.append(("前备箱", value ? "已开启" : "已关闭")) }
        rows.append(("后备箱", vehicle.isTrunkOpen ? "已开启" : "已关闭"))
        rows.append(("充电口", vehicle.isChargePortOpen ? "已开启" : "已关闭"))
        for key in ["左前门", "右前门", "左后门", "右后门"] {
            if let value = vehicle.doorStates[key] { rows.append((key, value ? "已开启" : "已关闭")) }
        }
        for key in ["左前窗", "右前窗", "左后窗", "右后窗"] {
            if let value = vehicle.windowStates[key] { rows.append((key, value ? "已开启" : "已关闭")) }
        }
        return rows
    }

    private var vehicleRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let value = vehicle.odometerKilometers { rows.append(("累计里程", String(format: "%.0f km", value))) }
        if let value = vehicle.softwareVersion { rows.append(("软件版本", value)) }
        if let value = vehicle.softwareUpdateStatus { rows.append(("软件更新", value)) }
        if let value = vehicle.vehicleSleepStatus { rows.append(("车辆电源", value)) }
        if let value = vehicle.currentGear { rows.append(("当前挡位", value)) }
        return rows
    }

    private var mediaRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let value = vehicle.mediaTitle { rows.append(("曲目", value)) }
        if let value = vehicle.mediaArtist { rows.append(("艺术家", value)) }
        if let value = vehicle.mediaAlbum { rows.append(("专辑", value)) }
        if let value = vehicle.mediaSource { rows.append(("来源", value)) }
        if let value = vehicle.mediaPlaybackStatus { rows.append(("播放状态", value)) }
        return rows
    }

    private var hasChargingData: Bool { !chargingRows.isEmpty }
    private var hasClimateData: Bool { vehicle.cabinTemperature != nil || vehicle.outsideTemperature != nil }
    private var hasClosureData: Bool { vehicle.isLocked != nil || vehicle.openDoorCount != nil || vehicle.openWindowCount != nil }
    private var hasTireData: Bool { [vehicle.tirePressureFL, vehicle.tirePressureFR, vehicle.tirePressureRL, vehicle.tirePressureRR].contains { $0 != nil } }
    private var hasVehicleData: Bool { !vehicleRows.isEmpty }
    private var hasMediaData: Bool { !mediaRows.isEmpty }
    private var updateLabel: String {
        guard let date = vehicle.lastStateUpdate else { return refreshing ? "正在读取车辆状态" : "尚未刷新" }
        return "更新于 \(date.formatted(date: .omitted, time: .shortened))"
    }
}
