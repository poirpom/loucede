//
//  ActionsView.swift
//  loucede
//
//  Actions settings view for managing user actions
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Filtre Réglages → Actions (K.unify.2)

/// Filtre sélectionné via le `Picker` en tête de la sidebar. Single-radio,
/// session-scoped (revient à `.all` au prochain démarrage — pas de
/// persistance UserDefaults par décision Faab).
fileprivate enum ActionsFilter: Hashable {
    case all
    case favorites
    case category(PromptCategory)
    case uncategorized
    case hidden

    var label: String {
        switch self {
        case .all: return "Toutes"
        case .favorites: return "Favoris"
        case .category(let c): return c.rawValue
        case .uncategorized: return "Sans catégorie"
        case .hidden: return "Masquées"
        }
    }

    /// Ordre des options dans le Picker. `.custom` exclu (DEPRECATED).
    static var allOptions: [ActionsFilter] {
        var out: [ActionsFilter] = [.all, .favorites]
        for c in PromptCategory.allCases where c != .custom {
            out.append(.category(c))
        }
        out.append(.uncategorized)
        out.append(.hidden)
        return out
    }
}

// MARK: - Actions Settings

struct ActionsSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var store = ActionsStore.shared
    @Binding var selectedAction: Action?
    /// Filtre actif (session-scoped, défaut `.all`).
    @State private var selectedFilter: ActionsFilter = .all
    /// Suivi de l'ID de l'action actuellement survolée par un drag actif
    /// (K.unify.2 : index → ID car le drop traverse des sections, plus
    /// d'index linéaire fiable). Affiche une ligne bleue au top edge.
    @State private var dropTargetActionID: UUID?
    /// `true` quand un drag survole le header FAVORIS depuis une action
    /// non-favorite — drop déclenche `isFavorite = true`.
    @State private var isFavoritesHeaderTargeted: Bool = false

    /// Mini-session Point 3 pre-V1 (2026-05-08) : couleur de texte
    /// adaptive light/dark mode. Aligné sur le pattern de `TemplatesView`
    /// pour que le header de cet onglet match exactement le style du
    /// header de l'onglet Modèles.
    var textGrayColor: Color {
        colorScheme == .light
            ? Color(white: 0.35)
            : Color(white: 0.65)
    }

    // MARK: - K.unify.2 — sections affichées selon filtre

    /// Section visible dans la sidebar : titre + actions ordonnées.
    fileprivate struct SidebarSection: Identifiable {
        let id: String     // ex: "favorites" / "category-translate" / "uncategorized" / "hidden"
        let title: String
        /// `true` pour la section FAVORIS (cible d'un drag depuis une
        /// action non-favorite). Les autres sections ne sont pas cibles
        /// de favorisation.
        let isFavoritesSection: Bool
        let actions: [Action]
    }

    /// Tri stable par `displayOrder` puis par ordre d'insertion (`firstIndex`).
    /// Les actions custom existantes sans displayOrder personnalisé (0)
    /// conservent leur ordre relatif d'insertion grâce au stable sort.
    private func sorted(_ acts: [Action]) -> [Action] {
        acts.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.displayOrder != rhs.element.displayOrder {
                    return lhs.element.displayOrder < rhs.element.displayOrder
                }
                return lhs.offset < rhs.offset
            }
            .map { $0.element }
    }

    /// Liste des sections à afficher selon le filtre actif. `isHidden`
    /// exclu partout sauf dans le filtre `.hidden`.
    fileprivate var displayedSections: [SidebarSection] {
        switch selectedFilter {
        case .all:
            var out: [SidebarSection] = []
            let favs = sorted(store.actions.filter { $0.isFavorite && !$0.isHidden })
            // FAVORIS toujours affiché en mode .all pour permettre le drop initial.
            out.append(SidebarSection(id: "favorites", title: "FAVORIS", isFavoritesSection: true, actions: favs))
            // SANS CATÉGORIE remontée juste après FAVORIS : les actions
            // générées via le Générateur (popup) y atterrissent par défaut —
            // l'utilisateur les retrouve sans scroller jusqu'en bas.
            let uncat = sorted(store.actions.filter { $0.category == nil && !$0.isFavorite && !$0.isHidden })
            if !uncat.isEmpty {
                out.append(SidebarSection(id: "uncategorized", title: "SANS CATÉGORIE", isFavoritesSection: false, actions: uncat))
            }
            for cat in PromptCategory.allCases where cat != .custom {
                let inCat = sorted(store.actions.filter { $0.category == cat && !$0.isFavorite && !$0.isHidden })
                if !inCat.isEmpty {
                    out.append(SidebarSection(id: "category-\(cat.rawValue)", title: cat.rawValue.uppercased(), isFavoritesSection: false, actions: inCat))
                }
            }
            return out

        case .favorites:
            let favs = sorted(store.actions.filter { $0.isFavorite && !$0.isHidden })
            return [SidebarSection(id: "favorites", title: "FAVORIS", isFavoritesSection: true, actions: favs)]

        case .category(let cat):
            let inCat = sorted(store.actions.filter { $0.category == cat && !$0.isHidden })
            return [SidebarSection(id: "category-\(cat.rawValue)", title: cat.rawValue.uppercased(), isFavoritesSection: false, actions: inCat)]

        case .uncategorized:
            let uncat = sorted(store.actions.filter { $0.category == nil && !$0.isHidden })
            return [SidebarSection(id: "uncategorized", title: "SANS CATÉGORIE", isFavoritesSection: false, actions: uncat)]

        case .hidden:
            let hid = sorted(store.actions.filter { $0.isHidden })
            return [SidebarSection(id: "hidden", title: "MASQUÉES", isFavoritesSection: false, actions: hid)]
        }
    }

    /// Toggle favori d'une action (clic étoile).
    fileprivate func toggleFavorite(_ action: Action) {
        guard let idx = store.actions.firstIndex(where: { $0.id == action.id }) else { return }
        store.actions[idx].isFavorite.toggle()
        if store.actions[idx].isFavorite {
            let maxOrder = store.actions.filter { $0.isFavorite }.map { $0.displayOrder }.max() ?? -1
            store.actions[idx].displayOrder = maxOrder + 1
        }
        store.saveActions()
    }

    /// Toggle masqué d'une action (clic œil ou toggle éditeur).
    fileprivate func toggleHidden(_ action: Action) {
        guard let idx = store.actions.firstIndex(where: { $0.id == action.id }) else { return }
        store.actions[idx].isHidden.toggle()
        store.saveActions()
    }

    /// K.unify.2-fix-3 — Deux actions appartiennent-elles à la même
    /// section visuelle ?
    ///
    /// - Section **FAVORIS** : tous les favoris (isFavorite=true)
    ///   forment une seule section, indépendamment de leur catégorie
    ///   (les 5 Top V1 ont des catégories différentes — `category ==`
    ///   ne marche pas comme filtre de section ici).
    /// - Sections **par catégorie** : seuls les non-favoris partagent
    ///   une section ; filtre `category == && isHidden ==`.
    /// - Croisement favori ↔ non-favori : sections différentes.
    private func inSameSection(_ a: Action, _ b: Action) -> Bool {
        if a.isFavorite && b.isFavorite {
            return true
        }
        if !a.isFavorite && !b.isFavorite {
            return a.category == b.category && a.isHidden == b.isHidden
        }
        return false
    }

    /// K.unify.2-fix-3 — Re-compacte les `displayOrder` de la section
    /// contenant `reference` en valeurs contiguës `0, 1, 2, ...`. Tri
    /// stable : par `displayOrder` courant, puis par ordre d'insertion
    /// dans `store.actions`. Évite l'accumulation de collisions au fil
    /// des drops successifs.
    private func normalizeDisplayOrder(forSectionOf reference: Action) {
        let sectionIndices = store.actions.indices.filter {
            inSameSection(store.actions[$0], reference)
        }
        let sortedIndices = sectionIndices.sorted { lhs, rhs in
            if store.actions[lhs].displayOrder != store.actions[rhs].displayOrder {
                return store.actions[lhs].displayOrder < store.actions[rhs].displayOrder
            }
            return lhs < rhs  // stable par ordre d'insertion
        }
        for (newOrder, idx) in sortedIndices.enumerated() {
            store.actions[idx].displayOrder = newOrder
        }
    }

    /// Drop d'une action sur une autre row. Réordonne via `displayOrder`
    /// et, si la cible est dans une autre section, **reclasse** l'action
    /// déposée pour qu'elle adopte la section visuelle de la cible
    /// (drag-to-recategorize).
    ///
    /// K.unify.2-fix-3 : la condition « même section » utilise
    /// `inSameSection(_:_:)` (favoris ignorent category) au lieu du
    /// filtre `category ==` qui empêchait le décalage correct entre
    /// favoris de catégories différentes. Normalisation post-drop pour
    /// re-compacter les displayOrder en 0,1,2,...
    ///
    /// Reclassement inter-sections : l'action déposée adopte la section
    /// de la CIBLE avant le calcul de section, ce qui réutilise toute la
    /// mécanique d'insertion/`displayOrder` existante.
    /// - Drop dans FAVORIS → devient favori, catégorie inchangée (les
    ///   favoris ignorent la catégorie).
    /// - Drop hors FAVORIS → quitte les favoris ET adopte la catégorie de
    ///   la cible (`nil` = « Sans catégorie »).
    /// La réaffectation est idempotente sur un drop intra-section (mêmes
    /// `isFavorite`/`category` que la cible) → réordonnancement inchangé.
    fileprivate func handleDrop(droppedID: UUID, ontoActionID: UUID, inFavoritesSection: Bool) {
        guard let fromIdx = store.actions.firstIndex(where: { $0.id == droppedID }),
              let toIdx = store.actions.firstIndex(where: { $0.id == ontoActionID }),
              fromIdx != toIdx else { return }

        // Adopter la section visuelle de la cible AVANT le calcul de
        // section (sinon `inSameSection(from, to)` resterait false sur un
        // drop inter-sections et le déplacement n'aurait pas lieu).
        if inFavoritesSection {
            store.actions[fromIdx].isFavorite = true
        } else {
            store.actions[fromIdx].isFavorite = false
            store.actions[fromIdx].category = store.actions[toIdx].category
        }

        // Source et cible sont désormais dans la même section visuelle.
        guard inSameSection(store.actions[fromIdx], store.actions[toIdx]) else { return }

        // Décalage « drop BEFORE target » : la source prend le
        // displayOrder de la cible, tous les autres de la section
        // dont displayOrder >= targetOrder sont décalés de +1.
        let targetOrder = store.actions[toIdx].displayOrder
        store.actions[fromIdx].displayOrder = targetOrder
        for i in store.actions.indices where i != fromIdx {
            if inSameSection(store.actions[i], store.actions[fromIdx])
                && store.actions[i].displayOrder >= targetOrder {
                store.actions[i].displayOrder += 1
            }
        }

        // Normalisation : compacte les displayOrder de la section en
        // 0, 1, 2, ... — propre pour les prochains drops.
        normalizeDisplayOrder(forSectionOf: store.actions[fromIdx])

        store.saveActions()
    }

    /// Drop sur le header FAVORIS : favorise + place en fin.
    fileprivate func handleDropOnFavoritesHeader(droppedID: UUID) {
        guard let idx = store.actions.firstIndex(where: { $0.id == droppedID }) else { return }
        if !store.actions[idx].isFavorite {
            store.actions[idx].isFavorite = true
            let maxOrder = store.actions.filter { $0.isFavorite }.map { $0.displayOrder }.max() ?? -1
            store.actions[idx].displayOrder = maxOrder + 1
            store.saveActions()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header — Mini-session Point 3 pre-V1 (2026-05-08).
            // Strictement aligné sur le header de `TemplatesView` (titre 18pt
            // bold à gauche + secondary text 12pt à droite, padding 24/20/16).
            // « Glisse pour réorganiser » communique la nouvelle affordance
            // drag-and-drop introduite dans cette session.
            HStack {
                Text("Tes actions")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(textGrayColor)

                Spacer()

                Text("Glisse pour réorganiser")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            HStack(spacing: 0) {
            // Sidebar - Actions list
            VStack(alignment: .leading, spacing: 0) {
                // K.unify.2 : barre filtres (Picker .menu, session-scoped).
                // 9 options : Toutes / Favoris / 6 catégories / Sans catégorie
                // / Masquées. Défaut .all à chaque démarrage.
                HStack {
                    Picker("Filtrer", selection: $selectedFilter) {
                        ForEach(ActionsFilter.allOptions, id: \.self) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // K.unify.2 : liste sectionnée selon le filtre actif.
                // Sections : FAVORIS (toujours en mode .all pour permettre
                // le drop initial) + catégories non-vides + Sans catégorie.
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(displayedSections) { section in
                            VStack(alignment: .leading, spacing: 2) {
                                // Header de section (style sidebar doc :
                                // 10pt semibold secondary, majuscules).
                                Text(section.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 6)
                                    .padding(.bottom, 2)
                                    // Drop sur le header FAVORIS depuis une
                                    // action non-favorite → favorise.
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        section.isFavoritesSection && isFavoritesHeaderTargeted
                                            ? Color.accentColor.opacity(0.15)
                                            : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .dropDestination(for: String.self) { items, _ in
                                        defer { isFavoritesHeaderTargeted = false }
                                        guard section.isFavoritesSection,
                                              let droppedIDStr = items.first,
                                              let droppedID = UUID(uuidString: droppedIDStr)
                                        else { return false }
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            handleDropOnFavoritesHeader(droppedID: droppedID)
                                        }
                                        return true
                                    } isTargeted: { targeted in
                                        if section.isFavoritesSection {
                                            isFavoritesHeaderTargeted = targeted
                                        }
                                    }

                                // K.unify.2-fix-2 : zone fantôme drop-en-tête
                                // retirée — comportement drag-n-drop favoris
                                // reste défaillant en tête de liste (régressé
                                // en fix-1 puis revert). Dette technique
                                // acceptée pour V1, à traiter post-V1
                                // (cf. backlog).

                                // Rows de la section.
                                ForEach(section.actions) { action in
                                    ActionListRow(
                                        action: action,
                                        isSelected: selectedAction?.id == action.id,
                                        onToggleFavorite: { toggleFavorite(action) },
                                        onToggleHidden: { toggleHidden(action) }
                                    )
                                    .onTapGesture {
                                        selectedAction = action
                                    }
                                    .overlay(alignment: .top) {
                                        if dropTargetActionID == action.id {
                                            Rectangle()
                                                .fill(Color.accentColor)
                                                .frame(height: 2)
                                        }
                                    }
                                    .dropDestination(for: String.self) { items, _ in
                                        defer { dropTargetActionID = nil }
                                        guard let droppedIDStr = items.first,
                                              let droppedID = UUID(uuidString: droppedIDStr),
                                              droppedID != action.id
                                        else { return false }
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            handleDrop(droppedID: droppedID,
                                                       ontoActionID: action.id,
                                                       inFavoritesSection: section.isFavoritesSection)
                                        }
                                        return true
                                    } isTargeted: { targeted in
                                        if targeted {
                                            dropTargetActionID = action.id
                                        } else if dropTargetActionID == action.id {
                                            dropTargetActionID = nil
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                    .animation(.easeInOut(duration: 0.1), value: dropTargetActionID)
                    .animation(.easeInOut(duration: 0.1), value: isFavoritesHeaderTargeted)
                }
                .scrollIndicators(.hidden)

                // K.unify.2 : bouton « Nouvelle action » dédié en bas,
                // séparé par Divider. Toujours visible (plus de cap). La
                // nouvelle action a category=nil + isFavorite=false par
                // défaut → va dans « Sans catégorie » quel que soit le
                // filtre actif (l'utilisateur peut la voir via le filtre
                // « Sans catégorie » ou « Toutes »).
                Divider()
                Button {
                    addNewAction()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13))
                        Text("Nouvelle action")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(red: 0.0, green: 0.584, blue: 1.0))

                // Footer sidebar : import / export (Phase 2.4 + 6.13)
                Divider()
                HStack(spacing: 8) {
                    // Phase 6.13 (2026-04-25) : menu déroulant pour choisir
                    // le format d'export. JSON pour la sauvegarde / ré-import,
                    // Markdown pour la lecture humaine / archivage / partage.
                    Menu {
                        Button {
                            exportActionsToFile()
                        } label: {
                            Label("Sauvegarde JSON", systemImage: "doc.badge.gearshape")
                        }
                        Button {
                            exportActionsAsMarkdown()
                        } label: {
                            Label("Lecture Markdown", systemImage: "doc.richtext")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11))
                            Text("Exporter")
                                .font(.system(size: 11))
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        importActionsFromFile()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 11))
                            Text("Importer")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            // F.4 C3 : 280 → 380 (ratio ~38/62 à la fenêtre 1000pt de
            // l'onglet Actions) — les noms d'actions respirent.
            .frame(width: 380)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            // Editor or Empty State
            //
            // Mini-session bug fix (2026-05-08) : la parent @State
            // `selectedAction` peut être STALE — Phase 6.8c-fix avait retiré
            // la réassignation de `selectedAction` dans `onSave` (ci-dessous)
            // pour éviter des boucles de re-render pendant la frappe. Le
            // trade-off : la snapshot du parent reste figée à la dernière
            // valeur posée par `addNewAction` ou par un clic sidebar, et
            // diverge du store dès la première frappe utilisateur.
            //
            // Tant que `ActionsSettingsView` reste vivante, l'éditeur a son
            // propre `@State var action` qui suit l'utilisateur — pas de bug
            // visible. Mais au tab switch (`Group.id(selectedTab)` dans
            // SettingsView détruit puis recrée cette vue), l'éditeur est
            // recréé avec la valeur stale du parent → champs vides au retour
            // sur l'onglet Actions après un détour par Modèles.
            //
            // Fix : on re-fetch toujours depuis le store par id avant de
            // construire l'éditeur. Coût : O(n) avec n ≤ 15 (cap V1) =
            // trivial. Aucune mutation, aucun risque de réintroduire le
            // render-loop documenté en Phase 6.8c-fix.
            if let staleSelected = selectedAction,
               let action = store.actions.first(where: { $0.id == staleSelected.id }) {
                ActionEditorView(
                    action: action,
                    onSave: { updatedAction in
                        // Phase 6.8c-fix : on ne réassigne PLUS `selectedAction`
                        // ici — le store est @Published, la sidebar (qui itère
                        // `store.actions`) se met à jour seule, et `.id(action.id)`
                        // ci-dessous préserve l'instance de l'éditeur. Réassigner
                        // `selectedAction` à chaque sauvegarde provoquait des
                        // boucles de re-render pendant la frappe et faisait planter
                        // l'app (timer firing pendant view update).
                        store.updateAction(updatedAction)
                    },
                    onDelete: {
                        deleteSelectedAction()
                    }
                )
                .id(action.id)
            } else {
                // Empty state with dot pattern background
                ZStack {
                    // Dot pattern background (canvas style)
                    DotPatternView()

                    VStack(spacing: 24) {
                        // Command icon - 3D style like keyboard key
                        Keyboard3DKeyLarge()

                        VStack(spacing: 10) {
                            Text("Aucune action sélectionnée")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.primary)

                            Text("Crée une nouvelle action ou sélectionnes-en\nune dans la liste.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                        }

                        // Bouton « Nouvelle action ».
                        // Mini-session 2026-05-08 : remplace le custom 3D
                        // « Duolingo » hérité de TexTab par le style système
                        // macOS, cohérent avec le pattern adopté en Session 5
                        // pour l'onboarding (cf. `Onboarding/WelcomeStep.swift`
                        // → bouton « Commencer ») — `.borderedProminent` +
                        // `.controlSize(.large)`. Ajout du SF Symbol `plus`
                        // via `Label` : renforce l'intention de création,
                        // convention macOS (Finder, Calendar, Notes), et
                        // cohérent avec le « + » placeholder de
                        // `EmojiPickerButton` ajouté dans le commit précédent.
                        Button(action: {
                            addNewAction()
                        }) {
                            Label("Nouvelle action", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
            }   // closes the inner HStack(spacing: 0) { sidebar + editor }
        }
    }

    func addNewAction() {
        // K.unify.2 : cap `maxActions` supprimé — création illimitée.
        // La nouvelle action a category=nil + isFavorite=false par défaut
        // → apparaîtra dans « Sans catégorie ».
        let newAction = Action(
            name: "",
            icon: "star",
            prompt: ""
        )
        store.addAction(newAction)
        selectedAction = newAction
    }

    func deleteSelectedAction() {
        if let action = selectedAction {
            store.deleteAction(action)
            selectedAction = nil
        }
    }

    // MARK: - Export / Import JSON (Phase 2.4)

    private func exportActionsToFile() {
        guard let data = store.exportActionsData() else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.title = "Exporter les actions (sauvegarde)"
        panel.allowedContentTypes = [.json]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "loucede-actions-\(formatter.string(from: Date())).json"
        panel.canCreateDirectories = true
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
    }

    /// Phase 6.13 (2026-04-25) : export Markdown lisible humain (non
    /// ré-importable). Utile pour archivage, partage, lecture dans un
    /// renderer Markdown (Bear, Notion, GitHub…).
    private func exportActionsAsMarkdown() {
        guard let data = store.exportActionsMarkdown() else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.title = "Exporter les actions (Markdown)"
        // Le système s'assure que l'extension est .md (UTType.plainText
        // accepte tous les .md, .txt). On force .md via nameFieldStringValue.
        panel.allowedContentTypes = [.plainText]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "loucede-actions-\(formatter.string(from: Date())).md"
        panel.canCreateDirectories = true
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
    }

    private func importActionsFromFile() {
        let panel = NSOpenPanel()
        panel.title = "Importer des actions"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url) else { return }
            DispatchQueue.main.async {
                askImportStrategyThenImport(data: data)
            }
        }
    }

    /// Demande à l'utilisateur s'il veut remplacer ou fusionner, puis exécute l'import.
    /// L'alert natif macOS garantit une UX cohérente avec le reste du système.
    private func askImportStrategyThenImport(data: Data) {
        let alert = NSAlert()
        alert.messageText = "Importer les actions"
        alert.informativeText = "Veux-tu remplacer les actions actuelles par celles du fichier, ou les ajouter à la liste existante ?"
        alert.addButton(withTitle: "Remplacer")
        alert.addButton(withTitle: "Ajouter")
        alert.addButton(withTitle: "Annuler")
        let response = alert.runModal()
        let strategy: ActionsStore.ImportStrategy
        switch response {
        case .alertFirstButtonReturn:  strategy = .replace
        case .alertSecondButtonReturn: strategy = .append
        default: return
        }
        do {
            try store.importActions(from: data, strategy: strategy)
            selectedAction = nil
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Import impossible"
            errorAlert.informativeText = error.localizedDescription
            errorAlert.alertStyle = .warning
            errorAlert.addButton(withTitle: "OK")
            errorAlert.runModal()
        }
    }
}

// MARK: - Action List Row

struct ActionListRow: View {
    @Environment(\.colorScheme) var colorScheme
    let action: Action
    let isSelected: Bool
    /// K.unify.2 : closures injectées depuis le call-site pour basculer
    /// les booléens isFavorite/isHidden via les icônes étoile/œil.
    var onToggleFavorite: () -> Void
    var onToggleHidden: () -> Void

    // Selected background color: #f1f1ef for light mode, accentColor opacity for dark mode
    var selectedBackgroundColor: Color {
        if !isSelected {
            return Color.clear
        }
        return colorScheme == .light
            ? Color(red: 241/255, green: 241/255, blue: 239/255)
            : Color.accentColor.opacity(0.1)
    }

    // Adaptive gray: darker in light mode, lighter in dark mode
    var textGrayColor: Color {
        colorScheme == .light
            ? Color(white: 0.35)
            : Color(white: 0.65)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Mini-session Point 3 pre-V1 (2026-05-08) : poignée de
            // drag-and-drop. Position fixe à gauche (convention macOS).
            // Toujours visible, couleur secondaire pour rester discrète.
            // Curseur `openHand` au survol (distinct du `pointingHand`
            // utilisé pour les zones cliquables — signale spécifiquement
            // « drag » plutôt que « click »). La zone draggable est limitée
            // à cette poignée (`.draggable` apposé ICI), pas à toute la
            // ligne — sinon conflit avec l'`onTapGesture` de sélection
            // appliqué au call-site.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
                .draggable(action.id.uuidString) {
                    // Drag preview : mini-card icône + nom (cohérent avec
                    // le rendu de l'action dans la sidebar, mais isolée
                    // de la grille pour éviter qu'AppKit ne montre la
                    // pleine ligne avec backgrounds/dividers pendant le
                    // drag).
                    HStack(spacing: 8) {
                        ActionIconView(icon: action.icon, boxSize: 24, fontSize: 18)
                        Text(action.name.isEmpty ? "Nouvelle action" : action.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(textGrayColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
                .onHover { hovering in
                    if hovering {
                        NSCursor.openHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }

            // Icon (Phase 6.4 : emoji via ActionIconView, avec fallback
            // placeholder gris pour les SF legacy non migrés)
            ActionIconView(icon: action.icon, boxSize: 24, fontSize: 18)

            // Name — Phase 1.5d : .semibold → .bold pour lisibilité / hiérarchie visuelle
            Text(action.name.isEmpty ? "Nouvelle action" : action.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(textGrayColor)
                .lineLimit(1)

            Spacer()

            // K.unify.2 : étoile (favoris) + œil (masqué/visible).
            // SF Symbols, fond rond léger au survol, accentColor pour
            // l'état actif (favori ou masqué).
            Button(action: onToggleFavorite) {
                Image(systemName: action.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(action.isFavorite ? Color.yellow : Color.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(action.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")

            Button(action: onToggleHidden) {
                Image(systemName: action.isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(action.isHidden ? Color.accentColor : Color.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(action.isHidden ? "Afficher dans la popup" : "Masquer de la popup")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selectedBackgroundColor)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Action Editor

struct ActionEditorView: View {
    @Environment(\.colorScheme) var colorScheme
    @State var action: Action
    var onSave: (Action) -> Void
    var onDelete: () -> Void

    /// Observation du store pour l'aperçu de test du prompt (provider /
    /// modèle / clé API courants). Singleton partagé : `@ObservedObject`
    /// est sûr ici (pas de cycle d'init multiple).
    @ObservedObject private var store = ActionsStore.shared

    @State private var isImprovingPrompt = false
    @State private var isNameFocused = false
    @State private var showDeleteConfirmation = false

    /// Phase 6.8c : sauvegarde automatique debouncée (300 ms). Le bouton
    /// « Enregistrer » a été retiré — l'utilisateur oubliait systématiquement
    /// de cliquer. À la disparition du composant (changement d'action sélectionnée
    /// dans la sidebar), on flush un dernier `onSave` pour ne jamais perdre la
    /// frappe en cours.
    ///
    /// Phase 6.8c-fix : le `Timer.scheduledTimer` initial faisait planter l'app
    /// à chaque modification (timer firing en plein view update + boucle de
    /// re-render via `selectedAction = updatedAction` côté parent). On a
    /// remplacé par un `DispatchWorkItem` (cancellation propre, pas de souci
    /// de RunLoop mode pendant les interactions menu) et on capture la valeur
    /// d'`action` au moment du planning plutôt qu'une référence vers `self`.
    @State private var pendingSaveWork: DispatchWorkItem?

    private func scheduleSave() {
        pendingSaveWork?.cancel()
        let snapshot = action
        let saveCallback = onSave
        let work = DispatchWorkItem {
            saveCallback(snapshot)
        }
        pendingSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // Input background color: #f1f1ef for light mode, controlBackgroundColor for dark mode
    var inputBackgroundColor: Color {
        colorScheme == .light
            ? Color(red: 241/255, green: 241/255, blue: 239/255)
            : Color(NSColor.controlBackgroundColor)
    }

    // Adaptive gray: darker in light mode, lighter in dark mode
    var textGrayColor: Color {
        colorScheme == .light
            ? Color(white: 0.35)
            : Color(white: 0.65)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                        // Header with icon and name
                        HStack(spacing: 12) {
                            // Phase 6.10 (2026-04-25) : bouton-emoji qui ouvre
                            // directement l'emoji picker système ancré dessous,
                            // sans popover custom. Cf. EmojiPickerButton dans
                            // IconPickerView.swift.
                            EmojiPickerButton(icon: $action.icon, boxSize: 36, fontSize: 24)
                                .onChange(of: action.icon) { _, _ in
                                    scheduleSave()
                                }

                            TextField("Nouvelle action", text: $action.name, onEditingChanged: { editing in
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                    isNameFocused = editing
                                }
                            })
                                .textFieldStyle(.plain)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(textGrayColor)
                                .scaleEffect(isNameFocused ? 1.05 : 1.0, anchor: .leading)
                                .onChange(of: action.name) { _, _ in
                                    scheduleSave()
                                }

                            Spacer()
                        }

                    // K.0 : bloc « Raccourci clavier » (lecture seule,
                    // Phase 6.8d-bis) retiré — les raccourcis ⌘1-⌘N
                    // positionnels ont été supprimés (navigation flèches + ↵).

                    // K.unify.2 : bloc « Catégorie + Afficher dans la popup ».
                    // Remplace l'ancien « Ajouter aux Modèles » (concept caduque
                    // avec le modèle unifié). `shortDescription` reste éditable
                    // via le champ ci-dessous (peuplé par les seeds, modifiable
                    // par l'utilisateur).
                    VStack(alignment: .leading, spacing: 14) {

                        // Menu déroulant catégorie. « Aucune catégorie » en bas
                        // correspond à `category = nil` (Sans catégorie). Case
                        // .custom exclue (DEPRECATED depuis K.unify.2).
                        HStack {
                            Text("Catégorie")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(textGrayColor)
                            Spacer()
                            Picker("Catégorie", selection: Binding(
                                get: { action.category },
                                set: { newCategory in
                                    action.category = newCategory
                                }
                            )) {
                                ForEach(PromptCategory.allCases.filter { $0 != .custom }, id: \.self) { cat in
                                    Text(cat.rawValue).tag(Optional(cat))
                                }
                                Divider()
                                Text("Aucune catégorie").tag(PromptCategory?.none)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .fixedSize()
                            .onChange(of: action.category) { _, _ in
                                scheduleSave()
                            }
                        }

                        // K.unify.2-fix-1 : Toggle « Afficher dans la popup »
                        // supprimé (redondant avec l'icône œil de
                        // ActionListRow — l'œil reste l'unique mécanisme).

                        // Description courte (≤80 signes) — héritée des seeds
                        // K.unify.1, modifiable. Sert à la popup K.unify.3
                        // (affichage discret sous le nom).
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Description courte")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(action.shortDescription?.count ?? 0) / 80")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor((action.shortDescription?.count ?? 0) > 80 ? .red : .secondary)
                            }

                            TextField(
                                "Optionnelle",
                                text: Binding(
                                    get: { action.shortDescription ?? "" },
                                    set: { newValue in
                                        action.shortDescription = String(newValue.prefix(80))
                                    }
                                )
                            )
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(textGrayColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(inputBackgroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                            )
                            .onChange(of: action.shortDescription) { _, _ in
                                scheduleSave()
                            }
                        }
                    }
                    .padding(16)
                    .background(inputBackgroundColor.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )

                    // Éditeur de prompt (V1 : toutes les actions sont de type .ai)
                    Group {
                        VStack(spacing: 0) {
                            ZStack(alignment: .topLeading) {
                                if action.prompt.isEmpty {
                                    Text("Saisis ton prompt ici")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(textGrayColor.opacity(0.6))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                }

                                TextEditor(text: $action.prompt)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(textGrayColor)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .onChange(of: action.prompt) { _, _ in
                                        scheduleSave()
                                    }
                            }
                            .frame(height: 220)

                            // Enhance button inside container
                            HStack {
                                Button(action: {
                                    improvePromptWithAI()
                                }) {
                                    HStack(spacing: 5) {
                                        ZStack {
                                            if isImprovingPrompt {
                                                ProgressView()
                                                    .scaleEffect(0.6)
                                            } else {
                                                Image(systemName: "sparkles")
                                                    .font(.system(size: 11))
                                            }
                                        }
                                        .frame(width: 14, height: 14)

                                        Text("Améliorer")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(NSColor.windowBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                    )
                                    .opacity(ActionsStore.shared.apiKey.isEmpty ? 0.4 : 1)
                                }
                                .buttonStyle(.plain)
                                .disabled(action.prompt.isEmpty || isImprovingPrompt || ActionsStore.shared.apiKey.isEmpty)
                                .help(ActionsStore.shared.apiKey.isEmpty ? "Ajoute une clé API dans l'onglet IA pour utiliser Améliorer" : "Améliorer le prompt avec l'IA")

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 10)
                        }
                        .background(inputBackgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )

                    }
                }
                .padding(24)
                }
                .scrollIndicators(.hidden)

                // Footer : Supprimer (gauche) + hint auto-save (droite).
                // Phase 6.8c : bouton « Enregistrer » retiré, remplacé par un
                // simple hint pour rassurer l'utilisateur que la sauvegarde
                // se fait bien en tâche de fond à chaque modification.
                HStack {
                    Button(action: {
                        if showDeleteConfirmation {
                            onDelete()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showDeleteConfirmation = true
                            }
                            // Reset after 3 seconds if not confirmed
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showDeleteConfirmation = false
                                }
                            }
                        }
                    }) {
                        Text(showDeleteConfirmation ? "Confirmer ?" : "Supprimer")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.red)
                            .padding(.horizontal, showDeleteConfirmation ? 16 : 0)
                            .padding(.vertical, showDeleteConfirmation ? 8 : 0)
                            .background(
                                Capsule()
                                    .fill(showDeleteConfirmation ? Color.red.opacity(0.15) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("Sauvegarde auto")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color(NSColor.windowBackgroundColor))
            }
            .onDisappear {
                // Flush la sauvegarde en attente si l'utilisateur change d'action
                // avant l'expiration du debounce 300 ms — on ne perd jamais la
                // dernière frappe. Si rien n'est en attente, on ne sauve PAS :
                // un onSave inconditionnel ré-écrirait l'action après une
                // suppression et restaurerait un fantôme dans la sidebar.
                if let pending = pendingSaveWork {
                    pending.cancel()
                    pendingSaveWork = nil
                    onSave(action)
                }
            }
            // Phase 6.10 : le popover custom EmojiPickerView a été retiré.
            // Le bouton emoji (EmojiPickerButton ci-dessus) ouvre désormais
            // directement le sélecteur emoji système ancré sous lui.
        }
    }

    func improvePromptWithAI() {
        let store = ActionsStore.shared
        guard !store.apiKey.isEmpty else { return }

        isImprovingPrompt = true

        let provider = store.selectedProvider
        let model = store.selectedModel
        let apiKey = store.apiKey

        Task {
            do {
                let improvedPrompt = try await PromptImprover.improve(
                    prompt: action.prompt,
                    provider: provider,
                    model: model,
                    apiKey: apiKey
                )
                await MainActor.run {
                    action.prompt = improvedPrompt
                    scheduleSave()
                    isImprovingPrompt = false
                }
            } catch {
                await MainActor.run {
                    isImprovingPrompt = false
                }
            }
        }
    }
}

// MARK: - Shortcut Tooltip

struct ShortcutTooltip: View {
    let recordedKeys: [String]
    var conflictName: String? = nil

    private var hasConflict: Bool { conflictName != nil }

    // Pad to at least 3 slots so all keys are visible
    private var displaySlots: [(id: String, text: String, filled: Bool)] {
        let slotCount = max(recordedKeys.count, 3)
        return (0..<slotCount).map { index in
            if index < recordedKeys.count {
                return (id: "slot-\(index)-\(recordedKeys[index])", text: recordedKeys[index], filled: true)
            } else {
                return (id: "empty-\(index)", text: "", filled: false)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tooltip content
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    if !hasConflict {
                        Text("ex.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    ForEach(displaySlots, id: \.id) { slot in
                        TooltipKey(text: slot.text, isError: hasConflict && slot.filled)
                            .opacity(slot.filled ? 1 : 0.4)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }

                if let conflictName = conflictName {
                    VStack(spacing: 4) {
                        Text("Déjà utilisé")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.red)

                        Text("Utilisé par « \(conflictName) »")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.8))
                    }
                } else {
                    VStack(spacing: 4) {
                        Text("Enregistrement…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        Text("Appuie sur \u{2318} ou \u{2325} + touche")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(hasConflict ? Color.red.opacity(0.5) : Color.gray.opacity(0.1), lineWidth: hasConflict ? 2 : 1)
            )

            // Arrow pointing down
            TooltipArrow()
                .fill(Color(NSColor.windowBackgroundColor))
                .frame(width: 16, height: 10)
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 2)
        }
    }
}

struct TooltipKey: View {
    @Environment(\.colorScheme) var colorScheme
    let text: String
    var isError: Bool = false

    var body: some View {
        ZStack {
            // Bottom layer (3D effect)
            RoundedRectangle(cornerRadius: 6)
                .fill(isError ? Color.red.opacity(0.6) : (colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.7)))
                .frame(width: 28, height: 28)
                .offset(y: 2)

            // Top layer
            RoundedRectangle(cornerRadius: 6)
                .fill(isError ? Color.red.opacity(0.15) : (colorScheme == .dark ? Color.white : Color(white: 0.95)))
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isError ? Color.red.opacity(0.5) : Color.gray.opacity(colorScheme == .dark ? 0 : 0.3), lineWidth: isError ? 2 : 1)
                )

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isError ? .red : .black)
        }
        .frame(width: 28, height: 30)
    }
}

struct TooltipArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Prompt Improver

class PromptImprover {
    enum PromptImproverError: Error {
        case noApiKey
        case invalidResponse
        case networkError(Error)
    }

    static func improve(prompt: String, provider: AIProvider, model: AIModel, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw PromptImproverError.noApiKey
        }

        let url = URL(string: provider.baseURL)!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Set authorization header based on provider
        if provider == .anthropic {
            request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let systemPrompt = """
        Tu es expert dans l'écriture de prompts pour des applications de transformation de texte.

        L'utilisateur te donne une idée basique, et tu la développes en un prompt détaillé qui guidera une IA pour transformer du texte.

        RÈGLES :
        - Écris des instructions claires décrivant le style, le ton et les caractéristiques attendus
        - Inclus les techniques et qualités spécifiques que le texte doit avoir
        - N'inclus PAS de phrases comme « Retourne uniquement le texte » ou « sans explications » à la fin
        - Ne commence PAS par « Réécris » ou « Transforme »
        - Conserve la même langue que celle de l'utilisateur

        EXEMPLES :
        Entrée : « formel »
        Sortie : « Utilise un langage professionnel et formel. Emploie un vocabulaire soutenu, une grammaire irréprochable et un ton respectueux adapté à la communication d'affaires. Évite les contractions et les tournures familières. »

        Entrée : « drôle »
        Sortie : « Ajoute de l'humour et de l'esprit au texte. Utilise un langage joueur, des jeux de mots astucieux et un ton léger. Glisse des observations amusantes tout en préservant le message de fond. »

        Entrée : "make it romantic"
        Sortie : "Use poetic and evocative language to express deep emotions. Include metaphors, sensory descriptions, and a passionate yet sincere tone that highlights beauty and connection."

        Retourne UNIQUEMENT le prompt amélioré, rien d'autre.
        """

        let body: [String: Any]

        if provider == .anthropic {
            body = [
                "model": model.id,
                "max_tokens": 1024,
                "system": systemPrompt,
                "messages": [
                    ["role": "user", "content": "Améliore ce prompt : \(prompt)"]
                ]
            ]
        } else {
            body = [
                "model": model.id,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": "Améliore ce prompt : \(prompt)"]
                ]
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        // Parse response based on provider
        if provider == .anthropic {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? [[String: Any]],
               let firstContent = content.first,
               let text = firstContent["text"] as? String {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        throw PromptImproverError.invalidResponse
    }
}

// MARK: - Preview

#Preview {
    ActionsSettingsView(selectedAction: .constant(nil))
        .frame(width: 700, height: 520)
}
