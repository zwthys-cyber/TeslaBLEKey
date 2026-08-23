import XCTest
@testable import TeslaBLEKey

final class VehicleDiscoveryTests: XCTestCase {
    func testTeslaAdvertisementNameValidation() {
        XCTAssertTrue(NearbyTeslaScanner.isTeslaAdvertisementName("S1a87a5a75f3df858C"))
        XCTAssertFalse(NearbyTeslaScanner.isTeslaAdvertisementName("Tesla Model 3"))
        XCTAssertFalse(NearbyTeslaScanner.isTeslaAdvertisementName("S-not-hex-value-C"))
    }

    func testVehicleSignalPresentation() {
        let close = NearbyTesla(id: UUID(), peripheralName: "S1a87a5a75f3df858C", rssi: -48, lastSeen: .now)
        let nearby = NearbyTesla(id: UUID(), peripheralName: "S1a87a5a75f3df858C", rssi: -63, lastSeen: .now)
        let far = NearbyTesla(id: UUID(), peripheralName: "S1a87a5a75f3df858C", rssi: -82, lastSeen: .now)

        XCTAssertEqual(close.signalLabel, "很近")
        XCTAssertEqual(nearby.signalLabel, "附近")
        XCTAssertEqual(far.signalLabel, "较远")
        XCTAssertEqual(close.shortIdentifier, "F858")
    }
}
