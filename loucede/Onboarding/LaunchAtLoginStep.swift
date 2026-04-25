//
//  LaunchAtLoginStep.swift
//  loucede
//
//  Phase 6.5b (2026-04-25) : étape onboarding qui propose à l'utilisateur
//  d'activer le lancement automatique de loucedé à l'ouverture de session.
//  Délègue à `LaunchAtLoginManager` (lui-même un wrapper sur SMAppService).
//
//  Style visuel aligné sur ShortcutStep (split gauche-blanc / droite-colorée
//  avec wavy edge) pour conserver le rythme visuel de la séquence
//  Permissions → Shortcut → LaunchAtLogin → Activation.
//

import SwiftUI

struct LaunchAtLoginStep: View {
    var onNext: () -> Void
    var onBack: () -> Void

    private let brandBlue = Color(hex: "0095ff")
    private let brandBlueDark = Color(hex: "0070cc")

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Côté gauche : formulaire blanc
            ZStack(alignment: .trailing) {
                Color.white

                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                        .frame(height: 40)

                    Text("Démarrage")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "1a1a1a"))

                    Spacer()
                        .frame(height: 10)

                    Text("Souhaites-tu que loucedé\ndémarre automatiquement\nà l'ouverture de session ?")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "666666"))
                        .lineSpacing(3)

                    Spacer()
                        .frame(height: 30)

                    // Bénéfices : 2 lignes courtes pour clarifier la valeur
                    VStack(alignment: .leading, spacing: 10) {
                        BenefitRow(
                            icon: "bolt.fill",
                            text: "Disponible dès l'allumage du Mac"
                        )
                        BenefitRow(
                            icon: "hand.tap.fill",
                            text: "Plus besoin de l'ouvrir manuellement"
                        )
                    }

                    Spacer()

                    // Bouton primaire : activer
                    Button(action: {
                        LaunchAtLoginManager.shared.setEnabled(true)
                        onNext()
                    }) {
                        Text("Activer")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                ZStack {
                                    // Bottom shadow layer (3D effect)
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(brandBlueDark)
                                        .offset(y: 5)

                                    // Main button
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(brandBlue)
                                }
                            )
                    }
                    .buttonStyle(LaunchAtLoginNoFadeButtonStyle())

                    Spacer()
                        .frame(height: 12)

                    // Bouton secondaire : passer
                    Button(action: {
                        // Pas d'appel à setEnabled(false) — l'état par défaut
                        // de SMAppService est `.notRegistered`, donc rien à faire.
                        onNext()
                    }) {
                        Text("Pas maintenant")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "666666"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                        .frame(height: 6)

                    Text("Modifiable à tout moment dans les réglages.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "999999"))
                        .frame(maxWidth: .infinity, alignment: .center)

                    Spacer()
                        .frame(height: 24)
                }
                .padding(.horizontal, 32)
                .padding(.trailing, 24)

                // Wavy edge — réutilise le composant existant en bleu via overlay
                LaunchWavyEdgeBlue()
                    .frame(width: 22)
                    .offset(x: 10)
            }
            .frame(width: 340)

            // MARK: - Côté droit : illustration bleue
            ZStack {
                brandBlue

                VStack(spacing: 24) {
                    Spacer()

                    // Grosse icône power animée
                    LaunchPowerIllustration()

                    // Tooltip d'info qui flotte
                    LaunchHintTooltip()

                    Spacer()
                }
                .padding(30)
            }
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Benefit Row

private struct BenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: "0095ff").opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "0095ff"))
            }
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "333333"))
        }
    }
}

// MARK: - Power Illustration (right side)

private struct LaunchPowerIllustration: View {
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.4

    var body: some View {
        ZStack {
            // Outer pulsing glow ring
            Circle()
                .stroke(Color.white.opacity(glowOpacity), lineWidth: 4)
                .frame(width: 200, height: 200)
                .scaleEffect(pulseScale)

            // Inner static circle
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 160, height: 160)

            // Power symbol
            Image(systemName: "power")
                .font(.system(size: 84, weight: .medium))
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
            ) {
                pulseScale = 1.15
                glowOpacity = 0.05
            }
        }
    }
}

// MARK: - Hint Tooltip (right side)

private struct LaunchHintTooltip: View {
    @State private var floatOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "0095ff"))
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
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
            ) {
                floatOffset = -6
            }
        }
    }
}

// MARK: - Wavy Edge (blue variant)

private struct LaunchWavyEdgeBlue: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let width = geo.size.width
                let height = geo.size.height
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
            .fill(Color(hex: "0095ff"))
        }
    }
}

// MARK: - No Fade Button Style

private struct LaunchAtLoginNoFadeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(1)
    }
}

// MARK: - Preview

#Preview {
    LaunchAtLoginStep(onNext: {}, onBack: {})
        .frame(width: 800, height: 520)
}
