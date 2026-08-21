import XCTest
@testable import TeslaBLEKey

final class VehicleDiscoveryTests: XCTestCase {
    func testTeslaAdvertisementNameValidation() {
        XCTAssertTrue(NearbyTeslaScanner.isTeslaAdvertisementName("S1a87a5a75f3df858C"))
        XCTAssertFalse(NearbyTeslaScanner.isTeslaAdvertisementName("Tesla Model 3"))
        XCTAssertFalse(NearbyTeslaScanner.isTeslaAdvertisementName("S-not-hex-value-C"))
    }
}
