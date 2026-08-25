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
        .scrollContentBackground(.hidden).background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("预约计划").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button { showingEditor = true } label: { Image(systemName: "plus") } }
        .task { await vehicle.refreshSchedules() }
        .sheet(isPresented: $showingEditor) { ScheduleEditorView().environment(vehicle) }
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
    var body: some View {
        List {
            if vehicle.nearbyChargingSites.isEmpty {
                ContentUnavailableView("暂无充电站数据", systemImage: "bolt.car", description: Text("请唤醒车辆后刷新。"))
                    .listRowBackground(Color.clear)
            }
            ForEach(vehicle.nearbyChargingSites) { site in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(site.name).font(.headline); Spacer(); Text(String(format: "%.1f km", site.distanceKilometers)).monospacedDigit() }
                    Text(site.address).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Label(site.closed ? "已关闭" : "\(site.availableStalls)/\(site.totalStalls) 空闲", systemImage: site.closed ? "xmark.circle" : "bolt.fill")
                        Spacer()
                        if site.maxPowerKilowatts > 0 { Text("最高 \(site.maxPowerKilowatts) kW") }
                    }.font(.caption.weight(.medium)).foregroundStyle(site.closed ? .secondary : .primary)
                }.padding(.vertical, 5)
            }
        }
        .scrollContentBackground(.hidden).background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("附近超级充电站").navigationBarTitleDisplayMode(.inline)
        .refreshable { await vehicle.refreshNearbyChargingSites() }
        .task { await vehicle.refreshNearbyChargingSites() }
    }
}
