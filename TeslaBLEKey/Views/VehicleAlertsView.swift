import SwiftUI

struct VehicleAlertsView: View {
    @Environment(VehicleController.self) private var vehicle
    @Environment(\.dismiss) private var dismiss
    @State private var preferences = VehicleAlertPreferences()
    @State private var authorizationDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Toggle("启用车辆提醒", isOn: $preferences.enabled)
                    .onChange(of: preferences.enabled) { _, enabled in
                        guard enabled else { persist(); return }
                        Task {
                            let allowed = await VehicleAlertManager.requestAuthorization()
                            if !allowed { preferences.enabled = false; authorizationDenied = true }
                            persist()
                        }
                    }
                Section("提醒项目") {
                    Toggle("低电量", isOn: $preferences.lowBattery)
                    if preferences.lowBattery {
                        Stepper("低于 \(preferences.lowBatteryThreshold)%", value: $preferences.lowBatteryThreshold, in: 5...50, step: 5)
                    }
                    Toggle("车门或车窗未关", isOn: $preferences.doorsAndWindows)
                    Toggle("充电停止或无电力", isOn: $preferences.chargingIssues)
                }.disabled(!preferences.enabled)
                Section { Text("提醒在 App 刷新到车辆真实状态或 iOS 恢复蓝牙会话时触发，不是云端全天候监控。") }
            }
            .navigationTitle("车辆提醒").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { persist(); dismiss() } } }
            .onAppear { preferences = vehicle.alertPreferences }
            .onChange(of: preferences) { _, _ in persist() }
            .alert("通知权限未开启", isPresented: $authorizationDenied) {
                Button("好", role: .cancel) {}
            } message: { Text("请在系统设置中允许“小特蓝牙钥匙”发送通知。") }
        }.preferredColorScheme(.dark)
    }

    private func persist() { vehicle.setAlertPreferences(preferences) }
}
