import SwiftUI

@main
struct XiaoteWatchApp: App {
    @StateObject private var bridge = WatchPhoneBridge()
    var body: some Scene { WindowGroup { WatchControlView().environmentObject(bridge) } }
}
