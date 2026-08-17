import SwiftUI

/// Shown once on first launch. The single biggest real-world reason a
/// Finder Sync extension goes unused is that nobody discovers the
/// System Settings toggle for it — this walks the user straight there.
struct OnboardingView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "display")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Welcome to Display Settings")
                .font(.title2.bold())

            Text("To get a “Display Settings” item in your Desktop's right-click menu, turn on this app's Finder extension.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            Button("Open Extension Settings…") {
                FinderExtensionHelper.openExtensionPreferences()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

            Button("I'll do this later") { onDismiss() }
                .buttonStyle(.link)
        }
        .padding(40)
        .frame(width: 440)
    }
}
