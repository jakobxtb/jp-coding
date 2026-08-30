import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Paths.ensure()
        Backend.writeProfile()
        // Proxy im Hintergrund hochfahren, blockiert den Start nicht.
        Task.detached { _ = await Backend.ensureProxy(wait: 40) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

@main
struct JPCodingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup("JP Coding") {
            ContentView()
                .frame(minWidth: 1040, minHeight: 660)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1360, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .help) {
                Link("JP Coding auf GitHub",
                     destination: URL(string: "https://github.com/jakobxtb/jp-coding")!)
            }
        }
    }
}
