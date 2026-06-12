//
//  DocumentationService.swift
//  loucede
//
//  Phase F.1 (2026-06-12) : bascule de la lecture réseau (proxy Scaleway
//  → Notion) vers la lecture locale du bundle. La documentation vit dans
//  `Resources/Documentation/` (folder reference, hiérarchie préservée
//  dans le bundle) : `manifest.json` + `tutos/*.md` + `images/*`,
//  générés par `scripts/migrate-notion-docs.py`.
//
//  Architecture conservée de l'ère réseau (B.1, 2026-05-09) :
//    - Singleton @MainActor avec init private
//    - API publique inchangée : `fetchList()` / `fetchPage(id:)`,
//      async throws — le manager et la vue ne voient aucune différence.
//      (async sans await désormais : signature préservée pour ne pas
//      toucher les call sites ; la lecture disque de fichiers de
//      quelques Ko sur le main actor est négligeable.)
//    - Erreurs typées DocumentationError (cf. DocumentationModels.swift)
//
//  Mapping manifest → modèles UI (la vue consomme les modèles
//  historiques, inchangés en F.1) :
//    - id ← tuto.id (slug, ex. "01-bienvenue-dans-loucede" — plus un
//      UUID Notion : la validation UUID de l'ère réseau a été retirée)
//    - icon ← emoji · category ← titre résolu via manifest.categories
//    - number ← notionNumber (strings zero-padded, le tri string de
//      DocumentationView reste valide)
//
//  La classe reste stateless — la gestion d'état (pages chargées, page
//  courante, loading flags, errors UI) est dans `DocumentationManager`.
//

import Foundation

@MainActor
final class DocumentationService {
    static let shared = DocumentationService()

    private let decoder: JSONDecoder

    /// Racine de la doc dans le bundle : `Contents/Resources/Documentation/`.
    /// `nil` théoriquement impossible (folder reference embarquée au build)
    /// — traité en `bundleResourceMissing` par les méthodes publiques.
    private var documentationRoot: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Documentation", isDirectory: true)
    }

    private init() {
        let dec = JSONDecoder()
        // Le manifest est en snake_case (generated_at, notion_number,
        // category_id…) — produit par le script Python. La conversion
        // automatique évite les CodingKeys manuelles.
        dec.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = dec
    }

    // MARK: - Public API

    /// Liste des tutos du manifest, triés par `sequence` ASC, mappés
    /// vers `DocumentationPage` (modèle UI historique).
    ///
    /// Erreurs possibles :
    ///   - `.bundleResourceMissing` (manifest.json absent du bundle)
    ///   - `.decodingFailed` (manifest non conforme au schéma)
    func fetchList() async throws -> [DocumentationPage] {
        let manifest = try loadManifest()
        let categoryTitles = Dictionary(
            uniqueKeysWithValues: manifest.categories.map { ($0.id, $0.title) }
        )
        return manifest.tutos
            .sorted { $0.sequence < $1.sequence }
            .map { tuto in
                DocumentationPage(
                    id: tuto.id,
                    title: tuto.title,
                    icon: tuto.emoji,
                    category: categoryTitles[tuto.categoryId],
                    number: tuto.notionNumber
                )
            }
    }

    /// Contenu Markdown d'un tuto, lu depuis `Documentation/<tuto.file>`.
    ///
    /// Erreurs possibles :
    ///   - `.notFound` (slug absent du manifest)
    ///   - `.bundleResourceMissing` (fichier .md absent du bundle —
    ///     désync manifest/fichiers, ne devrait pas arriver : le script
    ///     génère les deux ensemble)
    ///   - `.decodingFailed` (manifest non conforme)
    func fetchPage(id: String) async throws -> DocumentationPageContent {
        let manifest = try loadManifest()
        guard let tuto = manifest.tutos.first(where: { $0.id == id }) else {
            throw DocumentationError.notFound
        }
        guard let root = documentationRoot else {
            throw DocumentationError.bundleResourceMissing("Documentation/")
        }
        let fileURL = root.appendingPathComponent(tuto.file)
        guard let markdown = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw DocumentationError.bundleResourceMissing(tuto.file)
        }
        return DocumentationPageContent(
            id: tuto.id,
            title: tuto.title,
            markdown: Self.strippingLeadingTitle(markdown)
        )
    }

    /// Le script de migration écrit le titre du tuto en H1 en tête de
    /// chaque `.md` — la vue l'affiche déjà via son `pageHeader` (bloc
    /// bleu + titre 32pt), ce qui le doublonnait à l'écran (runtime F.3
    /// C1). Le bundle étant généré (hors scope côté app), on retire ce
    /// premier H1 au chargement. Strictement la première ligne + les
    /// lignes vides qui suivent — les H1 éventuels en cours de document
    /// sont préservés.
    private static func strippingLeadingTitle(_ markdown: String) -> String {
        var lines = markdown.components(separatedBy: "\n")
        guard let first = lines.first, first.hasPrefix("# ") else { return markdown }
        lines.removeFirst()
        while let next = lines.first,
              next.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Manifest

    /// Lit et décode `Documentation/manifest.json` depuis le bundle.
    /// Pas de cache : relu à chaque appel — fichier de quelques Ko,
    /// cohérent avec la décision « pas de cache » du manager (B.1).
    private func loadManifest() throws -> DocumentationManifest {
        guard let root = documentationRoot else {
            throw DocumentationError.bundleResourceMissing("Documentation/")
        }
        let manifestURL = root.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw DocumentationError.bundleResourceMissing("manifest.json")
        }
        do {
            return try decoder.decode(DocumentationManifest.self, from: data)
        } catch {
            throw DocumentationError.decodingFailed
        }
    }
}
