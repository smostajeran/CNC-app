import SwiftUI

@main
struct QuillApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Quill") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .commands {
            CommandGroup(after: .pasteboard) {
                Button("Paste Job") { model.pasteFromClipboard() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Button("Export Inkscape Template…") { model.exportInkscapeTemplate() }
            }
        }
        .handlesExternalEvents(matching: ["quill", "ta4host"])
    }
}
