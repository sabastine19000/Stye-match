import Foundation
import Security

protocol LegacyProviderCredentialSecurityClient {
    func delete(_ query: [String: Any]) -> OSStatus
}

private struct SystemLegacyProviderCredentialSecurityClient: LegacyProviderCredentialSecurityClient {
    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

/// Retires the one historical beta credential without ever reading, copying,
/// or exposing it. This is intentionally the only remaining Keychain touch.
enum LegacyProviderCredentialRetirement {
    private static let completionKey = "legacyProviderCredentialRetirementV1Complete"
    static let legacyFallbackKey = "openAIAPIKeyForBetaTesting"

    static func run(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        defaults: UserDefaults = .standard,
        security: any LegacyProviderCredentialSecurityClient = SystemLegacyProviderCredentialSecurityClient()
    ) {
        guard defaults.bool(forKey: completionKey) == false else { return }

        let service = "\(bundleIdentifier ?? "stylematchai").openai"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "openai-api-key"
        ]
        let status = security.delete(query)
        guard status == errSecSuccess || status == errSecItemNotFound else { return }
        // This historical fallback is deleted without being read. It is kept
        // here, and only here, until an owner-device cleanup release removes
        // this transitional retirement helper.
        defaults.removeObject(forKey: legacyFallbackKey)
        defaults.set(true, forKey: completionKey)
    }
}
