//
//  DocumentationService.swift
//  loucede
//
//  Point 4 pre-V1 — Sous-étape B.1 (2026-05-09) : couche réseau de
//  l'intégration native de la documentation Notion.
//
//  Architecture (réutilise le proxy déjà en place pour Polar) :
//  loucedé ──[X-Loucede-App-Key]──▶ proxy Scaleway ──[Bearer NOTION_TOKEN]──▶ api.notion.com
//
//  Pattern symétrique avec `LicenseService.swift` :
//    - Singleton @MainActor avec init private
//    - URLSession custom (timeouts 15s/30s, no cache HTTP)
//    - JSONDecoder avec convertFromSnakeCase (inerte ici puisque les
//      clés sont déjà en camelCase côté proxy, mais conservé par
//      cohérence + filet défensif si schéma proxy évoluait)
//    - Helpers privés : buildRequest → sendOrThrow → validateStatusCode
//    - LicenseConfig.assertConfigured() en début de chaque méthode pub
//    - Erreurs typées en DocumentationError (cf. DocumentationModels.swift)
//
//  La classe ne gère AUCUN état : c'est une API stateless. La gestion
//  d'état (pages chargées, page courante, loading flags, errors UI)
//  est dans `DocumentationManager`.
//

import Foundation

@MainActor
final class DocumentationService {
    static let shared = DocumentationService()

    private let session: URLSession
    private let decoder: JSONDecoder

    /// Regex de validation d'un UUID v4 textuel (8-4-4-4-12 hex). Utilisé
    /// par `fetchPage(id:)` pour rejeter localement un ID malformé avant
    /// l'appel réseau (évite un round-trip serveur garanti d'échouer +
    /// retourne une erreur sémantique propre `invalidPageID`).
    private static let uuidRegex = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        // Pas de cache HTTP — quand l'utilisateur ouvre la doc, on veut
        // toujours la version Notion la plus à jour. La perf n'est pas
        // un enjeu (≤ 30 pages typiquement).
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config)

        let dec = JSONDecoder()
        // `convertFromSnakeCase` est inerte sur les schemas actuels (le
        // proxy renvoie déjà des clés camelCase) mais on conserve le
        // réglage par cohérence avec `LicenseService` et comme filet
        // défensif si le schéma proxy évoluait un jour vers snake_case.
        dec.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = dec
    }

    // MARK: - Public API

    /// Récupère la liste des pages de documentation publiées. Le proxy
    /// filtre côté serveur sur `Type = Utilisateur AND État = Terminé`
    /// et trie par `N° ASC` — l'app reçoit la liste prête à afficher.
    ///
    /// Renvoie un tableau vide si aucune page ne match les critères
    /// (cas légitime, pas une erreur).
    ///
    /// Erreurs possibles :
    ///   - `.networkUnavailable` (pas de connexion)
    ///   - `.proxyUnreachable` (DNS / 502)
    ///   - `.invalidAppSecret` (401 du proxy)
    ///   - `.notionAPIError(code:)` (4xx/5xx Notion forwardé)
    ///   - `.decodingFailed` / `.serverError` / `.unknown`
    func fetchList() async throws -> [DocumentationPage] {
        LicenseConfig.assertConfigured()
        let response: ListResponse = try await postExpectingJSON(
            path: "notion-list",
            body: nil
        )
        return response.pages
    }

    /// Récupère le contenu Markdown d'une page. Le proxy convertit le
    /// block Notion via `notion-to-md` côté serveur.
    ///
    /// `id` doit être un UUID valide (8-4-4-4-12 hex) — sinon levée
    /// locale de `.invalidPageID` sans appel réseau.
    ///
    /// Erreurs possibles :
    ///   - `.invalidPageID` (validation locale UUID)
    ///   - `.networkUnavailable` / `.proxyUnreachable` / `.invalidAppSecret`
    ///   - `.notFound` (404 Notion : page supprimée ou ID inconnu)
    ///   - `.notionAPIError(code:)` (autres 4xx/5xx Notion)
    ///   - `.decodingFailed` / `.serverError` / `.unknown`
    func fetchPage(id: String) async throws -> DocumentationPageContent {
        LicenseConfig.assertConfigured()
        guard id.range(of: Self.uuidRegex, options: .regularExpression) != nil else {
            throw DocumentationError.invalidPageID
        }
        // Le proxy Scaleway `/notion-page` attend `page_id` (convention
        // Notion API + contrat documenté dans `proxy/README.md` section
        // « Notion Docs » + `proxy/handler.js → handleNotionPage` qui lit
        // `body.page_id`). On garde `id` côté API Swift pour la
        // lisibilité au call site — la traduction se fait ici, à la
        // frontière réseau.
        return try await postExpectingJSON(
            path: "notion-page",
            body: ["page_id": id]
        )
    }

    // MARK: - Helpers réseau

    /// Wrapper générique pour les POST attendant une réponse JSON
    /// décodable. `body` peut être `nil` pour les endpoints sans
    /// paramètre (ex. `notion-list`).
    private func postExpectingJSON<R: Decodable>(path: String, body: [String: String]?) async throws -> R {
        let request = try buildRequest(path: path, body: body)
        let (data, response) = try await sendOrThrow(request: request)
        try validateStatusCode(response, body: data)
        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            throw DocumentationError.decodingFailed
        }
    }

    /// Construit la requête POST avec headers d'auth + body JSON.
    /// `body == nil` envoie un body JSON `{}` (le proxy accepte un body
    /// vide pour les endpoints sans paramètre).
    private func buildRequest(path: String, body: [String: String]?) throws -> URLRequest {
        let url = LicenseConfig.proxyBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(LicenseConfig.appSecret, forHTTPHeaderField: "X-Loucede-App-Key")
        let payload = body ?? [:]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    /// Mappe les `URLError` en `DocumentationError` typées. Identique
    /// au pattern de `LicenseService.sendOrThrow`.
    private func sendOrThrow(request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .timedOut,
                 .dataNotAllowed,
                 .internationalRoamingOff:
                throw DocumentationError.networkUnavailable
            case .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed:
                throw DocumentationError.proxyUnreachable
            default:
                throw DocumentationError.unknown(error.localizedDescription)
            }
        } catch {
            throw DocumentationError.unknown(error.localizedDescription)
        }
    }

    /// Mappe le status code HTTP vers une `DocumentationError` typée.
    /// 200 est succès. 4xx/5xx sont mappés selon la sémantique :
    ///   - 401 → invalidAppSecret (rejet du proxy)
    ///   - 404 → notFound (page Notion introuvable)
    ///   - 502 → proxyUnreachable (Notion injoignable depuis le proxy)
    ///   - autres 4xx → notionAPIError (forwardé tel quel)
    ///   - autres 5xx → serverError
    private func validateStatusCode(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw DocumentationError.unknown("Réponse non-HTTP")
        }
        switch http.statusCode {
        case 200:
            return
        case 401:
            throw DocumentationError.invalidAppSecret
        case 404:
            throw DocumentationError.notFound
        case 502:
            throw DocumentationError.proxyUnreachable
        case 400...499:
            // 4xx Notion non couverts ci-dessus (rate-limit 429,
            // forbidden 403, etc.) — forwardés tels quels.
            throw DocumentationError.notionAPIError(code: http.statusCode)
        case 500...599:
            throw DocumentationError.serverError(http.statusCode)
        default:
            throw DocumentationError.serverError(http.statusCode)
        }
    }
}

// MARK: - Wrapper de la réponse /notion-list

/// Le proxy renvoie `{ pages: [...] }` plutôt qu'un array brut, pour
/// permettre une éventuelle évolution future (pagination, métadonnées,
/// total count). Wrapper interne au service — le manager n'expose que
/// `[DocumentationPage]` à la UI.
private struct ListResponse: Decodable {
    let pages: [DocumentationPage]
}
