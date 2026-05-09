//
//  DocumentationManager.swift
//  loucede
//
//  Point 4 pre-V1 — Sous-étape B.1 (2026-05-09) : gestion d'état de
//  l'intégration native de la documentation Notion.
//
//  Pattern symétrique avec `LicenseManager` :
//    - Singleton @MainActor + ObservableObject
//    - @Published properties pour binding SwiftUI
//    - Délègue le réseau à `DocumentationService` (stateless)
//    - Gère les loading flags + les erreurs UI
//
//  Décision MVP V1 : pas de cache. Chaque `loadList()` / `loadPage(id:)`
//  re-fetche depuis le proxy. Les pages restent peu nombreuses (≤ ~30
//  prévues) et le proxy a déjà du cache HTTP côté serveur — pas de
//  besoin urgent d'un cache client. À reconsidérer post-V1 si la doc
//  grandit ou si feedback utilisateur sur la latence.
//

import Foundation
import Combine

@MainActor
final class DocumentationManager: ObservableObject {
    static let shared = DocumentationManager()

    /// Liste des pages publiées, peuplée par `loadList()`. Vide tant
    /// que la première fetch n'a pas réussi. Reset à chaque nouvelle
    /// fetch pour ne pas afficher des données stales en cas d'erreur.
    @Published var pages: [DocumentationPage] = []

    /// Contenu de la page actuellement sélectionnée, peuplée par
    /// `loadPage(id:)`. `nil` quand aucune page n'a encore été chargée
    /// ou quand la dernière fetch a échoué. La UI peut afficher un
    /// empty state (« Sélectionne une page ») dans ce cas.
    @Published var currentPage: DocumentationPageContent?

    /// `true` pendant un `loadList()` en cours. La UI peut afficher un
    /// loader / spinner sur la sidebar pendant ce temps.
    @Published var isLoadingList: Bool = false

    /// `true` pendant un `loadPage(id:)` en cours. La UI peut afficher
    /// un loader sur la zone de contenu pendant ce temps.
    @Published var isLoadingPage: Bool = false

    /// Erreur de la dernière `loadList()`, ou `nil` si succès / pas
    /// encore tenté. Reset à `nil` au début de chaque nouvelle fetch.
    @Published var listError: DocumentationError?

    /// Erreur de la dernière `loadPage(id:)`, ou `nil` si succès /
    /// pas encore tenté. Reset à `nil` au début de chaque nouvelle fetch.
    @Published var pageError: DocumentationError?

    private let service: DocumentationService

    private init() {
        self.service = DocumentationService.shared
    }

    // MARK: - Public API

    /// Fetch la liste des pages publiées. Met à jour `pages`,
    /// `isLoadingList` et `listError`. Pas d'exception levée — toutes
    /// les erreurs sont stockées dans `listError` pour être consommées
    /// par la UI.
    ///
    /// Décision MVP : pas de cache. Chaque appel re-fetche, même si
    /// `pages` était déjà peuplée d'un précédent succès. À l'usage la
    /// UI appellera typiquement cette méthode une fois à l'ouverture
    /// de la fenêtre doc et au pull-to-refresh manuel (si introduit).
    func loadList() async {
        isLoadingList = true
        listError = nil
        defer { isLoadingList = false }

        do {
            self.pages = try await service.fetchList()
        } catch let error as DocumentationError {
            self.listError = error
            self.pages = []
        } catch {
            self.listError = .unknown(error.localizedDescription)
            self.pages = []
        }
    }

    /// Fetch le contenu d'une page. Met à jour `currentPage`,
    /// `isLoadingPage` et `pageError`. Pas d'exception levée — toutes
    /// les erreurs sont stockées dans `pageError` pour la UI.
    ///
    /// `id` doit être un UUID — sinon `DocumentationService.fetchPage`
    /// lève `.invalidPageID` qu'on capture et stocke dans `pageError`.
    func loadPage(id: String) async {
        isLoadingPage = true
        pageError = nil
        defer { isLoadingPage = false }

        do {
            self.currentPage = try await service.fetchPage(id: id)
        } catch let error as DocumentationError {
            self.pageError = error
            self.currentPage = nil
        } catch {
            self.pageError = .unknown(error.localizedDescription)
            self.currentPage = nil
        }
    }
}
