import AppKit
import SwiftUI

private final class FocusableCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class CaptureWindowController: NSObject, NSWindowDelegate {
    private enum Constants {
        static let panelWidth: CGFloat = 620
        static let minPanelHeight: CGFloat = 240
        static let maxPanelHeight: CGFloat = 620
        static let savedRelativeXKey = "quickbox.capturePanel.relativeX"
        static let savedRelativeYKey = "quickbox.capturePanel.relativeY"
    }

    private let panel: NSPanel
    private weak var appState: AppState?
    private var heightObserver: NSObjectProtocol?

    init(appState: AppState) {
        self.appState = appState
        panel = FocusableCapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: Constants.panelWidth, height: 320),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        let rootView = CaptureView(appState: appState, mode: .spotlight) { [weak self, weak panel] in
            self?.appState?.endSpotlightSession()
            panel?.orderOut(nil)
        }
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        heightObserver = NotificationCenter.default.addObserver(
            forName: .quickboxCaptureHeightDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let height = notification.object as? CGFloat else {
                return
            }
            self.resizePanel(contentHeight: height)
        }
    }

    deinit {
        if let heightObserver {
            NotificationCenter.default.removeObserver(heightObserver)
        }
    }

    func show(prefillAction: () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            NotificationCenter.default.post(name: .quickboxFocusCapture, object: nil)
            return
        }

        prefillAction()
        positionForPresentation()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        NotificationCenter.default.post(name: .quickboxCapturePresented, object: nil)
        NotificationCenter.default.post(name: .quickboxFocusCapture, object: nil)
    }

    func hide() {
        guard panel.isVisible else {
            return
        }

        appState?.endSpotlightSession()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    func windowDidMove(_ notification: Notification) {
        saveCurrentOrigin()
    }

    private func resizePanel(contentHeight: CGFloat) {
        let clampedHeight = min(max(contentHeight, Constants.minPanelHeight), Constants.maxPanelHeight)
        let currentFrame = panel.frame
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y + (currentFrame.height - clampedHeight),
            width: currentFrame.width,
            height: clampedHeight
        )
        panel.setFrame(newFrame, display: true, animate: true)
    }

    private func positionNearTopCenter() {
        guard let screen = targetScreenForPresentation() else {
            panel.center()
            return
        }

        let visible = screen.visibleFrame
        let x = visible.midX - (panel.frame.width / 2)
        let y = visible.minY + (visible.height * 0.72)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func positionForPresentation() {
        guard let targetScreen = targetScreenForPresentation() else {
            panel.center()
            return
        }

        if let savedRelativeOrigin = restoredRelativeOrigin() {
            let translated = translatedOrigin(fromRelative: savedRelativeOrigin, in: targetScreen)
            panel.setFrameOrigin(clampedOrigin(translated, in: targetScreen))
        } else {
            positionNearTopCenter()
        }
    }

    private func saveCurrentOrigin() {
        guard let screen = panel.screen ?? targetScreenForPresentation() else {
            return
        }

        let visible = screen.visibleFrame
        guard visible.width > panel.frame.width, visible.height > panel.frame.height else {
            return
        }

        let defaults = UserDefaults.standard
        let relativeX = (panel.frame.origin.x - visible.minX) / (visible.width - panel.frame.width)
        let relativeY = (panel.frame.origin.y - visible.minY) / (visible.height - panel.frame.height)
        defaults.set(min(max(relativeX, 0), 1), forKey: Constants.savedRelativeXKey)
        defaults.set(min(max(relativeY, 0), 1), forKey: Constants.savedRelativeYKey)
    }

    private func restoredRelativeOrigin() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Constants.savedRelativeXKey) != nil,
              defaults.object(forKey: Constants.savedRelativeYKey) != nil else {
            return nil
        }

        return NSPoint(
            x: defaults.double(forKey: Constants.savedRelativeXKey),
            y: defaults.double(forKey: Constants.savedRelativeYKey)
        )
    }

    private func clampedOrigin(_ origin: NSPoint, in screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        let maxX = max(visible.minX, visible.maxX - panel.frame.width)
        let maxY = max(visible.minY, visible.maxY - panel.frame.height)
        let x = min(max(origin.x, visible.minX), maxX)
        let y = min(max(origin.y, visible.minY), maxY)
        return NSPoint(x: x, y: y)
    }

    private func translatedOrigin(fromRelative relative: NSPoint, in screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        let clampedRelativeX = min(max(relative.x, 0), 1)
        let clampedRelativeY = min(max(relative.y, 0), 1)
        let x = visible.minX + ((visible.width - panel.frame.width) * clampedRelativeX)
        let y = visible.minY + ((visible.height - panel.frame.height) * clampedRelativeY)
        return NSPoint(x: x, y: y)
    }

    private func targetScreenForPresentation() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let hovered = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return hovered
        }
        return NSScreen.main
    }
}
