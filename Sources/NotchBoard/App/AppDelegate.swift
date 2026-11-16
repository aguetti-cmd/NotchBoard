import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var notch: NotchController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var pinItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch = NotchController(model: model)
        model.openSettings = { [weak self] in self?.openSettings() }
        setUpStatusItem()
        model.start()

        // Debug and screenshot aid: start expanded and pinned.
        if CommandLine.arguments.contains("--pinned") {
            model.isPinned = true
            notch?.expand()
        }
        if CommandLine.arguments.contains("--settings") { openSettings() }
        // Verification aid: `--snapshot <path.png>` renders the open panel
        // offscreen once data has loaded, then quits. Needs no screen recording.
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[i + 1]
            Task {
                try? await Task.sleep(for: .seconds(6))
                self.writeSnapshot(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
    }

    private func writeSnapshot(to url: URL) {
        let layout = NotchLayout()
        layout.notchSize = CGSize(width: 185, height: 32)  // MacBook Pro 14" notch
        layout.hasNotch = true
        model.isExpanded = true
        let view = NotchRootView(model: model, layout: layout)
            .frame(width: NotchLayout.expandedSize.width, height: NotchLayout.expandedSize.height)
            .background(Color(white: 0.85))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let image = renderer.nsImage,
           let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                     accessibilityDescription: "NotchBoard")
        let menu = NSMenu()
        let pin = NSMenuItem(title: "Keep Open", action: #selector(togglePin), keyEquivalent: "")
        pin.target = self
        menu.addItem(pin)
        pinItem = pin
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchBoard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    @objc private func togglePin() {
        model.isPinned.toggle()
        if model.isPinned { notch?.expand() } else { notch?.collapseIfMouseOutside() }
    }

    @objc private func refresh() {
        model.refreshAll()
    }

    @objc func openSettings() {
        // Settings must sit below the open panel, which floats above all windows.
        let gap: CGFloat = 12
        let screen = notch?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let panelBottom = notch?.panelFrame.minY ?? visible.maxY
        let top = min(visible.maxY, panelBottom) - gap
        let titleBar: CGFloat = 32
        let height = max(min(680, top - visible.minY - gap - titleBar), 300)

        let root = SettingsView(model: model, height: height)
        if let window = settingsWindow, let host = window.contentViewController as? NSHostingController<SettingsView> {
            host.rootView = root
        } else {
            let host = NSHostingController(rootView: root)
            host.sizingOptions = []  // size is set below, before positioning
            let window = NSWindow(contentViewController: host)
            window.title = "NotchBoard Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            settingsWindow = window
        }
        if let window = settingsWindow {
            window.setContentSize(CGSize(width: 420, height: height))
            let size = window.frame.size
            let x = (screen?.frame.midX ?? visible.midX) - size.width / 2
            window.setFrameTopLeftPoint(CGPoint(x: x, y: top))
        }
        notch?.beginPreview()
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow {
            notch?.endPreview()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        pinItem?.state = model.isPinned ? .on : .off
    }
}
