@preconcurrency import CoreBluetooth
import Foundation
import Observation

struct NearbyTesla: Identifiable, Equatable {
    let id: UUID
    let peripheralName: String
    let rssi: Int
    let txPower: Int?
    let lastSeen: Date
    let modelName: String?

    var signalLabel: String {
        switch rssi {
        case (-55)...: "很近"
        case (-70) ..< (-55): "附近"
        default: "较远"
        }
    }

    var shortIdentifier: String {
        String(peripheralName.dropLast().suffix(4)).uppercased()
    }

    var signalLevel: Int {
        switch rssi {
        case (-55)...: 3
        case (-70) ..< (-55): 2
        default: 1
        }
    }

    var estimatedDistance: Double {
        let calibratedPower = txPower ?? -59
        let meters = pow(10, Double(calibratedPower - rssi) / 22.0)
        return min(max(meters, 0.05), 99)
    }

    var distanceLabel: String {
        switch estimatedDistance {
        case ..<1: "1 米内"
        case ..<10: "约 \(max(Int(estimatedDistance.rounded()), 1)) 米"
        case ..<30: "约 \(Int((estimatedDistance / 5).rounded()) * 5) 米"
        default: "约 \(Int((estimatedDistance / 10).rounded()) * 10) 米"
        }
    }

    static func isNearer(_ lhs: NearbyTesla, than rhs: NearbyTesla) -> Bool {
        if abs(lhs.estimatedDistance - rhs.estimatedDistance) > 0.001 {
            return lhs.estimatedDistance < rhs.estimatedDistance
        }
        if lhs.rssi != rhs.rssi {
            return lhs.rssi > rhs.rssi
        }
        return lhs.peripheralName.localizedStandardCompare(rhs.peripheralName) == .orderedAscending
    }
}

@MainActor
@Observable
final class NearbyTeslaScanner: NSObject, @preconcurrency CBCentralManagerDelegate {
    struct RSSISample: Equatable {
        let value: Int
        let date: Date
    }

    static let vehicleService = CBUUID(string: "00000211-B2D1-43F0-9B88-960CEBF8B91E")

    private var central: CBCentralManager?
    private var vehiclesByID: [UUID: NearbyTesla] = [:]
    private var nearbyPeripheralLastSeen: [UUID: Date] = [:]
    private var recentRSSISamples: [UUID: [RSSISample]] = [:]
    private var primaryVehicleID: UUID?
    private var maintenanceTask: Task<Void, Never>?
    private var scanStartedAt: Date?
    private static let advertisementExpiry: TimeInterval = 6
    private static let sampleMaximumAge: TimeInterval = 4

    var vehicles: [NearbyTesla] = []
    var isScanning = false
    var nearbyDeviceCount = 0
    var scanTimedOut = false
    var bluetoothMessage: String?

    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else if central?.state == .poweredOn {
            beginScan()
        }
    }

    func stop() {
        maintenanceTask?.cancel()
        maintenanceTask = nil
        central?.stopScan()
        isScanning = false
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bluetoothMessage = nil
            beginScan()
        case .poweredOff:
            bluetoothMessage = "请打开 iPhone 蓝牙。"
            isScanning = false
        case .unauthorized:
            bluetoothMessage = "请在系统设置中允许本应用使用蓝牙。"
            isScanning = false
        case .unsupported:
            bluetoothMessage = "此设备不支持所需的低功耗蓝牙。"
            isScanning = false
        default:
            bluetoothMessage = "正在准备蓝牙…"
            isScanning = false
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard RSSI.intValue != 127 else { return }
        let now = Date()
        nearbyPeripheralLastSeen[peripheral.identifier] = now
        nearbyDeviceCount = nearbyPeripheralLastSeen.count

        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let advertisedTxPower = (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue
        let name = advertisedName ?? peripheral.name ?? "Tesla"

        // Tesla vehicle advertisements use S + 16 lowercase hex digits + C.
        // The broad foreground scan also sees normal Bluetooth devices, so strict
        // name validation prevents presenting unrelated peripherals as vehicles.
        guard Self.isTeslaAdvertisementName(name) else { return }

        let previous = vehiclesByID[peripheral.identifier]
        var samples = recentRSSISamples[peripheral.identifier] ?? []
        samples.append(RSSISample(value: RSSI.intValue, date: now))
        samples = Self.freshSamples(from: samples, now: now)
        recentRSSISamples[peripheral.identifier] = samples
        let smoothedRSSI = Self.stabilizedRSSI(samples: samples.map(\.value), previous: previous?.rssi)
        vehiclesByID[peripheral.identifier] = NearbyTesla(
            id: peripheral.identifier,
            peripheralName: name,
            rssi: smoothedRSSI,
            txPower: advertisedTxPower ?? previous?.txPower,
            lastSeen: now,
            modelName: UserDefaults.standard.string(forKey: AppStorageKeys.vehicleModelPrefix + name)
        )
        scanTimedOut = false
        publishVehicles()
    }

    static func isTeslaAdvertisementName(_ value: String) -> Bool {
        guard value.count == 18, value.first == "S", value.last == "C" else { return false }
        return value.dropFirst().dropLast().allSatisfy { $0.isHexDigit }
    }

    static func freshVehicles(
        from vehicles: [UUID: NearbyTesla],
        now: Date,
        maximumAge: TimeInterval = advertisementExpiry
    ) -> [UUID: NearbyTesla] {
        vehicles.filter { now.timeIntervalSince($0.value.lastSeen) <= maximumAge }
    }

    static func stabilizedRSSI(samples: [Int], previous: Int?) -> Int {
        guard !samples.isEmpty else { return previous ?? -100 }
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        guard let previous, samples.count >= 5 else { return median }
        let difference = median - previous
        if abs(difference) <= 1 { return previous }

        let alpha: Double
        if difference > 5 { alpha = 0.38 }
        else if difference < -5 { alpha = 0.14 }
        else { alpha = 0.18 }

        let blended = Int(
            (Double(previous) * (1 - alpha) + Double(median) * alpha).rounded()
        )
        return min(max(blended, previous - 3), previous + 6)
    }

    static func freshSamples(
        from samples: [RSSISample],
        now: Date,
        maximumAge: TimeInterval = sampleMaximumAge
    ) -> [RSSISample] {
        Array(samples.filter { now.timeIntervalSince($0.date) <= maximumAge }.suffix(7))
    }

    static func shouldReplacePrimary(current: NearbyTesla, challenger: NearbyTesla) -> Bool {
        let requiredGap = max(current.estimatedDistance * 0.20, 0.8)
        return challenger.estimatedDistance + requiredGap < current.estimatedDistance
    }

    static func stableOrder(
        vehicles: [NearbyTesla],
        primaryVehicleID: UUID?
    ) -> (vehicles: [NearbyTesla], primaryVehicleID: UUID?) {
        let distanceOrder = vehicles.sorted { NearbyTesla.isNearer($0, than: $1) }
        guard let nearest = distanceOrder.first else { return ([], nil) }
        guard let primaryVehicleID,
              let current = distanceOrder.first(where: { $0.id == primaryVehicleID }) else {
            return (distanceOrder, nearest.id)
        }

        let primary = nearest.id != current.id && shouldReplacePrimary(current: current, challenger: nearest)
            ? nearest : current
        return ([primary] + distanceOrder.filter { $0.id != primary.id }, primary.id)
    }

    private func beginScan() {
        maintenanceTask?.cancel()
        vehiclesByID.removeAll()
        nearbyPeripheralLastSeen.removeAll()
        recentRSSISamples.removeAll()
        primaryVehicleID = nil
        vehicles.removeAll()
        nearbyDeviceCount = 0
        scanTimedOut = false
        scanStartedAt = .now

        // Tesla's local name is reliable, but the service UUID is not present in
        // every advertisement frame seen by iOS. Scan broadly in the foreground
        // and apply the strict S + 16 hex + C validation in didDiscover.
        central?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                guard let self, self.isScanning else { return }
                let now = Date()
                self.vehiclesByID = Self.freshVehicles(from: self.vehiclesByID, now: now)
                self.recentRSSISamples = self.recentRSSISamples.reduce(into: [:]) { result, entry in
                    guard self.vehiclesByID[entry.key] != nil else { return }
                    let fresh = Self.freshSamples(from: entry.value, now: now)
                    if !fresh.isEmpty { result[entry.key] = fresh }
                }
                self.nearbyPeripheralLastSeen = self.nearbyPeripheralLastSeen.filter {
                    now.timeIntervalSince($0.value) <= Self.advertisementExpiry
                }
                self.publishVehicles()
                self.nearbyDeviceCount = self.nearbyPeripheralLastSeen.count
                self.scanTimedOut = self.vehicles.isEmpty
                    && now.timeIntervalSince(self.scanStartedAt ?? now) >= 15
            }
        }
    }

    private func publishVehicles() {
        let result = Self.stableOrder(
            vehicles: Array(vehiclesByID.values),
            primaryVehicleID: primaryVehicleID
        )
        vehicles = result.vehicles
        primaryVehicleID = result.primaryVehicleID
    }
}
