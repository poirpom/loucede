//
//  PopupItem.swift
//  loucede
//
//  Phase K.1 — modèle d'items unifié pour la liste de la popup
//  principale. K.unify.3 (2026-05-21) : aligné sur le modèle unifié
//  (FAVORIS + catégories + Sans catégorie + Générateur). Une seule
//  sorte de ligne d'action (`.action(Action)`) ; plus de distinction
//  « action custom » vs « modèle catalogue » (le shim PromptSuggestion
//  et TemplatesView ont disparu).
//

import Foundation

/// Titre d'une section de la liste popup (en-tête non sélectionnable).
/// K.unify.3 : 9 sections — FAVORIS, les 6 catégories sémantiques, Sans
/// catégorie, et Générateur (mode recherche seul). Inbox 12/06 : +ACCÈS
/// RAPIDES (entrées système, toujours en dernier).
enum SectionTitle: String {
    case favorites = "FAVORIS"
    case translate = "TRADUIRE"
    case analyze = "ANALYSER"
    case extract = "EXTRAIRE"
    case transform = "TRANSFORMER"
    case structure = "STRUCTURER"
    case propose = "PROPOSER"
    case uncategorized = "SANS CATÉGORIE"
    case generator = "GÉNÉRATEUR"
    case quickAccess = "ACCÈS RAPIDES"

    /// En-tête correspondant à une catégorie sémantique. `nil` pour
    /// `.custom` (déprécié depuis K.unify.2, exclu de la popup — les
    /// actions éventuellement classées `.custom` retombent dans
    /// « Sans catégorie », cf. PopupItemBuilder).
    init?(category: PromptCategory) {
        switch category {
        case .translate: self = .translate
        case .analyze:   self = .analyze
        case .extract:   self = .extract
        case .transform: self = .transform
        case .structure: self = .structure
        case .propose:   self = .propose
        case .custom:    return nil
        }
    }
}

/// Entrée système « accès rapide » de la popup (inbox 12/06). Ce n'est
/// PAS une `Action` (ni prompt, ni catégorie, ni persistance, exclue de
/// Réglages → Actions) : elle ouvre une fenêtre de l'app. `CaseIterable`
/// porte l'ordre d'affichage (Réglages avant Doc).
enum QuickAccessItem: String, CaseIterable {
    case settings
    case doc

    var title: String { self == .settings ? "Réglages" : "Doc" }
    var icon: String  { self == .settings ? "⚙️" : "📖" }
    /// Onglet Réglages ciblé : Général (0) pour Réglages, Doc (5) pour Doc.
    var settingsTab: Int { self == .settings ? 0 : 5 }
}

/// Item unifié rendu dans la liste de la popup principale.
/// `sectionHeader` est purement visuel (non navigable au clavier) ;
/// `.action`, `.generator` et `.quickAccess` sont sélectionnables (↑/↓/↵/clic).
/// K.unify.3 : `.myAction` + `.modelSuggestion` fusionnés en `.action`.
enum PopupItem: Identifiable {
    case sectionHeader(SectionTitle)
    case action(Action)
    case generator
    case quickAccess(QuickAccessItem)

    var id: String {
        switch self {
        case .sectionHeader(let title): return "header-\(title.rawValue)"
        case .action(let action):       return "action-\(action.id.uuidString)"
        case .generator:                return "generator"
        case .quickAccess(let item):    return "quickaccess-\(item.rawValue)"
        }
    }

    /// `false` pour les en-têtes de section : la navigation clavier
    /// (↑/↓) et la sélection les ignorent.
    var isSelectable: Bool {
        switch self {
        case .sectionHeader:                    return false
        case .action, .generator, .quickAccess: return true
        }
    }
}

// MARK: - Builder unifié (K.unify.3)

/// Construit la liste d'items de la popup à partir du modèle unifié.
/// Logique PURE (aucun état SwiftUI) pour être réutilisée à la fois par
/// `PopoverView` (rendu) et `AppDelegate.calculatedPopoverHeight`
/// (mesure de hauteur) — source de vérité unique de la structure popup.
enum PopupItemBuilder {

    /// • Recherche vide (vue par défaut) : FAVORIS, puis chaque catégorie
    ///   non vide, puis Sans catégorie (si non vide). Pas de Générateur.
    ///   Actions masquées (`isHidden`) exclues. Tri par `displayOrder`.
    /// • Recherche active : FAVORIS matchant + catégories matchant + Sans
    ///   catégorie matchant (max 5 chacun, tri par score décroissant),
    ///   puis GÉNÉRATEUR (toujours visible). Les sections sans résultat
    ///   sont MASQUÉES (décision K.unify.3 — « Masquer si vide »). Pas de
    ///   duplication : un favori matchant n'apparaît que dans FAVORIS.
    static func build(actions: [Action], searchQuery rawQuery: String) -> [PopupItem] {
        let visible = actions.filter { !$0.isHidden }
        let q = rawQuery.trimmingCharacters(in: .whitespaces)
        var items = q.isEmpty ? buildDefault(visible) : buildSearch(visible, query: q)
        // Inbox 12/06 — ACCÈS RAPIDES toujours en DERNIER (après Générateur en
        // mode recherche, après Sans catégorie en mode défaut). Append centralisé
        // ici pour garantir cette position dans les deux modes.
        appendQuickAccess(query: q, to: &items)
        return items
    }

    // MARK: Vue par défaut (champ vide)

    private static func buildDefault(_ visible: [Action]) -> [PopupItem] {
        var items: [PopupItem] = []

        appendSection(.favorites, byOrder(visible.filter { $0.isFavorite }), to: &items)

        for category in PromptCategory.allCases {
            guard let title = SectionTitle(category: category) else { continue }
            let inCat = byOrder(visible.filter { !$0.isFavorite && $0.category == category })
            appendSection(title, inCat, to: &items)
        }

        appendSection(.uncategorized, byOrder(visible.filter { isUncategorized($0) }), to: &items)
        return items
    }

    // MARK: Vue recherche (champ rempli)

    private static func buildSearch(_ visible: [Action], query: String) -> [PopupItem] {
        var items: [PopupItem] = []
        let limit = 5

        appendSection(.favorites,
                      topMatches(visible.filter { $0.isFavorite }, query: query, limit: limit),
                      to: &items)

        for category in PromptCategory.allCases {
            guard let title = SectionTitle(category: category) else { continue }
            let inCat = topMatches(visible.filter { !$0.isFavorite && $0.category == category },
                                   query: query, limit: limit)
            appendSection(title, inCat, to: &items)
        }

        appendSection(.uncategorized,
                      topMatches(visible.filter { isUncategorized($0) }, query: query, limit: limit),
                      to: &items)

        // GÉNÉRATEUR — toujours visible en mode recherche (placeholder K.2).
        items.append(.sectionHeader(.generator))
        items.append(.generator)
        return items
    }

    // MARK: Helpers

    /// Action sans catégorie réelle : `nil` ou `.custom` (déprécié). Le
    /// `|| .custom` est défensif — aucun chemin actuel ne produit `.custom`,
    /// mais ça évite la disparition silencieuse d'une éventuelle valeur
    /// héritée du décodage Codable.
    private static func isUncategorized(_ action: Action) -> Bool {
        guard !action.isFavorite else { return false }
        return action.category == nil || action.category == .custom
    }

    /// Ajoute un en-tête + ses lignes uniquement si la section est non vide.
    private static func appendSection(_ title: SectionTitle, _ actions: [Action],
                                      to items: inout [PopupItem]) {
        guard !actions.isEmpty else { return }
        items.append(.sectionHeader(title))
        items += actions.map { .action($0) }
    }

    /// Inbox 12/06 — section ACCÈS RAPIDES (entrées système). Recherche vide :
    /// les 2 items. Recherche active : items dont le titre matche (même
    /// `ActionSearch.score` que les actions = basique `localizedStandardContains`
    /// tant que le fuzzy est off). Section masquée si aucun match (cohérent
    /// K.unify.3 « masquer si vide »).
    private static func appendQuickAccess(query: String, to items: inout [PopupItem]) {
        let matching = query.isEmpty
            ? QuickAccessItem.allCases
            : QuickAccessItem.allCases.filter { ActionSearch.score(query: query, against: $0.title) > 0 }
        guard !matching.isEmpty else { return }
        items.append(.sectionHeader(.quickAccess))
        items += matching.map { .quickAccess($0) }
    }

    private static func byOrder(_ pool: [Action]) -> [Action] {
        pool.sorted { $0.displayOrder < $1.displayOrder }
    }

    private static func topMatches(_ pool: [Action], query: String, limit: Int) -> [Action] {
        // K.4-lot2-fix-1 : chaînage découpé en étapes typées explicitement.
        // L'expression monolithique (map → tuple inféré → filter → sorted
        // → prefix → map) dépassait le budget d'inférence de types Swift
        // (« unable to type-check this expression in reasonable time »).
        // Le tuple nommé typé `[(action:, score:)]` lève l'ambiguïté.
        let scored: [(action: Action, score: Double)] = pool.map { action in
            (action, ActionSearch.score(query: query, against: action.name))
        }
        let matched: [(action: Action, score: Double)] = scored.filter { $0.score > 0 }
        // Tri par score décroissant, puis displayOrder croissant en tie-break.
        // En recherche basique (K.4) tous les scores valent 1.0 → l'ordre
        // devient celui du displayOrder (déterministe). En fuzzy, le score
        // prime, displayOrder ne sert qu'aux ex æquo.
        let sorted: [(action: Action, score: Double)] = matched.sorted { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score
                                   : lhs.action.displayOrder < rhs.action.displayOrder
        }
        return sorted.prefix(limit).map { $0.action }
    }
}
