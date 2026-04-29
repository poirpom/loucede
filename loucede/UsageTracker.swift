//
//  UsageTracker.swift
//  loucede
//
//  Phase 7 (2026-04-29) : compteur d'utilisations totales (distinct du
//  trial counter). Incrémenté à chaque stream IA complété avec succès,
//  indépendamment du statut de licence.
//
//  Stockage UserDefaults :
//    - "loucede.usage.count"     → Int   (nombre de requêtes complètes)
//    - "loucede.usage.firstUseDate" → String ISO 8601 (date du 1er usage)
//
//  Note V2 (backlog) : migrer vers ObservableObject injecté via
//  environment plutôt que singleton — alignement avec LicenseManager.
//

import Foundation
import Combine

@MainActor
final class UsageTracker: ObservableObject {

    static let shared = UsageTracker()

    // MARK: - Clés UserDefaults

    private enum Keys {
        static let count       = "loucede.usage.count"
        static let firstUseDate = "loucede.usage.firstUseDate"
    }

    // MARK: - État publié

    @Published private(set) var count: Int
    @Published private(set) var firstUseDate: Date?

    // MARK: - Init

    private init() {
        count = UserDefaults.standard.integer(forKey: Keys.count)

        if let iso = UserDefaults.standard.string(forKey: Keys.firstUseDate) {
            firstUseDate = ISO8601DateFormatter().date(from: iso)
        } else {
            firstUseDate = nil
        }
    }

    // MARK: - API publique

    /// Incrémente le compteur et enregistre la date du premier usage si
    /// c'est le tout premier appel.
    func recordSuccessfulUse() {
        count += 1
        UserDefaults.standard.set(count, forKey: Keys.count)

        if firstUseDate == nil {
            let now = Date()
            firstUseDate = now
            UserDefaults.standard.set(
                ISO8601DateFormatter().string(from: now),
                forKey: Keys.firstUseDate
            )
        }
    }

    /// Format DD/MM/YYYY strict (pas de localisation système).
    func formattedFirstUseDate() -> String? {
        guard let date = firstUseDate else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "dd/MM/yyyy"
        return fmt.string(from: date)
    }
}
