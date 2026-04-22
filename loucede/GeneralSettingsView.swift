//
//  GeneralSettingsView.swift
//  loucede
//
//  Réglages généraux : API, préférences, permissions.
//

import SwiftUI

// MARK: - App Theme

enum AppTheme: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var displayName: String {
        switch self {
        case .system: return "Système"
        case .light:  return "Clair"
        case .dark:   return "Sombre"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

struct GeneralSettingsView: View {
    @StateObject private var store = ActionsStore.shared
    @State private var apiKeyInput: String = ""
    @State private var selectedProvider: AIProvider = .openai
    @State private var selectedModelId: String = ""
    @AppStorage("appTheme") private var appThemeString: String = "System"
    @State private var showModelTooltip: Bool = false
    @State private var isRecordingMainShortcut = false
    @State private var mainRecordedKeys: [String] = []
    @State private var mainShortcutConflict: String? = nil
    @State private var mainShortcutMonitor: Any? = nil
    @Environment(\.colorScheme) var colorScheme

    private var selectedTheme: AppTheme {
        get { AppTheme(rawValue: appThemeString) ?? .system }
    }

    private var availableModels: [AIModel] {
        AIModel.models(for: selectedProvider)
    }

    /// Renvoie le modelId persisté pour ce provider s'il est toujours
    /// dans la liste `availableModels`, sinon bascule sur le défaut et
    /// persiste immédiatement le nouveau choix pour nettoyer l'UserDefaults.
    /// Évite le cas où le Picker a un selection qui ne match aucun tag
    /// (ex. claude-3-5-sonnet-20241022 retiré de la liste) → Picker vide.
    private func resolvedModelId(for provider: AIProvider) -> String {
        let stored = store.modelId(for: provider)
        let validIds = AIModel.models(for: provider).map(\.id)
        if validIds.contains(stored) {
            return stored
        }
        let fallback = provider.defaultModelId
        store.saveModel(fallback, for: provider)
        return fallback
    }

    // App accent blue color
    private var appBlue: Color {
        Color(red: 0.0, green: 0.584, blue: 1.0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Section Configuration API
                VStack(alignment: .leading, spacing: 16) {
                    Text("Configuration API")
                        .font(.nunitoBold(size: 18))
                        .foregroundColor(.primary)

                    HStack {
                        HStack(spacing: 10) {
                            Image(systemName: "cpu")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.purple)
                            Text("Fournisseur IA")
                                .font(.nunitoRegularBold(size: 15))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 160, alignment: .leading)

                        Picker("", selection: $selectedProvider) {
                            ForEach(AIProvider.allCases, id: \.self) { provider in
                                Text(provider.rawValue).tag(provider)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: selectedProvider) { _, newValue in
                            store.saveProvider(newValue)
                            // Load saved model for this provider (auto-fallback si l'ID persisté n'est plus valide)
                            selectedModelId = resolvedModelId(for: newValue)
                            // Load API key for the new provider
                            apiKeyInput = store.apiKey(for: newValue)
                        }
                        .onAppear {
                            selectedProvider = store.selectedProvider
                            selectedModelId = resolvedModelId(for: store.selectedProvider)
                            apiKeyInput = store.apiKey(for: store.selectedProvider)
                        }

                        Picker("", selection: $selectedModelId) {
                            ForEach(availableModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: selectedModelId) { _, newValue in
                            store.saveModel(newValue)
                        }
                        .popover(isPresented: $showModelTooltip, arrowEdge: .bottom) {
                            if let model = availableModels.first(where: { $0.id == selectedModelId }) {
                                ModelSpecsTooltip(model: model)
                            }
                        }
                        .onHover { hovering in
                            showModelTooltip = hovering
                        }

                        Spacer()
                    }

                    HStack {
                        HStack(spacing: 10) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.orange)
                            Text("Clé API")
                                .font(.nunitoRegularBold(size: 15))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 160, alignment: .leading)

                        SecureField(selectedProvider.apiKeyPlaceholder, text: $apiKeyInput)
                            .textFieldStyle(.plain)
                            .font(.nunitoRegularBold(size: 13))
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .onChange(of: apiKeyInput) { _, newValue in
                                store.saveApiKey(newValue, for: selectedProvider)
                            }
                    }

                    Text("Obtenez votre clé API sur \(selectedProvider.websiteURL)")
                        .font(.nunitoRegularBold(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.leading, 160)
                }

                Divider()

                // Section Préférences
                VStack(alignment: .leading, spacing: 16) {
                    Text("Préférences")
                        .font(.nunitoBold(size: 18))
                        .foregroundColor(.primary)

                    VStack(spacing: 0) {
                        if isRecordingMainShortcut {
                            ShortcutTooltip(recordedKeys: mainRecordedKeys, conflictName: mainShortcutConflict)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.8, anchor: .bottom).combined(with: .opacity),
                                    removal: .scale(scale: 0.8, anchor: .bottom).combined(with: .opacity)
                                ))
                                .padding(.bottom, 8)
                        }

                        HStack {
                            HStack(spacing: 10) {
                                Image(systemName: "keyboard.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.pink)
                                Text("Raccourci global")
                                    .font(.nunitoRegularBold(size: 15))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: {
                                startRecordingMainShortcut()
                            }) {
                                HStack(spacing: 6) {
                                    ForEach(store.mainShortcutModifiers, id: \.self) { mod in
                                        Settings3DKey(text: mod)
                                    }
                                    Settings3DKey(text: store.mainShortcut)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.gray.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecordingMainShortcut)

                    HStack {
                        HStack(spacing: 10) {
                            Image(systemName: "paintbrush.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.indigo)
                            Text("Apparence")
                                .font(.nunitoRegularBold(size: 15))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 0) {
                            ForEach(AppTheme.allCases, id: \.self) { theme in
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        appThemeString = theme.rawValue
                                        applyTheme(theme)
                                    }
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: theme.icon)
                                            .font(.system(size: 12))
                                        Text(theme.displayName)
                                            .font(.nunitoRegularBold(size: 12))
                                    }
                                    .foregroundColor(selectedTheme == theme ? .white : .secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedTheme == theme ? appBlue : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(3)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.gray.opacity(0.1))
                        )
                    }
                }

                Divider()

                // Permissions Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Autorisations")
                        .font(.nunitoBold(size: 18))
                        .foregroundColor(.primary)

                    HStack {
                        HStack(spacing: 10) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Accessibilité")
                                    .font(.nunitoRegularBold(size: 15))
                                    .foregroundColor(.secondary)
                                Text("Requis pour les raccourcis clavier globaux")
                                    .font(.nunitoRegularBold(size: 12))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                        }

                        Spacer()

                        Button(action: {
                            openAccessibilitySettings()
                        }) {
                            Text("Ouvrir les réglages")
                                .font(.nunitoRegularBold(size: 13))
                                .foregroundColor(appBlue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(appBlue.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                #if DEBUG
                Divider()

                // Section Développeur (DEBUG uniquement)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Développeur")
                        .font(.nunitoBold(size: 18))
                        .foregroundColor(.primary)

                    HStack {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.red)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Réinitialiser l'onboarding")
                                    .font(.nunitoRegularBold(size: 15))
                                    .foregroundColor(.secondary)
                                Text("Réaffiche l'onboarding au prochain lancement")
                                    .font(.nunitoRegularBold(size: 12))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                        }

                        Spacer()

                        Button(action: {
                            OnboardingManager.shared.resetOnboarding()
                            NSApp.terminate(nil)
                        }) {
                            Text("Réinitialiser et quitter")
                                .font(.nunitoRegularBold(size: 13))
                                .foregroundColor(.red)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.red.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                #endif

                Spacer()
            }
            .padding(30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadSavedTheme()
        }
    }

    private func applyTheme(_ theme: AppTheme) {
        let appearance: NSAppearance?
        switch theme {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }

        NSApp.appearance = appearance
        // appThemeString is already set via @AppStorage, no need to save again
    }

    private func loadSavedTheme() {
        // Apply the theme from @AppStorage on appear
        applyTheme(selectedTheme)
    }

    private func stopRecordingMainShortcut() {
        if let monitor = mainShortcutMonitor {
            NSEvent.removeMonitor(monitor)
            mainShortcutMonitor = nil
        }
        isRecordingMainShortcut = false
        mainShortcutConflict = nil
        mainRecordedKeys = []
        globalAppDelegate?.resumeHotkeys()
    }

    private func startRecordingMainShortcut() {
        if let monitor = mainShortcutMonitor {
            NSEvent.removeMonitor(monitor)
            mainShortcutMonitor = nil
        }

        isRecordingMainShortcut = true
        mainRecordedKeys = []
        mainShortcutConflict = nil

        globalAppDelegate?.suspendHotkeys()

        let keyCodeMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: "."
        ]

        mainShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard self.isRecordingMainShortcut else { return event }

            if event.type == .keyDown && event.keyCode == 53 {
                withAnimation {
                    self.stopRecordingMainShortcut()
                }
                return nil
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            var currentModifiers: [String] = []
            if modifiers.contains(.control) { currentModifiers.append("^") }
            if modifiers.contains(.option) { currentModifiers.append("\u{2325}") }
            if modifiers.contains(.shift) { currentModifiers.append("\u{21E7}") }
            if modifiers.contains(.command) { currentModifiers.append("\u{2318}") }

            if event.type == .flagsChanged {
                self.mainShortcutConflict = nil
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    self.mainRecordedKeys = currentModifiers
                }
                return event
            }

            if event.type == .keyDown {
                let hasCommand = modifiers.contains(.command)
                let hasOption = modifiers.contains(.option)

                if !hasCommand && !hasOption {
                    return event
                }

                // On prend la lettre telle que le layout courant la produit
                // (charactersIgnoringModifiers respecte AZERTY/QWERTY), et on
                // ne retombe sur le dictionnaire QWERTY qu'en dernier recours.
                let key = event.charactersIgnoringModifiers?.uppercased() ?? keyCodeMap[event.keyCode] ?? ""
                if !key.isEmpty && key.count == 1 {
                    var finalKeys = currentModifiers
                    finalKeys.append(key)

                    // Depuis Phase 2 (2026-04-22) les actions n'ont plus de raccourci global
                    // individuel — la sélection se fait via les touches 1-9/0 *à l'intérieur*
                    // du popup, donc aucun conflit possible avec le main shortcut ici.

                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        self.mainRecordedKeys = finalKeys
                    }

                    // Save the new main shortcut
                    self.store.mainShortcutModifiers = currentModifiers
                    self.store.mainShortcut = key
                    self.store.mainShortcutKeyCode = event.keyCode
                    self.store.saveMainShortcut()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation {
                            self.stopRecordingMainShortcut()
                        }
                    }
                    return nil
                }
            }
            return event
        }
    }
}

// MARK: - Model Specs Tooltip

struct ModelSpecsTooltip: View {
    let model: AIModel
    @Environment(\.colorScheme) var colorScheme

    private var appBlue: Color {
        Color(red: 0.0, green: 0.584, blue: 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Model name with provider icon
            HStack(spacing: 8) {
                Image(model.provider.iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                Text(model.name)
                    .font(.nunitoBold(size: 15))
                    .foregroundColor(.primary)
            }

            // Description
            Text(model.specs.description)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Stats
            VStack(alignment: .leading, spacing: 8) {
                SpecsBar(label: "Vitesse", value: model.specs.speed)
                SpecsBar(label: "Intelligence", value: model.specs.intelligence)
                SpecsBar(label: "Coût tokens", value: model.specs.tokenUsage, inverted: true)
            }
        }
        .padding(14)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
    }
}

struct SpecsBar: View {
    let label: String
    let value: Int // 1-5
    var inverted: Bool = false // For token usage: higher value = lower consumption, so invert display

    private var appBlue: Color {
        Color(red: 0.0, green: 0.584, blue: 1.0)
    }

    // For inverted bars (like token usage), we flip the display
    // tokenUsage 5 (cheap) shows 1 bar, tokenUsage 1 (expensive) shows 5 bars
    private var displayValue: Int {
        inverted ? (6 - value) : value
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 75, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < displayValue ? appBlue : Color.gray.opacity(0.3))
                        .frame(width: 18, height: 6)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    GeneralSettingsView()
        .frame(width: 700, height: 520)
}
