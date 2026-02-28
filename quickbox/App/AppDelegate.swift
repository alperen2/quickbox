import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var captureWindowController: CaptureWindowController?
    private var settingsWindowController: SettingsWindowController?

    private var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let state = AppState(
            settingsStore: SettingsStore(),
            hotkeyManager: HotkeyManager()
        )
        self.appState = state

        let captureController = CaptureWindowController(appState: state)
        let settingsController = SettingsWindowController(appState: state)
        self.captureWindowController = captureController
        self.settingsWindowController = settingsController

        let popoverView = MenuBarDashboardView(
            appState: state,
            onOpenSettings: { [weak settingsController] in
                settingsController?.show()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        let popoverController = NSHostingController(rootView: popoverView)
        let menuBarController = MenuBarController(popoverContentViewController: popoverController)

        state.onCaptureRequested = { [weak self] in
            self?.presentCapture()
        }
        state.onSettingsRequested = { [weak settingsController] in
            settingsController?.show()
        }
        state.onCaptureSaved = { [weak self, weak state] in
            guard state?.isSpotlightModeActive == false else {
                return
            }
            self?.menuBarController?.openPopover()
        }

        self.menuBarController = menuBarController
    }

    private func presentCapture() {
        guard let appState, let captureWindowController else {
            return
        }

        captureWindowController.show {
            appState.prepareSpotlightSession()
        }
    }
}
