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
//    - "loucede.usage.perAction" → JSON [String: Int] (K.4-lot3, L2 —
//      compteur par action, clé = action.id.uuidString ; sans UI en V1)
//
//  K.4-lot3 (2026-05-22) : L1 (moyenne quotidienne, cf.
//  `formattedDailyAverage()`) + L2 (comptage par action, cf.
//  `recordActionUse(actionID:)`).
//
//  Note V2 (backlog) : migrer vers ObservableObject injecté via
//  environment plutôt que singleton — alignement avec LicenseManager.
//

import Foundation
import Combine

/// Tokens cumulés (entrée + sortie) pour un modèle donné. Persisté en JSON
/// dans `tokensByModel` (Phase L.3). Accumulatif, sans reset en V1.
struct TokenCounts: Codable {
    var input: Int
    var output: Int
}

@MainActor
final class UsageTracker: ObservableObject {

    static let shared = UsageTracker()

    // MARK: - Clés UserDefaults

    private enum Keys {
        static let count       = "loucede.usage.count"
        static let firstUseDate = "loucede.usage.firstUseDate"
        static let perAction   = "loucede.usage.perAction"   // K.4-lot3 (L2)
        static let tokensByModel = "loucede.usage.tokensByModel" // Phase L.3
    }

    // MARK: - État publié

    @Published private(set) var count: Int
    @Published private(set) var firstUseDate: Date?

    // MARK: - L.3 : tokens cumulés par modèle (Phase L)

    /// Tokens cumulés par modelId (clé = `AIModel.id`). `@Published` (à la
    /// différence de `perActionCount`) car la carte « Coût estimé » des
    /// Réglages (L.5) en dépend et doit réagir en temps réel. Persisté JSON
    /// sous `Keys.tokensByModel`.
    @Published private(set) var tokensByModel: [String: TokenCounts] = [:]

    // MARK: - L2 : comptage par action (K.4-lot3)

    /// Compteur par action (clé = `action.id.uuidString`, valeur = nombre
    /// d'exécutions réussies). PAS de `@Published` : aucune UI en V1 —
    /// collecte silencieuse, l'affichage viendra en V1.x/V2. Persisté en
    /// JSON sous `Keys.perAction`.
    private var perActionCount: [String: Int]

    // MARK: - Init

    private init() {
        count = UserDefaults.standard.integer(forKey: Keys.count)

        if let iso = UserDefaults.standard.string(forKey: Keys.firstUseDate) {
            firstUseDate = ISO8601DateFormatter().date(from: iso)
        } else {
            firstUseDate = nil
        }

        // L2 : chargement du dico par action (vide si absent ou JSON illisible).
        if let data = UserDefaults.standard.data(forKey: Keys.perAction),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            perActionCount = decoded
        } else {
            perActionCount = [:]
        }

        // L.3 : chargement des tokens par modèle (vide si absent/illisible).
        if let data = UserDefaults.standard.data(forKey: Keys.tokensByModel),
           let decoded = try? JSONDecoder().decode([String: TokenCounts].self, from: data) {
            tokensByModel = decoded
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

    // MARK: - L1 : moyenne quotidienne (K.4-lot3)

    /// Moyenne d'utilisation par jour, formatée FR (1 décimale, virgule).
    /// `nil` si aucune donnée exploitable (`count == 0` ou `firstUseDate`
    /// absente) → l'appelant n'affiche alors pas la phrase.
    ///
    /// Diviseur = jours calendaires écoulés depuis `firstUseDate` + 1
    /// (jour courant inclus, K.4-lot3 décision A) : évite la division par
    /// zéro le 1er jour et donne une sémantique « nb de jours
    /// d'utilisation, jour courant compris ». Jours comptés en jours
    /// calendaires via `startOfDay` (décision B), pas en intervalles 24 h.
    /// Le `max(1, …)` est purement défensif (dérive d'horloge éventuelle).
    func formattedDailyAverage() -> String? {
        guard count > 0, let first = firstUseDate else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: first),
                                      to: cal.startOfDay(for: Date())).day ?? 0
        let divisor = max(1, days + 1)
        let average = Double(count) / Double(divisor)

        let fmt = NumberFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.numberStyle = .decimal
        fmt.minimumFractionDigits = 1
        fmt.maximumFractionDigits = 1
        return fmt.string(from: NSNumber(value: average))
    }

    // MARK: - L2 : comptage par action (K.4-lot3)

    /// Incrémente le compteur d'usage de l'action `actionID` (clé =
    /// `uuidString`), crée l'entrée à 1 si absente, puis persiste en JSON.
    /// Appelé en même temps que `recordSuccessfulUse()` (un stream réussi
    /// = +1 total ET +1 par action). Pas d'UI en V1.
    func recordActionUse(actionID: UUID) {
        perActionCount[actionID.uuidString, default: 0] += 1
        if let data = try? JSONEncoder().encode(perActionCount) {
            UserDefaults.standard.set(data, forKey: Keys.perAction)
        }
    }

    // MARK: - L.3 : tokens par modèle (Phase L)

    /// Accumule les tokens d'un stream réussi pour `modelId` (crée l'entrée
    /// à 0 si absente), puis persiste. Appelé via le callback `onUsage` de
    /// `chatStream` (L.2), une seule fois par stream terminé. La mutation de
    /// `tokensByModel` (@Published) déclenche le re-render de la carte coût.
    func recordTokens(modelId: String, input: Int, output: Int) {
        var counts = tokensByModel[modelId] ?? TokenCounts(input: 0, output: 0)
        counts.input += input
        counts.output += output
        tokensByModel[modelId] = counts
        if let data = try? JSONEncoder().encode(tokensByModel) {
            UserDefaults.standard.set(data, forKey: Keys.tokensByModel)
        }
    }
}
