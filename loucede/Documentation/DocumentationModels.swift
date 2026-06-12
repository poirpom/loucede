//
//  DocumentationModels.swift
//  loucede
//
//  Point 4 pre-V1 — Sous-étape B.1 (2026-05-09) : modèles de données
//  pour l'intégration native de la documentation Notion.
//
//  Backend Scaleway proxy (déjà déployé, cf. commits 1f6dddb + c95914f) :
//    - POST /notion-list  → { pages: [DocumentationPage, ...] }
//    - POST /notion-page  → DocumentationPageContent
//
//  Pattern symétrique avec `LicenseService.swift` :
//    - Models = structs Decodable côté client
//    - Erreurs typées en enum LocalizedError + Equatable
//    - Messages français lisibles utilisateur final
//

import Foundation

// MARK: - Page (liste)

/// Une entrée de la liste des tutos publiés (réponse de
/// `POST /notion-list`). Le proxy filtre déjà côté serveur sur
/// `Type = Utilisateur AND État = Terminé` et trie par `N° ASC` —
/// l'app reçoit la liste prête à afficher dans la sidebar.
///
/// Tous les champs hors `id` et `title` sont optionnels : si l'auteur
/// Notion n'a pas rempli un attribut (icon vide, pas de cover, etc.),
/// le proxy renvoie `null` et le décodage Swift le reflète en `nil`.
///
/// `Identifiable` permet d'utiliser `ForEach` directement dans
/// les vues SwiftUI à venir (sous-étape B.4 sidebar).
struct DocumentationPage: Decodable, Identifiable, Equatable {
    /// UUID Notion de la page. Utilisé comme clé pour
    /// `DocumentationService.fetchPage(id:)`.
    let id: String

    /// Titre affiché dans la sidebar.
    let title: String

    /// Description courte (≤ ~200 signes) affichée sous le titre dans
    /// la sidebar quand fourni. Champ Notion `Résumé`.
    let summary: String?

    /// Emoji de l'icône Notion (ex. « 👋 », « ⚙️ »). Affiché à gauche
    /// du titre dans la sidebar quand fourni.
    let icon: String?

    /// URL de la cover image Notion. Réservé pour la sous-étape B.4
    /// (polish sidebar avec covers + emojis).
    let cover: String?

    /// Catégorie Notion (ex. « 🚀 Démarrer », « 🎯 Maîtriser »).
    /// Réservé pour un éventuel groupement par section dans la sidebar.
    let category: String?

    /// Niveau de difficulté Notion (ex. « Débutant », « Intermédiaire »).
    /// Réservé pour un éventuel filtre / badge.
    let level: String?

    /// Priorité Notion (ex. « Haute », « Moyenne »).
    let priority: String?

    /// Numéro d'ordre Notion (string brute — peut contenir des points
    /// pour des sous-numéros « 1.2 »). Utilisé côté proxy pour le tri ;
    /// pas re-trié côté Swift.
    let number: String?
}

// MARK: - Page (contenu)

/// Contenu Markdown d'une page (réponse de `POST /notion-page`). Le
/// proxy convertit le block Notion en Markdown via `notion-to-md` côté
/// serveur — l'app reçoit du texte prêt à rendre via `swift-markdown-ui`
/// (sous-étape B.3 polish rendu).
struct DocumentationPageContent: Decodable, Equatable {
    /// UUID Notion de la page (même valeur que `DocumentationPage.id`
    /// utilisée pour la requête).
    let id: String

    /// Titre de la page (même valeur que `DocumentationPage.title`).
    /// Conservé dans la réponse pour permettre au consommateur de
    /// l'afficher sans re-fetcher la liste.
    let title: String

    /// Contenu intégral de la page converti en Markdown. Peut contenir
    /// titres `##`, listes, code blocks, liens, images (chemin direct
    /// notion-static.com), etc. — selon ce que l'auteur a écrit côté
    /// Notion.
    let markdown: String
}

// MARK: - Manifest local (Phase F.1)

/// Schéma de `Resources/Documentation/manifest.json`, produit par
/// `scripts/migrate-notion-docs.py`. Décodé avec
/// `keyDecodingStrategy = .convertFromSnakeCase` (les clés JSON sont
/// en snake_case : generated_at, notion_number, category_id…).
///
/// Interne à la couche données : le service mappe vers les modèles UI
/// historiques (`DocumentationPage` / `DocumentationPageContent`),
/// la vue ne consomme jamais ces structs directement.
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
/// au manager qui les traduit ensuite en états UI (banderole d'erreur,
/// retry button, etc.). Messages français lisibles utilisateur final
/// — pas de jargon technique exposé en surface.
///
/// Pattern symétrique avec `LicenseError`.
///
/// Note F.1 : depuis la bascule en lecture locale, seuls
/// `.bundleResourceMissing`, `.notFound` et `.decodingFailed` sont
/// encore levés. Les cas réseau restent déclarés mais inertes —
/// suppression au cleanup F.3 (avec le code proxy doc).
enum DocumentationError: LocalizedError, Equatable {
    /// Une ressource attendue manque au bundle (manifest.json ou
    /// fichier .md référencé par le manifest). Désync bundle/manifest
    /// — ne devrait pas arriver : le script génère les deux ensemble.
    case bundleResourceMissing(String)

    /// Le device n'a pas de connexion (Wi-Fi off, mode avion…).
    case networkUnavailable

    /// DNS / connexion impossible vers le proxy Scaleway, ou le proxy
    /// a renvoyé 502 (Notion injoignable depuis le proxy).
    case proxyUnreachable

    /// Le proxy Scaleway a rejeté en 401 : le secret partagé
    /// `LicenseConfig.appSecret` ne matche pas le `LOUCEDE_APP_SECRET`
    /// côté env vars Scaleway. Probable config oubliée ou rotation
    /// côté serveur sans release de l'app.
    case invalidAppSecret

    /// L'`id` passé à `fetchPage(id:)` n'est pas un UUID valide. En
    /// pratique l'utilisateur ne verra jamais ce cas (les IDs viennent
    /// toujours de `fetchList()` qui retourne des UUIDs valides côté
    /// Notion) — c'est un filet pour le debug long-terme et pour
    /// éviter un round-trip serveur garanti d'échouer.
    case invalidPageID

    /// La page Notion n'existe pas (404 du proxy / Notion). Soit la
    /// page a été supprimée côté Notion, soit son ID est invalide
    /// (mais formé correctement — sinon `invalidPageID` serait levé
    /// avant l'appel réseau).
    case notFound

    /// Erreur Notion forwardée par le proxy (4xx/5xx Notion API).
    /// Le détail HTTP est conservé dans `code` pour faciliter le debug
    /// dans les logs côté Scaleway.
    case notionAPIError(code: Int)

    /// Erreur HTTP 5xx générique non couverte (ni Notion ni proxy).
    case serverError(Int)

    /// Le body retourné n'est pas du JSON parseable au schéma attendu.
    /// Probable changement de format côté proxy non synchronisé avec
    /// les models Swift.
    case decodingFailed

    /// Cas non classé — le détail brut est conservé pour diagnostic.
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .bundleResourceMissing:
            return "Documentation embarquée introuvable. Réinstalle loucedé si ça persiste."
        case .networkUnavailable:
            return "Pas de connexion réseau. Réessaie une fois connecté."
        case .proxyUnreachable:
            return "Service de documentation injoignable. Réessaie dans un instant."
        case .invalidAppSecret:
            return "Configuration interne invalide. Si ça persiste, contacte le support."
        case .invalidPageID:
            return "Identifiant de page invalide."
        case .notFound:
            return "Cette page de documentation est introuvable."
        case .notionAPIError(let code):
            return "Erreur Notion (\(code)). Réessaie plus tard."
        case .serverError(let code):
            return "Erreur serveur (\(code)). Réessaie plus tard."
        case .decodingFailed:
            return "Réponse serveur incompréhensible."
        case .unknown(let detail):
            return detail
        }
    }
}
