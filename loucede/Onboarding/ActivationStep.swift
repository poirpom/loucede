//
//  ActivationStep.swift
//  loucede
//
//  Étape finale de l'onboarding (Phase 0 : stub).
//  Sera refondue pour la config initiale : clé API + raccourci.
//

import SwiftUI

struct ActivationStep: View {
    var onComplete: () -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.bounce)

            Text("loucedé est prêt")
                .font(.system(size: 28, weight: .bold))

            Text("Utilise le raccourci configuré pour ouvrir la popup\nsur une sélection de texte dans n'importe quelle app.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            HStack(spacing: 16) {
                Button("Retour", action: onBack)
                    .buttonStyle(.bordered)
                Button("Terminer", action: onComplete)
                    .buttonStyle(.borderedProminent)
            }

            Spacer().frame(height: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    ActivationStep(onComplete: {}, onBack: {})
        .frame(width: 800, height: 520)
}
