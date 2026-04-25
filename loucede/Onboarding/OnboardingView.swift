//
//  OnboardingView.swift
//  typo
//

import SwiftUI

struct OnboardingView: View {
    @State private var currentStep = 0

    var onComplete: () -> Void

    /// Phase 6.5b (2026-04-25) : ajout de `LaunchAtLoginStep` entre Shortcut
    /// et Activation. L'utilisateur a déjà configuré son raccourci, on lui
    /// propose maintenant le démarrage automatique avant l'écran final.
    private let totalSteps = 6

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
                LaunchAtLoginStep(onNext: nextStep, onBack: previousStep)
            case 5:
                ActivationStep(
                    onComplete: onComplete,
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
    OnboardingView(onComplete: {})
}
