import SwiftUI

struct WatchControlView: View {
    @EnvironmentObject private var bridge: WatchPhoneBridge
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(bridge.vehicleName).font(.headline).lineLimit(1)
                HStack {
                    if let battery = bridge.battery { Label("\(battery)%", systemImage: "battery.75percent") }
                    if let range = bridge.range { Text("\(Int(range)) km") }
                }.font(.caption).monospacedDigit()
                Button { bridge.send(bridge.locked == true ? "unlock" : "lock") } label: {
                    Label(bridge.locked == true ? "解锁" : "上锁", systemImage: bridge.locked == true ? "lock.open.fill" : "lock.fill")
                }.tint(.white).foregroundStyle(.black)
                HStack {
                    Button { bridge.send("climate") } label: { Image(systemName: "fan.fill") }
                    Button { bridge.send("flash") } label: { Image(systemName: "light.beacon.max") }
                    Button { bridge.send("horn") } label: { Image(systemName: "speaker.wave.2.fill") }
                }
                Text(bridge.status).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }
}
