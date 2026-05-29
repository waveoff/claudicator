import CryptoKit
import Foundation

/// OAuth constants extracted from the Claude Code CLI bundle. This is the
/// same public PKCE client `claude setup-token` uses.
enum OAuthConfig {
    static let clientID    = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authorizeURL = "https://claude.ai/oauth/authorize"
    static let tokenURL    = "https://console.anthropic.com/v1/oauth/token"
    static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    static let scopes      = "org:create_api_key user:profile user:inference"
}

/// Drives the manual (paste-code) OAuth PKCE flow:
/// 1. `beginAuthorization()` → open the returned URL in the browser
/// 2. user authorizes, copies the code shown on the callback page
/// 3. `exchange(pastedCode:)` → trades it for tokens, stored in Keychain
/// 4. `validAccessToken()` → returns a fresh token, refreshing if expired
///
/// Tokens are cached in memory after the first Keychain read so we don't hit
/// the Keychain (and trigger an OS password prompt) on every 90s poll.
final class OAuthService {
    static let shared = OAuthService()
    private init() {}

    private var pendingVerifier: String?
    private var pendingState: String?

    /// In-memory cache of the Keychain tokens. `false`-y until first load.
    private var cached: OAuthTokens?
    private var didLoadFromKeychain = false

    private func currentTokens() -> OAuthTokens? {
        if didLoadFromKeychain { return cached }
        Log.auth.debug("Reading tokens from Keychain (first access this session)")
        cached = KeychainStore.load()
        didLoadFromKeychain = true
        Log.auth.debug("Keychain read \(self.cached == nil ? "found nothing" : "found tokens")")
        return cached
    }

    private func store(_ tokens: OAuthTokens) throws {
        try KeychainStore.save(tokens)
        cached = tokens
        didLoadFromKeychain = true
        Log.auth.debug("Saved tokens to Keychain")
    }

    var isConnected: Bool { currentTokens() != nil }
    var subscriptionType: String? { currentTokens()?.subscriptionType }

    // MARK: Step 1 — build authorize URL

    func beginAuthorization() -> URL {
        let verifier  = Self.randomURLSafe(32)
        let challenge = Self.codeChallenge(for: verifier)
        let state     = Self.randomURLSafe(32)
        pendingVerifier = verifier
        pendingState    = state

        var comps = URLComponents(string: OAuthConfig.authorizeURL)!
        comps.queryItems = [
            .init(name: "code",                  value: "true"),
            .init(name: "client_id",             value: OAuthConfig.clientID),
            .init(name: "response_type",         value: "code"),
            .init(name: "redirect_uri",          value: OAuthConfig.redirectURI),
            .init(name: "scope",                 value: OAuthConfig.scopes),
            .init(name: "code_challenge",        value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state",                 value: state)
        ]
        Log.auth.info("Begin authorization, opening browser")
        return comps.url!
    }

    // MARK: Step 2 — exchange pasted code

    func exchange(pastedCode raw: String) async throws -> OAuthTokens {
        guard let verifier = pendingVerifier else {
            throw err("Click “Open authorization page” first.")
        }
        // The callback page shows the code as "<code>#<state>".
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts   = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
        let code    = parts.first ?? trimmed
        let state   = parts.count > 1 ? parts[1] : (pendingState ?? "")

        Log.auth.info("Exchanging authorization code for tokens")
        let tokens = try await postToken([
            "grant_type":    "authorization_code",
            "code":          code,
            "state":         state,
            "client_id":     OAuthConfig.clientID,
            "redirect_uri":  OAuthConfig.redirectURI,
            "code_verifier": verifier
        ])
        try store(tokens)
        pendingVerifier = nil
        pendingState    = nil
        Log.auth.info("Connected. subscription=\(tokens.subscriptionType ?? "unknown", privacy: .public)")
        return tokens
    }

    // MARK: Token access + refresh

    func validAccessToken() async throws -> String {
        guard let tokens = currentTokens() else {
            throw err("Not connected. Click Connect to sign in.")
        }
        // Refresh if expiring within 60s and we have a refresh token.
        if let exp = tokens.expiresAt, exp.timeIntervalSinceNow < 60,
           let refresh = tokens.refreshToken {
            Log.auth.info("Access token expiring, refreshing")
            let refreshed = try await postToken([
                "grant_type":    "refresh_token",
                "refresh_token": refresh,
                "client_id":     OAuthConfig.clientID
            ])
            // Preserve refresh token / subscription if the response omits them.
            let merged = OAuthTokens(
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken ?? tokens.refreshToken,
                expiresAt: refreshed.expiresAt,
                subscriptionType: refreshed.subscriptionType ?? tokens.subscriptionType
            )
            try store(merged)
            return merged.accessToken
        }
        return tokens.accessToken
    }

    func disconnect() {
        KeychainStore.clear()
        cached = nil
        didLoadFromKeychain = true
        Log.auth.info("Disconnected, cleared tokens")
    }

    // MARK: Networking

    private func postToken(_ body: [String: Any]) async throws -> OAuthTokens {
        var request = URLRequest(url: URL(string: OAuthConfig.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw err("No HTTP response from token endpoint.")
        }
        Log.auth.debug("Token endpoint responded HTTP \(http.statusCode)")
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Log.auth.error("Token request failed: HTTP \(http.statusCode) \(msg.prefix(160), privacy: .public)")
            throw err("Token request failed (HTTP \(http.statusCode)): \(msg.prefix(160))")
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
            let scope: String?
            let account: Account?
            struct Account: Decodable { let subscription_type: String? }
        }
        let r = try JSONDecoder().decode(TokenResponse.self, from: data)
        return OAuthTokens(
            accessToken: r.access_token,
            refreshToken: r.refresh_token,
            expiresAt: r.expires_in.map { Date().addingTimeInterval($0) },
            subscriptionType: r.account?.subscription_type
        )
    }

    // MARK: PKCE helpers

    private static func randomURLSafe(_ byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private func err(_ message: String) -> NSError {
        NSError(domain: "OAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
