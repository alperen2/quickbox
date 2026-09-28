import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import QuickboxCore
import Security

nonisolated enum CloudConfiguration {
    /// Production endpoint. `defaults write alperen.quickbox quickbox.cloudBaseURL http://localhost:8787` overrides it for development.
    static var baseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "quickbox.cloudBaseURL"), let url = URL(string: override) {
            return url
        }
        return URL(string: "https://api.usepigeon.cc")!
    }
}

/// Published by the server at `/app/config`: everything needed to start OAuth as the quickbox app.
nonisolated struct AppCloudConfig: Decodable, Sendable {
    let clientId: String
    let redirectUri: String
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let resource: String
    let scope: String
}

nonisolated struct CloudTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    /// The server that issued them. Tokens are bound to that server's resource, so they are
    /// useless after a move to another address. `nil` for tokens saved before this was recorded.
    let origin: String?
}

enum CloudAuthError: LocalizedError, Equatable {
    case cancelled
    case invalidCallback
    case signedOut
    case server(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Sign-in was cancelled."
        case .invalidCallback: return "Sign-in could not be completed. Please try again."
        case .signedOut: return "Your \(Brand.cloudName) session ended. Connect again in Settings."
        case .server(let message): return "\(Brand.cloudName): \(message)"
        }
    }
}

protocol CloudTokenStoring {
    func load() -> CloudTokens?
    func save(_ tokens: CloudTokens)
    func clear()
}

/// Tokens live in the user's keychain, never in preferences or files.
final class KeychainTokenStore: CloudTokenStoring {
    private let service = "alperen.quickbox.cloud"
    private let account = "tokens"

    func load() -> CloudTokens? {
        var result: AnyObject?
        let status = SecItemCopyMatching(query(returningData: true) as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(CloudTokens.self, from: data)
    }

    func save(_ tokens: CloudTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let status = SecItemUpdate(query() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query()
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(query() as CFDictionary)
    }

    private func query(returningData: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if returningData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }
}

protocol WebAuthenticating {
    /// Opens `url` in a browser sheet and returns the callback URL with the given scheme.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

final class WebAuthenticationSessionRunner: NSObject, WebAuthenticating, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: CloudAuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? CloudAuthError.invalidCallback)
                }
            }
            session.presentationContextProvider = self
            self.session = session
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

/// OAuth 2.1 authorization code + PKCE as the quickbox app, with token refresh.
final class CloudAuthenticator {
    private let baseURL: URL
    private let urlSession: URLSession
    private let tokenStore: CloudTokenStoring
    private let web: WebAuthenticating
    private let now: () -> Date
    private var config: AppCloudConfig?

    init(
        baseURL: URL = CloudConfiguration.baseURL,
        urlSession: URLSession = .shared,
        tokenStore: CloudTokenStoring = KeychainTokenStore(),
        web: WebAuthenticating = WebAuthenticationSessionRunner(),
        now: @escaping () -> Date = Date.init
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.tokenStore = tokenStore
        self.web = web
        self.now = now
    }

    var isSignedIn: Bool { storedTokens() != nil }

    /// Signed in to a server at another address, e.g. before the cloud moved to its own domain.
    var hasSessionFromAnotherServer: Bool { tokenStore.load() != nil && storedTokens() == nil }

    func signIn() async throws {
        let config = try await appConfig()
        let verifier = Self.randomURLSafeString(bytes: 32)
        let state = Self.randomURLSafeString(bytes: 16)

        var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectUri),
            URLQueryItem(name: "scope", value: config.scope),
            URLQueryItem(name: "resource", value: config.resource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        let scheme = URL(string: config.redirectUri)?.scheme ?? "quickbox"
        let callback = try await web.authenticate(url: components.url!, callbackScheme: scheme)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first(where: { $0.name == name })?.value }

        if value("error") == "access_denied" { throw CloudAuthError.cancelled }
        guard value("state") == state, let code = value("code") else { throw CloudAuthError.invalidCallback }

        try await requestTokens([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectUri,
            "client_id": config.clientId,
            "code_verifier": verifier,
            "resource": config.resource,
        ])
    }

    /// A valid access token, refreshed shortly before it expires.
    func accessToken() async throws -> String {
        guard let tokens = storedTokens() else { throw CloudAuthError.signedOut }
        if tokens.expiresAt.timeIntervalSince(now()) > 60 { return tokens.accessToken }
        return try await refresh()
    }

    @discardableResult
    func refresh() async throws -> String {
        guard let tokens = storedTokens() else { throw CloudAuthError.signedOut }
        let config = try await appConfig()
        return try await requestTokens([
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": config.clientId,
        ])
    }

    func signOut() {
        tokenStore.clear()
    }

    /// Tokens issued by this server. Ones from another address (the server moved) count as signed out,
    /// so the user connects again instead of hitting authorization errors.
    private func storedTokens() -> CloudTokens? {
        guard let tokens = tokenStore.load(), tokens.origin == baseURL.absoluteString else { return nil }
        return tokens
    }

    private func appConfig() async throws -> AppCloudConfig {
        if let config { return config }
        let (data, response) = try await urlSession.data(from: baseURL.appendingPathComponent("app/config"))
        try Self.ensureSuccess(response, data: data)
        let config = try JSONDecoder().decode(AppCloudConfig.self, from: data)
        self.config = config
        return config
    }

    @discardableResult
    private func requestTokens(_ form: [String: String]) async throws -> String {
        let config = try await appConfig()
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((body.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)

        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 400 || http.statusCode == 401,
           let failure = try? JSONDecoder().decode(OAuthFailure.self, from: data), failure.error == "invalid_grant" {
            // The grant was revoked or expired: the user has to connect again.
            tokenStore.clear()
            throw CloudAuthError.signedOut
        }
        try Self.ensureSuccess(response, data: data)

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        let previousRefresh = storedTokens()?.refreshToken
        guard let refreshToken = token.refresh_token ?? previousRefresh else { throw CloudAuthError.invalidCallback }
        tokenStore.save(CloudTokens(
            accessToken: token.access_token,
            refreshToken: refreshToken,
            expiresAt: now().addingTimeInterval(TimeInterval(token.expires_in ?? 3600)),
            origin: baseURL.absoluteString
        ))
        return token.access_token
    }

    static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func randomURLSafeString(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func ensureSuccess(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw CloudAuthError.server("No response") }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ServerError.self, from: data))?.error ?? "HTTP \(http.statusCode)"
            throw CloudAuthError.server(message)
        }
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int?
    }

    private struct OAuthFailure: Decodable {
        let error: String
    }

    private struct ServerError: Decodable {
        let error: String
    }
}

protocol CloudAccountAPI {
    func account() async throws -> CloudAccount
    func disconnectApp(grantID: String) async throws
    /// Deletes the account and every cloud copy of the user's tasks and notes.
    func deleteAccount() async throws
}

/// The quickbox apps' HTTP API (sync and account management), authenticated with the app's access token.
final class CloudHTTPClient: CloudSyncAPI, CloudAccountAPI {
    private let baseURL: URL
    private let authenticator: CloudAuthenticator
    private let urlSession: URLSession

    init(baseURL: URL = CloudConfiguration.baseURL, authenticator: CloudAuthenticator, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.authenticator = authenticator
        self.urlSession = urlSession
    }

    func changes(since cursor: Int) async throws -> ChangesResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("mcp/sync/changes"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "cursor", value: String(cursor))]
        let data = try await send(URLRequest(url: components.url!))
        return try JSONDecoder().decode(ChangesResponse.self, from: data)
    }

    func push(_ pushRequest: PushRequest) async throws -> PushResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("mcp/sync/push"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(pushRequest)
        return try JSONDecoder().decode(PushResponse.self, from: try await send(request))
    }

    func account() async throws -> CloudAccount {
        try JSONDecoder().decode(CloudAccount.self, from: try await send(URLRequest(url: baseURL.appendingPathComponent("mcp/account"))))
    }

    func disconnectApp(grantID: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("mcp/account/apps").appendingPathComponent(grantID))
        request.httpMethod = "DELETE"
        _ = try await send(request)
    }

    func deleteAccount() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("mcp/account/delete"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"confirm":"DELETE"}"#.utf8)
        _ = try await send(request)
    }

    /// Retries once with a refreshed token if the access token was rejected.
    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.setValue("Bearer \(try await authenticator.accessToken())", forHTTPHeaderField: "Authorization")
        var (data, response) = try await urlSession.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            request.setValue("Bearer \(try await authenticator.refresh())", forHTTPHeaderField: "Authorization")
            (data, response) = try await urlSession.data(for: request)
        }
        try CloudAuthenticator.ensureSuccess(response, data: data)
        return data
    }
}
