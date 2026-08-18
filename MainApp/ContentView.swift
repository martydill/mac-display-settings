import SwiftUI

struct ContentView: View {
    @EnvironmentObject var manager: DisplayManager

    var body: some View {
        ZStack(alignment: .bottom) {
            HSplitView {
                sidebar
                detailPane
            }
            if let change = manager.pendingChange {
                RevertConfirmationBar(change: change)
                    .environmentObject(manager)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: manager.pendingChange?.id)
        .alert("Display Settings", isPresented: errorBinding) {
            Button("OK", role: .cancel) { manager.lastError = nil }
        } message: {
            Text(manager.lastError ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { manager.lastError != nil }, set: { if !$0 { manager.lastError = nil } })
    }

    private var sidebar: some View {
        List {
            Label("Display", systemImage: "display")
                .font(.headline)
            Section {
                Button {
                    FinderExtensionHelper.openExtensionPreferences()
                } label: {
                    Label("Enable Desktop Menu…", systemImage: "cursorarrow.click.2")
                }
                .buttonStyle(.link)
                .help("Opens System Settings so you can enable the Display Settings right-click menu item on your Desktop.")
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180, idealWidth: 200)
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Display")
                    .font(.system(size: 28, weight: .bold))

                if manager.displays.isEmpty {
                    emptyState
                } else {
                    arrangementSection

                    if let display = manager.selectedDisplay {
                        Divider()
                        selectedDisplayHeader(display)
                        scaleSection(display)
                        refreshRateSection(display)
                        displayModeSection
                        advancedDisplaySection(display)
                    }
                }
            }
            .padding(28)
        }
        .frame(minWidth: 650)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("No displays detected", systemImage: "display.trianglebadge.exclamationmark")
                .font(.title3.bold())
            Text("This can happen right after a monitor is connected or disconnected. Try Detect, or check your cable/dock connection.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Detect") { manager.reload() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 40)
    }

    private var arrangementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Rearrange your displays")
                    .font(.title3.bold())
                Spacer()
                Button("Identify") { manager.identifyDisplays() }
                Button("Detect") { manager.reload() }
                    .disabled(manager.hasPendingChange)
            }
            Text(manager.hasPendingChange
                 ? "Finish or revert the pending display change before rearranging displays."
                 : "Select a display below to change its settings. Drag displays to match their physical arrangement. The main display stays at the origin; make another display main first if you want to move it.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ArrangementCanvas()
                .environmentObject(manager)
                .frame(height: 260)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .underPageBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.25)))
                .opacity(manager.hasPendingChange ? 0.6 : 1)
        }
    }

    private func selectedDisplayHeader(_ display: DisplayInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(display.name).font(.title3.bold())
                Text(display.isMain ? "Main display" : (display.isMirrored ? "Mirrored display" : "Extended display"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !display.isMain {
                Button("Make this my main display") { manager.makeMain(display) }
                    .disabled(manager.hasPendingChange)
            }
        }
    }

    private func scaleSection(_ display: DisplayInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scale").font(.headline)

            Picker("", selection: currentResolutionBinding(display)) {
                ForEach(display.resolutionOptions) { option in
                    Text(scaleLabel(option, for: display))
                        .tag(Optional(option))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 380, alignment: .leading)
            .accessibilityLabel("Display scale and effective resolution")
            .disabled(manager.hasPendingChange || (display.isMirrored && !display.isMain))

            HStack(spacing: 6) {
                Text("Current:")
                Text(display.effectiveResolutionLabel).fontWeight(.medium)
                Text("•")
                Text(display.physicalResolutionLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let recommended = manager.recommendedResolution(for: display) {
                Text("Recommended: \(recommended.label) (based on macOS's current logical display size)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("macOS does not expose a public recommended-mode flag; available modes are shown using public Core Graphics APIs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if display.isMirrored && !display.isMain {
                Text("Scale is controlled by the main display while displays are mirrored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func scaleLabel(_ option: DisplayResolutionOption, for display: DisplayInfo) -> String {
        var label = option.label
        if let recommended = manager.recommendedResolution(for: display), recommended.id == option.id {
            label += "  — Recommended"
        }
        return label
    }

    private func currentResolutionBinding(_ display: DisplayInfo) -> Binding<DisplayResolutionOption?> {
        Binding(
            get: { display.currentResolutionOption },
            set: { newValue in
                guard let newValue else { return }
                manager.setResolution(newValue, for: display)
            }
        )
    }

    private func refreshRateSection(_ display: DisplayInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Refresh rate").font(.headline)

            Picker("", selection: currentRefreshRateBinding(display)) {
                ForEach(display.refreshRateOptions) { option in
                    Text(option.label).tag(Optional(option))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 240, alignment: .leading)
            .accessibilityLabel("Refresh rate")
            .disabled(manager.hasPendingChange || (display.isMirrored && !display.isMain))

            Text("Current refresh rate: \(display.currentRefreshRateLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if display.refreshRateOptions.isEmpty {
                Text("This display does not expose selectable refresh rates through the public display-mode API.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func currentRefreshRateBinding(_ display: DisplayInfo) -> Binding<DisplayRefreshRateOption?> {
        Binding(
            get: {
                guard let current = display.currentMode else { return nil }
                return display.refreshRateOptions.first { abs($0.rate - current.refreshRate) < 0.01 }
            },
            set: { newValue in
                guard let newValue else { return }
                manager.setRefreshRate(newValue, for: display)
            }
        )
    }

    private var displayModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display mode").font(.headline)
            Picker("", selection: Binding(
                get: { manager.multiDisplayMode },
                set: { manager.setMultiDisplayMode($0) }
            )) {
                ForEach(DisplayManager.MultiDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 300, alignment: .leading)
            .accessibilityLabel("Display mode")
            .disabled(manager.hasPendingChange || manager.displays.count < 2)

            Text("Extend keeps displays independent. Duplicate mirrors the displays using the main display as the source.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Turning individual displays completely off is not exposed by the public macOS display-configuration APIs, so this app does not emulate Windows' 'show only on 1/2' modes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func advancedDisplaySection(_ display: DisplayInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Advanced display").font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
                GridRow { Text("Display").foregroundStyle(.secondary); Text(display.name) }
                GridRow { Text("Connection").foregroundStyle(.secondary); Text(display.connectionDescription) }
                GridRow { Text("Effective resolution").foregroundStyle(.secondary); Text(display.effectiveResolutionLabel) }
                GridRow { Text("Physical resolution").foregroundStyle(.secondary); Text(display.physicalResolutionLabel) }
                GridRow { Text("Refresh rate").foregroundStyle(.secondary); Text(display.currentRefreshRateLabel) }
                GridRow { Text("Physical size").foregroundStyle(.secondary); Text(display.physicalSizeLabel) }
                GridRow { Text("Color space").foregroundStyle(.secondary); Text(display.colorSpaceName) }
                GridRow { Text("Vendor / model").foregroundStyle(.secondary); Text("\(display.vendorNumber) / \(display.modelNumber)") }
                if display.serialNumber != 0 && display.serialNumber != UInt32.max {
                    GridRow { Text("Serial").foregroundStyle(.secondary); Text(String(display.serialNumber)) }
                }
                GridRow { Text("Display ID").foregroundStyle(.secondary); Text(String(display.id)) }
            }
            .font(.callout)

            Text("Display identification and hardware metadata are read through public Core Graphics APIs. macOS does not expose every Windows advanced-display field, such as a universal HDR capability flag, through this API set.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

}

private struct RevertConfirmationBar: View {
    @EnvironmentObject var manager: DisplayManager
    let change: PendingDisplayChange

    var body: some View {
        HStack(spacing: 16) {
            Text("Keep \(change.kind.description) on \(change.displayName)? Reverting in \(change.secondsRemaining)s.")
                .font(.callout)
            Button("Revert") { manager.revertPendingChange() }
                .accessibilityHint("Undoes the change immediately")
            Button("Keep Changes") { manager.confirmPendingChange() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
        .accessibilityElement(children: .contain)
    }
}

private struct ArrangementCanvas: View {
    @EnvironmentObject var manager: DisplayManager
    @State private var dragOffsets: [CGDirectDisplayID: CGSize] = [:]

    var body: some View {
        GeometryReader { geo in
            let bounds = unionFrame()
            let scale = canvasScale(for: bounds, size: geo.size)
            let canvasCenter = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let contentCenter = CGPoint(x: bounds.midX * scale, y: bounds.midY * scale)

            ZStack {
                ForEach(manager.displays) { display in
                    let rect = CGRect(
                        x: display.frame.origin.x * scale,
                        y: display.frame.origin.y * scale,
                        width: display.frame.width * scale,
                        height: display.frame.height * scale
                    )
                    let offset = dragOffsets[display.id] ?? .zero
                    let isDraggable = !display.isMain && !manager.hasPendingChange

                    DisplayTile(display: display, isSelected: display.id == manager.selectedDisplayID)
                        .frame(width: max(rect.width, 60), height: max(rect.height, 40))
                        .position(
                            x: canvasCenter.x - contentCenter.x + rect.midX + offset.width,
                            y: canvasCenter.y - contentCenter.y + rect.midY + offset.height
                        )
                        .onTapGesture { manager.selectedDisplayID = display.id }
                        .accessibilityLabel("\(display.name)\(display.isMain ? ", main display" : "")")
                        .accessibilityHint(display.isMain
                                          ? "Selects this display. The main display cannot be dragged."
                                          : "Selects this display. Drag to reposition it.")
                        .accessibilityAddTraits(display.id == manager.selectedDisplayID ? [.isButton, .isSelected] : .isButton)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    guard isDraggable else { return }
                                    dragOffsets[display.id] = value.translation
                                }
                                .onEnded { value in
                                    guard isDraggable else { return }
                                    let newOrigin = CGPoint(
                                        x: display.frame.origin.x + value.translation.width / scale,
                                        y: display.frame.origin.y + value.translation.height / scale
                                    )
                                    dragOffsets[display.id] = .zero
                                    manager.moveDisplay(display, to: newOrigin)
                                }
                        )
                }
            }
        }
        .padding(20)
    }

    private func unionFrame() -> CGRect {
        manager.displays.reduce(CGRect.null) { $0.union($1.frame) }
    }

    private func canvasScale(for bounds: CGRect, size: CGSize) -> CGFloat {
        guard bounds.width > 0, bounds.height > 0 else { return 0.1 }
        let horizontal = max(0.01, (size.width - 40) / bounds.width)
        let vertical = max(0.01, (size.height - 40) / bounds.height)
        return min(0.22, horizontal, vertical)
    }
}

private struct DisplayTile: View {
    @ObservedObject var display: DisplayInfo
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
            .overlay(
                VStack(spacing: 2) {
                    Image(systemName: display.isMain ? "menubar.rectangle" : "display")
                    Text(display.name)
                        .font(.caption2)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
                .foregroundStyle(.white)
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.6), lineWidth: isSelected ? 2 : 0))
            .shadow(radius: 2)
    }
}
