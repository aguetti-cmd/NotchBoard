import AppKit
import SwiftUI
import NotchBoardCore

/// Size and shape inputs the SwiftUI view needs.
@MainActor @Observable
final class NotchLayout {
    var notchSize = CGSize(width: 190, height: 32)
    var hasNotch = false
    /// World clock row height. The panel grows by this plus the 10 pt gap above it,
    /// so the cards keep their original size.
    static let worldClockHeight: CGFloat = 30
    static let expandedSize = CGSize(width: 780, height: 250 + worldClockHeight + 10)
    /// Extra width each side of the notch while music plays.
    static let wingWidth: CGFloat = 46
}

/// Owns the panel, keeps it over the notch, and decides when it expands.
@MainActor
final class NotchController {
    private let model: AppModel
    private let layout = NotchLayout()
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var collapseTask: Task<Void, Never>?
    private var expandTask: Task<Void, Never>?
    private var screenFrame: CGRect = .zero

    init(model: AppModel) {
        self.model = model
        let size = NotchLayout.expandedSize
        panel = NotchPanel(contentRect: CGRect(origin: .zero, size: size))
        let root = NotchRootView(model: model, layout: layout)
        let host = FirstMouseHostingView(rootView: root)
        host.sizingOptions = []  // the panel keeps a fixed size; SwiftUI animates inside it
        host.frame = CGRect(origin: .zero, size: size)
        panel.contentView = host
        panel.ignoresMouseEvents = true

        position()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.position() }
        }
        installMouseMonitors()

        if ProcessInfo.processInfo.environment["NOTCHBOARD_DEBUG"] != nil {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }
                FileHandle.standardError.write(Data("after 3s panel \(self.panel.frame) visible \(self.panel.isVisible) screen \(self.panel.screen?.frame ?? .zero)\n".utf8))
            }
        }
    }

    // MARK: Placement

    /// The built-in display if it has a notch, otherwise the main screen.
    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func position() {
        guard let screen = Self.targetScreen() else { return }
        let geometry = NotchGeometry.compute(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            leftAuxWidth: screen.auxiliaryTopLeftArea?.width,
            rightAuxWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: NSStatusBar.system.thickness
        )
        layout.notchSize = geometry.notch.size
        layout.hasNotch = geometry.hasNotch
        screenFrame = screen.frame

        let size = NotchLayout.expandedSize
        let origin = CGPoint(x: geometry.notch.midX - size.width / 2, y: screen.frame.maxY - size.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        if ProcessInfo.processInfo.environment["NOTCHBOARD_DEBUG"] != nil {
            FileHandle.standardError.write(Data("screen \(screen.frame) notch \(geometry.notch) hasNotch \(geometry.hasNotch) panel \(panel.frame)\n".utf8))
        }
    }

    // MARK: Hover

    private func installMouseMonitors() {
        // Mouse-moved monitors need no Accessibility permission.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved() }
            return event
        }) {
            monitors.append(local)
        }
    }

    /// The visible collapsed shape, padded a little so it is easy to hit.
    private var hotZone: CGRect {
        let wings = model.music.isPlaying ? NotchLayout.wingWidth * 2 : 0
        let width = layout.notchSize.width + wings + 16
        let height = layout.notchSize.height + 4
        return CGRect(x: panel.frame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height + 2)
    }

    private var expandedZone: CGRect {
        panel.frame.insetBy(dx: -12, dy: -12)
    }

    private func mouseMoved() {
        let point = NSEvent.mouseLocation
        if model.isExpanded {
            if expandedZone.contains(point) {
                collapseTask?.cancel()
                collapseTask = nil
            } else if !model.isPinned, !model.isPreviewing, collapseTask == nil {
                collapseTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(280))
                    guard !Task.isCancelled else { return }
                    self?.collapse()
                }
            }
        } else if hotZone.contains(point) {
            // Short dwell, so sweeping along the menu bar does not open it.
            guard expandTask == nil else { return }
            expandTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, !Task.isCancelled else { return }
                self.expandTask = nil
                if self.hotZone.contains(NSEvent.mouseLocation) { self.expand() }
            }
        } else {
            expandTask?.cancel()
            expandTask = nil
        }
    }

    func expand() {
        collapseTask?.cancel()
        collapseTask = nil
        guard !model.isExpanded else { return }
        model.isExpanded = true
        panel.ignoresMouseEvents = false
        Task { await model.music.refresh() }
        model.agenda.refresh()
    }

    var panelFrame: CGRect { panel.frame }
    var screen: NSScreen? { panel.screen ?? Self.targetScreen() }

    func beginPreview() {
        model.isPreviewing = true
        expand()
    }

    func endPreview() {
        model.isPreviewing = false
        collapseIfMouseOutside()
    }

    func collapse() {
        collapseTask = nil
        guard !model.isPinned, !model.isPreviewing else { return }
        model.isExpanded = false
        panel.ignoresMouseEvents = true
    }

    func collapseIfMouseOutside() {
        if !expandedZone.contains(NSEvent.mouseLocation) { collapse() }
    }
}

/// A borderless panel above the menu bar that never takes focus.
final class NotchPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        acceptsMouseMovedEvents = true  // local monitor still sees moves when the app is active
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    /// AppKit pushes windows below the menu bar; this one belongs on top of it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on a button act immediately, without a focus click.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
