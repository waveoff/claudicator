import Foundation
import Security

enum TokenProviderError: LocalizedError {
    case keychainItemNotFound(OSStatus)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .keychainItemNotFound:
            return "Claude Code credentials were not found in Keychain. Please sign in to Claude Code and try again."
        case .invalidPayload:
            return "Claude Code credentials were found but could not be decoded."
        }
    }
}

struct ClaudeCredentials: Decodable {
    struct OAuthData: Decodable {
        let accessToken: String
        let expiresAt: TimeInterval?
        let subscriptionType: String?
    }

    let claudeAiOauth: OAuthData
}

final class ClaudeTokenProvider {
    static let shared = ClaudeTokenProvider()

    private let serviceName = "Claude Code-credentials"

    private init() {}

    func currentAccessToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            throw TokenProviderError.keychainItemNotFound(status)
        }

        guard let data = result as? Data,
              let payload = try? JSONDecoder().decode(ClaudeCredentials.self, from: data)
        else {
            throw TokenProviderError.invalidPayload
        }

        return payload.claudeAiOauth.accessToken
    }
}
