//
//  WelcomeStep.swift
//  loucede
//
//  Session 5 — Refonte premier écran d'onboarding (2026-05-01).
//  Layout final retenu : Split classique (gauche adaptive système /
//  droite pastel rose). Cohérent cross-touchpoint avec le site web
//  (texte sur container blanc, visuels sur fond rose pastel).
//

import SwiftUI

struct WelcomeStep: View {
    var onNext: () -> Void

    // MARK: - Animation states (Étape 1 — fade-in titre + spring bouton,
    // wave animée retirée pour cohérence avec le screenshot statique)

    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var buttonOffset: CGFloat = 50

    // MARK: - Couleur

    /// Rose pastel — couleur Welcome de la palette pastel V1
    /// (cf. mapping plan.md : Welcome → #FFD6E0).
    private let brandPastel = Color(hex: "FFD6E0")

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
            rightPanel
        }
        .ignoresSafeArea()
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

    // MARK: - Left panel : adaptive système avec wordmark + tagline + bouton

    /// Le fond `Color(NSColor.windowBackgroundColor)` s'adapte au mode
    /// système (light/dark). Couleurs texte en `.primary` / `.secondary`
    /// — pas d'ombre nécessaire, contraste OK natif.
    @ViewBuilder
    private var leftPanel: some View {
        Color(NSColor.windowBackgroundColor)
            // Wordmark + tagline, vertical-centrés via l'alignment de
            // l'overlay (.leading = horizontal-left + vertical-center).
            .overlay(alignment: .leading) {
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
                .padding(.leading, 40)
            }
            // Bouton "Commencer" en bas à gauche, fixé.
            .overlay(alignment: .bottomLeading) {
                commencerButton
                    .opacity(buttonOpacity)
                    .offset(y: buttonOffset)
                    .padding(.leading, 40)
                    .padding(.bottom, 40)
            }
    }

    // MARK: - Right panel : pastel rose avec screenshot popup centré

    /// L'overlay sans alignment explicite utilise `.center` par défaut.
    /// Le screenshot s'auto-adapte au mode système (light/dark) via
    /// l'Asset Catalog `PopupPreview.imageset/`.
    @ViewBuilder
    private var rightPanel: some View {
        brandPastel
            .overlay {
                Image("PopupPreview")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300)
            }
    }

    // MARK: - Bouton "Commencer"

    /// Bouton noir avec effet 3D (shadow inférieure). Style hérité du
    /// précédent WelcomeStep — sera basculé en bouton système en
    /// Étape 2 (boutons système sur les 5 écrans).
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
