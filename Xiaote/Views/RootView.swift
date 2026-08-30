import SwiftUI

struct RootView: View {
    @Environment(VehicleController.self) private var vehicle
    @Environment(FleetAccountController.self) private var fleetAccount
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var vehicle = vehicle

        NavigationStack {
            Group {
                if vehicle.isPaired {
                    VehicleControlView()
                        .transition(.opacity)
                } else if fleetAccount.isSignedIn {
                    FleetHomeView()
                        .transition(.opacity)
                } else {
                    PairVehicleView()
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? AppMotion.reduced : AppMotion.state, value: vehicle.isPaired)
            .animation(reduceMotion ? AppMotion.reduced : AppMotion.state, value: fleetAccount.isSignedIn)
            .alert("操作失败", isPresented: $vehicle.showingError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(vehicle.errorMessage)
            }
            .fullScreenCover(isPresented: $vehicle.showingVehicleIdentity) {
                VehicleIdentityView()
                    .environment(vehicle)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}
