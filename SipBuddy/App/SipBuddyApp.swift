import SwiftUI

@main
struct SipBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Everything lives in the menu bar; windows are managed by MenuBarManager.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: AppModel?

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }
        NSApp.setActivationPolicy(.accessory)
        let model = AppModel()
        self.model = model
        model.start()
        #if DEBUG
        // Developer shortcut: `-debugOpen popover|stats|settings|card` opens a screen at launch.
        if let target = UserDefaults.standard.string(forKey: "debugOpen") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                switch target {
                case "popover": model.menuBar.showPopover()
                case "stats": model.menuBar.showStatistics()
                case "settings": model.menuBar.showSettings()
                case "statsRender":
                    // Renders the dashboard straight to an image, bypassing window capture.
                    let renderer = ImageRenderer(content: model.inject(StatisticsView()).frame(width: 900, height: 1100)
                        .environment(\.colorScheme, NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light))
                    renderer.scale = 2
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
                           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                            try? png.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("stats-render.png"))
                        }
                    }
                case "card":
                    let msg = model.scheduler.makeMessage()
                    model.card.present(title: msg.title, message: msg.body)
                default: break
                }
            }
            // `-debugSnapshot name.png` saves (into the sandbox tmp folder) the opened screen so it can be reviewed headlessly.
            if let path = UserDefaults.standard.string(forKey: "debugSnapshot") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    let window = NSApp.windows.filter { $0.isVisible && $0.frame.width > 100 }
                        .max { $0.orderedIndex > $1.orderedIndex }
                    guard var view = window?.contentView else { return }
                    // Scroll views don't draw via cacheDisplay; capture their document view instead.
                    func findScroll(_ v: NSView) -> NSScrollView? {
                        if let s = v as? NSScrollView { return s }
                        for sub in v.subviews { if let s = findScroll(sub) { return s } }
                        return nil
                    }
                    if let doc = findScroll(view)?.documentView { view = doc }
                    let rect = view.bounds
                    guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return }
                    view.cacheDisplay(in: rect, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(path))
                }
            }
        }
        #endif
    }

    /// Launching SipBuddy again (e.g. from Finder) opens Settings. This is how you get
    /// back in after hiding the menu bar icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.menuBar.showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
