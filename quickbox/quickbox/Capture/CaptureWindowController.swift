import AppKit
import SwiftUI

final class CaptureWindowController: NSObject, NSWindowDelegate {
    private enum Constants {
        static let panelWidth: CGFloat = 620
        static let minPanelHeight: CGFloat = 220
        static let maxPanelHeight: CGFloat = 430
    }

    private let panel: NSPanel
    private weak var appState: AppState?
    private var heightObserver: NSObjectProtocol?

    init(appState: AppState) {
        self.appState = appState
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Constants.panelWidth, height: 320),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        let rootView = CaptureView(appState: appState, mode: .spotlight) { [weak self, weak panel] in
            self?.appState?.endSpotlightSession()
            panel?.orderOut(nil)
        }
        panel.contentView = NSHostingView(rootView: rootView)

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
            NotificationCenter.default.post(name: .quickboxFocusCapture, object: nil)
            return
        }

        prefillAction()
        positionNearTopCenter()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
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
        guard let screen = NSScreen.main else {
            panel.center()
            return
        }

        let visible = screen.visibleFrame
        let x = visible.midX - (panel.frame.width / 2)
        let y = visible.minY + (visible.height * 0.72)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
