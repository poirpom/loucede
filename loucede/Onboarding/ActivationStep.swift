//
//  ActivationStep.swift
//  loucede
//
//  Étape finale de l'onboarding (Phase 0 : stub).
//  Sera refondue pour la config initiale : clé API + raccourci.
//

import SwiftUI

struct ActivationStep: View {
    /// « Pas de tuto » — finalise l'onboarding.
    var onComplete: () -> Void
    /// « Faire le tuto » — en M.1, câblé au même finalize que `onComplete`
    /// (cf. `OnboardingView` / `showOnboarding`). En M.2, sera rebranché
    /// vers l'ouverture de la fenêtre tuto WKWebView, sans toucher à cette UI.
    var onStartTutorial: () -> Void
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

            Text("Toi, tu devrais faire le tuto. Il est rapide, interactif et tu seras une vraie flèche après. #protip")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Mention accès aux Réglages — cohérence visuelle avec ce
            // que l'utilisateur va voir dans les 30 secondes : l'icône
            // template `MenuBarIcon` dans la status bar (asset partagé
            // avec `loucedeApp.setupMenuBar`) et le bouton « Réglages »
            // dans le popup (SF Symbol `gearshape` partagé avec
            // `MenuBarMenuView.swift:32` + `PopoverView.swift:592`).
            //
            // Concaténation Text + Text(Image(...)) : les icônes
            // héritent automatiquement de la taille de police et de la
            // couleur `.secondary` via `foregroundStyle`. Le rendu
            // template du MenuBarIcon est respecté.
            // Note alignement vertical : `.baselineOffset(-2)` sur le
            // PNG template MenuBarIcon — sans ça, le PNG s'aligne sur
            // la bounding box du Text (donc flotte au-dessus de la
            // ligne) au lieu de la baseline. Le SF Symbol `gearshape`
            // ne nécessite pas d'offset (alignment baseline natif).
            // Valeur négative = décalage vers le bas (convention
            // SwiftUI documentée).
            (Text("Les réglages sont accessibles depuis la barre des menus ")
             + Text(Image("MenuBarIcon")).baselineOffset(-4)
             + Text(" comme depuis l'appli ")
             + Text(Image(systemName: "gearshape"))
             + Text("."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            HStack(spacing: 16) {
                Button("Retour", action: onBack)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                Button("Pas de tuto", action: onComplete)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                Button("Faire le tuto", action: onStartTutorial)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

            Spacer().frame(height: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    ActivationStep(onComplete: {}, onStartTutorial: {}, onBack: {})
        .frame(width: 800, height: 520)
}
