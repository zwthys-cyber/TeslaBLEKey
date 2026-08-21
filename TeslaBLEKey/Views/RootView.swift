import SwiftUI

struct RootView: View {
    @Environment(VehicleController.self) private var vehicle

    var body: some View {
        @Bindable var vehicle = vehicle

        NavigationStack {
            Group {
                if vehicle.isPaired {
                    VehicleControlView()
                } else {
                    PairVehicleView()
                }
            }
            .alert("操作失败", isPresented: $vehicle.showingError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(vehicle.errorMessage)
            }
        }
    }
}
