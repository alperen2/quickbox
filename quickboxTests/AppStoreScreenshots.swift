import AppKit
import Foundation
import SwiftUI
import Testing
@testable import quickbox

/// Renders the App Store screenshots from the real views with demo data, without touching the
/// screen (no Screen Recording permission) or the user's folder. Skipped unless asked for:
///
///     TEST_RUNNER_PIGEON_SCREENSHOTS_DIR=/tmp/shots xcodebuild test ... \
///       -only-testing:quickboxTests/AppStoreScreenshots
///
/// `brand/make_screenshots.py` then composes the raw renders into store-sized images.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["PIGEON_SCREENSHOTS_DIR"] != nil))
struct AppStoreScreenshots {
    private let outputDirectory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PIGEON_SCREENSHOTS_DIR"] ?? NSTemporaryDirectory())

    /// Each shot is the capture panel with a different draft; the list below shows the shared inbox.
    private static let shots: [(name: String, draft: String, appearance: NSAppearance.Name)] = [
        ("1-capture", "Plan onboarding emails @Marketing due:friday", .aqua),
        ("2-agents", "Summarize the customer interviews #research for:agent", .darkAqua),
        ("3-handback", "", .aqua),
    ]

    @Test
    func renderStoreScreenshots() async throws {
        let storage = try DemoInbox.make()
        defer { try? FileManager.default.removeItem(at: storage) }

        for shot in Self.shots {
            let state = try await Self.appState(storage: storage)
            state.prepareSpotlightSession()
            state.draftText = shot.draft
            let capture = CaptureView(appState: state, mode: .spotlight) {}
            try Self.render(capture, size: CGSize(width: 760, height: 560), appearance: shot.appearance,
                            to: outputDirectory.appendingPathComponent("\(shot.name).png"))
        }
    }

    private static func appState(storage: URL) async throws -> AppState {
        let suiteName = "pigeon.screenshots.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let resolver = DemoStorageResolver(baseURL: storage)
        let state = AppState(
            settingsStore: SettingsStore(userDefaults: defaults),
            hotkeyManager: HotkeyManager(),
            inboxWriter: InboxWriter(storageResolver: resolver),
            inboxRepository: InboxRepository(storageResolver: resolver),
            clipboardProvider: { nil },
            registerHotkeyOnInit: false,
            loadInboxOnInit: false
        )
        state.loadInbox()
        for _ in 0..<50 where state.inboxItems.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!state.inboxItems.isEmpty)
        return state
    }

    /// Draws the view offscreen at 2x into a PNG.
    private static func render<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name, to url: URL) throws {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        let scale = 2
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}

private struct DemoStorageResolver: StorageResolving {
    let baseURL: URL
    func resolvedBaseURL() throws -> URL { baseURL }
    func stopAccess(for url: URL) { _ = url }
}

/// A small inbox that shows capture, triage and the agent handoff.
private enum DemoInbox {
    static func make() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pigeon-demo-\(UUID().uuidString)")
        let day = FormatSettings.fileName(for: Date(), preferences: .default)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Marketing"), withIntermediateDirectories: true)
        try """
        - [ ] 08:45 Reply to Sam about the Q4 roadmap !2 #work id:demo0001
        - [x] 09:10 Book the dentist #personal id:demo0002
        - [ ] 09:30 Review the launch post draft for:me by:Claude id:demo0003
        - [ ] 10:05 Summarize this week's customer interviews #research for:agent id:demo0004
        - [ ] 12:30 Lunch with Ada #personal id:demo0005

        """.write(to: root.appendingPathComponent(day), atomically: true, encoding: .utf8)
        try """
        - [x] 09:02 Draft the launch post @Marketing #social for:agent id:demo0101
        - [ ] 11:20 Pick the launch date @Marketing !1 id:demo0102

        """.write(to: root.appendingPathComponent("Marketing").appendingPathComponent(day), atomically: true, encoding: .utf8)
        return root
    }
}
