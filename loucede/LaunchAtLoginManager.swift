//
//  LaunchAtLoginManager.swift
//  loucede
//
//  Wrapper autour de SMAppService (macOS 13+, API moderne pour les login
//  items). Centralise lecture/écriture pour que les vues n'aient pas à
//  importer ServiceManagement directement.
//
//  Phase 6.5a (2026-04-25) : toggle « Lancer au démarrage » côté Réglages.
//

import Foundation
import ServiceManagement
import os.log

@MainActor
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()
    private let logger = Logger(subsystem: "app.loucede.loucede", category: "LaunchAtLogin")

    private init() {}

    /// `true` si loucedé est actuellement enregistré comme login item du
    /// système. Fait un round-trip vers `SMAppService` à chaque appel —
    /// pas mis en cache car l'utilisateur peut désactiver depuis Réglages
    /// Système indépendamment de l'app, et on veut refléter l'état réel.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Active ou désactive le lancement automatique de loucedé à
    /// l'ouverture de session. Renvoie `true` si l'opération a réussi,
    /// `false` en cas d'erreur (cas rares : profil MDM bloquant, status
    /// `.requiresApproval` après désactivation manuelle, etc.).
    /// Idempotent : appeler avec la valeur déjà en place est un no-op.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                guard service.status != .enabled else { return true }
                try service.register()
            } else {
                guard service.status == .enabled else { return true }
                try service.unregister()
            }
            return true
        } catch {
            logger.error("setEnabled(\(enabled)) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
