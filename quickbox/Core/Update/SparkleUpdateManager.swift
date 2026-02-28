import AppKit
import Foundation

struct UpdateConfiguration {
    let releasePageURL: URL
    let stableAppcastURL: URL
    let betaAppcastURL: URL

    static let `default` = UpdateConfiguration(
        releasePageURL: URL(string: "https://github.com/alperen2/quickbox/releases")!,
        stableAppcastURL: URL(string: "https://alperen2.github.io/quickbox/appcast.xml")!,
        betaAppcastURL: URL(string: "https://alperen2.github.io/quickbox/appcast-beta.xml")!
    )
}

#if canImport(Sparkle)
import Sparkle

final class SparkleUpdateManager: NSObject, UpdateManaging {
    private let updaterController: SPUStandardUpdaterController
    private let configuration: UpdateConfiguration
    private let feedDelegate: SparkleFeedDelegate
    private var betaChannelEnabled: Bool

    init(configuration: UpdateConfiguration = .default, autoCheckEnabled: Bool, betaChannelEnabled: Bool) {
        self.configuration = configuration
        self.betaChannelEnabled = betaChannelEnabled
        self.feedDelegate = SparkleFeedDelegate(
            feedURL: betaChannelEnabled ? configuration.betaAppcastURL : configuration.stableAppcastURL
        )
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: feedDelegate,
            userDriverDelegate: nil
        )
        super.init()

        updaterController.updater.automaticallyChecksForUpdates = autoCheckEnabled
    }

    func start() {
        updaterController.startUpdater()
    }

    func checkForUpdates() throws {
        updaterController.checkForUpdates(nil)
    }

    func setAutoCheck(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
    }

    func setBetaChannel(_ enabled: Bool) {
        betaChannelEnabled = enabled
        feedDelegate.feedURL = activeFeedURL
    }

    private var activeFeedURL: URL {
        betaChannelEnabled ? configuration.betaAppcastURL : configuration.stableAppcastURL
    }

}

private final class SparkleFeedDelegate: NSObject, SPUUpdaterDelegate {
    var feedURL: URL

    init(feedURL: URL) {
        self.feedURL = feedURL
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        _ = updater
        return feedURL.absoluteString
    }
}

#else

final class SparkleUpdateManager: UpdateManaging {
    private let configuration: UpdateConfiguration
    private var autoCheckEnabled: Bool

    init(configuration: UpdateConfiguration = .default, autoCheckEnabled: Bool, betaChannelEnabled: Bool) {
        self.configuration = configuration
        self.autoCheckEnabled = autoCheckEnabled
        _ = betaChannelEnabled
    }

    func start() {
        // Sparkle package is optional at compile time. No-op without dependency.
    }

    func checkForUpdates() throws {
        NSWorkspace.shared.open(configuration.releasePageURL)
    }

    func setAutoCheck(_ enabled: Bool) {
        autoCheckEnabled = enabled
    }

    func setBetaChannel(_ enabled: Bool) {
        _ = enabled
    }
}

#endif
