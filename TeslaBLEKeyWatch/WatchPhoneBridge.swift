import Foundation
import Combine
import WatchConnectivity

final class WatchPhoneBridge: NSObject, ObservableObject, WCSessionDelegate {
    @Published var vehicleName = "Tesla"
    @Published var battery: Int?
    @Published var range: Double?
    @Published var locked: Bool?
    @Published var status = "正在连接 iPhone"

    override init() {
        super.init()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }

    func send(_ command: String) {
        guard WCSession.default.isReachable else { status = "请保持 iPhone 在附近"; return }
        status = "正在发送"
        WCSession.default.sendMessage(["command": command], replyHandler: { [weak self] reply in
            DispatchQueue.main.async { self?.status = (reply["accepted"] as? Bool) == true ? "已发送到 iPhone" : "操作未接收" }
        }, errorHandler: { [weak self] _ in DispatchQueue.main.async { self?.status = "发送失败" } })
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            self.vehicleName = applicationContext["name"] as? String ?? "Tesla"
            self.battery = applicationContext["battery"] as? Int
            self.range = applicationContext["range"] as? Double
            self.locked = applicationContext["locked"] as? Bool
            self.status = "iPhone 已连接"
        }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
}
