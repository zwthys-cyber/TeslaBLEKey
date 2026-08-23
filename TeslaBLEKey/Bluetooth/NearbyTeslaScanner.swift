@preconcurrency import CoreBluetooth
import Foundation
import Observation

struct NearbyTesla: Identifiable, Equatable {
    let id: UUID
    let peripheralName: String
    let rssi: Int
    let lastSeen: Date

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
}

@MainActor
@Observable
final class NearbyTeslaScanner: NSObject, @preconcurrency CBCentralManagerDelegate {
    static let vehicleService = CBUUID(string: "00000211-B2D1-43F0-9B88-960CEBF8B91E")

    private var central: CBCentralManager?
    private var vehiclesByID: [UUID: NearbyTesla] = [:]
    private var nearbyPeripheralIDs: Set<UUID> = []
    private var timeoutTask: Task<Void, Never>?

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
        timeoutTask?.cancel()
        timeoutTask = nil
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
        nearbyPeripheralIDs.insert(peripheral.identifier)
        nearbyDeviceCount = nearbyPeripheralIDs.count

        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "Tesla"

        // Tesla vehicle advertisements use S + 16 lowercase hex digits + C.
        // The broad foreground scan also sees normal Bluetooth devices, so strict
        // name validation prevents presenting unrelated peripherals as vehicles.
        guard Self.isTeslaAdvertisementName(name) else { return }

        let previousRSSI = vehiclesByID[peripheral.identifier]?.rssi
        // BLE RSSI moves several dBm even when neither phone nor car moves. A
        // light moving average keeps the ordering and signal UI from flickering.
        let smoothedRSSI = previousRSSI.map { Int((Double($0) * 0.7) + (Double(RSSI.intValue) * 0.3)) }
            ?? RSSI.intValue
        vehiclesByID[peripheral.identifier] = NearbyTesla(
            id: peripheral.identifier,
            peripheralName: name,
            rssi: smoothedRSSI,
            lastSeen: .now
        )
        scanTimedOut = false
        timeoutTask?.cancel()
        vehicles = vehiclesByID.values.sorted { $0.rssi > $1.rssi }
    }

    static func isTeslaAdvertisementName(_ value: String) -> Bool {
        guard value.count == 18, value.first == "S", value.last == "C" else { return false }
        return value.dropFirst().dropLast().allSatisfy { $0.isHexDigit }
    }

    private func beginScan() {
        timeoutTask?.cancel()
        vehiclesByID.removeAll()
        nearbyPeripheralIDs.removeAll()
        vehicles.removeAll()
        nearbyDeviceCount = 0
        scanTimedOut = false

        // Tesla's local name is reliable, but the service UUID is not present in
        // every advertisement frame seen by iOS. Scan broadly in the foreground
        // and apply the strict S + 16 hex + C validation in didDiscover.
        central?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.vehicles.isEmpty, self.isScanning else { return }
            self.scanTimedOut = true
        }
    }
}
