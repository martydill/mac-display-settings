import AppKit
import FinderSync

/// Wraps FIFinderSyncController's built-in "show me where to enable this"
/// API. This is the same call Apple's own Finder Sync sample code uses —
/// it opens System Settings directly to the Finder Extensions pane rather
/// than making users hunt for it themselves, which is by far the most
/// common reason people never discover this kind of feature.
///
/// NOTE: for this to link, add FinderSync.framework to the *main app's*
/// "Frameworks and Libraries" as well (not just the extension target) —
/// see README.md.
enum FinderExtensionHelper {
    static func openExtensionPreferences() {
        FIFinderSyncController.showExtensionManagementInterface()
    }
}
