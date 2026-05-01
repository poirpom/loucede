//
//  WelcomeStep.swift
//  loucede
//
//  Session 5 — Refonte premier écran d'onboarding (2026-05-01).
//
//  3 layouts en parallèle togglés via un pill picker dev (top-right) :
//  - Centré      : full pastel rose, wordmark + tagline + screenshot + bouton
//                  empilés verticalement, style "accueil cérémoniel"
//  - Split       : HStack 50/50, gauche = adaptive (windowBackgroundColor)
//                  + texte/bouton, droite = pastel rose + screenshot
//  - Full pastel : HStack 50/50, les DEUX panneaux en pastel rose
//
//  Le pill et les 2 layouts non retenus seront retirés au commit final
//  d'Étape 1 une fois le choix utilisateur tranché en runtime.
//

import SwiftUI

struct WelcomeStep: View {
    var onNext: () -> Void

    /// Mode d'affichage sélectionnable au runtime via le pill picker.
    /// Sera figé sur le mode retenu au commit final d'Étape 1.
    @State private var layoutMode: LayoutMode = .centered

    enum LayoutMode: String, CaseIterable, Identifiable {
        case centered   = "Centré"
        case split      = "Split"
        case fullPastel = "Full pastel"
        var id: String { rawValue }
    }

    // MARK: - Animation states (Étape 1 — cf. spec : on retire la wave,
    // on garde fade-in titre + spring bouton)

    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var buttonOffset: CGFloat = 50

    // MARK: - Couleur

    /// Rose pastel — couleur Welcome de la palette pastel V1
    /// (cf. mapping plan.md : Welcome → #FFD6E0).
    private let brandPastel = Color(hex: "FFD6E0")

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Layout actif
            Group {
                switch layoutMode {
                case .centered:   centeredLayout
                case .split:      splitLayout
                case .fullPastel: fullPastelLayout
                }
            }

            // Pill dev — à retirer au commit final d'Étape 1
            Picker("Layout", selection: $layoutMode) {
                ForEach(LayoutMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 200)
            .padding(12)
        }
        .onAppear {
            // Fade-in du titre
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                textOpacity = 1
            }
            // Spring du bouton
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6, blendDuration: 0).delay(0.5)) {
                buttonOpacity = 1
                buttonOffset = 0
            }
        }
    }

    // MARK: - Layout A : Centré

    @ViewBuilder
    private var centeredLayout: some View {
        ZStack {
            // Background full pastel
            brandPastel.ignoresSafeArea()

            VStack(spacing: 28) {
                // Bloc texte (wordmark + tagline)
                VStack(spacing: 6) {
                    // V1 : choix esthétique assumé (blanc sur rose pastel < AA WCAG).
                    // À revoir lors de l'audit a11y V1.1 : ombre renforcée OU couleur sombre.
                    Text("loucedé")
                        .font(.custom("IBMPlexMono-BoldItalic", size: 56))
                        .tracking(-1.7)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 3)

                    Text("Une IA au bout de tes doigts")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                }
                .opacity(textOpacity)

                // Screenshot du popup
                Image("PopupPreview")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 320)
                    .opacity(textOpacity)

                // Bouton "Commencer"
                commencerButton
                    .opacity(buttonOpacity)
                    .offset(y: buttonOffset)
            }
            .padding(.horizontal, 40)
            // Top padding compense la zone du pill picker en haut à droite
            .padding(.top, 24)
        }
    }

    // MARK: - Layout B.1 : Split classique

    @ViewBuilder
    private var splitLayout: some View {
        HStack(spacing: 0) {
            // Left panel : adaptive (windowBackgroundColor)
            ZStack {
                Color(NSColor.windowBackgroundColor)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {
                    Spacer().frame(height: 16)

                    // Bloc texte — sur fond adaptive, on utilise .primary
                    // (pas .white) pour rester lisible en light mode.
                    // (Compromis honnête : la spec wordmark blanc + shadow
                    // ne s'applique qu'aux backgrounds pastel, cf. layouts
                    // A et Full pastel ci-dessous.)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("loucedé")
                            .font(.custom("IBMPlexMono-BoldItalic", size: 48))
                            .tracking(-1.4)
                            .foregroundColor(.primary)

                        Text("Une IA au bout de tes doigts")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .opacity(textOpacity)

                    Spacer()

                    commencerButton
                        .opacity(buttonOpacity)
                        .offset(y: buttonOffset)

                    Spacer().frame(height: 30)
                }
                .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Right panel : pastel + screenshot
            ZStack {
                brandPastel.ignoresSafeArea()
                Image("PopupPreview")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Layout B.2 : Full pastel (les 2 panneaux en rose)

    @ViewBuilder
    private var fullPastelLayout: some View {
        HStack(spacing: 0) {
            // Left panel : pastel + texte/bouton
            ZStack {
                brandPastel.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {
                    Spacer().frame(height: 16)

                    VStack(alignment: .leading, spacing: 6) {
                        // V1 : choix esthétique assumé (blanc sur rose pastel < AA WCAG).
                        // À revoir lors de l'audit a11y V1.1 : ombre renforcée OU couleur sombre.
                        Text("loucedé")
                            .font(.custom("IBMPlexMono-BoldItalic", size: 48))
                            .tracking(-1.4)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 3)

                        Text("Une IA au bout de tes doigts")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .opacity(textOpacity)

                    Spacer()

                    commencerButton
                        .opacity(buttonOpacity)
                        .offset(y: buttonOffset)

                    Spacer().frame(height: 30)
                }
                .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Right panel : pastel + screenshot
            ZStack {
                brandPastel.ignoresSafeArea()
                Image("PopupPreview")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Bouton "Commencer" (réutilisé dans les 3 layouts)

    /// Bouton noir avec effet 3D (shadow inférieure). Style hérité du
    /// précédent WelcomeStep, sera basculé en bouton système en Étape 2.
    private var commencerButton: some View {
        Button(action: onNext) {
            Text("Commencer")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 200, height: 52)
                .background(
                    ZStack {
                        // Bottom shadow layer (3D effect)
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: "333333"))
                            .offset(y: 5)

                        // Main button
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: "1a1a1a"))
                    }
                )
        }
        .buttonStyle(WelcomeNoFadeButtonStyle())
    }
}

// MARK: - No Fade Button Style
//
// Conservé pour Étape 1. Sera retiré en Étape 2 quand le bouton sera
// basculé en `.borderedProminent` (style système qui gère son propre
// feedback de tap).

struct WelcomeNoFadeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(1)
    }
}
