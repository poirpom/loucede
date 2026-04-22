//
//  PopoverState.swift
//  loucede
//
//  État partagé du popup principal — centralisé ici (au lieu de @State
//  dans PopoverView) pour que la fenêtre AppKit puisse être préchargée
//  une seule fois au démarrage et que l'état soit réinitialisé à chaque
//  ouverture sans détruire/recréer le NSHostingView.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class PopoverState: ObservableObject {
    static let shared = PopoverState()

    @Published var activeAction: Action?
    @Published var selectedIndex: Int = 0
    @Published var isProcessing: Bool = false
    @Published var resultText: String = ""

    // Le Task de streaming n'est pas @Published car on ne veut pas
    // déclencher de re-render quand il change — c'est juste un handle
    // pour pouvoir l'annuler.
    var streamTask: Task<Void, Never>?

    private init() {}

    /// Réinitialise l'état avant un nouvel affichage du popup.
    /// Appelé par AppDelegate.showPopover juste avant orderFront.
    func reset() {
        streamTask?.cancel()
        streamTask = nil
        activeAction = nil
        selectedIndex = 0
        isProcessing = false
        resultText = ""
    }

    /// Lance une action (prompt) sur le texte capturé.
    /// Déplacé ici depuis PopoverView pour que l'action puisse être
    /// déclenchée depuis l'extérieur (ex. showPopoverWithAction).
    func runAction(_ action: Action) {
        let store = ActionsStore.shared
        let textManager = CapturedTextManager.shared

        activeAction = action
        resultText = ""
        isProcessing = true

        let apiKey = store.apiKey
        let provider = store.selectedProvider
        let model = store.selectedModel
        let inputText = textManager.capturedText
        let fullPrompt = inputText.isEmpty ? action.prompt : "\(action.prompt)\n\n\(inputText)"

        streamTask = Task { @MainActor in
            do {
                try await AIService.shared.chatStream(
                    messages: [(role: "user", content: fullPrompt)],
                    apiKey: apiKey,
                    provider: provider,
                    model: model
                ) { chunk in
                    self.resultText += chunk
                }
            } catch {
                self.resultText = "Erreur : \(error.localizedDescription)"
            }
            self.isProcessing = false
        }
    }
}
