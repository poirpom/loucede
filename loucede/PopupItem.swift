//
//  PopupItem.swift
//  loucede
//
//  Phase K.1 — modèle d'items unifié pour la liste de la popup
//  principale. Permet d'afficher dans une même liste filtrée :
//  les actions custom de l'utilisateur, les modèles du catalogue
//  proposés, le placeholder du Générateur (K.2), et les en-têtes
//  de section (non sélectionnables).
//

import Foundation

/// Titre d'une section de la liste popup (en-tête non sélectionnable).
enum SectionTitle: String {
    case myActions = "MES ACTIONS"
    case models = "MODÈLES"
    case generator = "GÉNÉRATEUR"
}

/// Item unifié rendu dans la liste de la popup principale.
/// `sectionHeader` est purement visuel (non navigable au clavier) ;
/// les autres cas sont sélectionnables (↑/↓/↵/clic).
enum PopupItem: Identifiable {
    case sectionHeader(SectionTitle)
    case myAction(Action)
    case modelSuggestion(PromptSuggestion)
    case generator

    var id: String {
        switch self {
        case .sectionHeader(let title): return "header-\(title.rawValue)"
        case .myAction(let action):     return "my-\(action.id.uuidString)"
        case .modelSuggestion(let s):   return "model-\(s.id.uuidString)"
        case .generator:                return "generator"
        }
    }

    /// `false` pour les en-têtes de section : la navigation clavier
    /// (↑/↓) et la sélection les ignorent.
    var isSelectable: Bool {
        switch self {
        case .sectionHeader:                       return false
        case .myAction, .modelSuggestion, .generator: return true
        }
    }
}
