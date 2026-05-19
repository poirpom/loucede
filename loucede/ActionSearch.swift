//
//  ActionSearch.swift
//  loucede
//
//  Phase K.1 — recherche floue (fuzzy) des actions/modèles dans la
//  popup. Normalisation accents-insensitive + table de synonymes
//  EN→FR + noms natifs de langues, puis scoring (contains shortcut
//  + distance de Levenshtein avec seuil).
//
//  ⚠️ Les clés ET valeurs de `synonyms` sont DÉJÀ normalisées
//  (minuscules + sans accents). La requête utilisateur est normalisée
//  de la même façon avant lookup → cohérence garantie.
//

import Foundation

enum ActionSearch {

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
    /// 0 = pas de match exploitable ; > 1 = match « contains » fort ;
    /// (0.5, 1] = proximité Levenshtein au-dessus du seuil.
    static func score(query: String, against target: String) -> Double {
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
