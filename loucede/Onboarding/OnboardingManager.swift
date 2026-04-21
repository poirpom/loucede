//
//  OnboardingManager.swift
//  typo
//

import SwiftUI
import Combine

class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    private let hasCompletedOnboardingKey = "loucede_has_completed_onboarding"
    private let licenseKeyKey = "loucede_license_key"
    private let isLicenseValidKey = "loucede_is_license_valid"

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: hasCompletedOnboardingKey)
        }
    }

    @Published var licenseKey: String {
        didSet {
            UserDefaults.standard.set(licenseKey, forKey: licenseKeyKey)
        }
    }

    @Published var isLicenseValid: Bool {
        didSet {
            UserDefaults.standard.set(isLicenseValid, forKey: isLicenseValidKey)
        }
    }

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey)
        self.licenseKey = UserDefaults.standard.string(forKey: licenseKeyKey) ?? ""
        self.isLicenseValid = UserDefaults.standard.bool(forKey: isLicenseValidKey)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
        licenseKey = ""
        isLicenseValid = false
    }

    func validateLicense(_ key: String) async -> Bool {
        // TODO: Implement actual license validation with your server
        // Remove dashes and whitespace, then uppercase
        let cleanedKey = key.replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        // Validate 32 alphanumeric characters
        let pattern = "^[A-Z0-9]{32}$"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(cleanedKey.startIndex..., in: cleanedKey)

        if regex?.firstMatch(in: cleanedKey, options: [], range: range) != nil {
            // Format with dashes for storage (8-4-4-4-12)
            let formatted = "\(cleanedKey.prefix(8))-\(cleanedKey.dropFirst(8).prefix(4))-\(cleanedKey.dropFirst(12).prefix(4))-\(cleanedKey.dropFirst(16).prefix(4))-\(cleanedKey.dropFirst(20))"
            licenseKey = formatted
            isLicenseValid = true
            return true
        }

        return false
    }
}
