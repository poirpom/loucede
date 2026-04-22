//
//  KeychainService.swift
//  loucede
//
//  Wrapper léger autour de Security.framework pour stocker les clés API
//  en Keychain plutôt qu'en clair dans UserDefaults (Phase 4.1a).
//
//  Usage :
//      KeychainService.save(account: "openai", value: "sk-...")
//      let key = KeychainService.read(account: "openai")
//      KeychainService.delete(account: "openai")
//
//  Sécurité :
//  - kSecClassGenericPassword : stockage standard mot de passe générique
//  - Un seul service : "app.loucede.loucede.apikey"
//  - Un account par provider : "openai", "anthropic", "mistral"
//  - Accessibilité : kSecAttrAccessibleAfterFirstUnlock
//    (disponible après le premier déverrouillage, y compris en arrière-plan)
//

import Foundation
import Security

enum KeychainService {

    /// Identifiant de service commun à toutes les entrées loucedé.
    /// Visible dans Trousseaux d'accès.app sous ce nom.
    private static let service = "app.loucede.loucede.apikey"

    // MARK: - Public API

    /// Enregistre (ou met à jour) la valeur associée à l'account donné.
    /// Retourne true si l'opération a réussi, false sinon.
    @discardableResult
    static func save(account: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Supprime l'éventuelle entrée existante avant d'ajouter — plus simple
        // qu'un SecItemUpdate conditionnel et couvre le cas "entrée absente".
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String]     = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Lit la valeur associée à l'account donné, ou `nil` si absente.
    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Supprime l'entrée correspondante. No-op si elle n'existait pas.
    /// Retourne true si supprimée ou inexistante, false sur vraie erreur.
    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
