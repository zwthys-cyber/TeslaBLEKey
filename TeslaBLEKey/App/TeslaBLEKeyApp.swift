import SwiftUI

@main
struct TeslaBLEKeyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var vehicle = VehicleController()
    @State private var fleetAccount = FleetAccountController()

    init() {
        AppDiagnostics.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vehicle)
                .environment(fleetAccount)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await vehicle.refreshAfterReturningToForeground()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        vehicle.noteAppMovedToBackground()
                    }
                }
                .task {
                    WatchBridge.shared.activate { command, completion in
                        Task { @MainActor in
                            let sensitive = command == "unlock"
                            if vehicle.faceIDProtection == .all || (sensitive && vehicle.faceIDProtection == .sensitive) {
                                completion(false)
                                vehicle.presentUserError("此操作受 Face ID 保护，请在 iPhone 上执行。")
                                return
                            }
                            completion(true)
                            switch command {
                            case "lock": await vehicle.lock()
                            case "unlock": await vehicle.unlock()
                            case "climate": if !vehicle.isClimateOn { await vehicle.toggleClimate() }
                            case "flash": await vehicle.flashLights()
                            case "horn": await vehicle.honk()
                            default: break
                            }
                        }
                    }
                }
        }
    }
}
