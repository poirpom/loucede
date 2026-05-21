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
/// K.unify.3 : 9 sections possibles — FAVORIS, les 6 catégories
/// sémantiques, Sans catégorie, et Générateur (mode recherche seul).
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

/// Item unifié rendu dans la liste de la popup principale.
/// `sectionHeader` est purement visuel (non navigable au clavier) ;
/// `.action` et `.generator` sont sélectionnables (↑/↓/↵/clic).
/// K.unify.3 : `.myAction` + `.modelSuggestion` fusionnés en `.action`.
enum PopupItem: Identifiable {
    case sectionHeader(SectionTitle)
    case action(Action)
    case generator

    var id: String {
        switch self {
        case .sectionHeader(let title): return "header-\(title.rawValue)"
        case .action(let action):       return "action-\(action.id.uuidString)"
        case .generator:                return "generator"
        }
    }

    /// `false` pour les en-têtes de section : la navigation clavier
    /// (↑/↓) et la sélection les ignorent.
    var isSelectable: Bool {
        switch self {
        case .sectionHeader:      return false
        case .action, .generator: return true
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
        return q.isEmpty ? buildDefault(visible) : buildSearch(visible, query: q)
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

    private static func byOrder(_ pool: [Action]) -> [Action] {
        pool.sorted { $0.displayOrder < $1.displayOrder }
    }

    private static func topMatches(_ pool: [Action], query: String, limit: Int) -> [Action] {
        pool.map { ($0, ActionSearch.score(query: query, against: $0.name)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }
}
