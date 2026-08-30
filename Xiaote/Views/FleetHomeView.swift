import SwiftUI

struct FleetHomeView: View {
    @Environment(FleetAccountController.self) private var account
    @Environment(VehicleController.self) private var localVehicle
    @State private var showingAccount = false
    @State private var showingBluetoothPairing = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 18) {
                    accountStatus
                    vehicles
                    bluetoothKeyCard
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .scrollIndicators(.hidden)
            .refreshable { await account.refreshVehicles() }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showingAccount) {
            TeslaAccountView().environment(account)
        }
        .fullScreenCover(isPresented: $showingBluetoothPairing, onDismiss: {
            Task { await localVehicle.finishVehicleAdditionSheet() }
        }) {
            NavigationStack { PairVehicleView(showsCloseButton: true) }
                .environment(localVehicle)
                .environment(account)
                .preferredColorScheme(.dark)
        }
        .task {
            if account.vehicles.isEmpty { await account.refreshVehicles() }
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Button { showingAccount = true } label: {
                TeslaAccountAvatarLabel(profile: account.profile, isSignedIn: true)
            }
            .buttonStyle(UtilityPressStyle())
            .accessibilityLabel("Tesla 账号")
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(AppTheme.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.hairline.opacity(0.55)).frame(height: 0.5)
        }
    }

    private var accountStatus: some View {
        HStack(spacing: 14) {
            Image(systemName: "network")
                .font(.title2)
                .frame(width: 40, height: 40)
                .background(AppTheme.raised, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(account.isDemoMode ? "演示模式" : "远程连接可用").font(.headline)
                Text(account.isDemoMode ? "当前显示本机测试数据，不会控制车辆" : "通过 Tesla Fleet API 获取车辆状态")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
            Spacer()
            if account.isWorking { ProgressView().controlSize(.small).tint(.white) }
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var vehicles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("车辆").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.muted)
            if account.vehicles.isEmpty {
                Text("暂未读取到账号车辆，下拉刷新重试。")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(account.vehicles.enumerated()), id: \.element.id) { index, fleetVehicle in
                        NavigationLink {
                            FleetVehicleOverviewView(fleetVehicle: fleetVehicle)
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "car.side.fill").frame(width: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 7) {
                                        Text(fleetVehicle.name).font(.headline)
                                        if account.isDemoMode {
                                            Text("演示")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.black)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.white, in: Capsule())
                                        }
                                    }
                                    Text("•••• \(fleetVehicle.vin.suffix(4))")
                                        .font(.caption.monospacedDigit()).foregroundStyle(AppTheme.muted)
                                }
                                Spacer()
                                HStack(spacing: 5) {
                                    Circle().fill(statusColor(fleetVehicle.state)).frame(width: 6, height: 6)
                                    Text(statusText(fleetVehicle.state)).font(.caption)
                                }
                                .foregroundStyle(AppTheme.muted)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.muted)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(16)
                        if index < account.vehicles.count - 1 {
                            Divider().overlay(AppTheme.hairline).padding(.leading, 61)
                        }
                    }
                }
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var bluetoothKeyCard: some View {
        Button {
            localVehicle.prepareForVehicleAddition()
            showingBluetoothPairing = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "key.horizontal.fill")
                    .font(.title3).frame(width: 38, height: 38)
                    .background(.white, in: Circle()).foregroundStyle(.black)
                VStack(alignment: .leading, spacing: 3) {
                    Text("添加手机蓝牙钥匙").font(.headline)
                    Text("用于无感进入和近距离本地控制")
                        .font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.muted)
            }
            .padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(UtilityPressStyle())
    }

    private func statusText(_ state: String?) -> String {
        switch state { case "online": "在线"; case "asleep": "休眠"; case "offline": "离线"; default: "未知" }
    }

    private func statusColor(_ state: String?) -> Color {
        state == "online" ? .green : AppTheme.muted
    }
}

private struct FleetVehicleOverviewView: View {
    @Environment(FleetAccountController.self) private var account
    let fleetVehicle: FleetVehicle

    var body: some View {
        List {
            Section("车辆") {
                LabeledContent("名称", value: fleetVehicle.name)
                LabeledContent("状态", value: statusText)
                LabeledContent("车辆识别码", value: "•••• \(fleetVehicle.vin.suffix(4))")
            }
            if account.isDemoMode {
                Section {
                    Label("这是界面演示车辆，不会连接或控制真实车辆。", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
            if let specs = account.vehicleSpecs[fleetVehicle.vin.uppercased()], !specs.rows.isEmpty {
                Section("车辆配置") {
                    ForEach(Array(specs.rows.enumerated()), id: \.offset) { _, row in
                        LabeledContent(row.0, value: row.1)
                    }
                }
            }
            if let notes = account.releaseNotes[fleetVehicle.vin.uppercased()] {
                Section("软件") {
                    if let version = notes.displayVersion { LabeledContent("已部署版本", value: version) }
                    ForEach(Array(notes.titledNotes.prefix(2).enumerated()), id: \.offset) { _, title in
                        Text(title)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appDestinationPage(title: fleetVehicle.name)
        .task {
            await account.loadSpecs(for: fleetVehicle.vin)
            await account.loadCloudDetails(for: fleetVehicle.vin)
        }
    }

    private var statusText: String {
        switch fleetVehicle.state { case "online": "在线"; case "asleep": "休眠"; case "offline": "离线"; default: "未知" }
    }
}
