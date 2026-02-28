import Foundation

protocol UpdateManaging {
    func start()
    func checkForUpdates() throws
    func setAutoCheck(_ enabled: Bool)
    func setBetaChannel(_ enabled: Bool)
}

enum UpdateError: LocalizedError {
    case updateCheckUnavailable

    var errorDescription: String? {
        switch self {
        case .updateCheckUnavailable:
            return "Update check is currently unavailable."
        }
    }
}
