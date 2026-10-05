import AppKit

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    init(popoverContentViewController: NSViewController) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.contentViewController = popoverContentViewController

        if let button = statusItem.button {
            // Template image from brand/make_icons.py, so the menu bar tints it for light and dark.
            if let image = NSImage(named: "MenuBarIcon") {
                image.isTemplate = true
                image.accessibilityDescription = Brand.name
                button.image = image
                button.imagePosition = .imageOnly
            } else {
                button.title = Brand.name
            }
            button.toolTip = Brand.name
            button.target = self
            button.action = #selector(togglePopover)
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    func openPopover() {
        guard let button = statusItem.button else {
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closePopover() {
        popover.performClose(nil)
    }
}
