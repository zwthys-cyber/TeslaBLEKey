import XCTest
@testable import Xiaote

final class V21ModelTests: XCTestCase {
    func testFleetCommandCatalogIsCompleteAndUnique() {
        let commands = FleetCommandDefinition.all
        XCTAssertEqual(commands.count, 72)
        XCTAssertEqual(Set(commands.map(\.id)).count, commands.count)
        XCTAssertTrue(commands.allSatisfy { !$0.title.isEmpty && !$0.summary.isEmpty })
        XCTAssertTrue(commands.allSatisfy {
            guard let data = $0.payloadTemplate.data(using: .utf8) else { return false }
            return (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
        })
    }

    func testPassiveLifecycleCoalescesDuplicateRecovery() {
        var lifecycle = PassiveKeyLifecycle(enabled: true)
        let generation = lifecycle.beginConnection()
        XCTAssertTrue(lifecycle.markWaiting(for: generation))

        XCTAssertTrue(lifecycle.beginRecovery(for: generation))
        XCTAssertFalse(lifecycle.beginRecovery(for: generation))
        XCTAssertEqual(lifecycle.state, .restoring)
    }

    func testPassiveLifecycleRejectsStaleAsyncCompletion() {
        var lifecycle = PassiveKeyLifecycle(enabled: true)
        let staleGeneration = lifecycle.beginConnection()
        let currentGeneration = lifecycle.interrupt()

        XCTAssertFalse(lifecycle.markListening(for: staleGeneration))
        XCTAssertTrue(lifecycle.beginRecovery(for: currentGeneration))
        XCTAssertTrue(lifecycle.markEstablishingSession(for: currentGeneration))
        XCTAssertTrue(lifecycle.markListening(for: currentGeneration))
        XCTAssertEqual(lifecycle.state, .listening)
    }

    func testPassiveLifecycleInvalidationCancelsOwnership() {
        var lifecycle = PassiveKeyLifecycle(enabled: true)
        let oldGeneration = lifecycle.beginConnection()
        lifecycle.setEnabled(false)

        XCTAssertEqual(lifecycle.state, .disabled)
        XCTAssertFalse(lifecycle.owns(oldGeneration))
        XCTAssertFalse(lifecycle.beginRecovery(for: oldGeneration))
    }

    func testAlertPreferencesRoundTrip() throws {
        let value = VehicleAlertPreferences(enabled: true, lowBattery: true, lowBatteryThreshold: 15,
                                            doorsAndWindows: false, chargingIssues: true)
        let decoded = try JSONDecoder().decode(VehicleAlertPreferences.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded, value)
    }

    @MainActor
    func testDefaultAutomationScenesHaveActions() {
        let controller = VehicleController()
        XCTAssertTrue(controller.automationScenes.allSatisfy { !$0.name.isEmpty && !$0.actions.isEmpty })
    }
}
