//
//  DocumentationView.swift
//  loucede
//
//  Point 4 pre-V1 — Sous-étape B.2 (2026-05-09) : layout 2 colonnes
//  via `NavigationSplitView` natif macOS 13+. Sidebar 280pt avec liste
//  des tutos groupée par catégorie (Source list style), zone détail à
//  droite affichant pour l'instant le titre du tuto sélectionné.
//
//  Étape progressive de l'incrément B :
//    B.1 ✅ — DocumentationModels + Service + Manager (foundation Swift)
//    B.2 — Layout 2 colonnes (CE FICHIER) avec données MOCKÉES
//    B.3 — Binding au vrai DocumentationManager.shared (fetch /notion-list)
//    B.4 — Rendu Markdown du contenu via swift-markdown-ui
//
//  À noter : à ce stade la zone contenu n'affiche que le titre — le
//  rendu Markdown réel viendra en B.4. Le mock data interne sera
//  remplacé par DocumentationManager.shared.pages en B.3 (cf. marqueur
//  « MARK: - Mock data (à retirer en B.3) » dans ce fichier).
//

import SwiftUI

struct DocumentationView: View {
    /// ID de la page actuellement sélectionnée dans la sidebar. `nil`
    /// avant la première frame (le `.onAppear` ci-dessous initialise sur
    /// la première page de la première section). Lié au `selection` du
    /// `List` via le `.tag(page.id)` de chaque ligne.
    @State private var selectedPageID: String?

    /// État de visibilité de la sidebar. `.all` (défaut) = sidebar
    /// visible. `.detailOnly` = sidebar repliée, contenu en pleine
    /// largeur. Géré explicitement (au lieu d'être laissé au défaut
    /// SwiftUI) pour pouvoir binder un bouton de toggle CUSTOM avec
    /// position stable — cf. fix mini-session 2026-05-09 ci-dessous.
    /// Pas de persistance entre sessions en V1 (sidebar visible à
    /// chaque ouverture, cohérent avec l'intention « j'ouvre la doc
    /// pour explorer »).
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // MARK: Sidebar
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
            .navigationSplitViewColumnWidth(280)
        } detail: {
            // MARK: Content area
            // B.2 (mock) : on affiche uniquement le titre du tuto
            // sélectionné en grande police centrée. B.4 remplacera ce
            // contenu par le rendu Markdown via swift-markdown-ui.
            Group {
                if let page = selectedPage {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(page.title)
                            .font(.system(size: 32, weight: .bold))
                            .padding(.horizontal, 32)
                            .padding(.top, 32)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    // Avant l'onAppear (typiquement 1 frame). Couleur
                    // transparente plutôt qu'un placeholder explicite —
                    // évite un flash de texte pendant le bootstrap.
                    Color.clear
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        // Mini-fix UX (2026-05-09) : on force la position du bouton de
        // toggle sidebar dans la titlebar via un `ToolbarItem(.navigation)`
        // CUSTOM, après avoir supprimé le bouton dynamique défaut via
        // `.toolbar(removing: .sidebarToggle)` (macOS 14+).
        //
        // Pourquoi : le bouton défaut SwiftUI « voyage » selon l'état
        // de la sidebar — quand la sidebar est ouverte (280pt), il
        // atterrit à ~280pt depuis la gauche, ce qui coïncide avec la
        // zone du titre AppKit centré « Documentation loucedé » (set
        // côté `loucedeApp.swift:openDocumentation()`) et le tronque
        // visuellement (« Documentation lo… »). Quand sidebar fermée,
        // le bouton se redéplace plus à droite.
        //
        // En forçant le bouton à `placement: .navigation` (= leading
        // edge de la titlebar sur macOS), il garde une position stable
        // QUEL QUE SOIT l'état de la sidebar, et le titre AppKit n'est
        // plus chevauché.
        //
        // NE PAS « simplifier » en retirant ce code : sans lui, le bug
        // visuel revient. Si refacto futur, conserver l'invariant
        // « toggle button stable + titre lisible ».
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation {
                        columnVisibility = (columnVisibility == .all ? .detailOnly : .all)
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(columnVisibility == .all ? "Masquer la sidebar" : "Afficher la sidebar")
            }
        }
        .onAppear {
            if selectedPageID == nil {
                selectedPageID = orderedPages.first?.id
            }
        }
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

    /// Pages groupées par catégorie. Les pages dont `category` est `nil`
    /// (cas légitime côté Notion si l'auteur a oublié) sont regroupées
    /// sous une clé vide qui ne figurera pas dans `categoryOrder` —
    /// elles seront donc filtrées par le `compactMap` ci-dessous.
    private var pagesByCategory: [String: [DocumentationPage]] {
        Dictionary(grouping: Self.mockPages, by: { $0.category ?? "" })
    }

    /// Sections dans l'ordre éditorial canonique. Chaque section
    /// contient ses pages triées par `number` ASC. Les catégories sans
    /// page sont filtrées (compactMap retourne nil pour les sections
    /// vides). Les pages dont la catégorie n'est PAS dans
    /// `categoryOrder` sont silencieusement omises — décision V1 mock,
    /// à raffiner en B.3 (filtre strict ou bucket « Autres » selon
    /// décision produit).
    private var orderedSections: [(name: String, pages: [DocumentationPage])] {
        Self.categoryOrder.compactMap { categoryName -> (name: String, pages: [DocumentationPage])? in
            guard let pages = pagesByCategory[categoryName], !pages.isEmpty else { return nil }
            // Tri par `number` ASC. Comparaison de strings — fonctionne
            // tant que les numéros sont zero-padded ("01", "02", ...,
            // "11"). Le proxy Scaleway garantit ce format en B.3.
            let sorted = pages.sorted { ($0.number ?? "") < ($1.number ?? "") }
            return (categoryName, sorted)
        }
    }

    /// Pages aplaties dans l'ordre d'affichage final (sections triées,
    /// puis pages triées par number ASC dans chaque section). Utilisée
    /// pour déterminer la sélection initiale (.first) au premier
    /// `.onAppear`.
    private var orderedPages: [DocumentationPage] {
        orderedSections.flatMap { $0.pages }
    }

    /// Page actuellement sélectionnée, lookupée par ID dans le mock.
    /// `nil` avant la première sélection.
    private var selectedPage: DocumentationPage? {
        guard let id = selectedPageID else { return nil }
        return Self.mockPages.first { $0.id == id }
    }

    // MARK: - Configuration éditoriale

    /// Ordre canonique des catégories de documentation, défini par Faab.
    /// Source de vérité pour le tri des sections de la sidebar. Les
    /// catégories non listées ici sont filtrées (cf. `orderedSections`).
    /// V1 mock — à conserver en B.3 puisque cet ordre est indépendant
    /// du `number` global qui ordonne les pages dans une section.
    private static let categoryOrder: [String] = [
        "🚀 Démarrer",
        "🔧 Configurer loucedé",
        "💡 loucedé au quotidien",
        "💳 Compte et licence",
        "🛠️ Résolution de problèmes",
        "📚 Ressources"
    ]

    // MARK: - Mock data (à retirer en B.3)

    /// Données mockées pour valider le layout, le tri, le groupement
    /// et l'interactivité sidebar ↔ contenu sans dépendance réseau.
    /// Remplacées en B.3 par `DocumentationManager.shared.pages`
    /// (fetch via `/notion-list` côté proxy Scaleway). 8 pages
    /// réparties sur 4 catégories — couvre les cas multi-pages-par-
    /// section, edge case 1-page (Compte) et 2 catégories vides
    /// (Résolution + Ressources) pour vérifier le filter compactMap.
    /// Les `id` `mock-XX` sont volontairement non-UUID — pas d'appel
    /// réseau en B.2.
    private static let mockPages: [DocumentationPage] = [
        DocumentationPage(id: "mock-01", title: "Bienvenue dans loucedé", summary: nil, icon: "🤗", cover: nil, category: "🚀 Démarrer", level: nil, priority: nil, number: "01"),
        DocumentationPage(id: "mock-02", title: "Installer loucedé", summary: nil, icon: "💻", cover: nil, category: "🚀 Démarrer", level: nil, priority: nil, number: "02"),
        DocumentationPage(id: "mock-03", title: "Premier lancement", summary: nil, icon: "🚀", cover: nil, category: "🚀 Démarrer", level: nil, priority: nil, number: "03"),
        DocumentationPage(id: "mock-04", title: "Obtenir une clé API", summary: nil, icon: "🗝️", cover: nil, category: "🔧 Configurer loucedé", level: nil, priority: nil, number: "04"),
        DocumentationPage(id: "mock-05", title: "Modifier ton raccourci", summary: nil, icon: "⌨️", cover: nil, category: "🔧 Configurer loucedé", level: nil, priority: nil, number: "05"),
        DocumentationPage(id: "mock-11", title: "Comprendre la fenêtre", summary: nil, icon: "🔲", cover: nil, category: "💡 loucedé au quotidien", level: nil, priority: nil, number: "11"),
        DocumentationPage(id: "mock-12", title: "Créer une action", summary: nil, icon: "✨", cover: nil, category: "💡 loucedé au quotidien", level: nil, priority: nil, number: "12"),
        DocumentationPage(id: "mock-21", title: "Activer ta licence", summary: nil, icon: "🔓", cover: nil, category: "💳 Compte et licence", level: nil, priority: nil, number: "21")
    ]
}

// MARK: - Preview

#Preview {
    DocumentationView()
        .frame(width: 900, height: 700)
}
