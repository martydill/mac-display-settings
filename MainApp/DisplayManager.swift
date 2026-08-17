import Foundation
import CoreGraphics
import AppKit
import Combine

struct DisplayMode: Identifiable, Hashable {
    let raw: CGDisplayMode

    var id: String {
        [
            String(raw.ioDisplayModeID),
            String(raw.pixelWidth), String(raw.pixelHeight),
            String(raw.width), String(raw.height),
            String(format: "%.3f", raw.refreshRate)
        ].joined(separator: ":")
    }

    var pixelWidth: Int { raw.pixelWidth }
    var pixelHeight: Int { raw.pixelHeight }
    var pointWidth: Int { raw.width }
    var pointHeight: Int { raw.height }
    var refreshRate: Double { raw.refreshRate }
    var isHiDPI: Bool { raw.pixelWidth > raw.width || raw.pixelHeight > raw.height }
    var isUsableForDesktopGUI: Bool { raw.isUsableForDesktopGUI() }

    var resolutionLabel: String {
        "\(pointWidth) × \(pointHeight)" + (isHiDPI ? "  (HiDPI)" : "")
    }

    var refreshRateLabel: String {
        refreshRate > 0 ? "\(Int(refreshRate.rounded())) Hz" : "Default"
    }

    static func == (lhs: DisplayMode, rhs: DisplayMode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct DisplayResolutionOption: Identifiable, Hashable {
    let pointWidth: Int
    let pointHeight: Int
    let isHiDPI: Bool
    let modes: [DisplayMode]

    var id: String { "\(pointWidth)x\(pointHeight)" }
    var label: String {
        "\(pointWidth) × \(pointHeight)" + (isHiDPI ? "  (HiDPI)" : "")
    }
}

struct DisplayRefreshRateOption: Identifiable, Hashable {
    let rate: Double
    let mode: DisplayMode

    var id: String { String(format: "%.3f", rate) }
    var label: String {
        rate > 0 ? "\(Int(rate.rounded())) Hz" : "Default"
    }
}

final class DisplayInfo: Identifiable, ObservableObject, Equatable {
    let id: CGDirectDisplayID
    @Published var frame: CGRect
    @Published var isMain: Bool
    @Published var isMirrored: Bool
    @Published var currentMode: DisplayMode?
    @Published var availableModes: [DisplayMode] = []
    let name: String

    var resolutionOptions: [DisplayResolutionOption] {
        let groups = Dictionary(grouping: availableModes) { mode in
            "\(mode.pointWidth)x\(mode.pointHeight)"
        }
        return groups.values.compactMap { modes in
            guard let first = modes.first else { return nil }
            return DisplayResolutionOption(
                pointWidth: first.pointWidth,
                pointHeight: first.pointHeight,
                isHiDPI: modes.contains(where: { $0.isHiDPI }),
                modes: modes.sorted { $0.refreshRate > $1.refreshRate }
            )
        }.sorted {
            let lhs = $0.pointWidth * $0.pointHeight
            let rhs = $1.pointWidth * $1.pointHeight
            if lhs != rhs { return lhs > rhs }
            return $0.pointWidth > $1.pointWidth
        }
    }

    var refreshRateOptions: [DisplayRefreshRateOption] {
        guard let current = currentMode else { return [] }
        var seen = Set<String>()
        return availableModes
            .filter { $0.pointWidth == current.pointWidth && $0.pointHeight == current.pointHeight }
            .sorted { $0.refreshRate > $1.refreshRate }
            .compactMap { mode in
                let id = String(format: "%.3f", mode.refreshRate)
                guard seen.insert(id).inserted else { return nil }
                return DisplayRefreshRateOption(rate: mode.refreshRate, mode: mode)
            }
    }

    var currentResolutionOption: DisplayResolutionOption? {
        guard let current = currentMode else { return nil }
        return resolutionOptions.first { $0.pointWidth == current.pointWidth && $0.pointHeight == current.pointHeight }
    }

    var physicalResolutionLabel: String {
        "\(CGDisplayPixelsWide(id)) × \(CGDisplayPixelsHigh(id)) pixels"
    }

    var effectiveResolutionLabel: String {
        currentMode?.resolutionLabel ?? "Unknown"
    }

    var currentRefreshRateLabel: String {
        currentMode?.refreshRateLabel ?? "Unknown"
    }

    var connectionDescription: String {
        CGDisplayIsBuiltin(id) != 0 ? "Built-in" : "External"
    }

    var vendorNumber: UInt32 { CGDisplayVendorNumber(id) }
    var modelNumber: UInt32 { CGDisplayModelNumber(id) }
    var serialNumber: UInt32 { CGDisplaySerialNumber(id) }
    var unitNumber: UInt32 { CGDisplayUnitNumber(id) }

    var colorSpaceName: String {
        let colorSpace = CGDisplayCopyColorSpace(id)
        return colorSpace.name as String? ?? "Display profile"
    }

    var physicalSizeLabel: String {
        let size = CGDisplayScreenSize(id)
        guard size.width > 0, size.height > 0 else { return "Unknown" }
        let widthInches = size.width / 25.4
        let heightInches = size.height / 25.4
        return String(format: "%.1f × %.1f in", widthInches, heightInches)
    }

    init(id: CGDirectDisplayID) {
        self.id = id
        self.frame = CGDisplayBounds(id)
        self.isMain = CGDisplayIsMain(id) != 0
        self.isMirrored = CGDisplayIsInMirrorSet(id) != 0
        self.name = DisplayInfo.displayName(for: id)
        refreshModes()
    }

    static func == (lhs: DisplayInfo, rhs: DisplayInfo) -> Bool { lhs.id == rhs.id }

    func refreshModes() {
        let options: [String: Any] = [kCGDisplayShowDuplicateLowResolutionModes as String: true]
        guard let modes = CGDisplayCopyAllDisplayModes(id, options as CFDictionary) as? [CGDisplayMode] else {
            availableModes = []
            currentMode = CGDisplayCopyDisplayMode(id).map(DisplayMode.init(raw:))
            return
        }

        // Remove duplicate modes and hide modes that have no useful geometry.
        // Keep refresh rate in the identity so e.g. 60/120Hz variants remain
        // independently selectable.
        var seen = Set<String>()
        availableModes = modes
            .map(DisplayMode.init(raw:))
            .filter { $0.pointWidth > 0 && $0.pointHeight > 0 && $0.isUsableForDesktopGUI }
            .filter { seen.insert($0.id).inserted }
            .sorted {
                let lhsPixels = $0.pointWidth * $0.pointHeight
                let rhsPixels = $1.pointWidth * $1.pointHeight
                if lhsPixels != rhsPixels { return lhsPixels > rhsPixels }
                return $0.refreshRate > $1.refreshRate
            }

        if let current = CGDisplayCopyDisplayMode(id) {
            currentMode = DisplayMode(raw: current)
        }
    }

    static func displayName(for id: CGDirectDisplayID) -> String {
        if let screen = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return number.uint32Value == id
        }) {
            if #available(macOS 10.15, *) {
                return screen.localizedName
            }
        }
        return CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "Display \(id)"
    }
}

struct DisplayStateSnapshot {
    struct DisplayState {
        let id: CGDirectDisplayID
        let origin: CGPoint
        let mode: DisplayMode?
        let isMain: Bool
    }

    let displays: [DisplayState]
    let mirroredIDs: Set<CGDirectDisplayID>
}

enum PendingDisplayChangeKind {
    case resolution
    case refreshRate
    case displayMode

    var description: String {
        switch self {
        case .resolution: return "this display resolution"
        case .refreshRate: return "this refresh rate"
        case .displayMode: return "this display mode"
        }
    }
}

struct PendingDisplayChange: Identifiable {
    let id = UUID()
    let displayID: CGDirectDisplayID
    let displayName: String
    let kind: PendingDisplayChangeKind
    let snapshot: DisplayStateSnapshot
    var secondsRemaining: Int
}

final class DisplayManager: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var selectedDisplayID: CGDirectDisplayID?
    @Published var multiDisplayMode: MultiDisplayMode = .extend
    @Published var lastError: String?
    @Published var pendingChange: PendingDisplayChange?

    enum MultiDisplayMode: String, CaseIterable, Identifiable {
        case extend = "Extend these displays"
        case mirror = "Duplicate these displays"
        var id: String { rawValue }
    }

    private var revertTimer: Timer?
    private static let revertWindowSeconds = 15
    private static let snapThreshold: CGFloat = 24

    private static let reconfigCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard let userInfo else { return }
        // CoreGraphics calls the callback before and after reconfiguration.
        // Never rebuild the model from the transient pre-change state.
        if flags.rawValue & CGDisplayChangeSummaryFlags.beginConfigurationFlag.rawValue != 0 {
            return
        }
        let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
        DispatchQueue.main.async { [weak manager] in
            manager?.reload()
        }
    }

    init() {
        reload()
        CGDisplayRegisterReconfigurationCallback(Self.reconfigCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(Self.reconfigCallback, Unmanaged.passUnretained(self).toOpaque())
        revertTimer?.invalidate()
    }

    var hasPendingChange: Bool { pendingChange != nil }

    func reload() {
        var count: UInt32 = 0
        let listErr = CGGetActiveDisplayList(0, nil, &count)
        guard listErr == .success else {
            // Preserve a known-good model during transient hot-plug errors.
            if displays.isEmpty {
                lastError = "Could not read the active displays."
            }
            return
        }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        let fetchErr = CGGetActiveDisplayList(count, &ids, &count)
        guard fetchErr == .success else {
            if displays.isEmpty {
                lastError = "Could not read the active displays."
            }
            return
        }

        let oldSelection = selectedDisplayID
        let newDisplays = ids.map(DisplayInfo.init(id:))
        displays = newDisplays

        if let oldSelection, ids.contains(oldSelection) {
            selectedDisplayID = oldSelection
        } else {
            selectedDisplayID = ids.first
        }

        multiDisplayMode = newDisplays.contains { $0.isMirrored } ? .mirror : .extend
    }

    var selectedDisplay: DisplayInfo? {
        displays.first { $0.id == selectedDisplayID }
    }

    // MARK: - Transaction / safety

    private func captureSnapshot() -> DisplayStateSnapshot {
        DisplayStateSnapshot(
            displays: displays.map {
                .init(id: $0.id, origin: $0.frame.origin, mode: $0.currentMode, isMain: $0.isMain)
            },
            mirroredIDs: Set(displays.filter { $0.isMirrored }.map(\.id))
        )
    }

    private func beginRevertCountdown(displayID: CGDirectDisplayID, displayName: String, kind: PendingDisplayChangeKind, snapshot: DisplayStateSnapshot) {
        revertTimer?.invalidate()
        pendingChange = PendingDisplayChange(
            displayID: displayID,
            displayName: displayName,
            kind: kind,
            snapshot: snapshot,
            secondsRemaining: Self.revertWindowSeconds
        )

        revertTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard var change = self.pendingChange else { timer.invalidate(); return }
            change.secondsRemaining -= 1
            if change.secondsRemaining <= 0 {
                timer.invalidate()
                self.revertPendingChange()
            } else {
                self.pendingChange = change
            }
        }
    }

    func confirmPendingChange() {
        revertTimer?.invalidate()
        revertTimer = nil
        pendingChange = nil
        reload()
    }

    func revertPendingChange() {
        revertTimer?.invalidate()
        revertTimer = nil
        guard let change = pendingChange else { return }
        pendingChange = nil
        if !restoreSnapshot(change.snapshot) {
            lastError = "The previous display configuration could not be fully restored."
        }
        reload()
    }

    // MARK: - Resolution

    func setMode(_ mode: DisplayMode, for display: DisplayInfo) {
        guard pendingChange == nil else { return }
        guard !display.isMirrored || display.isMain else {
            lastError = "While displays are mirrored, resolution is controlled by the main display."
            return
        }
        setMode(mode, for: display, kind: .resolution)
    }

    @discardableResult
    private func applyMode(_ mode: DisplayMode, for display: DisplayInfo) -> Bool {
        guard displays.contains(where: { $0.id == display.id }) else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            lastError = "Could not begin display configuration."
            return false
        }

        let setErr = CGConfigureDisplayWithDisplayMode(config, display.id, mode.raw, nil)
        guard setErr == .success else {
            CGCancelDisplayConfiguration(config)
            lastError = "Could not set that resolution on \(display.name)."
            return false
        }

        let completeErr = CGCompleteDisplayConfiguration(config, .permanently)
        guard completeErr == .success else {
            CGCancelDisplayConfiguration(config)
            lastError = "Failed to apply the resolution change to \(display.name)."
            return false
        }

        scheduleReload()
        return true
    }

    // MARK: - Resolution and refresh rate

    func setResolution(_ option: DisplayResolutionOption, for display: DisplayInfo) {
        guard pendingChange == nil else { return }
        guard !display.isMirrored || display.isMain else {
            lastError = "While displays are mirrored, resolution is controlled by the main display."
            return
        }

        let candidates = option.modes
        guard !candidates.isEmpty else { return }
        let currentRate = display.currentMode?.refreshRate ?? 0
        let selected = candidates.min { lhs, rhs in
            let lhsDistance = abs(lhs.refreshRate - currentRate)
            let rhsDistance = abs(rhs.refreshRate - currentRate)
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            return lhs.refreshRate > rhs.refreshRate
        } ?? candidates[0]
        setMode(selected, for: display, kind: .resolution)
    }

    func setRefreshRate(_ option: DisplayRefreshRateOption, for display: DisplayInfo) {
        guard pendingChange == nil else { return }
        guard !display.isMirrored || display.isMain else {
            lastError = "While displays are mirrored, refresh rate is controlled by the main display."
            return
        }
        guard let current = display.currentMode else { return }
        guard abs(current.refreshRate - option.rate) > 0.01 else { return }
        setMode(option.mode, for: display, kind: .refreshRate)
    }

    private func setMode(_ mode: DisplayMode, for display: DisplayInfo, kind: PendingDisplayChangeKind) {
        guard let previous = display.currentMode, previous != mode else { return }
        let snapshot = captureSnapshot()
        guard applyMode(mode, for: display) else { return }
        beginRevertCountdown(displayID: display.id, displayName: display.name, kind: kind, snapshot: snapshot)
    }

    // MARK: - Arrangement

    func snappedOrigin(for display: DisplayInfo, proposedOrigin: CGPoint) -> CGPoint {
        var result = CGPoint(x: proposedOrigin.x.rounded(), y: proposedOrigin.y.rounded())

        for other in displays where other.id != display.id {
            let width = display.frame.width
            let height = display.frame.height
            let otherFrame = other.frame

            let xCandidates = [
                otherFrame.minX,
                otherFrame.maxX,
                otherFrame.minX - width,
                otherFrame.maxX - width
            ]
            if let x = xCandidates.min(by: { abs($0 - result.x) < abs($1 - result.x) }), abs(x - result.x) <= Self.snapThreshold {
                result.x = x
            }

            let yCandidates = [
                otherFrame.minY,
                otherFrame.maxY,
                otherFrame.minY - height,
                otherFrame.maxY - height
            ]
            if let y = yCandidates.min(by: { abs($0 - result.y) < abs($1 - result.y) }), abs(y - result.y) <= Self.snapThreshold {
                result.y = y
            }
        }

        // Windows-style layouts do not allow display rectangles to overlap.
        // If the proposed position intersects another display, move it to
        // the nearest non-overlapping side. Iterate because moving past one
        // display can bring the tile into another one.
        let size = display.frame.size
        for _ in 0..<displays.count {
            let candidate = CGRect(origin: result, size: size)
            var changed = false
            for other in displays where other.id != display.id {
                let otherFrame = other.frame
                guard candidate.intersects(otherFrame) else { continue }

                let options = [
                    CGPoint(x: otherFrame.minX - size.width, y: result.y),
                    CGPoint(x: otherFrame.maxX, y: result.y),
                    CGPoint(x: result.x, y: otherFrame.minY - size.height),
                    CGPoint(x: result.x, y: otherFrame.maxY)
                ]
                if let nearest = options.min(by: {
                    hypot($0.x - result.x, $0.y - result.y) < hypot($1.x - result.x, $1.y - result.y)
                }) {
                    result = nearest
                    changed = true
                }
                break
            }
            if !changed { break }
        }

        return result
    }

    func moveDisplay(_ display: DisplayInfo, to newOrigin: CGPoint) {
        guard pendingChange == nil else { return }
        // The main display must remain at (0,0). Let the explicit "Make this
        // my main display" operation change the primary display instead of
        // pretending a dragged main tile can be moved independently.
        guard !display.isMain else {
            lastError = "The main display stays at (0,0). Select another display and make it the main display first."
            return
        }

        let snapped = snappedOrigin(for: display, proposedOrigin: newOrigin)
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            lastError = "Could not begin display configuration."
            return
        }

        let err = CGConfigureDisplayOrigin(config, display.id, Int32(snapped.x.rounded()), Int32(snapped.y.rounded()))
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            lastError = "Could not move \(display.name)."
            return
        }

        let completeErr = CGCompleteDisplayConfiguration(config, .permanently)
        guard completeErr == .success else {
            CGCancelDisplayConfiguration(config)
            lastError = "Could not apply the new display arrangement."
            return
        }
        scheduleReload()
    }

    func makeMain(_ display: DisplayInfo) {
        guard pendingChange == nil, !display.isMain else { return }

        // Moving the selected display to (0,0) and translating every other
        // display by the same amount preserves the relative arrangement.
        let delta = CGPoint(x: -display.frame.origin.x, y: -display.frame.origin.y)
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            lastError = "Could not begin display configuration."
            return
        }

        for d in displays {
            let newOrigin = CGPoint(x: d.frame.origin.x + delta.x, y: d.frame.origin.y + delta.y)
            let err = CGConfigureDisplayOrigin(config, d.id, Int32(newOrigin.x.rounded()), Int32(newOrigin.y.rounded()))
            guard err == .success else {
                CGCancelDisplayConfiguration(config)
                lastError = "Could not make \(display.name) the main display."
                return
            }
        }

        let completeErr = CGCompleteDisplayConfiguration(config, .permanently)
        guard completeErr == .success else {
            CGCancelDisplayConfiguration(config)
            lastError = "Could not apply the new main display."
            return
        }
        scheduleReload()
    }

    // MARK: - Mirroring

    func setMultiDisplayMode(_ mode: MultiDisplayMode) {
        guard pendingChange == nil else { return }
        guard displays.count > 1 else { return }
        guard mode != multiDisplayMode else { return }
        guard let main = displays.first(where: { $0.isMain }) ?? displays.first else { return }

        let snapshot = captureSnapshot()
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            lastError = "Could not begin display configuration."
            return
        }

        for d in displays where d.id != main.id {
            let err: CGError
            switch mode {
            case .mirror:
                err = CGConfigureDisplayMirrorOfDisplay(config, d.id, main.id)
            case .extend:
                err = CGConfigureDisplayMirrorOfDisplay(config, d.id, kCGNullDirectDisplay)
            }
            guard err == .success else {
                CGCancelDisplayConfiguration(config)
                lastError = "Could not change the multiple-display mode."
                return
            }
        }

        let completeErr = CGCompleteDisplayConfiguration(config, .permanently)
        guard completeErr == .success else {
            CGCancelDisplayConfiguration(config)
            lastError = "Could not apply the multiple-display mode."
            return
        }

        multiDisplayMode = mode
        beginRevertCountdown(
            displayID: main.id,
            displayName: "your displays",
            kind: .displayMode,
            snapshot: snapshot
        )
        scheduleReload()
    }

    // MARK: - Snapshot restore

    @discardableResult
    private func restoreSnapshot(_ snapshot: DisplayStateSnapshot) -> Bool {
        var success = true

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            return false
        }

        for state in snapshot.displays {
            guard CGDisplayIsActive(state.id) != 0 else { continue }
            if let mode = state.mode, CGConfigureDisplayWithDisplayMode(config, state.id, mode.raw, nil) != .success {
                success = false
            }
            if CGConfigureDisplayOrigin(config, state.id, Int32(state.origin.x.rounded()), Int32(state.origin.y.rounded())) != .success {
                success = false
            }
        }

        guard let mainID = snapshot.displays.first(where: { $0.isMain })?.id else {
            CGCancelDisplayConfiguration(config)
            return false
        }

        for state in snapshot.displays where state.id != mainID && CGDisplayIsActive(state.id) != 0 {
            let mirrorID: CGDirectDisplayID = snapshot.mirroredIDs.contains(state.id) ? mainID : kCGNullDirectDisplay
            if CGConfigureDisplayMirrorOfDisplay(config, state.id, mirrorID) != .success {
                success = false
            }
        }

        if CGCompleteDisplayConfiguration(config, .permanently) != .success {
            success = false
        }

        scheduleReload(after: 0.7)
        return success
    }

    // MARK: - Display information

    func recommendedResolution(for display: DisplayInfo) -> DisplayResolutionOption? {
        guard let screen = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return number.uint32Value == display.id
        }) else {
            return nil
        }

        // macOS does not expose a public "recommended resolution" flag.
        // Use the display's current logical screen size as the closest public-API
        // representation of the system-selected/default mode.
        let width = Int(screen.frame.width.rounded())
        let height = Int(screen.frame.height.rounded())
        return display.resolutionOptions.first { $0.pointWidth == width && $0.pointHeight == height }
    }

    var displayModeSummary: String {
        multiDisplayMode == .mirror ? "Duplicate displays" : "Extend displays"
    }

    // MARK: - Identify

    func identifyDisplays() {
        for display in displays {
            showIdentifyOverlay(for: display)
        }
    }

    private func showIdentifyOverlay(for display: DisplayInfo) {
        guard let screen = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return number.uint32Value == display.id
        }) else { return }

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: screen.frame.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: true)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let bg = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor

        let label = NSTextField(labelWithString: display.isMain ? "\(display.name) (Main)" : display.name)
        label.font = .systemFont(ofSize: min(96, max(36, screen.frame.height * 0.09)), weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: bg.leadingAnchor, constant: 30),
            label.trailingAnchor.constraint(lessThanOrEqualTo: bg.trailingAnchor, constant: -30)
        ])

        window.contentView = bg
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { window.orderOut(nil) }
    }

    private func scheduleReload(after delay: TimeInterval = 0.35) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.reload()
        }
    }
}
