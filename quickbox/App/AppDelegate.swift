import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var captureWindowController: CaptureWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var uiTestWindowController: NSWindowController?

    private var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        NSApp.setActivationPolicy(isUITesting ? .regular : .accessory)

        let state = AppState(
            settingsStore: SettingsStore(),
            hotkeyManager: HotkeyManager(),
            distributionChannel: .current,
            registerHotkeyOnInit: !isUITesting
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

        if isUITesting {
            seedUITestAutocompleteData()
            if ProcessInfo.processInfo.arguments.contains("--ui-test-host-window") {
                presentUITestHostWindow(with: state)
            }
        }
    }

    private func presentCapture() {
        guard let appState, let captureWindowController else {
            return
        }

        captureWindowController.show {
            appState.prepareSpotlightSession()
        }
    }

    private func seedUITestAutocompleteData() {
        IndexManager.shared.inject(tags: ["deepwork", "ops", "followup"], project: "ProjectAlpha")
        IndexManager.shared.inject(tags: ["ux"], project: "ProjectBeta")
    }

    private func presentUITestHostWindow(with state: AppState) {
        state.prepareSpotlightSession()

        let rootView = CaptureView(appState: state, mode: .spotlight) {}
        let hostController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostController)
        window.title = "quickbox UI Test Host"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 620))
        window.center()
        window.makeKeyAndOrderFront(nil)

        let controller = NSWindowController(window: window)
        uiTestWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
