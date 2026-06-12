//
//  DocumentationModels.swift
//  loucede
//
//  Modèles de données de la documentation embarquée.
//
//  Historique : nés réseau (B.1, 2026-05-09 — proxy Scaleway → Notion),
//  basculés en lecture locale du bundle en Phase F.1 (2026-06-12) puis
//  purgés des reliquats proxy en F.3 : les modèles UI sont désormais
//  construits par `DocumentationService` depuis `manifest.json`, plus
//  aucun décodage réseau.
//

import Foundation

// MARK: - Page (liste)

/// Une entrée de la liste des tutos pour la sidebar, construite par
/// `DocumentationService.fetchList()` depuis le manifest (tri par
/// `sequence`, catégorie résolue en titre affichable).
///
/// `Identifiable` pour le `ForEach` de la sidebar ; `Equatable` pour
/// le `.onChange(of: manager.pages)` de la sélection initiale.
struct DocumentationPage: Identifiable, Equatable {
    /// Slug stable du tuto (ex. "01-bienvenue-dans-loucede"), dérivé
    /// du nom de fichier par le script. Clé de sélection sidebar et
    /// paramètre de `DocumentationService.fetchPage(id:)`.
    let id: String

    /// Titre affiché dans la sidebar.
    let title: String

    /// Emoji du tuto (ex. « 🤗 », « 🔑 »). Affiché à gauche du titre
    /// dans la sidebar et en header de page (bloc bleu).
    let icon: String?

    /// Titre de catégorie, emoji inclus (ex. « 🚀 Démarrer ») — résolu
    /// depuis `manifest.categories`. Matche le `categoryOrder` hardcodé
    /// de DocumentationView pour le groupement en sections.
    let category: String?

    /// Numéro Notion zero-padded (ex. "04"). Utilisé pour le tri des
    /// pages au sein d'une section (comparaison de strings, valide car
    /// zero-padded).
    let number: String?
}

// MARK: - Page (contenu)

/// Contenu Markdown d'un tuto, lu depuis `Documentation/tutos/*.md`
/// du bundle par `DocumentationService.fetchPage(id:)` (premier H1
/// retiré — le titre est porté par le header de page de la vue).
struct DocumentationPageContent: Equatable {
    /// Slug du tuto (même valeur que `DocumentationPage.id`).
    let id: String

    /// Titre du tuto (même valeur que `DocumentationPage.title`).
    let title: String

    /// Markdown intégral du tuto : titres `##`, listes, code blocks,
    /// liens, images `bundle://images/...` (rendues via
    /// `BundleImageProvider`).
    let markdown: String
}

// MARK: - Manifest local (Phase F.1)

/// Schéma de `Resources/Documentation/manifest.json`, produit par
/// `scripts/migrate-notion-docs.py`. Décodé avec
/// `keyDecodingStrategy = .convertFromSnakeCase` (les clés JSON sont
/// en snake_case : generated_at, notion_number, category_id…).
///
/// Interne à la couche données : le service mappe vers les modèles UI
/// (`DocumentationPage` / `DocumentationPageContent`), la vue ne
/// consomme jamais ces structs directement.
struct DocumentationManifest: Decodable {
    /// Version du schéma manifest (ex. "1.0").
    let version: String

    /// Horodatage ISO 8601 du run du script (clé `generated_at`).
    let generatedAt: String

    /// Nom du ZIP d'export Notion source (clé `source_zip`) — trace
    /// de provenance, non consommé par l'app.
    let sourceZip: String

    /// Catégories éditoriales, avec leur ordre canonique.
    let categories: [Category]

    /// Tutos publiés, dans l'ordre du script (re-triés par `sequence`
    /// côté service par robustesse).
    let tutos: [Tuto]

    struct Category: Decodable {
        /// Slug stable (ex. "demarrer").
        let id: String
        /// Titre affiché, emoji inclus (ex. "🚀 Démarrer") — matche le
        /// `categoryOrder` hardcodé de DocumentationView.
        let title: String
        /// Ordre canonique 1-based.
        let order: Int
    }

    struct Tuto: Decodable {
        /// Slug stable, dérivé du nom de fichier (ex.
        /// "01-bienvenue-dans-loucede"). Sert d'ID de sélection sidebar.
        let id: String
        /// Ordre global d'affichage (1-based, trous possibles si un
        /// tuto est dépublié — ex. le 02 « Installer loucedé »).
        let sequence: Int
        /// Numéro Notion zero-padded (clé `notion_number`, ex. "04").
        let notionNumber: String
        let title: String
        let emoji: String
        /// Référence `Category.id` (clé `category_id`).
        let categoryId: String
        /// Chemin relatif à `Documentation/` (ex. "tutos/01-….md").
        let file: String
        /// Chemins relatifs des images du tuto (non consommé : les
        /// `.md` portent leurs propres références `bundle://`).
        let images: [String]
    }
}

// MARK: - Erreurs

/// Erreurs typées de la couche documentation. Exposées par le service
/// au manager qui les traduit en états UI (vue d'erreur + bouton
/// « Réessayer »). Messages français lisibles utilisateur final.
///
/// F.3 : les 6 cas réseau de l'ère proxy (networkUnavailable,
/// proxyUnreachable, invalidAppSecret, invalidPageID, notionAPIError,
/// serverError) ont été supprimés avec la bascule en lecture locale —
/// en pratique ces erreurs ne peuvent plus se produire que par bundle
/// corrompu/désynchronisé, jamais par le réseau.
enum DocumentationError: LocalizedError, Equatable {
    /// Une ressource attendue manque au bundle (manifest.json ou
    /// fichier .md référencé par le manifest). Désync bundle/manifest
    /// — ne devrait pas arriver : le script génère les deux ensemble.
    case bundleResourceMissing(String)

    /// Le slug passé à `fetchPage(id:)` n'existe pas dans le manifest.
    /// En pratique l'utilisateur ne verra jamais ce cas (les ids
    /// viennent toujours de `fetchList()`).
    case notFound

    /// `manifest.json` n'est pas du JSON conforme au schéma
    /// `DocumentationManifest`. Probable évolution du script non
    /// synchronisée avec les structs Swift.
    case decodingFailed

    /// Cas non classé — le détail brut est conservé pour diagnostic.
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .bundleResourceMissing:
            return "Documentation embarquée introuvable. Réinstalle loucedé si ça persiste."
        case .notFound:
            return "Cette page de documentation est introuvable."
        case .decodingFailed:
            return "Documentation embarquée illisible. Réinstalle loucedé si ça persiste."
        case .unknown(let detail):
            return detail
        }
    }
}
