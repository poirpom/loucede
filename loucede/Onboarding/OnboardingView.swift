//
//  OnboardingView.swift
//  loucede
//

import SwiftUI

struct OnboardingView: View {
    /// Phase R (2026-06-14) : refonte mono-écran. Les 5 écrans de config
    /// séquentiels (Features/Permissions/Shortcut/APIKey/LaunchAtLogin) sont
    /// remplacés par un seul écran accordéon `ConfigureView`. Séquence finale :
    /// Splash → Configure → Final.
    private enum Stage { case splash, configure, final }
    @State private var stage: Stage = .splash

    var onComplete: () -> Void
    /// Déclenché par « Faire le tuto » (écran final). Câblé côté
    /// `showOnboarding` : finalise l'onboarding PUIS ouvre le tuto WKWebView.
    var onStartTutorial: () -> Void

    var body: some View {
        Group {
            switch stage {
            case .splash:
                WelcomeStep(onNext: { go(.configure) })
            case .configure:
                ConfigureView(onNext: { go(.final) }, onBack: { go(.splash) })
            case .final:
                ActivationStep(
                    onComplete: onComplete,
                    onStartTutorial: onStartTutorial,
                    onBack: { go(.configure) }
                )
            }
        }
        .frame(width: 920, height: 640)
    }

    private func go(_ next: Stage) {
        withAnimation(.easeInOut(duration: 0.3)) {
            stage = next
        }
    }
}

#Preview {
    OnboardingView(onComplete: {}, onStartTutorial: {})
}
