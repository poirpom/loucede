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

    /// Phase 6.2 Étape 9 (2026-04-27) : flag de présentation du modal
    /// « trial épuisé ». Set à `true` par `runAction` quand
    /// `LicenseManager.canRunAction == false` (= pas de licence et
    /// 12 essais déjà consommés). PopoverView présente alors le modal
    /// en overlay. Reset à `false` au click « Plus tard » ou « Acheter ».
    @Published var showTrialExpiredModal: Bool = false

    // Phase 1.4g : champ de recherche dans la liste d'actions. Accumulé
    // via les frappes dans mainView (.onKeyPress générique). Quand non vide,
    // la liste est filtrée par substring case-insensitive sur le nom.
    @Published var searchQuery: String = ""

    // Compteur incrémenté à chaque ouverture du popup. Permet à PopoverView
    // de re-forcer le focus clavier via @FocusState lors de la réutilisation
    // de la fenêtre préchargée (sinon .onKeyPress reste "stale" et les
    // flèches directionnelles + Entrée ne sont plus captées).
    @Published var openCounter: Int = 0

    // Le Task de streaming n'est pas @Published car on ne veut pas
    // déclencher de re-render quand il change — c'est juste un handle
    // pour pouvoir l'annuler.
    var streamTask: Task<Void, Never>?

    // Phase 6.8g (2026-04-25) : tampon de chunks accumulés pendant le
    // streaming, vidé à 60 Hz dans `resultText` par `flushTask`. Avant
    // ce coalescing, chaque chunk déclenchait un re-render complet du
    // popup (Markdown ré-évalué + ScrollView relayouté), ce qui saturait
    // SwiftUI sur les streams rapides et faisait planter l'app pendant
    // l'exécution d'une action (crash signalé le 25 avril).
    private var pendingChunkBuffer: String = ""
    private var flushTask: Task<Void, Never>?

    /// Phase 6.14-fix (2026-04-26) : suspendre les flushes pendant les
    /// transitions de fenêtre AppKit (resize compact ↔ agrandi, retour à
    /// la liste). Sans ça, la mutation de `resultText` pendant l'animation
    /// NSWindow déclenche un re-layout SwiftUI alors qu'AppKit a déjà
    /// programmé une passe de constraints, et le solver lève
    /// `NSInternalInconsistencyException`: « The window has been marked as
    /// needing another Update Constraints in […] ». Voir le commit pour
    /// l'analyse détaillée.
    private var flushPaused: Bool = false

    private init() {}

    /// Réinitialise l'état avant un nouvel affichage du popup.
    /// Appelé par AppDelegate.showPopover juste avant orderFront.
    func reset() {
        endStream()
        activeAction = nil
        selectedIndex = 0
        isProcessing = false
        resultText = ""
        searchQuery = ""
        showTrialExpiredModal = false
        openCounter &+= 1
    }

    /// Annule le streaming LLM en cours et libère les ressources liées
    /// (timer de flush + buffer de chunks). Sûr à appeler même si aucun
    /// stream n'est actif. NE TOUCHE PAS à `activeAction` ni `resultText` :
    /// utiliser `clearResult()` pour aussi revenir à la liste.
    func endStream() {
        streamTask?.cancel()
        streamTask = nil
        flushTask?.cancel()
        flushTask = nil
        pendingChunkBuffer = ""
        isProcessing = false
    }

    /// Annule le streaming en cours, vide le résultat et revient à la
    /// liste d'actions. Appelé par les boutons Retour / Esc.
    func clearResult() {
        endStream()
        activeAction = nil
        resultText = ""
    }

    /// Ajoute le tampon de chunks accumulés à `resultText` en une seule
    /// passe. Appelé périodiquement par `flushTask` à ~60 Hz, ainsi qu'à
    /// la fin du stream (succès ou erreur) pour ne perdre aucun token.
    /// Phase 6.14-fix : si `flushPaused == true`, on laisse les chunks
    /// dans le buffer (le LLM continue de streamer côté `streamTask`,
    /// rien n'est perdu — juste retardé jusqu'au `resumeFlush()`).
    private func flushPendingChunks() {
        guard !flushPaused, !pendingChunkBuffer.isEmpty else { return }
        resultText += pendingChunkBuffer
        pendingChunkBuffer = ""
    }

    /// Phase 6.14-fix : suspend l'application des chunks streamés à
    /// `resultText`. À appeler avant une transition de fenêtre AppKit
    /// (resize compact↔agrandi, retour liste). Le buffer continue à
    /// recevoir les tokens du LLM, ils seront appliqués au `resumeFlush()`.
    func suspendFlush() {
        flushPaused = true
    }

    /// Phase 6.14-fix : reprend l'application des chunks et flush
    /// immédiatement le buffer accumulé pendant la pause (rattrapage en
    /// une seule passe — l'utilisateur voit les ~5-10 tokens manqués
    /// apparaître d'un bloc, ce qui est imperceptible visuellement).
    func resumeFlush() {
        flushPaused = false
        flushPendingChunks()
    }

    /// Démarre la boucle de flush 60 Hz. Idempotent : si une boucle
    /// tourne déjà, ne fait rien. Stoppée automatiquement par
    /// `endStream()`.
    private func startFlushLoop() {
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor [weak self] in
            // ~60 Hz = 16.66 ms. On vise une fréquence de rafraîchissement
            // alignée sur l'écran pour que le streaming reste fluide
            // visuellement, sans pour autant ré-évaluer Markdown à chaque
            // token reçu (la cadence des LLM dépasse souvent 100 tokens/s).
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_000_000)
                if Task.isCancelled { break }
                self?.flushPendingChunks()
            }
        }
    }

    /// Lance une action (prompt) sur le texte capturé.
    /// Déplacé ici depuis PopoverView pour que l'action puisse être
    /// déclenchée depuis l'extérieur (ex. showPopoverWithAction).
    ///
    /// Phase 6.2 Étape 9 (2026-04-27) : licence gate.
    /// - Si `LicenseManager.canRunAction == false` (= trial épuisé +
    ///   pas de licence active) → on ne lance pas le stream et on
    ///   présente le modal trial épuisé via `showTrialExpiredModal`.
    /// - Si action lancée et stream réussi : on incrémente le compteur
    ///   trial UNIQUEMENT si l'utilisateur n'a pas de vraie licence
    ///   (`!hasLicense`). Comportement Debug : le `#if DEBUG` force
    ///   `hasLicense = true` → pas d'incrément en dev, c'est OK pour
    ///   tester sans burner d'essais.
    /// - Incrément APRÈS le stream réussi (pas avant), pour ne pas
    ///   brûler des essais sur des erreurs réseau ou clé API absente.
    func runAction(_ action: Action) {
        // Phase 6.2 Étape 9 : gate licence/trial.
        let license = LicenseManager.shared
        guard license.canRunAction else {
            showTrialExpiredModal = true
            return
        }

        // Si un stream tournait déjà (cas extrême : double-tap sur une
        // action), on l'annule proprement avant d'en redémarrer un.
        endStream()

        let store = ActionsStore.shared
        let textManager = CapturedTextManager.shared

        activeAction = action
        resultText = ""
        isProcessing = true
        pendingChunkBuffer = ""

        let apiKey = store.apiKey
        let provider = store.selectedProvider
        let model = store.selectedModel
        let inputText = textManager.capturedText
        let fullPrompt = inputText.isEmpty ? action.prompt : "\(action.prompt)\n\n\(inputText)"

        // Snapshot du `hasLicense` au lancement : si l'utilisateur
        // active une licence en plein milieu d'un stream, on ne veut
        // pas changer la décision « ce stream consomme-t-il un essai
        // gratuit ou non » à mi-parcours. La décision est prise à
        // l'envoi de la requête, pas à sa terminaison.
        let consumesTrial = !license.hasLicense

        startFlushLoop()
        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var streamSucceeded = false
            do {
                try await AIService.shared.chatStream(
                    messages: [(role: "user", content: fullPrompt)],
                    apiKey: apiKey,
                    provider: provider,
                    model: model
                ) { [weak self] chunk in
                    // Le chunk callback est invoqué via `await MainActor.run`
                    // côté AIService — on est donc bien sur MainActor ici.
                    // On accumule plutôt que de modifier `resultText`
                    // directement : un seul re-render par frame.
                    self?.pendingChunkBuffer += chunk
                }
                streamSucceeded = true
            } catch {
                // Vide d'abord le tampon (ne pas perdre le partiel) puis
                // affiche l'erreur en complément.
                self.flushPendingChunks()
                self.resultText += "\n\nErreur : \(error.localizedDescription)"
            }
            // Flush final pour garantir qu'aucun token n'est perdu entre
            // le dernier tick du timer et la fin du stream.
            self.flushPendingChunks()
            self.flushTask?.cancel()
            self.flushTask = nil
            self.isProcessing = false

            // Incrémente le compteur trial UNIQUEMENT après un stream
            // réussi (pas brûler d'essai sur une erreur réseau / clé
            // API absente / token expiré côté provider). Le snapshot
            // `consumesTrial` capture l'état au lancement — pas
            // affecté par un changement de licence en cours de stream.
            if streamSucceeded && consumesTrial {
                license.incrementTrialUsage()
            }
        }
    }
}
