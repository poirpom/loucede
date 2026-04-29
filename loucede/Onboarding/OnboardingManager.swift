//
//  OnboardingManager.swift
//  loucede
//

import Foundation
import Combine

class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    private let hasCompletedOnboardingKey = "loucede_has_completed_onboarding"

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: hasCompletedOnboardingKey)
        }
    }

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
    }
}
