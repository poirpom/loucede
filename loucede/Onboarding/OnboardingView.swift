//
//  OnboardingView.swift
//  typo
//

import SwiftUI

struct OnboardingView: View {
    @State private var currentStep = 0

    var onComplete: () -> Void

    private let totalSteps = 5

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
