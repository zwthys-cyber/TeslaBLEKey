import SwiftUI

@main
struct TeslaBLEKeyWatchApp: App {
    @StateObject private var bridge = WatchPhoneBridge()
    var body: some Scene { WindowGroup { WatchControlView().environmentObject(bridge) } }
}
