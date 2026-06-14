//
//  ConfigureView.swift
//  loucede
//
//  Phase R : écran mono-accordéon « Configure loucedé » qui remplace les
//  5 écrans de config séquentiels (Features/Permissions/Shortcut/APIKey/
//  LaunchAtLogin). 4 cards empilées, une seule ouverte à la fois, panneau
//  droit contextuel. La logique métier est recâblée sur les sources de
//  vérité existantes (ActionsStore, LaunchAtLoginManager, AXIsProcessTrusted)
//  via 2 helpers levés (ShortcutRecorder, APIKeyValidator) — managers
//  intouchés. Complétion dérivée live, rien de persisté en propre.
//
//  E.1 — couleurs SÉMANTIQUES adaptatives uniquement (windowBackgroundColor,
//  controlBackgroundColor, separatorColor, primary/secondary, .green system).
//

import SwiftUI
import AppKit

// MARK: - Card model

enum OnboardingCard: Int, CaseIterable, Identifiable {
    case accessibility, shortcut, apiKey, launch
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .accessibility: return "Accessibilité"
        case .shortcut:      return "Raccourci clavier"
        case .apiKey:        return "Clé API"
        case .launch:        return "Lancement au démarrage"
        }
    }

    var icon: String {
        switch self {
        case .accessibility: return "checkmark.shield.fill"
        case .shortcut:      return "keyboard"
        case .apiKey:        return "key.fill"
        case .launch:        return "power"
        }
    }

    var isRequired: Bool { self == .accessibility || self == .apiKey }
}

// MARK: - ConfigureView

struct ConfigureView: View {
    /// « Terminer » — passe à l'écran final.
    var onNext: () -> Void
    /// Retour au splash.
    var onBack: () -> Void

    @ObservedObject private var store = ActionsStore.shared
    @StateObject private var completion = OnboardingCompletion()
    @StateObject private var recorder = ShortcutRecorder()

    @State private var openCard: OnboardingCard = .accessibility
    @State private var launchEnabled = false

    // Card Raccourci : la coche n'apparaît qu'après un geste explicite
    // (saisie d'un raccourci custom OU « Utiliser le raccourci par défaut »).
    // Le raccourci reste optionnel — n'entre jamais dans `canFinish`.
    @State private var shortcutAcknowledged = false
    @State private var shortcutUsedDefault = false

    // Card Clé API
    @State private var keyInput = ""
    @State private var detectedProvider: AIProvider?
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var showContinueAnyway = false

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
                .frame(width: 550)
            ConfigureRightPanel(
                card: openCard,
                accessibilityGranted: completion.accessibilityGranted,
                shortcutModifiers: store.mainShortcutModifiers,
                shortcutKey: store.mainShortcut
            )
        }
        .ignoresSafeArea()
        .onAppear {
            completion.start()
            launchEnabled = LaunchAtLoginManager.shared.isEnabled
            openCard = firstIncomplete()
        }
        .onDisappear {
            completion.stop()
            recorder.stop()
        }
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)

            VStack(alignment: .leading, spacing: 0) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("Retour")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 24)

                Spacer().frame(height: 14)

                Text("Configure loucedé")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer().frame(height: 6)

                (Text("4 étapes, 2 minutes. ")
                 + Text("*").foregroundColor(.red)
                 + Text(" requis pour ses tours de magie."))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Spacer().frame(height: 20)

                // Accordéon
                VStack(spacing: 10) {
                    ForEach(OnboardingCard.allCases) { card in
                        accordionCard(card)
                    }
                }

                Spacer(minLength: 16)

                footer
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)

            HStack {
                Text(requiredRemainingLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Terminer", action: onNext)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canFinish)
            }
        }
    }

    // MARK: - Accordion card shell

    @ViewBuilder
    private func accordionCard(_ card: OnboardingCard) -> some View {
        let isOpen = openCard == card
        VStack(alignment: .leading, spacing: 0) {
            // Header cliquable
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    openCard = card
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: card.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(card.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    if card.isRequired {
                        Text("*").font(.system(size: 14, weight: .bold)).foregroundColor(.red)
                    }
                    Spacer()
                    if headerComplete(card) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.green)
                            .transition(.opacity.combined(with: .scale))
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 0 : -90))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Contenu déplié
            if isOpen {
                cardContent(card)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
                )
        )
    }

    // MARK: - Card contents

    @ViewBuilder
    private func cardContent(_ card: OnboardingCard) -> some View {
        switch card {
        case .accessibility: accessibilityContent
        case .shortcut:      shortcutContent
        case .apiKey:        apiKeyContent
        case .launch:        launchContent
        }
    }

    private var accessibilityContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permet les raccourcis globaux, la détection du texte sélectionné et le collage du texte transformé.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if completion.accessibilityGranted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                    Text("Permission accordée").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    accessibilityStepRow(1, "Clique sur « Autoriser l'accès »")
                    accessibilityStepRow(2, "Trouve loucedé dans la liste")
                    accessibilityStepRow(3, "Active l'interrupteur")
                }
                Button("Autoriser l'accès", action: openAccessibilityPrefs)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
    }

    private func accessibilityStepRow(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text("\(n)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color(NSColor.separatorColor).opacity(0.3)))
            Text(text).font(.system(size: 12)).foregroundStyle(.primary)
        }
    }

    private var shortcutContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clique ci-dessous pour le définir (ou garde celui par défaut qui est très bien).")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                recorder.start {
                    // Geste explicite : raccourci custom capturé.
                    withAnimation {
                        shortcutUsedDefault = false
                        shortcutAcknowledged = true
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    let keys = recorder.isRecording ? recorder.liveKeys
                                                    : store.mainShortcutModifiers + [store.mainShortcut]
                    if keys.isEmpty {
                        Text(recorder.isRecording ? "Appuie sur ⌘ ou ⌥ + touche…" : "Clique pour enregistrer…")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                            Text(key)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(NSColor.windowBackgroundColor))
                                        .overlay(RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1))
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .foregroundColor(Color(NSColor.separatorColor)))
                )
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: recorder.isRecording)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: recorder.liveKeys)

            if shortcutAcknowledged {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(.green)
                    Text(shortcutUsedDefault ? "Raccourci par défaut conservé" : "Raccourci enregistré")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else {
                Button("Utiliser le raccourci par défaut", action: useDefaultShortcut)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shortcutAcknowledged)
    }

    /// Écrit explicitement le raccourci par défaut (⌥&) dans ActionsStore et
    /// marque la card comme acquittée. Geste explicite équivalent à une saisie.
    private func useDefaultShortcut() {
        store.mainShortcutModifiers = ["\u{2325}"]
        store.mainShortcut = "&"
        store.mainShortcutKeyCode = 18
        store.saveMainShortcut()
        withAnimation {
            shortcutUsedDefault = true
            shortcutAcknowledged = true
        }
    }

    private var apiKeyContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anthropic, OpenAI ou Mistral — au choix, ta propre clé.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if store.hasUsableProvider {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(.green)
                    Text("Clé validée").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }

            // Badge détection
            if let p = detectedProvider {
                HStack(spacing: 5) {
                    Image(p.iconName).resizable().scaledToFit().frame(width: 14, height: 14)
                    Text("\(p.rawValue) détecté").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }

            SecureField("Colle ta clé ici…", text: $keyInput)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 1.5))
                )
                .disabled(isValidating)
                .onChange(of: keyInput) { _, newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        detectedProvider = APIKeyValidator.detectProvider(from: newValue)
                    }
                    if validationError != nil {
                        withAnimation { validationError = nil; showContinueAnyway = false }
                    }
                }

            if let error = validationError {
                Text(error).font(.system(size: 12)).foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            HStack(spacing: 10) {
                Button(action: { Task { await performValidate() } }) {
                    HStack(spacing: 6) {
                        if isValidating { ProgressView().controlSize(.small) }
                        Text(isValidating ? "Validation…" : "Valider la clé")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)

                if showContinueAnyway {
                    Button("Continuer quand même", action: saveAnyway)
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .transition(.opacity)
                }
            }

            HStack(spacing: 14) {
                providerLink("Mistral", "https://console.mistral.ai/api-keys/")
                providerLink("OpenAI", "https://platform.openai.com/api-keys")
                providerLink("Anthropic", "https://console.anthropic.com/settings/keys")
            }
            .padding(.top, 2)

            Button("Comment obtenir une clé API →", action: openAPIKeyTutorial)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .animation(.easeInOut(duration: 0.2), value: showContinueAnyway)
        .animation(.easeInOut(duration: 0.2), value: detectedProvider)
    }

    private func providerLink(_ label: String, _ urlString: String) -> some View {
        Button {
            if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 3) {
                Text(label).font(.system(size: 12))
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var launchContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Souhaites-tu que loucedé démarre automatiquement à l'ouverture de session ?")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: Binding(
                get: { launchEnabled },
                set: { newValue in
                    LaunchAtLoginManager.shared.setEnabled(newValue)
                    withAnimation { launchEnabled = LaunchAtLoginManager.shared.isEnabled }
                }
            )) {
                Text(launchEnabled ? "Activé — toujours là quand tu en as besoin" : "Lancer loucedé au démarrage")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
            }
            .toggleStyle(.switch)

            Text("Modifiable à tout moment dans les réglages.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func openAccessibilityPrefs() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openAPIKeyTutorial() {
        guard let url = Bundle.main.url(forResource: "Tuto-cle-API-loucede", withExtension: "pdf") else { return }
        NSWorkspace.shared.open(url)
    }

    private func performValidate() async {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let detected = APIKeyValidator.detectProvider(from: trimmed)
        let target = detected ?? .mistral
        let isCertain = detected != nil

        isValidating = true
        validationError = nil

        do {
            try await APIKeyValidator.validate(trimmed, for: target)
            store.saveApiKey(trimmed, for: target)
            store.saveProvider(target)
            isValidating = false
            // Clé OK → ouvre la première card encore incomplète (souvent Démarrage).
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                openCard = firstIncomplete()
            }
        } catch {
            isValidating = false
            withAnimation {
                validationError = isCertain
                    ? "Impossible de valider la clé. Vérifie qu'elle est correcte et active."
                    : "Format de clé non reconnu. Vérifie qu'il s'agit bien d'une clé Anthropic, OpenAI ou Mistral."
                showContinueAnyway = true
            }
        }
    }

    private func saveAnyway() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let p = APIKeyValidator.detectProvider(from: trimmed) ?? .mistral
            store.saveApiKey(trimmed, for: p)
            store.saveProvider(p)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            openCard = firstIncomplete()
        }
    }

    // MARK: - Completion logic (dérivée live)

    /// Coche du header : reflète l'état réel par card (Raccourci toujours
    /// OK car seed par défaut ; Démarrage suit `launchEnabled`).
    private func headerComplete(_ card: OnboardingCard) -> Bool {
        switch card {
        case .accessibility: return completion.accessibilityGranted
        case .apiKey:        return store.hasUsableProvider
        case .shortcut:      return shortcutAcknowledged   // coche explicite (geste requis)
        case .launch:        return launchEnabled
        }
    }

    /// Complétion pour le choix de la card à ouvrir : les optionnelles
    /// (Raccourci, Démarrage) comptent comme « faites » → ne captent pas le
    /// focus (E.4).
    private func focusComplete(_ card: OnboardingCard) -> Bool {
        switch card {
        case .accessibility: return completion.accessibilityGranted
        case .apiKey:        return store.hasUsableProvider
        case .shortcut, .launch: return true
        }
    }

    private func firstIncomplete() -> OnboardingCard {
        OnboardingCard.allCases.first { !focusComplete($0) } ?? .accessibility
    }

    private var canFinish: Bool {
        headerComplete(.accessibility) && headerComplete(.apiKey)
    }

    private var requiredRemaining: Int {
        [OnboardingCard.accessibility, .apiKey].filter { !headerComplete($0) }.count
    }

    private var requiredRemainingLabel: String {
        let n = requiredRemaining
        if n == 0 { return "Tout est bon, à toi de jouer" }
        let s = n > 1 ? "s" : ""
        return "\(n) étape\(s) requise\(s) restante\(s)"
    }

    private var progress: Double {
        let done = OnboardingCard.allCases.filter { headerComplete($0) }.count
        return Double(done) / Double(OnboardingCard.allCases.count)
    }
}
