import AppKit
import SwiftUI
import Combine

/// Owns the status-bar item, its popover, and the Settings / Statistics windows.
final class MenuBarManager: NSObject, ObservableObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var statsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private weak var model: AppModel?

    @Published private(set) var isPopoverShown = false

    func install(model: AppModel) {
        self.model = model
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = icon(for: model.hydration.progress)
        item.button?.toolTip = "SipBuddy"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityLabel("SipBuddy")
        item.isVisible = model.settings.showMenuBarIcon
        statusItem = item

        let hosting = NSHostingController(rootView: model.inject(PopoverView()))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        // Icon fills as you drink: empty → half → full.
        model.hydration.objectWillChange
            .merge(with: model.settings.objectWillChange)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self, weak model] in
                guard let self, let model else { return }
                self.statusItem?.button?.image = self.icon(for: model.hydration.progress)
                self.statusItem?.isVisible = model.settings.showMenuBarIcon
            }
            .store(in: &cancellables)
    }

    /// The blue SipBuddy drop, filled to today's progress.
    private func icon(for progress: Double) -> NSImage? {
        Self.dropIcon(progress: progress)
    }

    static func dropIcon(progress: Double, size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
        let image = NSImage(size: size, flipped: false) { bounds in
            let h = bounds.height - 2
            let w = h * 0.76
            let rect = NSRect(x: bounds.midX - w / 2, y: 1, width: w, height: h)
            let drop = Self.dropPath(in: rect)

            // Empty part: soft aqua.
            NSColor(red: 0.62, green: 0.86, blue: 0.98, alpha: 0.55).setFill()
            drop.fill()

            // Water level: the app icon's blue gradient.
            let level = min(max(progress, 0), 1)
            if level > 0 {
                NSGraphicsContext.saveGraphicsState()
                drop.addClip()
                let water = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * max(level, 0.12))
                NSGradient(colors: [NSColor(red: 0.38, green: 0.86, blue: 0.96, alpha: 1),
                                    NSColor(red: 0.14, green: 0.48, blue: 0.95, alpha: 1)])!
                    .draw(in: water, angle: -90)
                NSGraphicsContext.restoreGraphicsState()
            }

            NSColor(red: 0.14, green: 0.48, blue: 0.95, alpha: 1).setStroke()
            drop.lineWidth = 1.2
            drop.stroke()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "SipBuddy, \(Int(progress * 100)) percent of today's goal"
        return image
    }

    /// A water drop in AppKit coordinates (tip at the top).
    static func dropPath(in r: NSRect) -> NSBezierPath {
        let p = NSBezierPath()
        let rad = r.width / 2, cy = r.minY + rad, k: CGFloat = 0.5523
        p.move(to: NSPoint(x: r.midX, y: r.maxY))
        p.curve(to: NSPoint(x: r.maxX, y: cy),
                controlPoint1: NSPoint(x: r.midX + rad * 0.25, y: r.maxY - (r.maxY - cy) * 0.35),
                controlPoint2: NSPoint(x: r.maxX, y: cy + rad * 0.75))
        p.curve(to: NSPoint(x: r.midX, y: r.minY),
                controlPoint1: NSPoint(x: r.maxX, y: cy - rad * k), controlPoint2: NSPoint(x: r.midX + rad * k, y: r.minY))
        p.curve(to: NSPoint(x: r.minX, y: cy),
                controlPoint1: NSPoint(x: r.midX - rad * k, y: r.minY), controlPoint2: NSPoint(x: r.minX, y: cy - rad * k))
        p.curve(to: NSPoint(x: r.midX, y: r.maxY),
                controlPoint1: NSPoint(x: r.minX, y: cy + rad * 0.75),
                controlPoint2: NSPoint(x: r.midX - rad * 0.25, y: r.maxY - (r.maxY - cy) * 0.35))
        p.close()
        return p
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open SipBuddy", action: #selector(openPopoverAction), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Statistics…", action: #selector(openStatsAction), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit SipBuddy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openPopoverAction() { showPopover() }
    @objc private func openStatsAction() { showStatistics() }
    @objc private func openSettingsAction() { showSettings() }

    func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    func showPopover() {
        guard let button = statusItem?.button, statusItem?.isVisible == true else {
            showStatistics()
            return
        }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() { popover.performClose(nil) }

    func popoverDidShow(_ notification: Notification) { isPopoverShown = true }
    func popoverDidClose(_ notification: Notification) { isPopoverShown = false }

    // MARK: - Windows

    func showSettings() {
        closePopover()
        guard let model else { return }
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "SipBuddy Settings",
                                        view: model.inject(SettingsView()),
                                        size: NSSize(width: 600, height: 560), resizable: false)
        }
        present(settingsWindow)
    }

    func showStatistics() {
        closePopover()
        guard let model else { return }
        if statsWindow == nil {
            statsWindow = makeWindow(title: "Hydration Statistics",
                                     view: model.inject(StatisticsView()),
                                     size: NSSize(width: 900, height: 760), resizable: true)
            statsWindow?.minSize = NSSize(width: 760, height: 560)
        }
        present(statsWindow)
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow<V: View>(title: String, view: V, size: NSSize, resizable: Bool) -> NSWindow {
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable { mask.insert(.resizable) }
        window.styleMask = mask
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        window.center()
        return window
    }
}
