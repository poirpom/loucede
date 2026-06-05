//
//  OnboardingView.swift
//  loucede
//

import SwiftUI

struct OnboardingView: View {
    @State private var currentStep = 0

    var onComplete: () -> Void
    /// Déclenché par « Faire le tuto » (écran 7). En M.1, câblé au même
    /// finalize que `onComplete` côté `showOnboarding` ; rebranché en M.2
    /// vers l'ouverture du tuto interactif.
    var onStartTutorial: () -> Void

    /// Phase 7.2 (2026-04-29) : ajout de `APIKeyStep` entre Shortcut (3)
    /// et LaunchAtLogin (5). Séquence finale : 7 écrans.
    private let totalSteps = 7

    var body: some View {
        Group {
            switch currentStep {
            case 0:
                WelcomeStep(onNext: nextStep)
            case 1:
                FeaturesStep(onNext: nextStep, onBack: previousStep)
            case 2:
                PermissionsStep(onNext: nextStep, onBack: previousStep)
            case 3:
                ShortcutStep(onNext: nextStep, onBack: previousStep)
            case 4:
                APIKeyStep(onNext: nextStep, onBack: previousStep)
            case 5:
                LaunchAtLoginStep(onNext: nextStep, onBack: previousStep)
            case 6:
                ActivationStep(
                    onComplete: onComplete,
                    onStartTutorial: onStartTutorial,
                    onBack: previousStep
                )
            default:
                EmptyView()
            }
        }
        .frame(width: 800, height: 520)
    }

    private func nextStep() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if currentStep < totalSteps - 1 {
                currentStep += 1
            }
        }
    }

    private func previousStep() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if currentStep > 0 {
                currentStep -= 1
            }
        }
    }
}

#Preview {
    OnboardingView(onComplete: {}, onStartTutorial: {})
}
