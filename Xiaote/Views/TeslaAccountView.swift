import SwiftUI

struct TeslaAccountView: View {
    @Environment(FleetAccountController.self) private var account
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if account.isSignedIn { signedInContent } else { signedOutContent }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Tesla 账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .overlay {
                if account.isWorking { ProgressView().controlSize(.large).tint(.white) }
            }
            .alert("无法完成操作", isPresented: Binding(
                get: { account.errorMessage != nil },
                set: { if !$0 { account.errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { account.errorMessage = nil }
            } message: {
                Text(account.errorMessage ?? "未知错误")
            }
            .task {
                if account.isSignedIn && account.vehicles.isEmpty { await account.refreshVehicles() }
            }
            .refreshable {
                if account.isSignedIn { await account.refreshVehicles() }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: account.isSignedIn) { wasSignedIn, isSignedIn in
            if !wasSignedIn && isSignedIn { dismiss() }
        }
    }

    private var signedOutContent: some View {
        Section {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 38, weight: .light))
                Text("连接 Tesla 账号")
                    .font(.title2.weight(.semibold))
                Text("登录后可在蓝牙范围外读取车辆状态并使用受支持的远程控制。现有蓝牙钥匙无需登录，仍可独立使用。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await account.signIn() }
                } label: {
                    Text("继续登录")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .disabled(account.isWorking)
            }
            .padding(.vertical, 12)
        } footer: {
            Text("Tesla 密码只在 Tesla 官方授权页面输入，本应用和 txx.app 均不会接触或保存密码。")
        }
    }

    private var signedInContent: some View {
        Group {
            Section {
                Label("已安全连接", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } footer: {
                Text("账号连接用于 Fleet API；手机蓝牙钥匙和被动进入仍由本地密钥负责。")
            }

            Section("账号中的车辆") {
                if account.vehicles.isEmpty {
                    Text("暂未读取到车辆，下拉刷新重试。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(account.vehicles) { vehicle in
                        HStack(spacing: 12) {
                            Image(systemName: "car.side.fill").frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(vehicle.name).font(.headline)
                                Text("•••• \(vehicle.vin.suffix(4)) · \(stateText(vehicle.state))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Section {
                Button("退出 Tesla 账号", role: .destructive) {
                    Task { await account.signOut(); dismiss() }
                }
            }
        }
    }

    private func stateText(_ state: String?) -> String {
        switch state {
        case "online": "在线"
        case "asleep": "休眠"
        case "offline": "离线"
        default: "状态未知"
        }
    }
}
