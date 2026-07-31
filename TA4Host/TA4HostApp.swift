import SwiftUI

@main
struct TA4HostApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("TA4Host") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
