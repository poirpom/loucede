//
//  GenerationProgressIndicator.swift
//  loucede
//
//  Phase Q.3 — Polish compteur génération d'action.
//
//  Indicateur de progression du mini-popover Générateur (phase `.loading`) :
//  un `ProgressView` natif (indéterminé) surmontant un compteur temps réel
//  `00.0s` qui change de couleur par paliers (snap, sans fondu) selon la durée
//  écoulée. Composant auto-contenu, piloté par son cycle de vie : le timer
//  démarre à l'apparition de la vue et s'arrête à sa disparition (cross-fade de
//  sortie vers `.resultEditable` ou `.error`). Aucun gel : compteur et spinner
//  disparaissent ensemble en fin de génération.
//
//  Cadrage : loucede-private/details/Q.3-polish-compteur-generation.md
//

import SwiftUI

struct GenerationProgressIndicator: View {
    /// Instant de référence du compteur, posé au premier `onAppear`. `nil`
    /// avant l'apparition → affichage `00.0s` (le `TimelineView` rafraîchit
    /// dès que la valeur est posée).
    @State private var startDate: Date?

    var body: some View {
        VStack(spacing: 8) {
            // Spinner natif macOS, agrandi dans une zone réservée (token Q.3).
            // Pas d'animation custom, pas de cycle d'emojis (pivot 09/06).
            ProgressView()
                .controlSize(.large)
                .frame(height: PolishTokens.generationSpinnerHeight)

            // Compteur temps réel : rafraîchi en continu par TimelineView(.animation).
            // `monospacedDigit` fige la largeur des chiffres (pas de jitter).
            TimelineView(.animation) { context in
                let elapsed = elapsed(at: context.date)
                Text(String(format: "%04.1fs", elapsed))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(color(forElapsed: elapsed))
            }
        }
        .onAppear { if startDate == nil { startDate = Date() } }
    }

    /// Secondes écoulées depuis `startDate` (clampé à 0 avant l'init).
    private func elapsed(at now: Date) -> Double {
        guard let startDate else { return 0 }
        return max(0, now.timeIntervalSince(startDate))
    }

    /// Palier couleur (snap, pas de fondu) : vert ≤ 8.0s, jaune ≤ 18.0s,
    /// rouge au-delà. Couleurs sémantiques système (cohérence macOS natif).
    private func color(forElapsed elapsed: Double) -> Color {
        if elapsed <= 8.0 { return Color(nsColor: .systemGreen) }
        if elapsed <= 18.0 { return Color(nsColor: .systemYellow) }
        return Color(nsColor: .systemRed)
    }
}
