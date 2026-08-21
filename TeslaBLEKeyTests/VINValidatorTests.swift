import XCTest
@testable import TeslaBLEKey

final class VINValidatorTests: XCTestCase {
    func testNormalizesVIN() {
        XCTAssertEqual(VINValidator.normalized(" 5yj3e1ea7jf000001 "), "5YJ3E1EA7JF000001")
    }

    func testValidVIN() {
        XCTAssertTrue(VINValidator.isValid("5YJ3E1EA7JF000001"))
        XCTAssertFalse(VINValidator.isValid("5YJ3E1EA7JF00000"))
        XCTAssertFalse(VINValidator.isValid("5YJ3E1EA7IF000001"))
    }

    func testBluetoothAdvertisementName() {
        XCTAssertEqual(
            VINValidator.bluetoothName(for: "5YJS0000000000000"),
            "S1a87a5a75f3df858C"
        )
    }

    func testTeslaAdvertisementNameValidation() {
        XCTAssertTrue(NearbyTeslaScanner.isTeslaAdvertisementName("S1a87a5a75f3df858C"))
        XCTAssertFalse(NearbyTeslaScanner.isTeslaAdvertisementName("Tesla Model 3"))
    }
}
