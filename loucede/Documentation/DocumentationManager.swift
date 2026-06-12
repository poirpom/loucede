//
//  DocumentationManager.swift
//  loucede
//
//  Gestion d'état de la documentation embarquée (né B.1 2026-05-09 à
//  l'ère proxy Notion, inchangé à la bascule locale F.1 2026-06-12 —
//  seule la sémantique des erreurs a suivi).
//
//  Pattern symétrique avec `LicenseManager` :
//    - Singleton @MainActor + ObservableObject
//    - @Published properties pour binding SwiftUI
//    - Délègue la lecture du bundle à `DocumentationService` (stateless)
//    - Gère les loading flags + les erreurs UI
//
//  Pas de cache : chaque `loadList()` / `loadPage(id:)` relit le bundle
//  — lecture locale de fichiers de quelques Ko, instantanée.
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

    /// Charge la liste des tutos depuis le manifest du bundle. Met à
    /// jour `pages`, `isLoadingList` et `listError`. Pas d'exception
    /// levée — toutes les erreurs sont stockées dans `listError` pour
    /// être consommées par la UI. Appelée par le `.task` de
    /// `DocumentationView` à chaque entrée dans l'onglet Doc.
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

    /// Charge le contenu Markdown d'un tuto (par slug manifest). Met à
    /// jour `currentPage`, `isLoadingPage` et `pageError`. Pas
    /// d'exception levée — toutes les erreurs sont stockées dans
    /// `pageError` pour la UI.
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
