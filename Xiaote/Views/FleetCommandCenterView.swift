import SwiftUI

struct FleetCommandCenterView: View {
    @Environment(FleetAccountController.self) private var account
    let vehicle: FleetVehicle
    @State private var search = ""

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "car.side.fill").font(.title2).frame(width: 44, height: 44)
                        .background(AppTheme.raised, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(vehicle.name).font(.headline)
                        Text("VIN •••• \(vehicle.vin.suffix(4)) · Tesla Fleet API")
                            .font(.caption).foregroundStyle(AppTheme.muted)
                    }
                }
            }
            ForEach(FleetCommandDefinition.Category.allCases) { category in
                let commands = filtered.filter { $0.category == category }
                if !commands.isEmpty {
                    Section(category.rawValue) {
                        ForEach(commands) { command in
                            NavigationLink {
                                FleetCommandDetailView(vehicle: vehicle, command: command)
                            } label: {
                                HStack(spacing: 13) {
                                    Image(systemName: command.symbol).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(command.title)
                                        Text(command.summary).font(.caption).foregroundStyle(AppTheme.muted).lineLimit(2)
                                    }
                                    if command.risk == .critical {
                                        Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.orange)
                                            .accessibilityLabel("高风险操作")
                                    }
                                }.padding(.vertical, 3)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "搜索车辆命令")
        .navigationTitle("车辆控制中心")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .preferredColorScheme(.dark)
    }

    private var filtered: [FleetCommandDefinition] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return FleetCommandDefinition.all }
        return FleetCommandDefinition.all.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.summary.localizedCaseInsensitiveContains(query) ||
            $0.id.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct FleetCommandDetailView: View {
    @Environment(FleetAccountController.self) private var account
    let vehicle: FleetVehicle
    let command: FleetCommandDefinition
    @State private var payload: String
    @State private var isSending = false
    @State private var showConfirmation = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    init(vehicle: FleetVehicle, command: FleetCommandDefinition) {
        self.vehicle = vehicle; self.command = command
        _payload = State(initialValue: Self.pretty(command.payloadTemplate))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 15) {
                    Image(systemName: command.symbol).font(.title2).frame(width: 52, height: 52)
                        .background(AppTheme.raised, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(command.title).font(.title3.weight(.semibold))
                        Text(command.summary).font(.subheadline).foregroundStyle(AppTheme.muted)
                    }
                }
                if command.risk == .critical {
                    Label("高风险车辆操作。执行前请确认车辆周围环境、乘员和账号安全。", systemImage: "exclamationmark.shield.fill")
                        .font(.subheadline).foregroundStyle(.orange).padding(14)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("命令参数").font(.headline)
                    TextEditor(text: $payload)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: command.payloadTemplate == "{}" ? 80 : 170)
                        .padding(10).scrollContentBackground(.hidden)
                        .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 14))
                    HStack {
                        Label(payloadData == nil ? "JSON 参数无效" : "参数格式有效",
                              systemImage: payloadData == nil ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(payloadData == nil ? .red : .green)
                        Spacer()
                        Button("恢复模板") { payload = Self.pretty(command.payloadTemplate) }.font(.caption)
                    }
                    Text("参数将经小特服务端校验后，通过 Tesla 官方 Fleet API 加密发送。")
                        .font(.caption).foregroundStyle(AppTheme.muted)
                }
                .padding(16).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20))

                Button {
                    if command.risk == .normal { Task { await send() } }
                    else { showConfirmation = true }
                } label: {
                    HStack {
                        if isSending { ProgressView().tint(.black) }
                        Text(isSending ? "正在发送" : "执行\(command.title)")
                    }.frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                .disabled(payloadData == nil || isSending || account.isDemoMode)
                .accessibilityHint("向车辆发送 \(command.id) 命令")

                if account.isDemoMode {
                    Label("演示模式已禁止发送真实车辆命令", systemImage: "hand.raised.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }.padding(20)
        }
        .navigationTitle(command.title).navigationBarTitleDisplayMode(.inline)
        .background(AppTheme.background.ignoresSafeArea()).preferredColorScheme(.dark)
        .confirmationDialog("确认执行“\(command.title)”？", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button(command.risk == .critical ? "确认高风险操作" : "确认执行", role: command.risk == .critical ? .destructive : nil) {
                Task { await send() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(command.risk == .critical ? "此操作可能影响车辆访问、驾驶权限或车内数据，执行后可能无法立即撤销。" : command.summary)
        }
        .alert("操作成功", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("完成", role: .cancel) { resultMessage = nil }
        } message: { Text(resultMessage ?? "") }
        .alert("命令未执行", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var payloadData: Data? {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data), object is [String: Any] else { return nil }
        return data
    }

    @MainActor private func send() async {
        guard let payloadData else { return }
        isSending = true; defer { isSending = false }
        do {
            try await account.send(command: command, to: vehicle, payload: payloadData)
            resultMessage = "车辆已接受“\(command.title)”命令。"
        } catch { errorMessage = error.localizedDescription }
    }

    private static func pretty(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return raw }
        return String(data: formatted, encoding: .utf8) ?? raw
    }
}
