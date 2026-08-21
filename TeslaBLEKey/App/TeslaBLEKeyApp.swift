import SwiftUI

@main
struct TeslaBLEKeyApp: App {
    @State private var vehicle = VehicleController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vehicle)
        }
    }
}

