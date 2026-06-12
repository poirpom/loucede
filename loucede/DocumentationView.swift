//
//  DocumentationView.swift
//  loucede
//
//  Point 4 pre-V1 — Sous-étape B.4 (2026-05-09) : rendu Markdown du
//  contenu sélectionné via swift-markdown-ui (`MarkdownUI`). La zone
//  droite affiche désormais le tuto rendu en pleine page (titres, gras,
//  listes, code blocks, etc.) au lieu du titre seul utilisé en B.3.
//
//  Polish K+L+M (2026-05-10) : ajout du header de page (cover image
//  bandeau 200pt, emoji 80pt centré, titre 32pt bold) au-dessus du
//  rendu Markdown dans le case Loaded de `detailContent`. Esprit
//  visuel Notion natif côté zone de lecture. Sources des icon/title :
//  `manager.pages` (peuplé par /notion-list) — pas d'enrichissement
//  du proxy /notion-page nécessaire (couplage minime).
//
//  Mini-fix UX (2026-05-10, post-K+L+M) : pivot sur 2 points suite
//  aux observations runtime :
//    1. Cover image remplacée par fond bleu loucedé (#3F84F7) derrière
//       l'emoji. La cover créait une surcharge visuelle redondante
//       avec la sidebar (qui joue déjà le rôle de navigation), et
//       impliquait des fetchs AsyncImage + URLs S3 expirées sans
//       bénéfice utilisateur clair. Le bloc bleu unifie l'identité
//       visuelle loucedé (couleur de sélection design system) et
//       élimine l'item E (proxy images V1.x) devenu obsolète.
//    2. Padding bottom du titre retiré : l'écart cumulé titre ↔
//       Markdown atteignait 56pt (24pt bottom titre + 32pt vertical
//       Markdown). Retrait du `.padding(.bottom, 24)` du titre →
//       écart final 32pt via le padding vertical du Markdown seul.
//
//  Polish typographie (2026-05-10) : customisation des styles MarkdownUI
//  pour le rendu de la doc native. Élements stylisés via les modifiers
//  `.markdownBlockStyle(\.<key>)` et `.markdownTextStyle(\.<key>)` :
//    - Callouts (blockquote) : border 1px adaptatif + fond subtil + radius 8pt
//    - HR (thematicBreak) : ligne dashed adaptative via Shape custom
//    - Code fenced : monospace + bg + radius + padding 16pt + WRAP activé
//      (via Text(config.content) au lieu de config.label) — supporte
//      le détournement code block en mise en exergue de texte
//    - Code inline : monospace + bg subtil
//    - Liens : couleur loucedé + underline
//
//  Note H2 (rollback runtime, 2026-05-10) : la customisation
//  `.markdownBlockStyle(\.heading2)` initialement appliquée (couleur
//  #3F84F7) écrasait la taille/poids défaut MarkdownUI, rendant H2
//  indistinguable du paragraphe. Retrait pragmatique du modifier —
//  défaut MarkdownUI conservé. La couleur loucedé reste présente sur
//  le header (bloc emoji) et les liens, pas besoin de la doubler sur
//  H2. À investiguer proprement en V1.x si la customisation devient
//  désirable (pattern textStyle vs blockStyle pour headings).
//
//  Étape progressive de l'incrément B :
//    B.1 ✅ — DocumentationModels + Service + Manager (foundation Swift)
//    B.2 ✅ — Layout 2 colonnes avec données mockées
//    B.3 ✅ — Binding au DocumentationManager.shared (liste réelle)
//    B.4 ✅ — Rendu Markdown du contenu via MarkdownUI
//    K+L+M ✅ — Cover + emoji + titre dans la zone détail
//    Polish typo — Customisation styles MarkdownUI (CE FICHIER)
//
//  4 états visuels gérés par `sidebarContent` (priorité décroissante) :
//    1. Loading : ProgressView centré (~500ms typique)
//    2. Error : icône + message + détail localisé + bouton « Réessayer »
//    3. Empty : sidebar naturellement vide + message zone droite
//       (cas très rare — Faab a dépublié tous les tutos Notion)
//    4. Loaded : List avec sections groupées par catégorie + tri par N°
//
//  5 états visuels gérés par `detailContent` (priorité décroissante) :
//    1. Empty list : message « Aucun tuto disponible pour le moment »
//    2. Bootstrap (selectedPage == nil) : Color.clear (avant init de
//       sélection par `.onChange(of: pages, initial: true)`)
//    3. Loading page : ProgressView centré (~500ms typique)
//    4. Error page : errorView avec bouton « Réessayer »
//    5. Loaded : ScrollView + Markdown(content) + padding 32px
//    6 (fallback) : ProgressView pour le cas race rare entre 2 fetches
//      où selectedPageID a changé mais currentPage encore stale.
//
//  Trigger des fetches — sources distinctes pour liste vs page :
//    - LISTE : côté AppKit dans `loucedeApp.swift:openDocumentation()`
//      (Task lancé à chaque ouverture de la fenêtre, B.3 fix). Cette
//      vue est passive sur la liste — elle observe via @ObservedObject.
//    - PAGE : côté SwiftUI via `.onChange(of: selectedPageID, initial: true)`
//      ci-dessous. Fire au mount (initial: true, si la sélection est
//      déjà set par la chain `pages → first.id`) et à chaque clic
//      utilisateur sur une autre page de la sidebar.
//
//  Sélection par défaut robuste via `.onChange(of: manager.pages, initial: true)` :
//    - `initial: true` couvre le cas où le Task `loadList()` termine
//      AVANT que la vue soit mountée (manager.pages déjà rempli au
//      premier render).
//    - Init au premier remplissage : set sur la première page de la
//      première section (categoryOrder + N° ASC).
//    - Correction si refresh ramène un set différent où la sélection
//      actuelle a disparu : fallback sur la première page disponible.
//    - Sinon (sélection toujours présente après refresh) : préservée.
//

import SwiftUI
import MarkdownUI

struct DocumentationView: View {
    /// ID de la page actuellement sélectionnée dans la sidebar. `nil`
    /// avant la première arrivée de pages depuis le manager. Lié au
    /// `selection` du `List` via le `.tag(page.id)` de chaque ligne.
    /// Initialisé/corrigé par `.onChange(of: manager.pages)`.
    @State private var selectedPageID: String?

    /// Manager de la documentation (singleton). Observé pour réagir
    /// aux changements côté liste (`pages`, `isLoadingList`, `listError`)
    /// ET côté page sélectionnée (`currentPage`, `isLoadingPage`,
    /// `pageError`). Pattern `@ObservedObject` (et non `@StateObject`)
    /// car la durée de vie du singleton est gérée par l'app, pas par
    /// cette vue.
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
        // Le trigger du fetch a été déplacé côté AppKit dans
        // `loucedeApp.swift:openDocumentation()` (B.3 fix 2026-05-09).
        // Pas de `.task` ici — la vue est passive, observe le manager
        // via `@ObservedObject` et réagit à l'arrivée de `pages`.
        .onChange(of: manager.pages, initial: true) { _, _ in
            // `initial: true` (macOS 14+) fait fire la closure aussi
            // au premier render, avec la valeur courante de
            // `manager.pages`. Couvre l'edge case où le Task lancé par
            // `openDocumentation()` termine AVANT que la vue soit
            // mountée — sans `initial: true`, `selectedPageID` resterait
            // `nil` indéfiniment (pas de changement de `manager.pages`
            // après mount donc pas de fire `.onChange`).
            //
            // Triple rôle :
            //   1. Init au mount (initial: true) si manager.pages déjà
            //      rempli → set sur la première page.
            //   2. Init au premier remplissage async (selectedPageID
            //      toujours nil) → idem.
            //   3. Correction si refresh ramène un set différent où la
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
        // Trigger lazy du fetch de la page sélectionnée (B.4).
        //
        // `initial: true` (macOS 14+) : fire la closure au mount avec
        // la valeur courante de `selectedPageID`. Couvre le cas où
        // `.onChange(of: pages, initial: true)` ci-dessus a déjà set
        // `selectedPageID` à la première page avant que cet observer
        // soit armé — sans `initial: true`, on raterait ce changement
        // initial. Quand l'utilisateur clique sur une autre page dans
        // la sidebar, le `selection` binding du List met à jour
        // `selectedPageID` → cet observer fire → nouveau loadPage.
        //
        // Race condition acceptée V1 : si l'utilisateur clique
        // rapidement sur 2 pages, 2 Tasks `loadPage` fire en parallèle.
        // Pas de cancellation explicite du Task précédent — le dernier
        // fetch terminé devient `currentPage` final. Possible flicker
        // UI bref (loading → A → loading → B) mais pas de crash. Le
        // guard `content.id == selectedPageID` côté `detailContent`
        // (état Loaded) protège contre l'affichage d'un contenu stale
        // pendant la fenêtre de race. À mitiger en V1.x via task
        // cancellation explicite si feedback utilisateur.
        .onChange(of: selectedPageID, initial: true) { _, newID in
            guard let id = newID else { return }
            Task { await manager.loadPage(id: id) }
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
            errorView(
                title: "Impossible de charger la documentation",
                message: error.errorDescription ?? "Erreur inconnue.",
                retry: { Task { await manager.loadList() } }
            )
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

    /// Vue d'erreur générique réutilisable (sidebar OU zone détail) :
    /// icône + titre + détail localisé + bouton « Réessayer ».
    /// Généralisée en B.4 (initialement hardcodée pour la liste, puis
    /// étendue avec `title` + `retry: () -> Void` paramétrables pour
    /// supporter aussi les erreurs de chargement de page côté
    /// `detailContent`. Single helper, deux contextes d'usage.
    @ViewBuilder
    private func errorView(title: String, message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Réessayer", action: retry)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Page header (polish K+L+M, mini-fix 2x 2026-05-10)

    /// Header visuel d'une page chargée : bloc bleu loucedé 200pt
    /// (plein-largeur, fond `#3F84F7`) avec emoji 80pt centré H+V,
    /// suivi du titre 32pt bold (aligné gauche). Insère au-dessus du
    /// rendu Markdown dans le case Loaded de `detailContent`.
    ///
    /// Chaque élément est indépendamment optionnel :
    /// - Pas d'icon → pas de bloc bleu, le titre apparaît directement
    ///   en haut du ScrollView (cas hypothétique V1, ne devrait pas
    ///   arriver — Faab fournit toujours un emoji par page Notion).
    /// - `metadata == nil` (race rare où la page a disparu de
    ///   `manager.pages` entre 2 refresh) → header entièrement skippé,
    ///   le Markdown s'affiche seul (graceful fallback).
    ///
    /// Source des données : `manager.pages` (peuplé par /notion-list).
    /// Pas dans `currentPage` (réponse /notion-page) qui ne contient
    /// que id/title/markdown — décision V1 pour ne pas enrichir le
    /// proxy (couplage minime sidebar/detail).
    ///
    /// Espacements verticaux finaux :
    ///   - Bloc bleu (si emoji présent) : 200pt height, plein-largeur
    ///     contenue dans la zone detail visible, emoji centré H+V via
    ///     `.overlay` (alignment center par défaut).
    ///   - Titre top : 32pt constant (qu'il y ait emoji ou non).
    ///   - Titre bottom : 0 (Markdown gère l'aération via son propre
    ///     `.padding(.vertical, 32)` → écart final titre ↔ Markdown
    ///     = 32pt, symétrique avec le 32pt au-dessus du titre).
    ///
    /// Pattern `Color()` racine + `.overlay` (au lieu de `.background`
    /// modifier sur Text) : empêche le bleu de déborder physiquement
    /// sous la sidebar translucide du NavigationSplitView. La sidebar
    /// macOS native a un fond vibrancy qui laisse passer les fonds
    /// opaques du detail content quand celui-ci s'étend logiquement
    /// sous la sidebar via `frame(maxWidth: .infinity)`. Avec `Color()`
    /// comme view racine, le frame respecte les safe areas horizontales
    /// du detail container (zone visible uniquement).
    ///
    /// Couleur `#3F84F7` : token design system loucedé (couleur de
    /// sélection cf. CLAUDE.md), déjà utilisée dans `PopoverView` et
    /// `LaunchAtLoginStep`. Extension `Color(hex:)` globale définie
    /// dans `Onboarding/ColorExtension.swift`.
    @ViewBuilder
    private func pageHeader(metadata: DocumentationPage?) -> some View {
        if let metadata {
            let hasIcon = (metadata.icon?.isEmpty == false)

            VStack(alignment: .leading, spacing: 0) {
                // 1. Bloc bleu loucedé avec emoji centré H+V (200pt
                // height, plein-largeur contenue dans la zone detail).
                // Pattern `Color()` racine + `.overlay` : la color view
                // respecte les safe areas horizontales du parent
                // NavigationSplitView, contrairement à un `.background`
                // modifier qui peut bypass via `frame(maxWidth: .infinity)`.
                // L'overlay centre l'emoji par défaut (alignment .center).
                if hasIcon, let icon = metadata.icon {
                    Color(hex: "3F84F7")
                        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 200)
                        .overlay {
                            Text(icon)
                                .font(.system(size: 80))
                        }
                }

                // 2. Titre (32pt bold, aligné gauche, toujours présent
                // côté Notion donc pas optional ici).
                // `.padding(.top, 32)` constant : symétrique avec le
                // `.padding(.vertical, 32)` du Markdown qui suit
                // (écart 32pt au-dessus + 32pt en-dessous).
                Text(metadata.title)
                    .font(.system(size: 32, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 32)
                    .padding(.horizontal, 32)
            }
        }
        // Si metadata == nil → EmptyView implicite (le Markdown s'affichera seul).
    }

    // MARK: - Detail content (5 états visuels + fallback)

    @ViewBuilder
    private var detailContent: some View {
        Group {
            if !manager.isLoadingList && manager.listError == nil && manager.pages.isEmpty {
                // État 1 : Empty list (succès du fetch liste mais
                // 0 page — cas très rare où Faab a dépublié tous les
                // tutos Notion). Message dans la zone droite, pas dans
                // la sidebar (cohérent avec « zone détail = comprendre
                // l'état »).
                Text("Aucun tuto disponible pour le moment")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedPage == nil {
                // État 2 : Bootstrap — avant que `selectedPageID` soit
                // set par `.onChange(of: pages, initial: true)`.
                // Color.clear pour éviter un flash de placeholder
                // pendant le bootstrap (1 frame typiquement).
                Color.clear
            } else if manager.isLoadingPage {
                // État 3 : Loading page — ProgressView centré, cohérent
                // avec le pattern Loading sidebar.
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = manager.pageError {
                // État 4 : Error page — errorView avec bouton
                // « Réessayer » qui re-déclenche `loadPage(id:)`.
                errorView(
                    title: "Impossible de charger ce tuto",
                    message: error.errorDescription ?? "Erreur inconnue.",
                    retry: {
                        guard let id = selectedPageID else { return }
                        Task { await manager.loadPage(id: id) }
                    }
                )
            } else if let content = manager.currentPage, content.id == selectedPageID {
                // État 5 : Loaded — header de page (cover + emoji + titre)
                // suivi du rendu Markdown via MarkdownUI.
                //
                // Guard `content.id == selectedPageID` : protège contre
                // l'affichage d'un contenu stale d'un fetch précédent
                // pendant la fenêtre de race où l'utilisateur a déjà
                // changé de sélection mais le nouveau loadPage n'a
                // pas encore terminé. Si stale, on retombe sur le
                // fallback ProgressView ci-dessous (état attendu = en
                // cours de chargement de la nouvelle page).
                //
                // Note padding (polish K+L+M, 2026-05-10) : le padding
                // 32pt horizontal a été DÉPLACÉ du VStack vers le
                // Markdown lui-même. Sans ce déplacement, la cover
                // image plein-largeur héritait du padding et laissait
                // des bandes blanches de 32pt sur les côtés. Le
                // `pageHeader` gère son propre padding interne (cover
                // sans padding, emoji et titre avec padding horizontal
                // 32pt). Le padding vertical 32pt reste sur le Markdown
                // pour une zone de lecture confortable (au-dessus = bas
                // du titre du header, en dessous = fin du ScrollView).
                //
                // ScrollView vertical pour les contenus longs.
                // `.textSelection(.enabled)` permet à l'utilisateur de
                // copier des bouts de tuto (cohérent avec PopoverView
                // qui l'a déjà sur le rendu Markdown des résultats LLM).
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        pageHeader(metadata: selectedPage)
                        Markdown(content.markdown)
                            .textSelection(.enabled)
                            // Callouts (blockquote Notion) : border 1px
                            // adaptatif + fond subtil + radius 8pt + padding
                            // interne. Pas de traitement italique car
                            // MarkdownUI n'en applique pas par défaut sur
                            // \.blockquote. L'emoji du callout Notion est
                            // conservé en début de blockquote (présent dans
                            // le markdown converti).
                            .markdownBlockStyle(\.blockquote) { config in
                                config.label
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            // HR (thematicBreak) : ligne dashed 1px via
                            // helper `DashedLine: Shape` défini en bas du
                            // fichier. Couleur secondary adaptative
                            // light/dark. Padding vertical 8pt pour aérer.
                            .markdownBlockStyle(\.thematicBreak) {
                                DashedLine()
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                                    .foregroundStyle(Color.secondary.opacity(0.4))
                                    .frame(height: 1)
                                    .padding(.vertical, 8)
                            }
                            // Code block (fenced) : on remplace `config.label`
                            // (rendu MarkdownUI par défaut, avec scroll
                            // horizontal possible) par un `Text(config.content)`
                            // explicite. Le Text() natif SwiftUI WRAP
                            // automatiquement sur les espaces — clé pour le
                            // détournement « code block = mise en exergue
                            // de texte » sans scroll horizontal indésirable.
                            // On perd la coloration syntaxique éventuelle
                            // (no-op : MarkdownUI n'en a pas par défaut).
                            .markdownBlockStyle(\.codeBlock) { config in
                                Text(config.content)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            // Code inline (`backticks`) : monospace + fond
                            // subtil. Pas de padding micro paramétrable côté
                            // text style — trade-off accepté V1 (pattern
                            // standard MarkdownUI).
                            .markdownTextStyle(\.code) {
                                FontFamilyVariant(.monospaced)
                                BackgroundColor(Color.secondary.opacity(0.1))
                            }
                            // Liens : couleur loucedé #3F84F7 + underline
                            // single (pattern macOS natif).
                            .markdownTextStyle(\.link) {
                                ForegroundColor(Color(hex: "3F84F7"))
                                UnderlineStyle(.single)
                            }
                            // Images bundle://images/… de la doc locale
                            // (F.2) — résolues dans Documentation/images/
                            // du bundle. Cf. BundleImageProvider.swift.
                            .markdownImageProvider(BundleImageProvider())
                            .padding(.horizontal, 32)
                            .padding(.vertical, 32)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                // Fallback : selected mais pas encore currentPage (ou
                // currentPage stale du fetch précédent). Cas race rare
                // entre 2 fetches successifs (clic rapide). ProgressView
                // cohérent avec « en cours de chargement de la nouvelle
                // page ».
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Helper Shapes (polish typographie)

/// Ligne horizontale dashed pour le rendu custom des `<hr>` Markdown.
/// Pattern simple : Path tracé sur la largeur du rect, à mi-hauteur.
/// Utilisé exclusivement par `.markdownBlockStyle(\.thematicBreak)` du
/// rendu Markdown de la doc native (cf. case Loaded de `detailContent`).
///
/// Note scope : `fileprivate` car helper visuel local au fichier — pas
/// besoin d'exposer ailleurs dans l'app. Si un jour on a besoin d'une
/// `DashedLine` dans plusieurs vues, on la promeut en `internal` dans
/// un fichier dédié `Helpers/Shapes.swift` (pas urgent V1).
fileprivate struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
