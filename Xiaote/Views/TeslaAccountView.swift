import SwiftUI

struct TeslaAccountView: View {
    @Environment(FleetAccountController.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if account.isSignedIn { signedInContent }
                    else { signedOutContent }
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 34)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                if account.isSignedIn { await account.refreshVehicles() }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("小特账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .confirmationDialog("退出 Tesla 账号？", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("退出", role: .destructive) {
                    Task { await account.signOut(); dismiss() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("本地蓝牙钥匙不会被移除，之后仍可重新连接账号。")
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
        }
        .preferredColorScheme(.dark)
        .onChange(of: account.isSignedIn) { wasSignedIn, isSignedIn in
            if !wasSignedIn && isSignedIn { dismiss() }
        }
    }

    private var signedInContent: some View {
        VStack(spacing: 0) {
            connectionIdentity

            if account.isWorking && account.vehicles.isEmpty {
                loadingState.padding(.top, 72)
            } else if account.vehicles.isEmpty {
                emptyVehicleState.padding(.top, 62)
            } else {
                vehicleList.padding(.top, 38)
            }

            Spacer(minLength: 72)
            connectionDetails
                .padding(.top, 44)
            signOutButton
                .padding(.top, 24)
        }
        .frame(minHeight: 650, alignment: .top)
    }

    private var connectionIdentity: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(AppTheme.surface)
                    .frame(width: 72, height: 72)
                    .overlay(Circle().stroke(AppTheme.hairline, lineWidth: 0.5))
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.88))
                Circle()
                    .fill(.green)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(AppTheme.background, lineWidth: 3))
                    .offset(x: -1, y: -1)
            }
            Text("已连接 Tesla")
                .font(.title2.weight(.semibold))
                .tracking(-0.2)
            Text("远程服务已就绪")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tesla 账号已连接，远程服务已就绪")
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.regular).tint(.white)
            Text("正在同步车辆")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
        }
    }

    private var emptyVehicleState: some View {
        VStack(spacing: 18) {
            Image(systemName: "car.side")
                .font(.system(size: 46, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.72))
                .frame(height: 58)
            VStack(spacing: 7) {
                Text("此账号暂无车辆")
                    .font(.headline)
                Text("车辆添加到 Tesla 账号后会显示在这里")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task { await account.refreshVehicles() }
            } label: {
                HStack(spacing: 7) {
                    if account.isWorking { ProgressView().controlSize(.mini).tint(.white) }
                    else { Image(systemName: "arrow.clockwise") }
                    Text("重新同步")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18)
                .frame(height: 42)
                .background(AppTheme.surface, in: Capsule())
                .overlay(Capsule().stroke(AppTheme.hairline, lineWidth: 0.5))
            }
            .buttonStyle(UtilityPressStyle())
            .disabled(account.isWorking)
        }
        .frame(maxWidth: .infinity)
    }

    private var vehicleList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("账号中的车辆")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(account.vehicles.enumerated()), id: \.element.id) { index, vehicle in
                    HStack(spacing: 14) {
                        Image(systemName: "car.side.fill")
                            .font(.title3)
                            .frame(width: 34, height: 34)
                            .background(AppTheme.raised, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(vehicle.name).font(.headline)
                            Text("•••• \(vehicle.vin.suffix(4))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        HStack(spacing: 5) {
                            Circle().fill(vehicle.state == "online" ? Color.green : AppTheme.muted)
                                .frame(width: 6, height: 6)
                            Text(stateText(vehicle.state)).font(.caption)
                        }
                        .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 72)
                    .accessibilityElement(children: .combine)
                    if index < account.vehicles.count - 1 {
                        Divider().overlay(AppTheme.hairline).padding(.leading, 64)
                    }
                }
            }
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 0.5)
            }
        }
    }

    private var connectionDetails: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text("连接与隐私").font(.subheadline.weight(.semibold))
                Text("Fleet API 负责联网数据，本地蓝牙密钥仍只保存在这台 iPhone。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var signOutButton: some View {
        Button("退出账号") { confirmSignOut = true }
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppTheme.muted)
            .buttonStyle(UtilityPressStyle())
            .accessibilityHint("不会移除本地蓝牙钥匙")
    }

    private var signedOutContent: some View {
        VStack(spacing: 0) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.82))
                .padding(.top, 46)
            Text("连接 Tesla 账号")
                .font(.title2.weight(.semibold))
                .padding(.top, 22)
            Text("在蓝牙范围外查看车辆状态并使用受支持的远程控制。账号连接完全可选。")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 18)
                .padding(.top, 10)
            Button {
                Task { await account.signIn() }
            } label: {
                HStack(spacing: 8) {
                    if account.isWorking { ProgressView().controlSize(.small).tint(.black) }
                    Text("使用 Tesla 账号继续")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(.black)
            }
            .buttonStyle(PrimaryPressStyle())
            .disabled(account.isWorking)
            .padding(.top, 38)
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "lock.fill").font(.caption2).padding(.top, 2)
                Text("密码只在 Tesla 官方页面输入，小特不会读取或保存你的密码。")
                    .font(.caption)
            }
            .foregroundStyle(AppTheme.muted)
            .padding(.horizontal, 12)
            .padding(.top, 18)
        }
        .frame(minHeight: 620, alignment: .top)
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
