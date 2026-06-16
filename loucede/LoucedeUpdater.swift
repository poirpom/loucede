//
//  LoucedeUpdater.swift
//  loucede
//
//  Phase H.1 — Façade mince autour de Sparkle (SPUStandardUpdaterController).
//
//  DORMANTE en H.1 : instanciée en parallèle de `UpdateChecker.shared`
//  (le système custom GitHub-Releases reste le système ACTIF consommé par
//  les vues). H.2 rebranchera les vues sur cette façade puis supprimera
//  `UpdateChecker`. La façade découple le code app du SDK Sparkle et
//  préserve le pattern Combine (@Published) déjà utilisé par les vues.
//
//  App non sandboxée (ENABLE_APP_SANDBOX = NO) → pas de service XPC requis,
//  SPUStandardUpdaterController fonctionne directement.
//

import Foundation
import Combine
import Sparkle

final class LoucedeUpdater: NSObject, ObservableObject {
    static let shared = LoucedeUpdater()

    /// `true` quand l'updater peut lancer une vérification (filet anti
    /// double-clic côté UI en H.2).
    @Published private(set) var canCheckForUpdates = false
    /// Passe à `true` quand l'appcast annonce une version plus récente.
    @Published private(set) var updateAvailable = false
    /// Dernier message d'erreur d'une vérification (réseau, appcast, etc.).
    @Published var lastError: String?

    private var updaterController: SPUStandardUpdaterController!
    private var cancellable: AnyCancellable?

    private override init() {
        super.init()
        // startingUpdater: true → démarre l'updater + un SPUStandardUserDriver
        // (UI native « Mise à jour disponible »). Les clés SUFeedURL /
        // SUPublicEDKey / SUEnableAutomaticChecks sont lues depuis Info.plist.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        // Reflète `canCheckForUpdates` (KVO Sparkle) vers @Published.
        cancellable = updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
    }

    /// Vérification déclenchée par l'utilisateur : UI native Sparkle, affiche
    /// les erreurs (« Impossible de vérifier les mises à jour »).
    func checkForUpdates() {
        lastError = nil
        updaterController.updater.checkForUpdates()
    }

    /// Vérification silencieuse en arrière-plan : pas d'UI sur erreur réseau.
    func checkForUpdatesInBackground() {
        updaterController.updater.checkForUpdatesInBackground()
    }
}

// MARK: - SPUUpdaterDelegate

extension LoucedeUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        DispatchQueue.main.async { [weak self] in
            self?.updateAvailable = true
            self?.lastError = nil
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        DispatchQueue.main.async { [weak self] in
            self?.updateAvailable = false
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.lastError = error.localizedDescription
        }
    }
}
