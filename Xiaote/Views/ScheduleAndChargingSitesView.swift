import SwiftUI

enum TeslaScheduleDayMask {
    static let mondayFirstBits: [Int32] = [2, 4, 8, 16, 32, 64, 1]

    static func mask(for mondayFirstIndices: Set<Int>) -> Int32 {
        mondayFirstIndices.reduce(0) { result, index in
            guard mondayFirstBits.indices.contains(index) else { return result }
            return result | mondayFirstBits[index]
        }
    }

    static func labels(for mask: Int32) -> [String] {
        let names = ["一", "二", "三", "四", "五", "六", "日"]
        return names.indices.compactMap { index in
            mask & mondayFirstBits[index] != 0 ? "周" + names[index] : nil
        }
    }
}

struct VehicleSchedulesView: View {
    @Environment(VehicleController.self) private var vehicle
    @State private var showingEditor = false

    var body: some View {
        List {
            if vehicle.vehicleSchedules.isEmpty {
                ContentUnavailableView("暂无预约", systemImage: "calendar.badge.clock", description: Text("添加充电或预热计划，预约会保存在车辆中。"))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(vehicle.vehicleSchedules) { schedule in
                    HStack(spacing: 14) {
                        Image(systemName: schedule.kind == .charging ? "bolt.fill" : "fan.fill")
                            .frame(width: 38, height: 38).background(AppTheme.raised, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(schedule.name.isEmpty ? (schedule.kind == .charging ? "预约充电" : "预约预热") : schedule.name)
                            Text(timeText(schedule.minutes) + " · " + dayText(schedule.days)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Circle().fill(schedule.enabled ? Color.green : AppTheme.muted).frame(width: 7, height: 7)
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) { Task { await vehicle.removeSchedule(schedule) } }
                    }
                }
            }
            if let name = vehicle.scheduleLocationName {
                Section { Label("预约位置：\(name)", systemImage: "location") }
            }
        }
        .scrollContentBackground(.hidden)
        .appDestinationPage(title: "预约计划")
        .toolbar { Button { showingEditor = true } label: { Image(systemName: "plus") } }
        .task { await vehicle.refreshSchedules() }
        .fullScreenCover(isPresented: $showingEditor) { ScheduleEditorView().environment(vehicle) }
    }

    private func timeText(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
    private func dayText(_ mask: Int32) -> String {
        if mask == 0 || mask == 127 { return mask == 127 ? "每天" : "单次" }
        return TeslaScheduleDayMask.labels(for: mask).joined(separator: " ")
    }
}

private struct ScheduleEditorView: View {
    @Environment(VehicleController.self) private var vehicle
    @Environment(\.dismiss) private var dismiss
    @State private var kind: VehicleController.ScheduleKind = .charging
    @State private var name = ""
    @State private var time = Date()
    @State private var selectedDays: Set<Int> = Set(0...6)

    var body: some View {
        NavigationStack {
            Form {
                Picker("类型", selection: $kind) {
                    Text("充电").tag(VehicleController.ScheduleKind.charging)
                    Text("预热").tag(VehicleController.ScheduleKind.preconditioning)
                }.pickerStyle(.segmented)
                TextField("名称", text: $name)
                DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                Section("重复") {
                    HStack {
                        ForEach(0..<7) { day in
                            Button(["一","二","三","四","五","六","日"][day]) {
                                if selectedDays.contains(day) { selectedDays.remove(day) } else { selectedDays.insert(day) }
                            }
                            .buttonStyle(.bordered).tint(selectedDays.contains(day) ? .white : .gray)
                        }
                    }
                }
            }
            .navigationTitle("添加预约").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let mask = TeslaScheduleDayMask.mask(for: selectedDays)
                        Task { await vehicle.addSchedule(kind: kind, name: name, date: time, days: mask); dismiss() }
                    }.disabled(selectedDays.isEmpty)
                }
            }
        }.preferredColorScheme(.dark)
    }
}

struct NearbyChargingSitesView: View {
    @Environment(VehicleController.self) private var vehicle
    @Environment(FleetAccountController.self) private var fleetAccount
    var body: some View {
        List {
            if vehicle.isLoadingNearbyChargingSites, vehicle.nearbyChargingSites.isEmpty, cloudSites.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("正在通过车辆查询附近充电站…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .listRowBackground(Color.clear)
            } else if vehicle.nearbyChargingSites.isEmpty && cloudSites.isEmpty {
                ContentUnavailableView {
                    Label("暂无充电站数据", systemImage: "bolt.car")
                } description: {
                    Text(vehicle.nearbyChargingSitesMessage ?? "请唤醒车辆后重试。")
                } actions: {
                    Button("重新查询") { Task { await vehicle.refreshNearbyChargingSites() } }
                        .buttonStyle(.bordered)
                }
                    .listRowBackground(Color.clear)
            }
            if let message = vehicle.nearbyChargingSitesMessage, !vehicle.nearbyChargingSites.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.arrow.trianglehead.counterclockwise")
                    Text(message).font(.caption)
                    Spacer()
                    Button("重试") { Task { await vehicle.refreshNearbyChargingSites() } }
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .listRowBackground(AppTheme.raised)
            }
            ForEach(vehicle.nearbyChargingSites) { site in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(site.name).font(.headline); Spacer(); Text(String(format: "%.1f km", site.distanceKilometers)).monospacedDigit() }
                    if !site.address.isEmpty { Text(site.address).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Label(site.closed ? "站点已关闭" : "\(site.availableStalls) 空闲 · 共 \(site.totalStalls)", systemImage: site.closed ? "xmark.circle" : "bolt.fill")
                        Spacer()
                        if site.maxPowerKilowatts > 0 { Text("最高 \(site.maxPowerKilowatts) kW") }
                    }.font(.caption.weight(.medium)).foregroundStyle(site.closed ? .secondary : .primary)
                    if site.outOfOrderStalls > 0 {
                        Label("\(site.outOfOrderStalls) 个充电桩暂不可用", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    } else if !site.withinRange {
                        Label("车辆标记为续航范围外", systemImage: "road.lanes")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 5)
            }
            if vehicle.nearbyChargingSites.isEmpty {
                ForEach(cloudSites) { site in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(site.displayName).font(.headline)
                            Spacer()
                            if let distance = site.distanceKilometers {
                                Text(String(format: "%.1f km", distance)).monospacedDigit()
                            }
                        }
                        HStack {
                            if site.siteClosed == true {
                                Label("站点已关闭", systemImage: "xmark.circle")
                            } else if let available = site.availableStalls, let total = site.totalStalls {
                                Label("\(available) 空闲 · 共 \(total)", systemImage: "bolt.fill")
                            } else {
                                Label("Tesla 充电网络", systemImage: "bolt.fill")
                            }
                            Spacer()
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(site.siteClosed == true ? .secondary : .primary)
                    }
                    .padding(.vertical, 5)
                }
            }
            if let updated = vehicle.nearbyChargingSitesUpdatedAt, !vehicle.nearbyChargingSites.isEmpty {
                Text("车辆数据更新于 \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .appDestinationPage(title: "附近超级充电站")
        .refreshable { await refreshSites() }
        .task { await refreshSites() }
    }

    private var cloudSites: [FleetNearbyChargingSites.Site] {
        guard let vin = vehicle.currentVIN?.uppercased() else { return [] }
        return fleetAccount.nearbyChargingSites[vin] ?? []
    }

    private func refreshSites() async {
        await vehicle.refreshNearbyChargingSites()
        if let vin = vehicle.currentVIN, vehicle.nearbyChargingSites.isEmpty {
            await fleetAccount.loadNearbyChargingSites(for: vin)
        }
    }
}
