//
//  KeychainService.swift
//  loucede
//
//  Wrapper léger autour de Security.framework. Deux espaces logiques,
//  dérivés du Bundle ID runtime (fallback littéral Release) :
//    - le service par défaut `<bundleID>.apikey` pour les clés API par
//      provider (Phase 4.1a)
//    - le sous-namespace `KeychainService.License` (service séparé
//      `<bundleID>.license`) pour la licence Polar.sh et le compteur du
//      trial gratuit (Phase 6.2, 2026-04-27)
//
//  Debug (`app.loucede.loucede.debug`) et Release (`app.loucede.loucede`)
//  ont donc des trousseaux distincts, sans migration en Release : le
//  service dérivé y est identique à l'ancien littéral hardcodé.
//
//  Sécurité commune :
//    - kSecClassGenericPassword
//    - kSecAttrAccessibleAfterFirstUnlock (disponible après le premier
//      déverrouillage du compte, y compris en arrière-plan)
//

import Foundation
import Security

enum KeychainService {

    /// Identifiant de service par défaut (clés API par provider).
    /// Visible dans Trousseaux d'accès.app sous ce nom.
    private static let apiKeyService = (Bundle.main.bundleIdentifier ?? "app.loucede.loucede") + ".apikey"

    // MARK: - Public API par défaut (service = clés API)

    @discardableResult
    static func save(account: String, value: String) -> Bool {
        save(service: apiKeyService, account: account, value: value)
    }

    static func read(account: String) -> String? {
        read(service: apiKeyService, account: account)
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        delete(service: apiKeyService, account: account)
    }

    // MARK: - Core paramétré (utilisé par le sous-namespace `License`)

    @discardableResult
    static func save(service: String, account: String, value: String) -> Bool {
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
        addQuery[kSecValueData as String]      = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func read(service: String, account: String) -> String? {
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

    @discardableResult
    static func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - License namespace (Phase 6.2)

extension KeychainService {

    /// Stockage Keychain dédié au système de licence Polar.sh.
    /// Service séparé (`<bundleID>.license`) pour isoler des
    /// clés API : la licence n'est pas un secret API, elle peut avoir
    /// des règles de backup différentes, et la séparation rend le
    /// debug plus simple dans Trousseaux d'accès.
    enum License {

        private static let service = (Bundle.main.bundleIdentifier ?? "app.loucede.loucede") + ".license"

        // MARK: - Accounts

        private static let keyAccount             = "loucede.license.key"
        private static let activationIdAccount    = "loucede.license.activationId"
        private static let licenseKeyIdAccount    = "loucede.license.licenseKeyId"
        private static let trialUsageCountAccount = "loucede.license.trialUsageCount"
        private static let lastValidatedAtAccount = "loucede.license.lastValidatedAt"
        private static let lastKnownStatusAccount = "loucede.license.lastKnownStatus"
        private static let customerEmailAccount   = "loucede.license.customerEmail"
        private static let heroNameAccount        = "loucede.license.heroName"

        // MARK: - Type-safe accessors

        /// La clé licence Polar (UUID). `nil` = pas de licence activée.
        static var key: String? {
            get { KeychainService.read(service: service, account: keyAccount) }
            set { setOrDelete(account: keyAccount, value: newValue) }
        }

        /// L'`activation_id` retourné par Polar lors du `/activate`.
        /// Nécessaire pour `/validate` et `/deactivate` ensuite.
        static var activationId: String? {
            get { KeychainService.read(service: service, account: activationIdAccount) }
            set { setOrDelete(account: activationIdAccount, value: newValue) }
        }

        /// L'`id` Polar de la licence (UUID, distinct de `key` et de
        /// `activationId`). Persisté au premier `/activate` réussi puis
        /// re-confirmé à chaque `/validate`. Utilisé par
        /// `LicenseService.getLicenseKey(id:)` pour récupérer la liste
        /// des activations (compteur X/Y dans Réglages → Licence +
        /// futur cross-device deactivate).
        ///
        /// Pour les utilisateurs pré-Session-3 (qui ont activé avant que
        /// ce code n'existe), cette valeur est `nil` au premier launch
        /// post-update. `LicenseManager.refreshActivations()` détecte
        /// ce cas et déclenche un `validate()` pour la peupler.
        static var licenseKeyId: String? {
            get { KeychainService.read(service: service, account: licenseKeyIdAccount) }
            set { setOrDelete(account: licenseKeyIdAccount, value: newValue) }
        }

        /// Compteur du trial gratuit (12 utilisations max). Stocké en
        /// Keychain et pas UserDefaults pour résister aux resets
        /// accidentels et aux outils de cleanup tierce-partie.
        static var trialUsageCount: Int {
            get {
                Int(KeychainService.read(service: service, account: trialUsageCountAccount) ?? "0") ?? 0
            }
            set {
                KeychainService.save(service: service, account: trialUsageCountAccount, value: String(newValue))
            }
        }

        /// Date de la dernière validation réussie côté Polar. Sert au
        /// mode offline : si dernière validation < 7 jours et status
        /// connu = granted, on considère la licence active même si
        /// le réseau est down. Stocké en `timeIntervalSince1970` pour
        /// éviter les soucis d'ISO8601.
        static var lastValidatedAt: Date? {
            get {
                guard let str = KeychainService.read(service: service, account: lastValidatedAtAccount),
                      let interval = TimeInterval(str) else {
                    return nil
                }
                return Date(timeIntervalSince1970: interval)
            }
            set {
                if let date = newValue {
                    KeychainService.save(service: service, account: lastValidatedAtAccount,
                                         value: String(date.timeIntervalSince1970))
                } else {
                    KeychainService.delete(service: service, account: lastValidatedAtAccount)
                }
            }
        }

        /// Dernier status connu côté Polar (raw value : `granted` /
        /// `revoked` / `disabled`). Sert au mode offline et au reload
        /// rapide du state au démarrage avant que validate ne réponde.
        static var lastKnownStatus: String? {
            get { KeychainService.read(service: service, account: lastKnownStatusAccount) }
            set { setOrDelete(account: lastKnownStatusAccount, value: newValue) }
        }

        /// Email du customer Polar. Affiché dans Réglages → Licence
        /// (« Activé pour user@example.com ») pour confirmer à
        /// l'utilisateur quel compte est lié.
        static var customerEmail: String? {
            get { KeychainService.read(service: service, account: customerEmailAccount) }
            set { setOrDelete(account: customerEmailAccount, value: newValue) }
        }

        /// Nom de super-héros généré une seule fois par le LLM
        /// configuré, à la demande de l'utilisateur (bouton « Obtenir
        /// mon nom » dans LicenseSettingsView). Sobriquet attribué
        /// arbitrairement, ne change jamais une fois généré. Wipe lors
        /// du `deactivate()` pour repartir sur un nom propre à la
        /// prochaine activation.
        static var heroName: String? {
            get { KeychainService.read(service: service, account: heroNameAccount) }
            set { setOrDelete(account: heroNameAccount, value: newValue) }
        }

        // MARK: - Cleanup

        /// Efface toutes les données de licence d'un coup. Utilisé par
        /// `LicenseManager.deactivate()` après succès du call API.
        ///
        /// Le trial counter est volontairement **conservé par défaut** :
        /// il a été consommé, pas question que la désactivation le
        /// reset. `includingTrialCounter: true` est réservé aux cas de
        /// reset complet (ex. bouton « Réinitialiser » DEBUG).
        static func wipe(includingTrialCounter: Bool = false) {
            KeychainService.delete(service: service, account: keyAccount)
            KeychainService.delete(service: service, account: activationIdAccount)
            KeychainService.delete(service: service, account: licenseKeyIdAccount)
            KeychainService.delete(service: service, account: lastValidatedAtAccount)
            KeychainService.delete(service: service, account: lastKnownStatusAccount)
            KeychainService.delete(service: service, account: customerEmailAccount)
            KeychainService.delete(service: service, account: heroNameAccount)
            if includingTrialCounter {
                KeychainService.delete(service: service, account: trialUsageCountAccount)
            }
        }

        // MARK: - Internals

        private static func setOrDelete(account: String, value: String?) {
            if let value {
                KeychainService.save(service: service, account: account, value: value)
            } else {
                KeychainService.delete(service: service, account: account)
            }
        }
    }
}
