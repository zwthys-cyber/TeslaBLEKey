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
        .sheet(isPresented: $showingAccount) {
            TeslaAccountView().environment(account).presentationDetents([.large])
        }
        .sheet(isPresented: $showingBluetoothPairing, onDismiss: {
            Task { await localVehicle.finishVehicleAdditionSheet() }
        }) {
            NavigationStack { PairVehicleView() }
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
            VStack(alignment: .leading, spacing: 3) {
                Text(primaryVehicle?.name ?? "我的 Tesla")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.5)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("账号已连接").font(.caption).foregroundStyle(AppTheme.muted)
                }
            }
            Spacer()
            Button { showingAccount = true } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(AppTheme.hairline, lineWidth: 0.5))
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
                Text("远程连接可用").font(.headline)
                Text("通过 Tesla Fleet API 获取车辆状态")
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
                    ForEach(Array(account.vehicles.enumerated()), id: \.element.id) { index, vehicle in
                        HStack(spacing: 13) {
                            Image(systemName: "car.side.fill").frame(width: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(vehicle.name).font(.headline)
                                Text("•••• \(vehicle.vin.suffix(4))")
                                    .font(.caption.monospacedDigit()).foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            HStack(spacing: 5) {
                                Circle().fill(statusColor(vehicle.state)).frame(width: 6, height: 6)
                                Text(statusText(vehicle.state)).font(.caption)
                            }
                            .foregroundStyle(AppTheme.muted)
                        }
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

    private var primaryVehicle: FleetVehicle? { account.vehicles.first }

    private func statusText(_ state: String?) -> String {
        switch state { case "online": "在线"; case "asleep": "休眠"; case "offline": "离线"; default: "未知" }
    }

    private func statusColor(_ state: String?) -> Color {
        state == "online" ? .green : AppTheme.muted
    }
}
