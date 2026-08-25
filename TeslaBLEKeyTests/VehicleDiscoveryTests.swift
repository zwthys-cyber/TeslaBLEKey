import XCTest
@testable import TeslaBLEKey

@MainActor
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
        XCTAssertEqual(VehicleController.beaconName(forVIN: "5YJS0000000000000"), "S1a87a5a75f3df858C")
    }

    func testVehiclesSortByEstimatedDistanceThenSignalStrength() {
        let farther = NearbyTesla(id: UUID(), peripheralName: "S0000000000000002C", rssi: -60, txPower: -45, lastSeen: .now, modelName: nil)
        let closer = NearbyTesla(id: UUID(), peripheralName: "S0000000000000001C", rssi: -60, txPower: -70, lastSeen: .now, modelName: nil)

        let sorted = [farther, closer].sorted { NearbyTesla.isNearer($0, than: $1) }

        XCTAssertEqual(sorted.first?.id, closer.id)
    }

    func testScannerDropsVehiclesWhoseAdvertisementsExpired() {
        let now = Date()
        let fresh = NearbyTesla(id: UUID(), peripheralName: "S0000000000000001C", rssi: -50, txPower: nil, lastSeen: now.addingTimeInterval(-2), modelName: nil)
        let stale = NearbyTesla(id: UUID(), peripheralName: "S0000000000000002C", rssi: -50, txPower: nil, lastSeen: now.addingTimeInterval(-7), modelName: nil)

        let result = NearbyTeslaScanner.freshVehicles(from: [fresh.id: fresh, stale.id: stale], now: now)

        XCTAssertEqual(Set(result.keys), [fresh.id])
    }

    func testRSSIFilterRejectsSingleSampleSpike() {
        XCTAssertEqual(
            NearbyTeslaScanner.stabilizedRSSI(samples: [-61, -60, -59, -28, -60], previous: -60),
            -60
        )
        XCTAssertEqual(
            NearbyTeslaScanner.stabilizedRSSI(samples: [-49, -48, -47, -48, -49], previous: -70),
            -67
        )
    }

    func testDistancePresentationAvoidsFalsePrecision() {
        let veryClose = NearbyTesla(id: UUID(), peripheralName: "S0000000000000001C", rssi: -48, txPower: -59, lastSeen: .now, modelName: nil)
        let nearby = NearbyTesla(id: UUID(), peripheralName: "S0000000000000002C", rssi: -66, txPower: -59, lastSeen: .now, modelName: nil)

        XCTAssertEqual(veryClose.distanceLabel, "1 米内")
        XCTAssertFalse(nearby.distanceLabel.contains("."))
    }

    func testLegacyVCSECWireVectors() {
        let keyID = Data([1, 2, 3, 4])
        let request = LegacyVCSECClient.enumField(1, 3)
            + LegacyVCSECClient.messageField(2, LegacyVCSECClient.bytesField(1, keyID))
        let encoded = LegacyVCSECClient.toVCSECUnsigned(LegacyVCSECClient.messageField(1, request))

        XCTAssertEqual(encoded.map { String(format: "%02x", $0) }.joined(), "120c0a0a080312060a0401020304")
        XCTAssertEqual(LegacyVCSECClient.messageField(3, Data()), Data([0x1a, 0x00]))
        XCTAssertEqual(LegacyVCSECClient.enumField(2, 1), Data([0x10, 0x01]))

        let getStatus = LegacyVCSECClient.toVCSECUnsigned(LegacyVCSECClient.messageField(1, Data()))
        XCTAssertEqual(getStatus, Data([0x12, 0x02, 0x0a, 0x00]))
        let closeRearTrunk = LegacyVCSECClient.messageField(
            4,
            LegacyVCSECClient.enumField(5, 4)
        )
        XCTAssertEqual(closeRearTrunk, Data([0x22, 0x02, 0x28, 0x04]))

        XCTAssertEqual(LegacyVCSECClient.vcsecPayload(from: encoded), encoded)
    }

    func testTeslaScheduleDayMaskUsesSundayAsBitZero() {
        XCTAssertEqual(TeslaScheduleDayMask.mask(for: [0]), 2)
        XCTAssertEqual(TeslaScheduleDayMask.mask(for: [6]), 1)
        XCTAssertEqual(TeslaScheduleDayMask.mask(for: Set(0...6)), 127)
        XCTAssertEqual(TeslaScheduleDayMask.labels(for: 3), ["周一", "周日"])
        XCTAssertEqual(TeslaScheduleDayMask.labels(for: 62), ["周一", "周二", "周三", "周四", "周五"])
    }
}
