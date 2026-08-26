import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity

final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()
    private var commandHandler: ((String, @escaping (Bool) -> Void) -> Void)?

    func activate(commandHandler: @escaping (String, @escaping (Bool) -> Void) -> Void) {
        self.commandHandler = commandHandler
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publish(name: String, battery: Int?, range: Double?, locked: Bool?) {
        guard WCSession.default.activationState == .activated else { return }
        var state: [String: Any] = ["name": name]
        if let battery { state["battery"] = battery }
        if let range { state["range"] = range }
        if let locked { state["locked"] = locked }
        try? WCSession.default.updateApplicationContext(state)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        guard let command = message["command"] as? String else { replyHandler(["accepted": false]); return }
        guard let commandHandler else { replyHandler(["accepted": false]); return }
        commandHandler(command) { accepted in replyHandler(["accepted": accepted]) }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
#endif
