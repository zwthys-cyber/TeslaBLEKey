import Foundation
import UserNotifications

struct VehicleAlertPreferences: Codable, Hashable {
    var enabled = false
    var lowBattery = true
    var lowBatteryThreshold = 20
    var doorsAndWindows = true
    var chargingIssues = true
}

enum VehicleAlertManager {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) == true
    }

    static func evaluate(vehicleID: String, name: String, preferences: VehicleAlertPreferences,
                         battery: Int?, openDoors: Int?, openWindows: Int?, chargingStatus: String?) async {
        guard preferences.enabled else { return }
        if preferences.lowBattery, let battery {
            await updateCondition(battery <= preferences.lowBatteryThreshold, key: "lowBattery.\(vehicleID)", title: "\(name) 电量偏低", body: "当前电量 \(battery)%")
        }
        if preferences.doorsAndWindows {
            if let openDoors { await updateCondition(openDoors > 0, key: "doors.\(vehicleID)", title: "\(name) 车门未关", body: "检测到 \(openDoors) 个车门开启") }
            if let openWindows { await updateCondition(openWindows > 0, key: "windows.\(vehicleID)", title: "\(name) 车窗未关", body: "检测到 \(openWindows) 个车窗开启") }
        }
        if preferences.chargingIssues, let chargingStatus {
            let issue = chargingStatus.contains("无电力") || chargingStatus.contains("停止")
            await updateCondition(issue, key: "charging.\(vehicleID)", title: "\(name) 充电状态异常", body: chargingStatus)
        }
    }

    private static func updateCondition(_ active: Bool, key: String, title: String, body: String) async {
        let defaultsKey = "vehicleAlert.sent.\(key)"
        guard active else { UserDefaults.standard.removeObject(forKey: defaultsKey); return }
        guard !UserDefaults.standard.bool(forKey: defaultsKey) else { return }
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
        UserDefaults.standard.set(true, forKey: defaultsKey)
    }
}
