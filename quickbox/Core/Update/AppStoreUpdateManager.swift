import Foundation

final class AppStoreUpdateManager: UpdateManaging {
    func start() {
        // App Store handles updates externally.
    }

    func checkForUpdates() throws {
        throw UpdateError.updateCheckUnavailable
    }

    func setAutoCheck(_ enabled: Bool) {
        _ = enabled
    }

    func setBetaChannel(_ enabled: Bool) {
        _ = enabled
    }
}
