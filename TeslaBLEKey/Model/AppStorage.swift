import Foundation
import CryptoKit

enum AppStorageKeys {
    static let pairedVIN = "pairedVIN"
    static let paired = "paired"
}

enum VINValidator {
    static func normalized(_ input: String) -> String {
        input.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    static func isValid(_ vin: String) -> Bool {
        vin.count == 17 && !vin.contains(where: { "IOQ".contains($0) })
    }

    static func bluetoothName(for vin: String) -> String? {
        let normalizedVIN = normalized(vin)
        guard isValid(normalizedVIN) else { return nil }
        let digest = Insecure.SHA1.hash(data: Data(normalizedVIN.utf8))
        let identifier = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "S\(identifier)C"
    }
}
