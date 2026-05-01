//
//  FeaturesStep.swift
//  loucede
//
//  Étape d'onboarding : présentation des fonctionnalités (Phase 0 : stub).
//  Sera refondue avec animations SF Symbols et illustrations natives.
//

import SwiftUI

struct FeaturesStep: View {
    var onNext: () -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer().frame(height: 20)

            Text("Comment ça marche")
                .font(.system(size: 32, weight: .black))

            VStack(alignment: .leading, spacing: 20) {
                featureRow(icon: "text.cursor",
                           title: "Sélectionne du texte",
                           detail: "Dans n'importe quelle app macOS.")
                featureRow(icon: "keyboard",
                           title: "Déclenche le raccourci",
                           detail: "La popup s'ouvre instantanément.")
                featureRow(icon: "wand.and.stars",
                           title: "Applique un prompt",
                           detail: "La réponse arrive en streaming.")
                featureRow(icon: "arrow.down.doc",
                           title: "Copie ou colle",
                           detail: "Le résultat retourne dans l'app active.")
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            Spacer()

            HStack(spacing: 16) {
                Button("Retour", action: onBack)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                Button("Continuer", action: onNext)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

            Spacer().frame(height: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    FeaturesStep(onNext: {}, onBack: {}).frame(width: 800, height: 520)
}
