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
}

