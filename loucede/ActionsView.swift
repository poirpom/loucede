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

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar - Actions list
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.actions) { action in
                            ActionListRow(
                                action: action,
                                isSelected: selectedAction?.id == action.id
                            )
                            .onTapGesture {
                                selectedAction = action
                            }
                        }

                        // Nouvelle action - sous la dernière action
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .black))
                            Text("Nouvelle action")
                                .font(.system(size: 14, weight: .semibold))

                            Spacer()
                        }
                        .foregroundColor(Color(red: 0.0, green: 0.584, blue: 1.0))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 10)
                        .onTapGesture {
                            addNewAction()
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
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
            .frame(width: 220)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            // Editor or Empty State
            if let action = selectedAction {
                ActionEditorView(
                    action: action,
                    onSave: { updatedAction in
                        store.updateAction(updatedAction)
                        selectedAction = updatedAction
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
        // V1 : nombre d'actions illimité (licence personnelle).
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

    @State private var isImprovingPrompt = false
    @State private var hasUnsavedChanges = false
    @State private var showIconPicker = false
    @State private var isNameFocused = false
    @State private var showDeleteConfirmation = false

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
                            // Custom Icon Picker Button (Phase 6.4 : emoji)
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showIconPicker.toggle()
                                }
                            }) {
                                ActionIconView(icon: action.icon, boxSize: 36, fontSize: 24)
                            }
                            .buttonStyle(.plain)

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
                                    hasUnsavedChanges = true
                                }

                            Spacer()
                        }

                    // Slot clavier — position dans la rangée de chiffres du popup (1/& à 0/à).
                    // La sélection par keycode physique garantit la compat AZERTY/QWERTY.
                    SlotPicker(
                        slotIndex: $action.slotIndex,
                        conflictName: conflictName(for: action.slotIndex, excluding: action.id),
                        usedSlots: usedSlots(excluding: action.id),
                        onChange: { hasUnsavedChanges = true }
                    )
                    .background(inputBackgroundColor)
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
                                        hasUnsavedChanges = true
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

                // Footer with Delete and Saved buttons (fixed at bottom)
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

                    // Save button
                    Button(action: saveChanges) {
                        Text(hasUnsavedChanges ? "Enregistrer" : "Enregistré")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(red: 0.0, green: 0.584, blue: 1.0))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.0, green: 0.584, blue: 1.0).opacity(0.2))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasUnsavedChanges)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color(NSColor.windowBackgroundColor))
            }

            // Floating Icon Picker - above everything
            if showIconPicker {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showIconPicker = false
                        }
                    }

                EmojiPickerView(
                    selectedIcon: action.icon,
                    onSelect: { icon in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            action.icon = icon
                            hasUnsavedChanges = true
                            showIconPicker = false
                        }
                    }
                )
                .fixedSize(horizontal: true, vertical: true)
                .offset(x: 24, y: 68)
                .transition(.opacity)
            }
        }
    }

    /// Nom de l'action qui occupe déjà ce slot (hors action en cours d'édition), ou nil.
    /// Utilisé pour prévenir l'utilisateur qu'il va écraser une assignation existante.
    /// En pratique, avec `usedSlots` qui désactive les slots déjà pris, ce chemin
    /// ne devrait plus se déclencher à la sélection — gardé comme garde-fou pour
    /// les états existants (import de config, migration, etc.).
    private func conflictName(for slot: Int?, excluding actionId: UUID) -> String? {
        guard let slot = slot else { return nil }
        return ActionsStore.shared.actions.first {
            $0.id != actionId && $0.slotIndex == slot
        }?.name
    }

    /// Ensemble des slots occupés par d'autres actions (hors celle éditée).
    /// Passé à SlotPicker pour désactiver l'entrée correspondante dans le menu
    /// et éviter qu'un utilisateur attribue le même raccourci à deux actions.
    private func usedSlots(excluding actionId: UUID) -> Set<Int> {
        Set(ActionsStore.shared.actions
            .filter { $0.id != actionId }
            .compactMap { $0.slotIndex })
    }

    func saveChanges() {
        onSave(action)
        withAnimation {
            hasUnsavedChanges = false
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
                    hasUnsavedChanges = true
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
                        Text("e.g.")
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

// MARK: - Slot Picker (Phase 2)

/// Sélecteur de position clavier pour une action. `nil` = aucun raccourci.
/// Les libellés affichent d'abord la touche AZERTY FR (`&é"'(§è!çà`) puis la touche
/// QWERTY équivalente (`1234567890`), ce qui correspond au mapping des keycodes
/// physiques 18-29 utilisé dans PopoverView.
struct SlotPicker: View {
    @Binding var slotIndex: Int?
    let conflictName: String?
    /// Slots déjà attribués à d'autres actions — désactivés dans le menu pour
    /// empêcher l'utilisateur d'attribuer le même raccourci à deux actions.
    /// Le slot actuellement sélectionné par CETTE action n'y est PAS inclus
    /// (il reste sélectionnable / affichable).
    let usedSlots: Set<Int>
    var onChange: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Raccourci clavier")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: Binding(
                    get: { slotIndex ?? -1 },
                    set: { newValue in
                        slotIndex = (newValue == -1) ? nil : newValue
                        onChange()
                    }
                )) {
                    Text("Aucun").tag(-1)
                    ForEach(0..<10, id: \.self) { i in
                        // Phase 1.4g / Option B : raccourci déclenché par ⌘+chiffre
                        // (i=9 → ⌘0 par convention rangée clavier). Les chiffres
                        // sont affichés tels quels car indépendants du layout :
                        // ⌘+1 fonctionne identiquement en AZERTY et QWERTY.
                        Text("⌘\(i == 9 ? 0 : i + 1)")
                            .tag(i)
                            .disabled(usedSlots.contains(i))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
            }
            if let name = conflictName {
                Text("⚠︎ Déjà utilisé par « \(name) » — ce choix écrasera l'assignation précédente.")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
