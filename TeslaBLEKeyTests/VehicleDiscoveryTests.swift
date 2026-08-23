import XCTest
@testable import TeslaBLEKey

final class VehicleDiscoveryTests: XCTestCase {
    func testTeslaAdvertisementNameValidation() {
        XCTAssertTrue(NearbyTeslaScanner.isTeslaAdvertisementName("S1a87a5a75f3df858C"))
        XCTAssertFalse(NearbyTeslaScanner.isTeslaAdvertisementName("Tesla Model 3"))
        XCTAssertFalse(NearbyTeslaScanner.isTeslaAdvertisementName("S-not-hex-value-C"))
    }

    func testVehicleSignalPresentation() {
        let close = NearbyTesla(id: UUID(), peripheralName: "S1a87a5a75f3df858C", rssi: -48, txPower: -59, lastSeen: .now, modelName: nil)
        let nearby = NearbyTesla(id: UUID(), peripheralName: "S1a87a5a75f3df858C", rssi: -63, txPower: -59, lastSeen: .now, modelName: nil)
        let far = NearbyTesla(id: UUID(), peripheralName: "S1a87a5a75f3df858C", rssi: -82, txPower: -59, lastSeen: .now, modelName: nil)

        XCTAssertEqual(close.signalLabel, "很近")
        XCTAssertEqual(nearby.signalLabel, "附近")
        XCTAssertEqual(far.signalLabel, "较远")
        XCTAssertEqual(close.shortIdentifier, "F858")
        XCTAssertLessThan(close.estimatedDistance, nearby.estimatedDistance)
        XCTAssertLessThan(nearby.estimatedDistance, far.estimatedDistance)
        XCTAssertEqual(VehicleController.modelName(fromVIN: "LRWYGCEK1NC000000"), "Model Y")
        XCTAssertEqual(VehicleController.modelName(fromVIN: "5YJ3E1EA7KF000000"), "Model 3")
    }

    func testLegacyVCSECWireVectors() {
        let keyID = Data([1, 2, 3, 4])
        let request = LegacyVCSECClient.enumField(1, 4)
            + LegacyVCSECClient.messageField(2, LegacyVCSECClient.bytesField(1, keyID))
        let encoded = LegacyVCSECClient.toVCSECUnsigned(LegacyVCSECClient.messageField(1, request))

        XCTAssertEqual(encoded.map { String(format: "%02x", $0) }.joined(), "120c0a0a080412060a0401020304")
        XCTAssertEqual(LegacyVCSECClient.messageField(3, Data()), Data([0x1a, 0x00]))
        XCTAssertEqual(LegacyVCSECClient.enumField(2, 1), Data([0x10, 0x01]))

        let vehicleInfo = LegacyVCSECClient.toVCSECUnsigned(
            LegacyVCSECClient.messageField(1, LegacyVCSECClient.enumField(1, 7))
        )
        let universal = LegacyVCSECClient.universalVCSECMessage(vehicleInfo)
        XCTAssertEqual(universal.map { String(format: "%02x", $0) }.joined(), "32020802520612040a020807")
        XCTAssertEqual(LegacyVCSECClient.vcsecPayload(from: universal), vehicleInfo)
        XCTAssertEqual(LegacyVCSECClient.vcsecPayload(from: vehicleInfo), vehicleInfo)
    }
}
