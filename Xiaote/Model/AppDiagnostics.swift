import Foundation
import MetricKit

/// Keeps privacy-safe, local evidence for terminations that do not appear in
/// Settings > Privacy & Security > Analytics Data (common with watchdog/jetsam
/// and sideloaded builds). No VIN, location, media, or command payloads enter
/// this log.
final class AppDiagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = AppDiagnostics()
    private let defaults = UserDefaults.standard
    private let queue = DispatchQueue(label: "com.local.teslablekey.diagnostics")
    private let eventsKey = "localDiagnosticEvents"
    private let payloadKey = "latestMetricKitDiagnostic"

    private override init() { super.init() }

    func start() {
        MXMetricManager.shared.add(self)
        record("app.launch")
    }

    func record(_ event: String) {
        queue.async {
            var events = self.defaults.stringArray(forKey: self.eventsKey) ?? []
            events.append("\(ISO8601DateFormatter().string(from: .now))  \(event)")
            self.defaults.set(Array(events.suffix(40)), forKey: self.eventsKey)
        }
    }

    var recentEvents: [String] {
        defaults.stringArray(forKey: eventsKey) ?? []
    }

    var latestMetricKitDiagnostic: String? {
        defaults.string(forKey: payloadKey)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard let payload = payloads.last,
              let text = String(data: payload.jsonRepresentation(), encoding: .utf8) else { return }
        defaults.set(text, forKey: payloadKey)
        record("metrickit.diagnostic.received")
    }
}
