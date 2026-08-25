import XCTest
@testable import TeslaBLEKey

final class V21ModelTests: XCTestCase {
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
