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

    // MARK: - Mode tuto (M.2.3)
    /// `true` quand la fenêtre tuto est active. Modifie 3 comportements,
    /// gardés par ce flag (sinon comportement normal intact) :
    /// trigger (popover ouvert programmatiquement), modèle (tier rapide),
    /// paste (injection JS au lieu de Cmd+V système).
    @Published var tutorialMode: Bool = false
    /// Paste tuto : injecte le résultat dans le contenteditable de la
    /// WKWebView (posé par `TutorialWindowController`).
    var tutorialPasteHandler: ((String) -> Void)?
    /// Notifie le lancement d'une action (→ coche « action ») en mode tuto.
    var tutorialActionRunHandler: (() -> Void)?

    // Phase 1.4g : champ de recherche dans la liste d'actions. Accumulé
    // via les frappes dans mainView (.onKeyPress générique). Quand non vide,
    // la liste est filtrée par substring case-insensitive sur le nom.
    @Published var searchQuery: String = ""

    // Compteur incrémenté à chaque ouverture du popup. Permet à PopoverView
    // de re-forcer le focus clavier via @FocusState lors de la réutilisation
    // de la fenêtre préchargée (sinon .onKeyPress reste "stale" et les
    // flèches directionnelles + Entrée ne sont plus captées).
    @Published var openCounter: Int = 0

    // MARK: - K.2-B lot 2a — Générateur d'actions AI

    /// Phase courante du Générateur d'actions AI. `nil` = pas en mode
    /// générateur (la popup affiche `mainView` ou `resultView`).
    /// Non-nil = la popup affiche `generatorView`. Mutuellement exclusif
    /// avec `activeAction` (la priorité dans le `body` de PopoverView est
    /// générateur > résultat > main).
    @Published var generatorPhase: GeneratorPhase?

    /// Texte du champ « Action à générer » dans le popover générateur.
    /// Lié au TextField (mono-ligne) via `Binding`. Pré-rempli par
    /// `enterGeneratorMode(prefilled:)`, éditable par l'utilisateur.
    @Published var generatorInputText: String = ""

    // K.2-B lot 2b — Champs édités de l'action en cours d'élaboration.
    // Peuplés depuis le `GeneratedAction` au moment où on entre en
    // `.resultEditable`, éditables nativement par l'utilisateur via
    // bindings SwiftUI. En cas de regénération, ils sont écrasés par la
    // nouvelle proposition (décision actée). Vidés à la sortie du mode
    // générateur (Esc, validation, `reset()`).
    /// Titre éditable de l'action générée (mono-ligne).
    @Published var editableTitle: String = ""
    /// Emoji éditable de l'action générée (mono-ligne, généralement 1 char).
    @Published var editableEmoji: String = ""
    /// Description courte éditable (mono-ligne, ≤80 signes idéalement).
    @Published var editableDescription: String = ""
    /// Prompt éditable (multi-ligne, peut faire 30+ lignes).
    @Published var editablePrompt: String = ""
    /// Catégorie choisie pour l'action générée. `nil` = « Sans catégorie »
    /// (choix par défaut et valide ; l'utilisateur peut catégoriser plus
    /// tard via Réglages → Actions s'il laisse `nil`).
    @Published var editableCategory: PromptCategory? = nil

    /// Token UUID renouvelé à chaque déclenchement de génération. Sert à
    /// l'annulation LOGIQUE d'une génération en cours (Esc pendant
    /// loading) : à la fin du Task, on vérifie que le token n'a pas
    /// changé ; sinon le résultat est ignoré. `ActionGenerator.generate`
    /// ne vérifie pas `Task.isCancelled` (fichier sain à ne pas toucher),
    /// l'appel API se poursuit donc en arrière-plan — coût accepté V1.
    private var currentGenerationToken: UUID?

    /// Handle vers le Task de génération courant. `Task.cancel()` à
    /// l'annulation pour hygiène, même si la cancellation logique passe
    /// par le token.
    private var generationTask: Task<Void, Never>?

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
        cancelOngoingGeneration()
        activeAction = nil
        selectedIndex = 0
        isProcessing = false
        resultText = ""
        searchQuery = ""
        generatorPhase = nil
        generatorInputText = ""
        clearEditableFields()
        showTrialExpiredModal = false
        openCounter &+= 1
    }

    /// K.2-B lot 2b — vide les 4 champs éditables + le sélecteur de
    /// catégorie. Appelé par `reset()`, `exitGeneratorMode()`, et par
    /// `validateAndRun()` après ajout au catalogue.
    private func clearEditableFields() {
        editableTitle = ""
        editableEmoji = ""
        editableDescription = ""
        editablePrompt = ""
        editableCategory = nil
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

    /// Nettoie l'état transitoire affiché (mode résultat, mode générateur
    /// ET état liste : recherche + sélection) à la fermeture du popup, pour
    /// éviter qu'il ne « flashe » à la réouverture — le `reset()` côté
    /// ouverture étant dispatché async (Task @MainActor), il arrive trop
    /// tard, après que la fenêtre a déjà été affichée. searchQuery et
    /// selectedIndex sont tout aussi transitoires que le reste (sinon la
    /// liste réapparaît brièvement filtrée sur la recherche précédente).
    /// NE TOUCHE PAS openCounter (incrémenté uniquement à l'ouverture).
    func clearTransientContent() {
        endStream()
        cancelOngoingGeneration()
        activeAction = nil
        resultText = ""
        generatorPhase = nil
        generatorInputText = ""
        clearEditableFields()
        searchQuery = ""
        selectedIndex = 0
    }

    // MARK: - Générateur — méthodes (K.2-B lot 2a)

    /// Active le mode Générateur. Affecte `generatorInputText` à la valeur
    /// pré-remplie (typiquement la `searchQuery` de la popup au moment du
    /// clic « Générer cette action ») et passe `generatorPhase` à
    /// `.compact`. PopoverView observe ce changement et bascule le `body`
    /// vers `generatorView` + redimensionne la NSWindow.
    func enterGeneratorMode(prefilled: String) {
        generatorInputText = prefilled
        generatorPhase = .compact
    }

    /// Déclenche la génération à partir de `generatorInputText`. Si vide
    /// (après trim), no-op. Sinon : token + `.loading` + Task qui appelle
    /// `ActionGenerator.generate`. À la fin du Task, ignore le résultat
    /// si le token a changé (cas Esc pendant loading).
    func runGeneration() {
        let input = generatorInputText.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }

        let myToken = UUID()
        currentGenerationToken = myToken
        generatorPhase = .loading

        // Annule un éventuel Task précédent (sécurité — il ne devrait pas
        // y avoir 2 générations simultanées).
        generationTask?.cancel()
        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await ActionGenerator.generate(userRequest: input)

            // Annulation logique : si le token a changé entre-temps
            // (Esc pendant le loading), on jette le résultat.
            guard self.currentGenerationToken == myToken else { return }

            switch result {
            case .success(let action):
                // K.2-B lot 2b — peuple les 4 champs éditables depuis la
                // proposition IA. En regénération (lot 2b : bouton
                // « Regénérer » côté UI), ce code écrase les éditions
                // manuelles de l'utilisateur — comportement « Regénérer
                // = recommence », décision actée.
                self.editableTitle = action.title
                self.editableEmoji = action.emoji
                self.editableDescription = action.description
                self.editablePrompt = action.prompt
                // Catégorie remise à « Sans catégorie » à chaque
                // (re)génération — l'IA ne catégorise pas, l'utilisateur
                // choisit (ou laisse nil pour catégoriser plus tard).
                self.editableCategory = nil
                // K.2-B lot 2b — synchronisation animation : le NSWindow
                // resize est piloté par NSAnimationContext 0.25s côté
                // AppDelegate (`.onChange(generatorPhase)` → `resizePopover`).
                // Le withAnimation SwiftUI synchrone côté state permet
                // au contenu interne de cross-fade pendant que la fenêtre
                // s'agrandit — passage compact → éditable plus doux.
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.generatorPhase = .resultEditable(action)
                }
            case .failure(let error):
                let msg = Self.userFacingErrorMessage(for: error)
                self.generatorPhase = .error(message: msg)
            }
        }
    }

    /// Esc en mode Générateur — comportement dépendant de la phase :
    /// - `.loading` → annule + retour à `.compact` (préserve l'input pour
    ///   retry rapide).
    /// - `.compact` / `.resultEditable` / `.error` → quitte le mode
    ///   Générateur entièrement, retour à `mainView`.
    func handleEscapeInGeneratorMode() {
        guard let phase = generatorPhase else { return }
        cancelOngoingGeneration()
        switch phase {
        case .loading:
            generatorPhase = .compact
        case .compact, .resultEditable, .error:
            exitGeneratorMode()
        }
    }

    /// K.2-B lot 2b — sortie franche du mode générateur. Vide tous les
    /// champs (input + edits + catégorie) et met `generatorPhase = nil`.
    /// Appelé par le bouton Annuler de la bottom bar, par Esc en phases
    /// `.compact` / `.resultEditable` / `.error` (via
    /// `handleEscapeInGeneratorMode`), et par `validateAndRun()` après
    /// ajout au catalogue.
    func exitGeneratorMode() {
        cancelOngoingGeneration()
        generatorPhase = nil
        generatorInputText = ""
        clearEditableFields()
    }

    /// Invalide le token (annulation logique d'un résultat en cours) et
    /// `cancel()` le Task. Sûr à appeler même sans génération active.
    private func cancelOngoingGeneration() {
        currentGenerationToken = nil
        generationTask?.cancel()
        generationTask = nil
    }

    /// Mappe un `GeneratorError` vers le message user-facing affiché dans
    /// la phase `.error`. K.3 (polish) : 4 messages ciblés (le Lot 2a n'en
    /// avait que 2, en attendant ce polish). `noApiKey` actionnable ·
    /// `timeout` dédié · `providerUnavailable` (réseau/5xx) · le trio
    /// emptyResponse/invalidJSON/incompleteFields regroupé sous « réponse
    /// inattendue » (même cause vécue côté utilisateur : l'IA n'a pas
    /// renvoyé ce qu'on attendait).
    private static func userFacingErrorMessage(for error: GeneratorError) -> String {
        switch error {
        case .noApiKey:
            return "Aucun fournisseur IA configuré. Va dans les Réglages pour en configurer un."
        case .timeout:
            return "Délai dépassé. Réessaie."
        case .providerUnavailable:
            return "Service IA momentanément indisponible. Réessaie."
        case .emptyResponse, .invalidJSON, .incompleteFields:
            return "Réponse inattendue de l'IA. Réessaie."
        }
    }

    // MARK: - K.2-B lot 2b — Validation et ajout au catalogue

    /// Les 4 champs (Titre/Emoji/Description/Prompt) sont non-vides
    /// après trim. `editableCategory == nil` (« Sans catégorie ») est un
    /// choix valide, pas une absence. Le bouton ⌘↵ Valider de la bottom
    /// bar lit cette propriété via `.disabled(!state.canValidate)`.
    var canValidate: Bool {
        !editableTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !editableEmoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !editableDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !editablePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Convertit les 4 champs édités + la catégorie choisie en une
    /// `Action` complète, l'ajoute au catalogue via
    /// `ActionsStore.addAction()`, puis :
    /// - Si du texte a été capturé à l'ouverture du popup
    ///   (`CapturedTextManager.shared.hasSelection`) → lance l'action
    ///   immédiatement via `runAction(_:)`. Le popup bascule en mode
    ///   résultat compact via `.onChange(activeAction)` côté
    ///   PopoverView.
    /// - Sinon (aucun texte capturé) → l'action est ajoutée au
    ///   catalogue mais pas lancée (pas de texte cible). Le popup se
    ///   ferme proprement via `hidePopover()`. Garde défensive : le
    ///   popup s'ouvre désormais uniquement sur sélection
    ///   (`showPopover(requireSelection: true)`), mais le cas reste
    ///   couvert sans risque.
    ///
    /// La sélection capturée est figée à l'ouverture du popup
    /// (cf. `AppDelegate.captureSelectedText()` appelée uniquement
    /// dans `showPopover` / `showPopoverWithAction`), donc la lecture
    /// de `hasSelection` ici est stable — pas besoin de snapshot.
    ///
    /// Ordre des opérations critique : `runAction` D'ABORD (set
    /// `activeAction`), `generatorPhase = nil` APRÈS — le
    /// `.onChange(of: generatorPhase)` côté PopoverView lit
    /// `state.activeAction != nil` au moment du retour à nil pour
    /// décider de NE PAS resize vers `.list` (le `.onChange(activeAction)`
    /// resize vers `.resultCompact` à la place).
    func validateAndRun() {
        guard canValidate else { return }

        let store = ActionsStore.shared
        // K.2-B lot 2b — `displayOrder` en queue de catalogue : max
        // existant + 1. Évite la collision avec les actions au
        // `displayOrder = 0` par défaut et place l'action générée à
        // la fin (cohérent avec « action ajoutée »).
        let nextDisplayOrder = (store.actions.map(\.displayOrder).max() ?? 0) + 1
        let newAction = Action(
            id: UUID(),
            name: editableTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: editableEmoji.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: editablePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            actionType: .ai,
            shortDescription: editableDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            originTemplateName: nil,
            isFavorite: false,
            isHidden: false,
            displayOrder: nextDisplayOrder,
            category: editableCategory
        )
        store.addAction(newAction)

        let hasText = CapturedTextManager.shared.hasSelection
        if hasText {
            // Lance l'action immédiatement — la popup bascule en mode
            // résultat via `.onChange(activeAction)`. Ordre :
            // runAction d'abord (set activeAction), nettoyage et
            // generatorPhase = nil ensuite.
            runAction(newAction)
            generatorInputText = ""
            clearEditableFields()
            generatorPhase = nil
        } else {
            // Pas de texte cible : action ajoutée au catalogue, popup
            // fermé sans lancement (pas d'erreur, pas de plantage).
            exitGeneratorMode()
            globalAppDelegate?.hidePopover()
        }
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

        // M.2.3 — coche « action » côté tuto dès le lancement.
        if tutorialMode { tutorialActionRunHandler?() }

        let apiKey = store.apiKey
        let provider = store.selectedProvider
        // M.2.3 — en mode tuto, force le tier 🚀 rapide du provider (1ᵉʳ par
        // convention d'ordre dans `allModels`). Override transitoire, non
        // persisté → le modèle par défaut de l'utilisateur reste intact.
        let model = tutorialMode
            ? (AIModel.models(for: provider).first ?? store.selectedModel)
            : store.selectedModel
        let inputText = textManager.capturedText
        #if DEBUG
        if tutorialMode { print("🧪 [tuto] inputText au run [\(inputText.count)] = \(inputText.debugDescription)") }
        #endif
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
                    model: model,
                    onChunk: { [weak self] chunk in
                        // Le chunk callback est invoqué via `await MainActor.run`
                        // côté AIService — on est donc bien sur MainActor ici.
                        // On accumule plutôt que de modifier `resultText`
                        // directement : un seul re-render par frame.
                        self?.pendingChunkBuffer += chunk
                    },
                    onUsage: { modelId, inputTokens, outputTokens in
                        // L.2 — invoqué via MainActor.run côté AIService, une
                        // seule fois en fin de stream réussi. UsageTracker est
                        // @MainActor → recordTokens sûr ici.
                        UsageTracker.shared.recordTokens(modelId: modelId,
                                                         input: inputTokens,
                                                         output: outputTokens)
                    }
                )
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

            // Compteur d'utilisations total (distinct du trial) —
            // incrémenté sur tout stream réussi, quel que soit le
            // statut de licence. K.4-lot3 (L2) : on incrémente AUSSI le
            // compteur par action (clé = action.id) sur le MÊME événement
            // « stream réussi » → total et par-action restent cohérents.
            if streamSucceeded {
                UsageTracker.shared.recordSuccessfulUse()
                UsageTracker.shared.recordActionUse(actionID: action.id)
            }
        }
    }
}

// MARK: - GeneratorPhase (K.2-B lot 2a, étendu lot 2b)

/// Phase courante du popover Générateur d'actions AI. Stockée dans
/// `PopoverState.generatorPhase: GeneratorPhase?` ; `nil` signifie
/// « pas en mode générateur ».
///
/// - `.compact` : saisie de la demande. TextField focalisé, bouton
///   « Générer » actif.
/// - `.loading` : appel `ActionGenerator.generate` en cours. UI affiche
///   un spinner. TextField désactivé.
/// - `.resultEditable(GeneratedAction)` (K.2-B lot 2b) : génération
///   réussie. Les 4 champs (titre/emoji/description/prompt) sont
///   éditables nativement via les `editable*` de `PopoverState` +
///   sélecteur de catégorie + barre Annuler/Valider. Le payload
///   `GeneratedAction` est la proposition initiale (peuplée dans les
///   `editable*` au moment de la transition vers cette phase).
/// - `.error(message: String)` : génération échouée. Message affiché,
///   bouton Générer prêt à relancer. Popover reste compact.
enum GeneratorPhase: Equatable {
    case compact
    case loading
    case resultEditable(GeneratedAction)
    case error(message: String)
}
