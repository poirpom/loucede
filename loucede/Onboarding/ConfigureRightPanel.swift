//
//  ConfigureRightPanel.swift
//  loucede
//
//  Phase R : panneau droit contextuel de l'écran accordéon « Configure
//  loucedé ». Fond pastel par card (colorsets Any+Dark) + illustration
//  contextuelle. Trois illustrations sont reprises VERBATIM des anciens
//  steps (assets déjà shippés — leur palette interne est une décision
//  antérieure, pas un littéral du proto) ; la card Raccourci utilise le
//  nouveau composant `AZERTYKeyboard`.
//

import SwiftUI

struct ConfigureRightPanel: View {
    /// `nil` = accordéon tout replié (tout complété) → panneau « C'est prêt ».
    let card: OnboardingCard?
    let accessibilityGranted: Bool
    let shortcutModifiers: [String]
    let shortcutKey: String

    var body: some View {
        ZStack {
            pastel
            content
                .padding(30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pastel: Color {
        switch card {
        case .accessibility: return Color("OnboardPastelAccessibility")
        case .shortcut:      return Color("OnboardPastelShortcut")
        case .apiKey:        return Color("OnboardPastelApiKey")
        case .launch:        return Color("OnboardPastelLaunch")
        case .none:          return Color("OnboardPastelAccessibility")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch card {
        case .accessibility:
            AccessibilityStatusIllustration(granted: accessibilityGranted)
        case .shortcut:
            AZERTYKeyboard(modifiers: shortcutModifiers, key: shortcutKey)
        case .apiKey:
            ProviderCardsIllustration()
        case .launch:
            LaunchPowerIllustration()
        case .none:
            DonePanel()
        }
    }
}

// MARK: - Panneau « tout est prêt » (accordéon replié)

private struct DonePanel: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.green)
                .symbolEffect(.bounce)
            Text("Bien ouèj !")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                // Pastel fixe (clair dans les 2 modes) → texte forcé sombre
                // pour rester lisible en dark (même parti pris que ProviderCard).
                .foregroundStyle(Color.black)
        }
    }
}

// MARK: - Accessibilité : bulle de statut (reprise de PermissionsStep)

private struct AccessibilityStatusIllustration: View {
    let granted: Bool

    @State private var rotationAngle: Double = 0

    private let accentYellow = Color(hex: "F9A825")
    private let accentGreen  = Color(hex: "00ce44")

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(accentYellow)
                    .rotationEffect(.degrees(rotationAngle))
                    .opacity(granted ? 0 : 1)
                    .scaleEffect(granted ? 0.5 : 1)

                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(accentGreen)
                    .opacity(granted ? 1 : 0)
                    .scaleEffect(granted ? 1 : 0.5)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: granted)

            Text(granted ? "Accès accordé !" : "En attente d'accès")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(granted ? accentGreen : accentYellow)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.white))
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
    }
}

// MARK: - Clé API : éventail de cartes providers (repris de APIKeyStep)

private struct ProviderCardsIllustration: View {
    @State private var floatOffset:    CGFloat = 0
    @State private var mistralScale:   CGFloat = 1.0
    @State private var openaiScale:    CGFloat = 1.0
    @State private var anthropicScale: CGFloat = 1.0
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                ProviderCard(iconName: AIProvider.anthropic.iconName, name: "Anthropic")
                    .rotationEffect(.degrees(13))
                    .offset(x: 52, y: 12)
                    .scaleEffect(anthropicScale)

                ProviderCard(iconName: AIProvider.openai.iconName, name: "OpenAI")
                    .rotationEffect(.degrees(-13))
                    .offset(x: -52, y: 12)
                    .scaleEffect(openaiScale)

                ProviderCard(iconName: AIProvider.mistral.iconName, name: "Mistral")
                    .scaleEffect(mistralScale)
            }
            .frame(width: 260, height: 150)
            .offset(y: floatOffset)
            .onAppear {
                isVisible = true
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    floatOffset = -8
                }
                scheduleBounceSequence(after: 0.6)
            }
            .onDisappear { isVisible = false }

            ProviderHintTooltip()

            Spacer()
        }
    }

    private func scheduleBounceSequence(after delay: Double) {
        let b = DispatchTime.now() + delay
        DispatchQueue.main.asyncAfter(deadline: b + 0.0) {
            guard isVisible else { return }
            withAnimation(.easeInOut(duration: 0.2)) { mistralScale = 1.05 }
        }
        DispatchQueue.main.asyncAfter(deadline: b + 0.2) {
            guard isVisible else { return }
            withAnimation(.easeInOut(duration: 0.2)) { mistralScale = 1.0 }
        }
        DispatchQueue.main.asyncAfter(deadline: b + 0.6) {
            guard isVisible else { return }
            withAnimation(.easeInOut(duration: 0.2)) { openaiScale = 1.05 }
        }
        DispatchQueue.main.asyncAfter(deadline: b + 0.8) {
            guard isVisible else { return }
            withAnimation(.easeInOut(duration: 0.2)) { openaiScale = 1.0 }
        }
        DispatchQueue.main.asyncAfter(deadline: b + 1.2) {
            guard isVisible else { return }
            withAnimation(.easeInOut(duration: 0.2)) { anthropicScale = 1.05 }
        }
        DispatchQueue.main.asyncAfter(deadline: b + 1.4) {
            guard isVisible else { return }
            withAnimation(.easeInOut(duration: 0.2)) { anthropicScale = 1.0 }
        }
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
                .foregroundStyle(Color.black)
        }
        .frame(width: 88, height: 98)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }
}

private struct ProviderHintTooltip: View {
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

// MARK: - Démarrage : bouton power animé (repris de LaunchAtLoginStep)

private struct LaunchPowerIllustration: View {
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.30
    @State private var floatOffset: CGFloat = 0

    private let interfaceBlue = Color(hex: "3F84F7")

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(glowOpacity), lineWidth: 4)
                    .frame(width: 200, height: 200)
                    .scaleEffect(pulseScale)

                Circle()
                    .fill(interfaceBlue)
                    .frame(width: 160, height: 160)

                Image(systemName: "power")
                    .font(.system(size: 84, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    pulseScale = 1.15
                    glowOpacity = 0.05
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "6B4FB8"))
                Text("Toujours là quand tu en as besoin")
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

            Spacer()
        }
    }
}
