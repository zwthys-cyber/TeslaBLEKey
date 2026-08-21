import Foundation

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
}

