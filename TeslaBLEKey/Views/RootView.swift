import SwiftUI

struct RootView: View {
    @Environment(VehicleController.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var vehicle = vehicle

        NavigationStack {
            Group {
                if vehicle.isPaired {
                    VehicleControlView()
                        .transition(.opacity)
                } else {
                    PairVehicleView()
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? AppMotion.reduced : AppMotion.state, value: vehicle.isPaired)
            .alert("操作失败", isPresented: $vehicle.showingError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(vehicle.errorMessage)
            }
        }
    }
}
