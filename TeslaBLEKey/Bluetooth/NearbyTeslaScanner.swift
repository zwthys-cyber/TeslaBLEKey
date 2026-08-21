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
        case -55...: "很近"
        case -70 ..< -55: "附近"
        default: "较远"
        }
    }
}

@MainActor
@Observable
final class NearbyTeslaScanner: NSObject, CBCentralManagerDelegate {
    static let vehicleService = CBUUID(string: "00000211-B2D1-43F0-9B88-960CEBF8B91E")

    private var central: CBCentralManager?
    private var vehiclesByID: [UUID: NearbyTesla] = [:]

    var vehicles: [NearbyTesla] = []
    var isScanning = false
    var bluetoothMessage: String?

    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else if central?.state == .poweredOn {
            beginScan()
        }
    }

    func stop() {
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
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "Tesla"

        // Tesla vehicle advertisements use S + 16 lowercase hex digits + C.
        // Filtering the service UUID already excludes normal Bluetooth devices;
        // validating the name prevents presenting unrelated service collisions.
        guard Self.isTeslaAdvertisementName(name) else { return }

        vehiclesByID[peripheral.identifier] = NearbyTesla(
            id: peripheral.identifier,
            peripheralName: name,
            rssi: RSSI.intValue,
            lastSeen: .now
        )
        vehicles = vehiclesByID.values.sorted { $0.rssi > $1.rssi }
    }

    static func isTeslaAdvertisementName(_ value: String) -> Bool {
        guard value.count == 18, value.first == "S", value.last == "C" else { return false }
        return value.dropFirst().dropLast().allSatisfy { $0.isHexDigit }
    }

    private func beginScan() {
        vehiclesByID.removeAll()
        vehicles.removeAll()
        central?.scanForPeripherals(
            withServices: [Self.vehicleService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
    }
}

