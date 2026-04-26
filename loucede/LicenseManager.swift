//
//  LicenseManager.swift
//  loucede
//
//  Stub pour la Phase 6.2 (système de licence Creem.io). En attendant
//  l'implémentation complète, expose `hasLicense` qui sera utilisée par
//  les fonctionnalités license-gated (ex. envoi de suggestion).
//
//  Phase 6.16 (2026-04-26) : création du stub. `hasLicense` retourne
//  `true` pour permettre à toutes les builds de tester librement les
//  features qui dépendront de la licence en V1. Sera étendu en 6.2.
//

import Foundation

@MainActor
final class LicenseManager {
    static let shared = LicenseManager()

    /// `true` si l'utilisateur dispose d'une licence active. Déterminera
    /// l'accès aux fonctionnalités payantes (Phase 6.2).
    ///
    /// V1 stub : retourne toujours `true` — les UIs license-gated sont en
    /// place (boutons grisés, sheet bloquée…) mais la gate elle-même est
    /// désactivée pendant le développement. La logique réelle (clé
    /// Creem.io stockée Keychain + activation device + vérif au lancement)
    /// arrivera en Phase 6.2.
    ///
    /// Quand 6.2 sera implémentée, cette classe conformera à
    /// `ObservableObject` et exposera `@Published var hasLicense: Bool`
    /// pour que les vues react automatiquement aux changements (achat,
    /// expiration, désactivation).
    var hasLicense: Bool {
        // TODO Phase 6.2 : remplacer par lecture Keychain + validation
        // de la clé Creem.io + check device activation.
        true
    }

    private init() {}
}
