//
//  ActionSearch.swift
//  loucede
//
//  Phase K.1 — recherche floue (fuzzy) des actions/modèles dans la
//  popup. Normalisation accents-insensitive + table de synonymes
//  EN→FR + noms natifs de langues, puis scoring (contains shortcut
//  + distance de Levenshtein avec seuil).
//
//  K.4-P2 (2026-05-22) — moteur fuzzy DÉSACTIVÉ au profit d'une
//  recherche basique `localizedStandardContains` (cf. `useFuzzySearch`).
//  Le code fuzzy K.1 reste présent et intact pour la future refonte
//  « Moteur fuzzy/sémantique propre » (cf. backlog).
//
//  ⚠️ Les clés ET valeurs de `synonyms` sont DÉJÀ normalisées
//  (minuscules + sans accents). La requête utilisateur est normalisée
//  de la même façon avant lookup → cohérence garantie.
//

import Foundation

enum ActionSearch {

    // MARK: - Mode de recherche (K.4-P2)

    /// K.4-P2 (2026-05-22) : le moteur fuzzy K.1 (synonymes + Levenshtein
    /// + normalisation custom) est DÉSACTIVÉ au profit d'une recherche
    /// basique `localizedStandardContains` (casse + accents gérés
    /// nativement, comportement prévisible). Le dogfooding avait révélé
    /// des faux positifs : « Traduis en russe » matchait toutes les
    /// actions de traduction (préfixe commun « Traduis en » trop fort,
    /// « russe » pas assez discriminant). En basique, aucun match →
    /// l'utilisateur tombe sur le Générateur (K.2), comportement attendu.
    /// Perte assumée : tolérance aux fautes de frappe.
    ///
    /// Flag DÉVELOPPEUR (pas une option utilisateur). Le code fuzzy reste
    /// présent et intact (`fuzzyScore` + `synonyms` + `levenshtein` +
    /// `normalize`) pour la future refonte « Moteur fuzzy/sémantique
    /// propre » (cf. backlog). Repasser à `true` réactive K.1.
    static let useFuzzySearch = false

    // MARK: - Table de synonymes (normalisée)

    /// Mappe une requête normalisée vers un terme FR normalisé.
    /// Couvre : noms natifs de langues, EN→FR usuels, concepts.
    static let synonyms: [String: String] = [
        // Langues — noms natifs + EN → FR
        "espanol": "espagnol",       // español (accents déjà retirés par normalize)
        "deutsch": "allemand",
        "italiano": "italien",
        "portugues": "portugais",
        "english": "anglais",
        "french": "francais",
        "german": "allemand",
        "spanish": "espagnol",
        "italian": "italien",
        "portuguese": "portugais",

        // Actions courantes EN → FR
        "summary": "resume",
        "summarize": "resume",
        "translate": "traduis",
        "translation": "traduis",
        "correct": "corrige",
        "fix": "corrige",
        "improve": "ameliore",
        "rewrite": "reformule",
        "reformulate": "reformule",
        "explain": "explique",
        "simplify": "simplifie",
        "format": "convertis",
        "table": "tableau",
        "outline": "plan",
        "todo": "todo",
        "checklist": "todo",
        "questions": "questions",
        "title": "titres",
        "titles": "titres",
        "headlines": "titres",

        // Concepts
        "mail": "email",
        "name": "noms",
        "names": "noms",
        "person": "noms",
        "people": "noms",
        "recipe": "recette",
        "cooking": "recette",
        "date": "dates",
    ]

    // MARK: - Normalisation

    /// minuscules + trim + suppression des diacritiques (é→e, ç→c…).
    static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
    }

    // MARK: - Scoring

    /// Score de pertinence de `query` contre `target`.
    /// K.4-P2 : route vers la recherche basique (V1) ou le moteur fuzzy
    /// (K.1, préservé) selon `useFuzzySearch`.
    /// 0 = pas de match. Basique : 1.0 si match, 0 sinon. Fuzzy :
    /// > 1 = match « contains » fort ; (0.5, 1] = proximité Levenshtein.
    static func score(query: String, against target: String) -> Double {
        useFuzzySearch ? fuzzyScore(query: query, against: target)
                       : basicScore(query: query, against: target)
    }

    /// K.4-P2 — recherche basique V1 : match binaire via
    /// `localizedStandardContains` (insensible casse + accents,
    /// locale-aware). Pas de scoring fin : soit ça matche, soit non.
    /// L'ordre d'affichage est porté par `displayOrder` (tie-break dans
    /// `PopupItemBuilder.topMatches`).
    private static func basicScore(query: String, against target: String) -> Double {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return 0 }
        return target.localizedStandardContains(q) ? 1.0 : 0.0
    }

    /// Moteur fuzzy K.1 — PRÉSERVÉ pour la future refonte (cf. backlog).
    /// Branche NON exécutée tant que `useFuzzySearch == false`.
    /// Synonymes (requête normalisée) → contains shortcut → Levenshtein.
    /// 0 = pas de match exploitable ; > 1 = match « contains » fort ;
    /// (0.5, 1] = proximité Levenshtein au-dessus du seuil.
    private static func fuzzyScore(query: String, against target: String) -> Double {
        let nq = normalize(query)
        let nt = normalize(target)
        guard !nq.isEmpty else { return 0 }

        // Expansion via synonymes (requête déjà normalisée).
        let q = synonyms[nq] ?? nq

        // Contains direct → gros bonus, proportionnel au recouvrement.
        if nt.contains(q) {
            return 1.0 + Double(q.count) / Double(max(nt.count, 1))
        }

        // Sinon : distance de Levenshtein, seuil de proximité.
        let distance = levenshtein(q, nt)
        let maxLen = max(q.count, nt.count)
        guard maxLen > 0, distance < maxLen else { return 0 }
        let proximity = 1.0 - Double(distance) / Double(maxLen)
        return proximity > 0.5 ? proximity : 0
    }

    // MARK: - Levenshtein

    /// Distance d'édition classique (insertions/suppressions/
    /// substitutions). Implémentation à 2 lignes de DP, O(n·m) temps,
    /// O(min(n,m)) mémoire — largement suffisant pour des noms courts.
    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }

        var prev = Array(0...y.count)
        var curr = [Int](repeating: 0, count: y.count + 1)

        for i in 1...x.count {
            curr[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                curr[j] = Swift.min(
                    prev[j] + 1,        // suppression
                    curr[j - 1] + 1,    // insertion
                    prev[j - 1] + cost  // substitution
                )
            }
            swap(&prev, &curr)
        }
        return prev[y.count]
    }
}
