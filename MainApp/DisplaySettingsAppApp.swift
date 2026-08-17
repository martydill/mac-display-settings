import SwiftUI

@main
struct DisplaySettingsAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var displayManager = DisplayManager()
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasSeenOnboarding")

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(displayManager)
                .frame(minWidth: 900, minHeight: 620)
                .onOpenURL { url in
                    // Fired when the Finder extension launches us via
                    // the "displaysettings://" custom URL scheme.
                    handleIncomingURL(url)
                }
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView {
                        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                        showOnboarding = false
                    }
                }
                .onAppear {
                    // The revert-safety countdown (see DisplayManager) lives
                    // in this process as a Timer. If the app quits while a
                    // change is still unconfirmed, the timer dies with it
                    // and the change silently never reverts. AppDelegate
                    // needs this reference so it can revert on the way out.
                    appDelegate.displayManager = displayManager
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {} // single-window utility app
        }
    }

    private func handleIncomingURL(_ url: URL) {
        // displaysettings://open  -> just bring to front (default behavior)
        // displaysettings://open?display=<id> -> could preselect a display later
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

/// Handles being launched/activated by the Finder Sync extension and
/// makes sure only one window is ever shown (utility-app behavior).
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var displayManager: DisplayManager?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    // This is a single-purpose utility window, not a document-based app —
    // closing the window should feel like quitting, not leaving a
    // windowless app lingering in the Dock.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // Safety net: never let the process disappear while a resolution or
    // on a display setting they never actually agreed to keep, with
    // nothing left running to revert it. Reverting on quit (rather than
    // blocking quit) matches the spirit of "unconfirmed = don't keep it."
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let manager = displayManager, manager.pendingChange != nil else {
            return .terminateNow
        }
        manager.revertPendingChange()
        return .terminateNow
    }
}
