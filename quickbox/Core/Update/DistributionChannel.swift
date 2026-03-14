import Foundation

enum DistributionChannel: String, Sendable {
    case direct
    case appStore

    var supportsInAppUpdates: Bool {
        self == .direct
    }

    static var current: DistributionChannel {
        guard
            let rawValue = Bundle.main.object(forInfoDictionaryKey: "QBDistributionChannel") as? String,
            let channel = DistributionChannel(rawValue: rawValue)
        else {
            return .direct
        }
        return channel
    }
}
