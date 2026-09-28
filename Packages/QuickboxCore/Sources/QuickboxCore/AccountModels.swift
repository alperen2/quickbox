import Foundation

/// The signed-in user's cloud account, as returned by `GET /mcp/account`.
public struct CloudAccount: Decodable, Equatable, Sendable {
    public let email: String?
    public let apps: [ConnectedApp]

    public init(email: String?, apps: [ConnectedApp]) {
        self.email = email
        self.apps = apps
    }
}

/// An app or agent the user allowed to use their inbox (one OAuth grant).
public struct ConnectedApp: Decodable, Equatable, Identifiable, Sendable {
    public let grantId: String
    public let name: String
    /// Milliseconds since the Unix epoch.
    public let connectedAt: Double
    public let isQuickboxApp: Bool
    public let isThisDevice: Bool

    public var id: String { grantId }
    public var connectedDate: Date { Date(timeIntervalSince1970: connectedAt / 1000) }

    public init(grantId: String, name: String, connectedAt: Double, isQuickboxApp: Bool, isThisDevice: Bool) {
        self.grantId = grantId
        self.name = name
        self.connectedAt = connectedAt
        self.isQuickboxApp = isQuickboxApp
        self.isThisDevice = isThisDevice
    }
}
