//
//  OnboardingCompletion.swift
//  loucede
//
//  Phase R : view-model dérivé de l'écran accordéon. Ne persiste rien —
//  l'état de complétion est entièrement dérivé des sources de vérité
//  existantes. Seule l'accessibilité demande un polling (l'utilisateur
//  l'accorde dans Réglages Système pendant que l'onboarding est ouvert) ;
//  la clé API est lue live depuis ActionsStore et le démarrage est piloté
//  depuis sa card. Pattern calqué sur l'ancien PermissionsStep.
//

import SwiftUI
import AppKit
import Combine

final class OnboardingCompletion: ObservableObject {
    /// Reflète `AXIsProcessTrusted()`, rafraîchi toutes les secondes.
    @Published var accessibilityGranted = AXIsProcessTrusted()

    private var timer: Timer?

    func start() {
        accessibilityGranted = AXIsProcessTrusted()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = AXIsProcessTrusted()
            if granted != self.accessibilityGranted {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    self.accessibilityGranted = granted
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
