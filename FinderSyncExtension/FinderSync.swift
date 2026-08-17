import Cocoa
import FinderSync

/// This class is instantiated by Finder itself (out-of-process) once the
/// extension is enabled in System Settings > General > Login Items &
/// Extensions > Finder Extensions. It watches the user's Desktop folder
/// and adds a contextual-menu item whenever they right-click its
/// background (or an item inside it).
class FinderSync: FIFinderSync {

    override init() {
        super.init()
        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            // Extremely unlikely, but a force-unwrap here would crash the
            // Finder extension host process rather than just this app.
            assertionFailure("Could not resolve the user's Desktop directory")
            return
        }
        FIFinderSyncController.default().directoryURLs = [desktop]
    }

    // We don't need any badge icons — this extension exists purely to
    // add a menu item, not to decorate files.
    override func beginObservingDirectory(at url: URL) {}
    override func endObservingDirectory(at url: URL) {}

    override var toolbarItemName: String { "Display Settings" }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")

        // .contextualMenuForContainer fires for a right-click on empty
        // desktop space — exactly the "right click on the desktop" case.
        // .contextualMenuForItems would fire for right-clicking a file/icon;
        // we skip that so the item only shows on background clicks, like
        // Windows' "Display settings" entry.
        guard menuKind == .contextualMenuForContainer else { return menu }

        let item = NSMenuItem(title: "Display Settings", action: #selector(openDisplaySettings(_:)), keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc func openDisplaySettings(_ sender: AnyObject) {
        // Launch (or bring to front) the main app via its custom URL scheme.
        // Using a URL scheme keeps the extension decoupled from the app's
        // exact bundle path and works whether or not the app is running.
        guard let url = URL(string: "displaysettings://open") else {
            NSLog("Display Settings Finder extension: could not construct app URL")
            return
        }
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
            if app == nil {
                NSLog("Display Settings Finder extension: could not open displaysettings://open (\(error?.localizedDescription ?? "unknown error"))")
            }
        }
    }
}
