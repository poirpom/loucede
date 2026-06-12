//
//  APIKeyStep.swift
//  loucede
//
//  Phase 7.2 (2026-04-29) : étape onboarding « Clé API ».
//  Insérée entre ShortcutStep (case 3) et LaunchAtLoginStep (case 5).
//
//  Comportement :
//   - Détection silencieuse du provider via préfixe (sk-ant- → Anthropic,
//     sk- → OpenAI). Badge animé (fade 200 ms) dès détection positive.
//   - Tentative Mistral quand pas de préfixe reconnu (badge "Mistral ?").
//   - Validation légère via 1 token avant sauvegarde.
//   - "Configurer plus tard" : skip sans sauvegarde (toujours visible).
//   - "Continuer quand même" : sauvegarde sans validation (après échec seulement).
//

import SwiftUI
import AppKit

// MARK: - Badge state

private enum BadgeState: Equatable {
    case none
    case confirmed(AIProvider)  // préfixe reconnu (sk-ant- ou sk-)
    case tentative              // Mistral présumé, validation en cours
}

// MARK: - APIKeyStep

struct APIKeyStep: View {
    var onNext: () -> Void
    var onBack: () -> Void

    // Étape 4 : vert pastel (Clé API → modèles d'API sur le site).
    // ProviderCards adaptées en blanc translucide pour rester lisibles
    // sur ce fond clair (cf. APIKeyProviderIllustration ci-dessous).
    private let brandPastel = Color(hex: "C8EDD8")

    @State private var keyInput           = ""
    @State private var badgeState         = BadgeState.none
    @State private var isValidating       = false
    @State private var validationError: String? = nil
    @State private var showContinueAnyway = false

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
            rightPanel
        }
        .ignoresSafeArea()
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)

            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 40)

                Text("Clé API")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer().frame(height: 10)

                Text("Configure ton fournisseur d'IA\npour utiliser loucedé. Tu peux\nutiliser Anthropic, OpenAI ou Mistral.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)

                Spacer().frame(height: 32)

                apiKeyField

                if let error = validationError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding(.top, 8)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }

                providerLinksSection

                Spacer().frame(height: 18)

                tutorialLinkButton

                Spacer()

                // Boutons système : Retour secondaire + Valider primaire
                HStack(spacing: 12) {
                    Button("Retour", action: onBack)
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    validateButton
                }

                if showContinueAnyway {
                    Spacer().frame(height: 10)
                    continueAnywayButton
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer().frame(height: 24)

                skipButton

                Spacer().frame(height: 6)

                // Avertissement factuel — discret mais informatif. Ferré
                // gauche pour cohérence avec le reste du panneau.
                Text("Une clé API est nécessaire pour utiliser loucedé.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "F39C12"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                Spacer().frame(height: 14)

                Text("Modifiable à tout moment dans les réglages.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 32)
            .animation(.easeInOut(duration: 0.2), value: validationError)
            .animation(.easeInOut(duration: 0.2), value: showContinueAnyway)
        }
        .frame(width: 340)
    }

    // MARK: - API key field with badge au-dessus

    private var apiKeyField: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // Badge détection — aligné à droite, fade in/out 200 ms
            if badgeState != .none {
                providerBadgeView
                    .transition(.opacity)
            }

            SecureField("Colle ta clé ici…", text: $keyInput)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 1.5)
                )
                .disabled(isValidating)
                .onChange(of: keyInput) { _, newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if let p = detectProvider(from: newValue) {
                            badgeState = .confirmed(p)
                        } else {
                            badgeState = .none
                        }
                    }
                    if validationError != nil {
                        withAnimation {
                            validationError = nil
                            showContinueAnyway = false
                        }
                    }
                }
        }
        .animation(.easeInOut(duration: 0.2), value: badgeState)
    }

    @ViewBuilder
    private var providerBadgeView: some View {
        switch badgeState {
        case .none:
            EmptyView()
        case .confirmed(let provider):
            HStack(spacing: 5) {
                Image(provider.iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                Text("\(provider.rawValue) détecté")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .tentative:
            HStack(spacing: 5) {
                Image(AIProvider.mistral.iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .opacity(0.6)
                Text("Mistral ?")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Buttons

    private var isValidateEnabled: Bool {
        !keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isValidating
    }

    private var validateButton: some View {
        Button(action: { Task { await performValidate() } }) {
            HStack(spacing: 6) {
                if isValidating {
                    ProgressView().controlSize(.small)
                }
                Text(isValidating ? "Validation…" : "Valider et continuer")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isValidateEnabled)
    }

    /// Action plus engagée que le simple skip — l'utilisateur force-pass
    /// après une erreur de validation. `.bordered` (pas `.plain`) pour
    /// signaler que c'est une décision active. Content-sized, ferré
    /// gauche via le parent VStack(.leading).
    private var continueAnywayButton: some View {
        Button("Continuer quand même", action: saveAndContinue)
            .buttonStyle(.bordered)
            .controlSize(.regular)
    }

    /// Skip total — `.plain` discret pour ne pas concurrencer le bouton
    /// primaire « Valider ». Content-sized, ferré gauche via le parent
    /// VStack(.leading).
    private var skipButton: some View {
        Button("Configurer plus tard →", action: { onNext() })
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    /// Lien texte vers le tuto PDF clé API (Q.2.f) — réplique exacte du
    /// style skipButton (« Configurer plus tard → ») : .plain, 14 semibold,
    /// secondary, sans curseur main. Ouvre le PDF bundlé dans le lecteur
    /// PDF système (NSWorkspace), pas de fenêtre interne.
    private var tutorialLinkButton: some View {
        Button("Comment obtenir une clé API →", action: openAPIKeyTutorial)
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    /// Échec silencieux assumé si le PDF manque au bundle (improbable :
    /// embarqué via la folder reference Resources/Documentation/).
    private func openAPIKeyTutorial() {
        guard let url = Bundle.main.url(forResource: "Tuto-cle-API-loucede",
                                        withExtension: "pdf",
                                        subdirectory: "Documentation") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Provider quick-links

    private var providerLinksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pas encore de clé ?")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            ProviderLinkButton(
                iconName: AIProvider.mistral.iconName,
                label:    "Mistral",
                url:      URL(string: "https://console.mistral.ai/api-keys/")!,
                tooltip:  "Obtenir une clé sur la console Mistral"
            )
            ProviderLinkButton(
                iconName: AIProvider.openai.iconName,
                label:    "OpenAI",
                url:      URL(string: "https://platform.openai.com/api-keys")!,
                tooltip:  "Obtenir une clé sur la console OpenAI"
            )
            ProviderLinkButton(
                iconName: AIProvider.anthropic.iconName,
                label:    "Anthropic",
                url:      URL(string: "https://console.anthropic.com/settings/keys")!,
                tooltip:  "Obtenir une clé sur la console Anthropic"
            )
        }
        .padding(.top, 14)
    }

    // MARK: - Right panel

    private var rightPanel: some View {
        ZStack {
            brandPastel
            APIKeyProviderIllustration()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Provider detection

    private func detectProvider(from key: String) -> AIProvider? {
        if key.hasPrefix("sk-ant-") { return .anthropic }
        if key.hasPrefix("sk-")     { return .openai }
        return nil
    }

    // MARK: - Validate action

    private func performValidate() async {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let detectedProvider = detectProvider(from: trimmed)
        let targetProvider   = detectedProvider ?? .mistral
        let isCertain        = detectedProvider != nil

        if !isCertain {
            withAnimation(.easeInOut(duration: 0.2)) { badgeState = .tentative }
        }

        isValidating    = true
        validationError = nil

        do {
            try await validateAPIKey(trimmed, for: targetProvider)
            // Succès → confirme le badge et sauvegarde
            withAnimation(.easeInOut(duration: 0.2)) {
                badgeState = .confirmed(targetProvider)
            }
            ActionsStore.shared.saveApiKey(trimmed, for: targetProvider)
            ActionsStore.shared.saveProvider(targetProvider)
            isValidating = false
            onNext()
        } catch {
            isValidating = false
            // Remet le badge à l'état pré-tentative
            withAnimation(.easeInOut(duration: 0.2)) {
                badgeState = detectedProvider.map { .confirmed($0) } ?? .none
            }
            withAnimation {
                validationError = isCertain
                    ? "Impossible de valider la clé. Vérifie qu'elle est correcte et active."
                    : "Format de clé non reconnu. Vérifie qu'il s'agit bien d'une clé Anthropic, OpenAI ou Mistral."
                showContinueAnyway = true
            }
        }
    }

    /// Sauvegarde sans validation (skip "Continuer quand même").
    private func saveAndContinue() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let provider = detectProvider(from: trimmed) ?? .mistral
            ActionsStore.shared.saveApiKey(trimmed, for: provider)
            ActionsStore.shared.saveProvider(provider)
        }
        onNext()
    }

    // MARK: - Lightweight API validation (1 token, timeout 10 s)

    private func validateAPIKey(_ key: String, for provider: AIProvider) async throws {
        let urlString: String
        let headers: [(String, String)]
        let body: [String: Any]

        switch provider {
        case .anthropic:
            urlString = "https://api.anthropic.com/v1/messages"
            headers = [
                ("x-api-key",          key),
                ("anthropic-version",  "2023-06-01"),
                ("Content-Type",       "application/json"),
            ]
            body = [
                "model":      "claude-haiku-4-5-20251001",
                "max_tokens": 1,
                "messages":   [["role": "user", "content": "Hi"]],
            ]
        case .openai:
            urlString = "https://api.openai.com/v1/chat/completions"
            headers = [
                ("Authorization", "Bearer \(key)"),
                ("Content-Type",  "application/json"),
            ]
            body = [
                "model":      "gpt-4o-mini",
                "max_tokens": 1,
                "messages":   [["role": "user", "content": "Hi"]],
            ]
        case .mistral:
            urlString = "https://api.mistral.ai/v1/chat/completions"
            headers = [
                ("Authorization", "Bearer \(key)"),
                ("Content-Type",  "application/json"),
            ]
            body = [
                "model":      "ministral-3b-latest",
                "max_tokens": 1,
                "messages":   [["role": "user", "content": "Hi"]],
            ]
        }

        var req = URLRequest(url: URL(string: urlString)!, timeoutInterval: 10)
        req.httpMethod = "POST"
        for (field, value) in headers { req.setValue(value, forHTTPHeaderField: field) }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

// MARK: - Provider Cards Illustration (right side)

private struct APIKeyProviderIllustration: View {
    @State private var floatOffset:    CGFloat = 0

    // Scales individuels pour le bounce séquentiel
    @State private var mistralScale:   CGFloat = 1.0
    @State private var openaiScale:    CGFloat = 1.0
    @State private var anthropicScale: CGFloat = 1.0

    // Flag de présence — stoppe la chaîne asyncAfter si la vue disparaît
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            // Trois cartes en éventail — Mistral au premier plan (🇫🇷)
            ZStack {
                // Anthropic — droite, derrière
                ProviderCard(iconName: AIProvider.anthropic.iconName, name: "Anthropic")
                    .rotationEffect(.degrees(13))
                    .offset(x: 52, y: 12)
                    .scaleEffect(anthropicScale)

                // OpenAI — gauche, derrière
                ProviderCard(iconName: AIProvider.openai.iconName, name: "OpenAI")
                    .rotationEffect(.degrees(-13))
                    .offset(x: -52, y: 12)
                    .scaleEffect(openaiScale)

                // Mistral — centre, premier plan 🇫🇷
                ProviderCard(iconName: AIProvider.mistral.iconName, name: "Mistral")
                    .scaleEffect(mistralScale)
            }
            .frame(width: 260, height: 150)
            .offset(y: floatOffset)
            .onAppear {
                isVisible = true
                // Float perpétuel
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    floatOffset = -8
                }
                // Bounce séquentiel — petite pause initiale pour laisser la vue s'installer
                scheduleBounceSequence(after: 0.6)
            }
            .onDisappear {
                isVisible = false
            }

            APIKeyHintTooltip()

            Spacer()
        }
        .padding(30)
    }

    // MARK: - Bounce séquentiel

    /// Séquence Mistral → OpenAI → Anthropic, puis boucle.
    ///
    /// Timings depuis `base` (= .now() + delay) :
    ///   t+0.0  Mistral ↑   t+0.2  Mistral ↓
    ///   t+0.6  OpenAI ↑    t+0.8  OpenAI ↓      (0.4 bounce + 0.2 pause)
    ///   t+1.2  Anthropic ↑ t+1.4  Anthropic ↓   (idem)
    ///   t+3.1  boucle suivante                   (0.4 Anthropic + 1.5 repos)
    ///   Cycle total ≈ 3.1 s
    private func scheduleBounceSequence(after delay: Double) {
        let b = DispatchTime.now() + delay

        // — Mistral —
        DispatchQueue.main.asyncAfter(deadline: b + 0.0) {
            guard isVisible else { return }
            withAnimation(.easeInOut(duration: 0.2)) { mistralScale = 1.05 }
        }
        DispatchQueue.main.asyncAfter(deadline: b + 0.2) {
            guard isVisible else { return }
            withAnimation(.easeInOut(duration: 0.2)) { mistralScale = 1.0 }
        }

        // — OpenAI —
        DispatchQueue.main.asyncAfter(deadline: b + 0.6) {
            guard isVisible else { return }
            withAnimation(.easeInOut(duration: 0.2)) { openaiScale = 1.05 }
        }
        DispatchQueue.main.asyncAfter(deadline: b + 0.8) {
            guard isVisible else { return }
            withAnimation(.easeInOut(duration: 0.2)) { openaiScale = 1.0 }
        }

        // — Anthropic —
        DispatchQueue.main.asyncAfter(deadline: b + 1.2) {
            guard isVisible else { return }
            withAnimation(.easeInOut(duration: 0.2)) { anthropicScale = 1.05 }
        }
        DispatchQueue.main.asyncAfter(deadline: b + 1.4) {
            guard isVisible else { return }
            withAnimation(.easeInOut(duration: 0.2)) { anthropicScale = 1.0 }
        }

        // — Boucle —
        DispatchQueue.main.asyncAfter(deadline: b + 3.1) {
            guard isVisible else { return }
            scheduleBounceSequence(after: 0.0)
        }
    }
}

private struct ProviderCard: View {
    let iconName: String
    let name: String

    var body: some View {
        VStack(spacing: 10) {
            Image(iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                // Couleur sombre FIXE : la card a un fond blanc translucide
                // fixe dans les 2 modes ; `.primary` passerait en blanc en
                // dark mode → illisible. On force du noir indépendamment du
                // Color Scheme.
                .foregroundStyle(Color.black)
        }
        .frame(width: 88, height: 98)
        .background(
            RoundedRectangle(cornerRadius: 18)
                // Étape 4 : fond blanc translucide pour relief clair sur
                // fond vert pastel. Les 3 logos (Mistral coloré, OpenAI
                // teal+blanc, Claude orange/cream) ont leur propre fond
                // intégré, ils restent visibles sur card blanche.
                .fill(Color.white.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }
}

private struct APIKeyHintTooltip: View {
    @State private var floatOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "3D8B5C"))
            Text("Au choix, ta propre clé")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "333333"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
        .offset(y: floatOffset)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                floatOffset = -6
            }
        }
    }
}

// MARK: - Provider link button

private struct ProviderLinkButton: View {
    let iconName: String
    let label:    String
    let url:      URL
    let tooltip:  String

    @State private var isHovered = false

    var body: some View {
        Button(action: { NSWorkspace.shared.open(url) }) {
            HStack(spacing: 8) {
                Image(iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(isHovered ? 0.04 : 0))
            )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    APIKeyStep(onNext: {}, onBack: {})
        .frame(width: 800, height: 520)
}
