import SwiftUI
import VisionKit

struct VINScannerView: UIViewControllerRepresentable {
    let onRecognized: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onRecognized: onRecognized) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text(textContentType: nil)],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onRecognized: (String) -> Void
        private var delivered = false

        init(onRecognized: @escaping (String) -> Void) { self.onRecognized = onRecognized }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                guard case let .text(text) = item else { continue }
                let compact = text.transcript.uppercased().filter { $0.isLetter || $0.isNumber }
                guard let vin = Self.vin(in: compact) else { continue }
                delivered = true
                dataScanner.stopScanning()
                onRecognized(vin)
                return
            }
        }

        private static func vin(in text: String) -> String? {
            guard text.count >= 17 else { return nil }
            for index in 0...(text.count - 17) {
                let start = text.index(text.startIndex, offsetBy: index)
                let end = text.index(start, offsetBy: 17)
                let candidate = String(text[start..<end])
                if !candidate.contains(where: { "IOQ".contains($0) }) { return candidate }
            }
            return nil
        }
    }
}
