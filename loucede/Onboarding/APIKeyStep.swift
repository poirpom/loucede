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

    private let brandViolet     = Color(hex: "6C5CE7")
    private let brandVioletDark = Color(hex: "5649C0")
    @Environment(\.colorScheme) private var colorScheme

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
        ZStack(alignment: .trailing) {
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

                Spacer()

                validateButton

                if showContinueAnyway {
                    Spacer().frame(height: 10)
                    continueAnywayButton
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer().frame(height: 8)

                skipButton

                Spacer().frame(height: 6)

                // Avertissement factuel — discret mais informatif
                Text("Une clé API est nécessaire pour utiliser loucedé.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "F39C12"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 4)

                Text("Modifiable à tout moment dans les réglages.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 32)
            .padding(.trailing, 24)
            .animation(.easeInOut(duration: 0.2), value: validationError)
            .animation(.easeInOut(duration: 0.2), value: showContinueAnyway)

            APIKeyWavyEdge()
                .frame(width: 22)
                .offset(x: 10)
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
            HStack(spacing: 8) {
                if isValidating {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text(isValidating ? "Validation…" : "Valider et continuer")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                ZStack {
                    // Shadow 3D — uniquement quand le bouton est actif pour éviter
                    // la transparence mutuelle "pâteuse" en disabled + dark mode
                    if isValidateEnabled {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(brandVioletDark)
                            .offset(y: 5)
                    }
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isValidateEnabled ? brandViolet : brandViolet.opacity(0.4))
                }
            )
            .shadow(
                color: colorScheme == .dark && isValidateEnabled
                    ? brandViolet.opacity(0.25) : .clear,
                radius: 4, x: 0, y: 2
            )
        }
        .buttonStyle(APIKeyNoFadeButtonStyle())
        .disabled(!isValidateEnabled)
    }

    private var continueAnywayButton: some View {
        Button(action: saveAndContinue) {
            Text("Continuer quand même")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(brandViolet)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .buttonStyle(.plain)
    }

    private var skipButton: some View {
        Button(action: { onNext() }) {
            Text("Configurer plus tard")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .buttonStyle(.plain)
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
            brandViolet
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
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(width: 88, height: 98)
        .background(
            RoundedRectangle(cornerRadius: 18)
                // Fond sombre translucide — rend les logos blancs (OpenAI)
                // et colorés (Mistral, Claude) visibles sur fond violet
                .fill(Color(hex: "2a1f6e").opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 6)
    }
}

private struct APIKeyHintTooltip: View {
    @State private var floatOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "6C5CE7"))
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

// MARK: - Wavy edge (violet)

private struct APIKeyWavyEdge: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let width       = geo.size.width
                let height      = geo.size.height
                let notchRadius: CGFloat = 4
                let notchSpacing: CGFloat = 20

                path.move(to: CGPoint(x: width, y: 0))
                path.addLine(to: CGPoint(x: width, y: height))
                path.addLine(to: CGPoint(x: 0, y: height))

                var y: CGFloat = height - notchSpacing / 2
                while y > 0 {
                    path.addLine(to: CGPoint(x: 0, y: y + notchRadius))
                    path.addArc(
                        center: CGPoint(x: 0, y: y),
                        radius: notchRadius,
                        startAngle: .degrees(90),
                        endAngle: .degrees(-90),
                        clockwise: true
                    )
                    y -= notchSpacing
                }

                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: width, y: 0))
                path.closeSubpath()
            }
            .fill(Color(hex: "6C5CE7"))
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

// MARK: - Button style

private struct APIKeyNoFadeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(1)
    }
}

// MARK: - Preview

#Preview {
    APIKeyStep(onNext: {}, onBack: {})
        .frame(width: 800, height: 520)
}
