//
//  DocumentationView.swift
//  loucede
//
//  Point 4 pre-V1 — Sous-étape B.3 (2026-05-09) : sidebar bindée aux
//  vraies données via `DocumentationManager.shared` (fetch /notion-list
//  côté proxy Scaleway). Mock data interne retiré.
//
//  Étape progressive de l'incrément B :
//    B.1 ✅ — DocumentationModels + Service + Manager (foundation Swift)
//    B.2 ✅ — Layout 2 colonnes avec données mockées
//    B.3 — Binding au DocumentationManager.shared (CE FICHIER)
//    B.4 — Rendu Markdown du contenu via swift-markdown-ui
//
//  4 états visuels gérés par `sidebarContent` (priorité décroissante) :
//    1. Loading : ProgressView centré (~500ms typique)
//    2. Error : icône + message + détail localisé + bouton « Réessayer »
//    3. Empty : sidebar naturellement vide + message zone droite
//       (cas très rare — Faab a dépublié tous les tutos Notion)
//    4. Loaded : List avec sections groupées par catégorie + tri par N°
//
//  Sélection par défaut robuste via `.onChange(of: manager.pages)` :
//    - Init au premier remplissage : set sur la première page de la
//      première section (categoryOrder + N° ASC).
//    - Correction si refresh ramène un set différent où la sélection
//      actuelle a disparu : fallback sur la première page disponible.
//    - Sinon (sélection toujours présente après refresh) : préservée.
//
//  À noter : à ce stade la zone contenu n'affiche que le titre — le
//  rendu Markdown réel viendra en B.4.
//

import SwiftUI

struct DocumentationView: View {
    /// ID de la page actuellement sélectionnée dans la sidebar. `nil`
    /// avant la première arrivée de pages depuis le manager. Lié au
    /// `selection` du `List` via le `.tag(page.id)` de chaque ligne.
    /// Initialisé/corrigé par `.onChange(of: manager.pages)`.
    @State private var selectedPageID: String?

    /// Manager de la documentation (singleton). Observé pour réagir
    /// aux changements de `pages`, `isLoadingList`, `listError`.
    /// Pattern `@ObservedObject` (et non `@StateObject`) car la durée
    /// de vie du singleton est gérée par l'app, pas par cette vue.
    @ObservedObject private var manager = DocumentationManager.shared

    // Note pivot UX (2026-05-09) : on n'utilise PAS de custom toolbar
    // (`ToolbarItem(.navigation)` + `@State columnVisibility` +
    // `.toolbar(removing: .sidebarToggle)`) pour forcer la position du
    // bouton de toggle sidebar. Tentative initiale (commit `35e4fbc`)
    // a échoué runtime : l'API `.toolbar(removing: .sidebarToggle)` ne
    // supprime pas le bouton natif quand le `NavigationSplitView` est
    // hosté dans une `NSWindow` AppKit via `NSHostingView` (probable
    // interaction avec le NSToolbar implicite du `[.titled]` styleMask).
    //
    // Pivot pragmatique : on cache le titre dans la titlebar AppKit
    // côté `loucedeApp.swift:openDocumentation()` via
    // `titleVisibility = .hidden` + `titlebarAppearsTransparent = true`,
    // pattern cohérent avec les fenêtres Settings et Onboarding du
    // projet. Le bouton natif continue de « voyager » selon l'état de
    // la sidebar, mais n'a plus rien à chevaucher. Le titre AppKit
    // reste dans `window.title` (visible dans le Dock, Cmd+Tab et
    // menu Window — juste plus dans la titlebar).
    //
    // NE PAS retenter `.toolbar(removing: .sidebarToggle)` ici sans
    // d'abord vérifier que SwiftUI a corrigé le bug ou qu'on a basculé
    // hors NSHostingView. L'invariant à préserver : « bouton de toggle
    // ne tronque rien » (assuré par titlebar transparente sans titre).

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(280)
        } detail: {
            detailContent
        }
        .task {
            // `.task` est lié au cycle de vie de la vue, pas à l'ouverture
            // de fenêtre. Avec `isReleasedWhenClosed = false` côté
            // `loucedeApp.swift:openDocumentation()`, la vue persiste entre
            // les ouvertures (juste cachée via `orderOut`) — le `.task` ne
            // re-fire pas typiquement. L'utilisateur a le bouton
            // « Réessayer » côté `errorView` pour forcer un refresh, et
            // la liste ne change pas plusieurs fois par session en
            // pratique. Si feedback runtime montre le besoin d'un
            // refresh systématique sur ouverture de fenêtre, on
            // ajoutera un trigger explicite dans `openDocumentation()`.
            await manager.loadList()
        }
        .onChange(of: manager.pages) { _, _ in
            // Double rôle :
            //   1. Init au premier remplissage (selectedPageID == nil)
            //      → set sur la première page de la première section.
            //   2. Correction si refresh ramène un set différent où la
            //      sélection actuelle a disparu (page supprimée côté
            //      Notion entre 2 fetches) → fallback sur la première
            //      page disponible.
            // Si la sélection est toujours présente après refresh, on
            // ne touche à rien (pas de scroll/changement surprise).
            let newOrdered = orderedPages
            if selectedPageID == nil || !newOrdered.contains(where: { $0.id == selectedPageID }) {
                selectedPageID = newOrdered.first?.id
            }
        }
    }

    // MARK: - Sidebar content (4 états visuels)

    @ViewBuilder
    private var sidebarContent: some View {
        if manager.isLoadingList {
            // État 1 : Loading — ProgressView centré, pas de message
            // texte (l'attente est ~500ms en pratique).
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = manager.listError {
            // État 2 : Error — vue dédiée avec bouton « Réessayer ».
            errorView(message: error.errorDescription ?? "Erreur inconnue.")
        } else {
            // État 4 : Loaded (couvre aussi l'état 3 « Empty » — la
            // List est juste vide, pas de message dans la sidebar car
            // le message empty s'affiche dans la zone droite).
            List(selection: $selectedPageID) {
                ForEach(orderedSections, id: \.name) { section in
                    Section(section.name) {
                        ForEach(section.pages) { page in
                            sidebarRow(page: page)
                                .tag(page.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    /// Vue d'erreur de la sidebar : icône + message principal +
    /// détail localisé (`DocumentationError.errorDescription`) +
    /// bouton « Réessayer » qui re-déclenche `loadList()`.
    @ViewBuilder
    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Impossible de charger la documentation")
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Réessayer") {
                Task { await manager.loadList() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail content

    @ViewBuilder
    private var detailContent: some View {
        Group {
            // Empty state légitime : succès du fetch mais 0 page
            // (cas très rare — Faab a dépublié tous les tutos Notion
            // temporairement). Message dans la zone droite, pas dans
            // la sidebar (cohérent avec « zone détail = comprendre
            // l'état »).
            if !manager.isLoadingList && manager.listError == nil && manager.pages.isEmpty {
                Text("Aucun tuto disponible pour le moment")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let page = selectedPage {
                // B.3 (mock detail) : titre seul. B.4 remplacera par
                // le Markdown rendu via swift-markdown-ui.
                VStack(alignment: .leading, spacing: 0) {
                    Text(page.title)
                        .font(.system(size: 32, weight: .bold))
                        .padding(.horizontal, 32)
                        .padding(.top, 32)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                // Pendant loading initial / avant onChange initial /
                // pendant état error : pas de placeholder explicite
                // pour éviter un flash de texte pendant le bootstrap.
                Color.clear
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Sidebar row

    /// Ligne de la sidebar : emoji icône (si fourni) + titre. Style
    /// natif macOS Source list — pas de styling custom.
    @ViewBuilder
    private func sidebarRow(page: DocumentationPage) -> some View {
        HStack(spacing: 8) {
            if let icon = page.icon, !icon.isEmpty {
                Text(icon)
                    .font(.system(size: 14))
            }
            Text(page.title)
                .lineLimit(1)
        }
    }

    // MARK: - Computed helpers

    /// Pages groupées par catégorie depuis `manager.pages` (B.3 : data
    /// réelle remplace le mock B.2). Les pages dont `category` est `nil`
    /// (cas légitime côté Notion si l'auteur a oublié) sont regroupées
    /// sous une clé vide qui ne figurera pas dans `categoryOrder` —
    /// elles seront donc filtrées par le `compactMap` ci-dessous.
    private var pagesByCategory: [String: [DocumentationPage]] {
        Dictionary(grouping: manager.pages, by: { $0.category ?? "" })
    }

    /// Sections dans l'ordre éditorial canonique. Chaque section
    /// contient ses pages triées par `number` ASC. Les catégories sans
    /// page sont filtrées (compactMap retourne nil). Les pages dont la
    /// catégorie n'est PAS dans `categoryOrder` sont silencieusement
    /// omises — décision V1 MVP (Faab contrôle totalement les
    /// catégories Notion via la BDD ; si une nouvelle catégorie
    /// apparaît, elle est ignorée jusqu'à mise à jour de l'array).
    private var orderedSections: [(name: String, pages: [DocumentationPage])] {
        Self.categoryOrder.compactMap { categoryName -> (name: String, pages: [DocumentationPage])? in
            guard let pages = pagesByCategory[categoryName], !pages.isEmpty else { return nil }
            // Tri par `number` ASC. Comparaison de strings — fonctionne
            // sur les numéros zero-padded ("01", "02", ..., "11")
            // garantis par le proxy Scaleway côté serveur.
            let sorted = pages.sorted { ($0.number ?? "") < ($1.number ?? "") }
            return (categoryName, sorted)
        }
    }

    /// Pages aplaties dans l'ordre d'affichage final (sections triées,
    /// puis pages triées par number ASC dans chaque section). Utilisée
    /// par `.onChange(of: manager.pages)` pour la sélection initiale
    /// et la correction post-refresh.
    private var orderedPages: [DocumentationPage] {
        orderedSections.flatMap { $0.pages }
    }

    /// Page actuellement sélectionnée, lookupée par ID dans
    /// `manager.pages`. `nil` avant la première sélection ou si la
    /// page a disparu après un refresh (le `.onChange` corrigera
    /// `selectedPageID` au prochain cycle).
    private var selectedPage: DocumentationPage? {
        guard let id = selectedPageID else { return nil }
        return manager.pages.first { $0.id == id }
    }

    // MARK: - Configuration éditoriale

    /// Ordre canonique des catégories de documentation, défini par Faab.
    /// Source de vérité pour le tri des sections de la sidebar. Les
    /// catégories non listées ici sont filtrées (cf. `orderedSections`)
    /// — V1 MVP, à enrichir si Faab ajoute de nouvelles catégories
    /// côté Notion.
    private static let categoryOrder: [String] = [
        "🚀 Démarrer",
        "🔧 Configurer loucedé",
        "💡 loucedé au quotidien",
        "💳 Compte et licence",
        "🛠️ Résolution de problèmes",
        "📚 Ressources"
    ]
}

// MARK: - Preview

#Preview {
    DocumentationView()
        .frame(width: 900, height: 700)
}
