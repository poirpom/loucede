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

            Text("Ce que tu vas faire")
                .font(.system(size: 32, weight: .black))

            VStack(alignment: .leading, spacing: 20) {
                featureRow(icon: "checkmark.shield.fill",
                           title: "Autoriser l'accessibilité à loucedé",
                           detail: "Pour fonctionner correctement")
                featureRow(icon: "keyboard",
                           title: "Configurer le raccourci clavier",
                           detail: "Ou conserver celui par défaut (qui est très bien)")
                featureRow(icon: "key.fill",
                           title: "Configurer ta clé API",
                           detail: "Pour que loucedé puisse utiliser l'IA")
                featureRow(icon: "power",
                           title: "Autoriser loucedé à se lancer au démarrage de ton ordi",
                           detail: "Pour l'avoir toujours à dispo")
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
