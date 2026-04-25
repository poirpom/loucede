//
//  ActionsView.swift
//  typo
//
//  Actions settings view for managing user actions
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Actions Settings

struct ActionsSettingsView: View {
    @StateObject private var store = ActionsStore.shared
    @Binding var selectedAction: Action?

    /// Hauteur d'une ligne d'action dans la sidebar, paddings inclus.
    /// Phase 6.11c : utilisée pour dimensionner exactement la `List` à la
    /// hauteur de son contenu (sinon SwiftUI laisse de l'espace mort entre
    /// la List et les EmptySlotRow en dessous).
    /// Composition : icône 24pt + padding vertical (8 + 8) + `listRowInsets`
    /// vertical (1 + 1) = 42pt par row.
    private let rowHeight: CGFloat = 42

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar - Actions list
            VStack(alignment: .leading, spacing: 0) {
                // Phase 6.11c (2026-04-25) : la liste des actions remplies
                // passe en `List` SwiftUI pour bénéficier de `.onMove` (drag &
                // drop natif). Les slots vides restent dans un `ForEach`
                // séparé en-dessous, intouchables au drag — sinon `onMove`
                // permettrait de drag depuis un slot vide, UX confuse.
                //
                // Styling adapté pour matcher le rendu pré-6.11c (`.plain`
                // + séparateurs cachés + fonds transparents + paddings calés).
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 8) // marge top
                        // Liste draggable des actions remplies.
                        List {
                            ForEach(Array(store.actions.enumerated()), id: \.element.id) { position, action in
                                ActionListRow(
                                    action: action,
                                    position: position,
                                    isSelected: selectedAction?.id == action.id
                                )
                                .onTapGesture {
                                    selectedAction = action
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                            }
                            .onMove { source, destination in
                                // Le `selectedAction` reste pointé sur la même
                                // Action (id stable) — la sélection est donc
                                // préservée même si la position change. C'est
                                // le comportement attendu (Q1 = A).
                                store.moveActions(fromOffsets: source, toOffset: destination)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)  // scroll géré par le ScrollView parent
                        // Hauteur dynamique : exactement ce qu'il faut pour les
                        // actions présentes, pas plus. Sans ça, la `List` se
                        // donne une hauteur arbitraire qui crée un trou avant
                        // les slots vides.
                        .frame(height: rowHeight * CGFloat(store.actions.count))

                        // Slots vides (non-draggables, non-droppables).
                        // Le premier slot après les actions remplies est
                        // tappable pour créer une nouvelle action.
                        ForEach(store.actions.count..<ActionsStore.maxActions, id: \.self) { position in
                            EmptySlotRow(
                                position: position,
                                isNextAvailable: position == store.actions.count
                            )
                            .onTapGesture {
                                if position == store.actions.count {
                                    addNewAction()
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                        }

                        Spacer().frame(height: 8) // marge bottom
                    }
                }
                .scrollIndicators(.hidden)

                // Footer sidebar : import / export JSON (Phase 2.4)
                Divider()
                HStack(spacing: 8) {
                    Button {
                        exportActionsToFile()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11))
                            Text("Exporter")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.plain)
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
            .frame(width: 280)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            // Editor or Empty State
            if let action = selectedAction {
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

                        // Bouton "Nouvelle action" - style 3D Duolingo
                        Button(action: {
                            addNewAction()
                        }) {
                            Text("Nouvelle action")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 40)
                                .padding(.vertical, 12)
                                .background(
                                    ZStack {
                                        // Bottom layer (3D effect) - darker blue
                                        RoundedRectangle(cornerRadius: 22)
                                            .fill(Color(red: 0.0, green: 0.45, blue: 0.8))
                                            .offset(y: 4)

                                        // Top layer - #0095ff
                                        RoundedRectangle(cornerRadius: 22)
                                            .fill(Color(red: 0.0, green: 0.584, blue: 1.0))
                                    }
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }

    func addNewAction() {
        // Phase 6.8d-bis : cap dur à 15 actions. La table `positionShortcuts`
        // ne contient que 15 entrées (⌘1-⌘0 + ⌘A/Z/E/R/T) ; au-delà il n'y a
        // plus de raccourci unique disponible. La UI empêche déjà d'arriver
        // jusqu'ici (les slots vides au-dessus du prochain libre ne sont
        // pas tappables), mais on garde la garde côté store par sécurité.
        guard store.actions.count < ActionsStore.maxActions else { return }
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
        panel.title = "Exporter les actions"
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
    /// Phase 6.8d-bis : position de l'action dans `store.actions`. Détermine
    /// le raccourci clavier ⌘+touche affiché à droite (table de référence
    /// dans `ActionsStore.positionShortcuts`).
    let position: Int
    let isSelected: Bool

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
            // Icon (Phase 6.4 : emoji via ActionIconView, avec fallback
            // placeholder gris pour les SF legacy non migrés)
            ActionIconView(icon: action.icon, boxSize: 24, fontSize: 18)

            // Name — Phase 1.5d : .semibold → .bold pour lisibilité / hiérarchie visuelle
            Text(action.name.isEmpty ? "Nouvelle action" : action.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(textGrayColor)
                .lineLimit(1)

            Spacer()

            // Phase 6.8d-bis : raccourci clavier déterminé par la position
            // dans la liste (plus de slotIndex stocké). Même rendu que dans
            // la popup, pour aider l'utilisateur à repérer visuellement ses
            // actions sans ouvrir chaque éditeur.
            if let s = ActionsStore.shortcut(forPosition: position) {
                KeyboardKey("⌘\(s.label)")
            }
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

// MARK: - Empty Slot Row (Phase 6.8d-bis)

/// Slot vide affiché dans la sidebar des Réglages. Montre déjà le raccourci
/// ⌘+touche qui sera attribué à la future action à cette position. Le slot
/// `isNextAvailable` (= immédiatement après la dernière action existante)
/// affiche un libellé « Nouvelle action » en bleu accent et est tappable
/// pour créer ; les autres slots ultérieurs sont neutres et non interactifs.
struct EmptySlotRow: View {
    @Environment(\.colorScheme) var colorScheme
    let position: Int
    let isNextAvailable: Bool

    var textColor: Color {
        if isNextAvailable {
            return Color(red: 0.0, green: 0.584, blue: 1.0)
        }
        return colorScheme == .light
            ? Color(white: 0.55)
            : Color(white: 0.45)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Boîte vide alignée sur l'icône d'une action remplie (24×24)
            // pour préserver l'alignement vertical de la liste.
            if isNextAvailable {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(textColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(textColor)
                }
                .frame(width: 24, height: 24)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(textColor.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: 24, height: 24)
            }

            Text(isNextAvailable ? "Nouvelle action" : "Slot disponible")
                .font(.system(size: 14, weight: isNextAvailable ? .bold : .medium))
                .foregroundColor(textColor)
                .lineLimit(1)

            Spacer()

            if let s = ActionsStore.shortcut(forPosition: position) {
                KeyboardKey("⌘\(s.label)")
                    .opacity(isNextAvailable ? 1 : 0.5)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Action Editor

struct ActionEditorView: View {
    @Environment(\.colorScheme) var colorScheme
    @State var action: Action
    var onSave: (Action) -> Void
    var onDelete: () -> Void

    /// Observation du store pour que le badge « Raccourci clavier ⌘X »
    /// (Phase 6.8d-bis) refresh si la position de l'action change suite à
    /// une suppression / un import. Singleton partagé : `@ObservedObject`
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

                    // Phase 6.8d-bis (2026-04-25) : raccourci clavier en
                    // lecture seule, déterminé par la position de l'action
                    // dans la liste. Plus de Picker manuel — l'utilisateur
                    // change le raccourci en réordonnant les actions (V1 :
                    // pas de drag-reorder, mais supprimer + recréer suffit).
                    if let position = store.position(of: action),
                       let shortcut = ActionsStore.shortcut(forPosition: position) {
                        HStack {
                            Text("Raccourci clavier")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            KeyboardKey("⌘\(shortcut.label)")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(inputBackgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )
                    }

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
