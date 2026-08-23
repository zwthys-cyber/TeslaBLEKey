import XCTest
@testable import TeslaBLEKey

final class V21ModelTests: XCTestCase {
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
