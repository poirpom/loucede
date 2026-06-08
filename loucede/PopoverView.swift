//
//  PopoverView.swift
//  loucede
//
//  Vue principale de la popup. Phase 1 — l'état est centralisé dans
//  PopoverState (singleton) pour permettre le préchargement en mémoire
//  de la fenêtre (createPopoverWindow appelé une seule fois au démarrage).
//

import SwiftUI
import AppKit
import Combine
import MarkdownUI

// MARK: - Shared UI helpers

extension View {
    func pointerCursor() -> some View {
        self.onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// Champs de focus possibles dans le popup. Utilisés avec @FocusState pour
// forcer le focus clavier sur la bonne sous-vue à chaque ouverture — nécessaire
// depuis que la fenêtre AppKit est préchargée (cf. PopoverState.openCounter).
private enum PopoverFocus: Hashable {
    case main
    case result
    case generator   // K.2-B lot 2a
}

struct PopoverView: View {
    var onClose: () -> Void
    var onOpenSettings: () -> Void
    /// Phase 6.3 : callback pour ouvrir les Réglages directement sur
    /// l'onglet Mises à jour. Injecté depuis `createPopoverWindow()`.
    var onOpenUpdates: () -> Void

    @StateObject private var store = ActionsStore.shared
    @StateObject private var textManager = CapturedTextManager.shared
    @StateObject private var updateChecker = UpdateChecker.shared
    @ObservedObject private var state = PopoverState.shared
    @FocusState private var focus: PopoverFocus?
    // Message du toast de confirmation (ex. "Copié", "Collé"). Nil = pas de toast.
    @State private var confirmation: String?
    // Monitor NSEvent pour capter les keycodes physiques 18-29 (touches 1/& à 0/à)
    // et exécuter l'action au slot correspondant. Installé une seule fois au premier
    // .onAppear — NSEvent.addLocalMonitor ne matche que les events de cette app, donc
    // il ne se déclenche que quand le popup est key window (pas de conflit hors popup).
    @State private var slotMonitor: Any?
    // K.0 : focus du vrai TextField de recherche (remplace le hack
    // Text + Rectangle clignotant + capture .onKeyPress). Forcé à
    // l'ouverture en mode liste (NSWindow préchargée → focus à re-armer).
    @FocusState private var isSearchFocused: Bool
    // K.2-B lot 2a : focus du TextField « Action à générer » dans le mode
    // Générateur. Re-armé via .onChange(of: state.generatorPhase) quand on
    // entre/sort des phases qui requièrent un TextField focalisé
    // (.compact et .error).
    @FocusState private var isGeneratorFocused: Bool
    // K.2-B lot 2b : focus du TextField « Titre » du popover éditable.
    // Armé à l'entrée en `.resultEditable` (premier des 4 champs à
    // retoucher, prompt en bas). Désarmé dans toutes les autres phases.
    @FocusState private var isEditableTitleFocused: Bool
    // Phase 1.4b : état « fenêtre résultat agrandie » (touche F).
    // Reset à false dès qu'on quitte la vue résultat (retour liste ou réouverture
    // du popup), pour que chaque nouvelle action reparte en format compact.
    @State private var resultExpanded: Bool = false

    init(
        onClose: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onOpenUpdates: @escaping () -> Void = {}
    ) {
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
        self.onOpenUpdates = onOpenUpdates
    }

    // Phase 6.7b revertée (2026-04-29) : loucedé suit le mode système.
    // Les fonds #2E2E2E / #1B1C1C sont remplacés par des couleurs
    // sémantiques NSColor (windowBackgroundColor / controlBackgroundColor)
    // qui s'adaptent automatiquement à light et dark.

    // K.0 : `position(forPhysicalKeyCode:)` + table `positionShortcuts`
    // supprimés — les raccourcis ⌘1-⌘N positionnels n'existent plus
    // (navigation flèches + ↵ uniquement, gérée par le monitor NSEvent).

    var body: some View {
        VStack(spacing: 0) {
            // K.2-B lot 2a : 3 branches mutuellement exclusives. Priorité
            // générateur > résultat > main : si une génération est en
            // cours, elle prime sur tout le reste.
            if state.generatorPhase != nil {
                generatorView
            } else if let action = state.activeAction {
                resultView(for: action)
            } else {
                mainView
            }
        }
        // Phase 1.4b : largeur responsive (400 compact → 500 agrandi). Nécessaire
        // pour que le contenu SwiftUI suive l'animation de la NSWindow ; sinon
        // on verrait une bande transparente de chaque côté.
        .frame(width: resultExpanded ? 500 : 400)
        // Q.1.b : vibrancy hudWindow (PolishVibrancyView) sur le popup principal.
        // TODO Q.1.d: supprimer ce conditionnel une fois resultView migré (Q.1.c
        // migrera generator). Cette condition est temporaire pour ne pas affecter
        // les surfaces hors-périmètre Q.1.b — generator/result gardent le fond
        // solide `windowBackgroundColor` inchangé jusqu'à Q.1.c/d.
        .background {
            if state.generatorPhase == nil && state.activeAction == nil {
                PolishVibrancyView()
            } else {
                Color(NSColor.windowBackgroundColor)
            }
        }
        // K.4-lot1 (P3) : radius 12 → 16 (look macOS récent sans copier les
        // radius exagérés de Tahoe). DOIT rester synchro avec le layer de la
        // NSWindow (`hostingView.layer.cornerRadius` dans loucedeApp.swift).
        // Couvre liste ET résultat (même body/fenêtre).
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // Q.1.b-bis : bordure intérieure subtile du panneau (4 côtés). Appliquée
        // ici directement car le body pose son fond via le conditionnel Q.1.b
        // (pas `polishVibrancy()`). Couvre toutes branches via le clip partagé.
        .polishInnerBorder(cornerRadius: 16)
        // Phase 6.2 Étape 9 (2026-04-27) : modal « trial épuisé »
        // présenté en overlay (reste dans la fenêtre popup, pas une
        // sheet macOS séparée). Apparaît quand `state.showTrialExpiredModal`
        // devient true (set par `runAction` quand `canRunAction` fail).
        .overlay {
            if state.showTrialExpiredModal {
                TrialExpiredOverlay(
                    onDismiss: { state.showTrialExpiredModal = false },
                    onPurchase: {
                        state.showTrialExpiredModal = false
                        onClose()   // ferme le popup (la fenêtre Polar ne reste pas derrière)
                        PurchaseWindowController.presentCheckout()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.showTrialExpiredModal)
        // L'overlay trial (boutons .defaultAction/.cancelAction) doit posséder
        // le clavier : sinon le champ de recherche focalisé capte ⏎ via son
        // `.onKeyPress(.return)` (renvoie `.handled`) et « Acheter » ne se
        // déclenche jamais. On retire le focus à l'affichage, on le rend à la
        // fermeture (« Plus tard » → reprise de la frappe).
        .onChange(of: state.showTrialExpiredModal) { _, shown in
            isSearchFocused = !shown
        }
        // Re-force le focus à chaque ouverture du popup (openCounter s'incrémente
        // dans PopoverState.reset()). Sans ça, la fenêtre préchargée garde un
        // focus stale. K.0 : en mode liste, le focus va au TextField de
        // recherche (`isSearchFocused`) ; en mode résultat, au conteneur
        // `.result`. Async pour fiabiliser sur NSWindow préchargée.
        .onChange(of: state.openCounter) { _, _ in
            focus = state.activeAction == nil ? .main : .result
            if state.activeAction == nil {
                DispatchQueue.main.async { isSearchFocused = true }
            }
            confirmation = nil
            // Reset : showPopover remet déjà la fenêtre à 400×500, on n'a
            // qu'à synchroniser l'état local.
            resultExpanded = false
        }
        // Focus initial au premier affichage (avant le premier openCounter).
        .onAppear {
            focus = state.activeAction == nil ? .main : .result
            if state.activeAction == nil {
                DispatchQueue.main.async { isSearchFocused = true }
            }
            installSlotMonitorIfNeeded()
        }
        // Bascule aussi le focus quand on passe de liste → résultat ou retour.
        .onChange(of: state.activeAction) { _, newValue in
            focus = newValue == nil ? .main : .result
            if newValue == nil {
                DispatchQueue.main.async { isSearchFocused = true }
            } else {
                isSearchFocused = false
            }
            confirmation = nil
            // Phase 6.9b (2026-04-25) : la fenêtre est désormais dimensionnée
            // dynamiquement selon le mode. Sans resize au passage liste→résultat,
            // le résultat (~394pt) déborderait d'une fenêtre liste compacte
            // (ex. 296pt avec 5 actions). Inversement, le retour à la liste
            // doit recalculer la hauteur (les actions ont pu changer depuis).
            //
            // Phase 6.14-fix (2026-04-26) : suspend/resume flush autour du
            // resize, même raison que `toggleResultExpanded` ci-dessous.
            // Particulièrement critique au passage liste→résultat : le
            // streaming démarre, et le premier flush peut atterrir pile
            // pendant l'animation NSWindow.
            if newValue == nil {
                state.suspendFlush()
                // Point 2 pre-V1 (2026-05-08) : passe la recherche courante
                // pour que la popup retrouve sa taille dynamique (le builder
                // K.unify.3 reconstruit la liste pour mesurer la hauteur).
                globalAppDelegate?.resizePopover(to: .list, searchQuery: state.searchQuery)
                // Phase 6.14-fix-2 : set instantané, pas de withAnimation
                // (cf. `toggleResultExpanded` pour l'analyse complète).
                if resultExpanded {
                    resultExpanded = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    state.resumeFlush()
                }
            } else if !resultExpanded {
                state.suspendFlush()
                globalAppDelegate?.resizePopover(to: .resultCompact)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    state.resumeFlush()
                }
            }
            // Si newValue != nil ET resultExpanded == true, on ne resize pas :
            // l'utilisateur reste en mode résultat agrandi (cas extrême : il
            // déclenche une nouvelle action depuis le résultat agrandi, ce
            // qui n'arrive pas dans l'UX actuelle mais reste safe).
        }
        // K.2-B lot 2a — Transitions du mode Générateur :
        // 1) Resize la NSWindow selon la phase (compact vs resultEditable).
        // 2) Gère le focus du TextField « Action à générer ».
        // 3) Au retour à `nil` (sortie du mode), retour à `.list`.
        .onChange(of: state.generatorPhase) { _, newPhase in
            if let phase = newPhase {
                // Resize selon la phase.
                let popupPhase: AppDelegate.GeneratorPopupPhase
                switch phase {
                case .compact, .loading, .error: popupPhase = .compact
                case .resultEditable:            popupPhase = .resultEditable
                }
                state.suspendFlush()
                globalAppDelegate?.resizePopover(to: .generator(popupPhase))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    state.resumeFlush()
                }
                // Focus :
                // - `.compact` / `.error` : focus sur le TextField « Action à générer ».
                // - `.loading` : pas de focus (champ désactivé).
                // - `.resultEditable` (K.2-B lot 2b) : focus sur le champ Titre
                //   éditable (premier des 4 champs à retoucher — le prompt est
                //   en bas, donc on commence par le haut).
                switch phase {
                case .compact, .error:
                    isEditableTitleFocused = false
                    DispatchQueue.main.async { isGeneratorFocused = true }
                case .loading:
                    isGeneratorFocused = false
                    isEditableTitleFocused = false
                case .resultEditable:
                    isGeneratorFocused = false
                    DispatchQueue.main.async { isEditableTitleFocused = true }
                }
                focus = .generator
            } else {
                // K.2-B lot 2b — Retour à la liste, SAUF si l'utilisateur
                // vient de valider l'action et qu'elle a été lancée
                // (`activeAction != nil`). Dans ce cas, on laisse
                // `.onChange(activeAction)` resize vers `.resultCompact` —
                // pas de double resize ni de saut `.generator` → `.list`
                // → `.resultCompact` (animation moche).
                if state.activeAction == nil {
                    state.suspendFlush()
                    globalAppDelegate?.resizePopover(to: .list, searchQuery: state.searchQuery)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        state.resumeFlush()
                    }
                    focus = .main
                    DispatchQueue.main.async { isSearchFocused = true }
                }
                isGeneratorFocused = false
                isEditableTitleFocused = false
            }
        }
    }

    // MARK: - Confirmation toast helper

    /// Affiche un toast de confirmation au centre de la vue (copie / collage).
    /// `duration` = temps avant disparition auto. `then` = action à exécuter
    /// après la disparition (utile pour Coller qui ferme le popup).
    /// Installe le monitor NSEvent qui capte les touches 1/& → 0/à (keycodes 18-29)
    /// et lance l'action assignée au slot correspondant, quand le popup est en mode liste.
    /// N'installe qu'une seule fois (pas de leak, pas de double capture).
    private func installSlotMonitorIfNeeded() {
        guard slotMonitor == nil else { return }
        // Capture locale : évite que le closure du monitor ne retienne `self`.
        let closeHandler = onClose
        let settingsHandler = onOpenSettings
        slotMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Esc — K.0-fix-1 : la gestion dépend du contexte.
            // • Mode générateur (K.2-B lot 2a) : monitor handles
            //   ENTIRELY (consume). Le TextField du générateur ne
            //   déclare PAS .onKeyPress(.escape) — single source of
            //   truth, pas de double-traitement.
            // • Vue liste (TextField focalisé) : on LAISSE PASSER à
            //   SwiftUI (`return event`). Le `.onKeyPress(.escape)` du
            //   TextField gère le 2-temps (clear puis close) en lisant
            //   directement la valeur SwiftUI — pas de staleness
            //   inter-couche (cause de la régression K.0).
            // • Vue résultat / empty state (pas de TextField focalisé) :
            //   le monitor ferme ici (couche fiable sans field editor).
            if mods.isEmpty && event.keyCode == 53 {
                if state.generatorPhase != nil {
                    state.handleEscapeInGeneratorMode()
                    return nil
                }
                if state.activeAction == nil && store.hasUsableProvider {
                    return event // → SwiftUI .onKeyPress(.escape) du TextField
                }
                state.endStream()
                closeHandler()
                return nil
            }

            // K.2-B lot 2a — En mode générateur, le flux est focalisé.
            // • Esc : géré ci-dessus (consume + handleEscapeInGeneratorMode).
            // • ⌘, / ⌘D : DÉSACTIVÉS, consommés silencieusement. Le mode
            //   générateur ne se quitte que par Esc — on n'ouvre pas
            //   Réglages/Doc par-dessus une génération en cours ou un
            //   résultat non sauvegardé.
            // • Autres touches (incl. ↵) : déléguées à SwiftUI (TextField
            //   pour la frappe, .onSubmit pour ↵ → runGeneration).
            if state.generatorPhase != nil {
                if mods == [.command]
                    && (event.charactersIgnoringModifiers == ","
                        || event.charactersIgnoringModifiers == "d") {
                    return nil
                }
                return event
            }

            // Le reste (⌘,, ⌘D) ne s'applique qu'en vue liste.
            // En vue résultat → laisser passer à SwiftUI.
            guard state.activeAction == nil else { return event }

            // Empty state (pas de provider utilisable, pas de TextField) :
            // ↵ et ⌘, ouvrent les Réglages. Reste géré ici car aucun
            // TextField focalisé pour relayer en SwiftUI.
            if !store.hasUsableProvider {
                if (mods == [.command] && event.charactersIgnoringModifiers == ",")
                    || (mods.isEmpty && event.keyCode == 36) {
                    settingsHandler()
                    return nil
                }
                return event
            }

            // K.0-fix-1 : ↑/↓/↵ ne sont plus captés ici. Avec un
            // TextField focalisé, la navigation liste est gérée par
            // `.onKeyPress(.upArrow/.downArrow/.return)` posés sur le
            // TextField (couche fiable sur vue focalisée). Tout le
            // sans-modifier passe nativement au TextField.
            if mods.isEmpty {
                return event
            }

            // --- ⌘ seul : ⌘, Réglages + ⌘D Doc. K.0 : les slots ⌘1-⌘N
            // ont été supprimés. charactersIgnoringModifiers pour
            // indépendance layout clavier (AZERTY/QWERTY).
            if mods == [.command] {
                if event.charactersIgnoringModifiers == "," {
                    settingsHandler()
                    return nil
                }
                // ⌘D — ouvre la doc embarquée. Ferme le popup AVANT
                // (sinon la fenêtre doc ouvre derrière, popoverWindow
                // ayant un NSWindow level supérieur). `closeHandler()`
                // joue le rôle du « hidePopover » côté Settings.
                if event.charactersIgnoringModifiers == "d" {
                    closeHandler()
                    globalAppDelegate?.openDocumentation()
                    return nil
                }
                return event
            }

            return event
        }
    }

    /// Phase 1.4b : bascule le format de la fenêtre résultat (compact ↔ agrandi).
    /// Deux animations jouent en parallèle et de même durée (0.25 s easeInOut) :
    /// 1) la NSWindow via NSAnimationContext (AppDelegate.resizePopover)
    /// 2) les frames SwiftUI via withAnimation
    /// La 2e évite le saut abrupt à la réduction : sans elle, SwiftUI recalcule
    /// instantanément maxHeight=300, ce qui crée un espace vide avant que la
    /// fenêtre elle-même n'ait fini de rétrécir.
    private func toggleResultExpanded() {
        let newExpanded = !resultExpanded
        // Phase 6.14-fix (2026-04-26) : suspend le flush du buffer LLM
        // pendant l'animation NSWindow. Sans ça, la mutation de
        // `state.resultText` à 60Hz pendant que AppKit anime la fenêtre
        // déclenche un crash NSInternalInconsistencyException
        // « The window has been marked as needing another Update Constraints ».
        //
        // Phase 6.14-fix-2 (2026-04-26) : RETRAIT du `withAnimation` sur
        // `resultExpanded`. La cause résiduelle du crash était l'animation
        // SwiftUI qui interpolait la frame du ScrollView (300 ↔ 2000pt) en
        // parallèle de l'animation NSWindow — ~15 re-renders SwiftUI pendant
        // les 250ms, chacun forçant le solver de constraints à reculer en
        // même temps qu'AppKit animait la window. Race condition fatale.
        // Avec le set instantané, `resultExpanded` passe à la nouvelle
        // valeur en 1 frame, et seule la NSWindow s'anime côté AppKit —
        // pas de chevauchement. Trade-off : à la réduction, pendant 250ms,
        // une fine bande noire peut apparaître en bas (window rétrécit
        // progressivement, ScrollView déjà à 300pt). Largement acceptable.
        state.suspendFlush()
        globalAppDelegate?.resizePopover(to: newExpanded ? .resultExpanded : .resultCompact)
        resultExpanded = newExpanded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [state] in
            state.resumeFlush()
        }
    }

    private func showConfirmation(_ message: String, duration: Double = 1.2, then completion: (() -> Void)? = nil) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            confirmation = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if confirmation == message {
                withAnimation(.easeOut(duration: 0.2)) {
                    confirmation = nil
                }
            }
            completion?()
        }
    }

    // MARK: - Main

    /// K.unify.3 — liste unifiée de la popup (FAVORIS + catégories +
    /// Sans catégorie + Générateur). Toute la logique de construction
    /// vit dans `PopupItemBuilder` (pure, partagée avec le calcul de
    /// hauteur de la fenêtre). Plus de filtrage `originTemplateName` :
    /// avec le modèle unifié, une action n'existe qu'une fois, pas de
    /// duplication possible entre « actions » et « modèles ».
    private var popupItems: [PopupItem] {
        PopupItemBuilder.build(actions: store.actions, searchQuery: state.searchQuery)
    }

    /// Items navigables au clavier (en-têtes de section exclus).
    /// `state.selectedIndex` indexe CE tableau.
    private var selectableItems: [PopupItem] {
        popupItems.filter { $0.isSelectable }
    }

    /// Exécute l'item activé (↵ ou clic). K.unify.3 : une seule sorte de
    /// ligne d'action (`.action`) — plus de conversion modèle→action.
    /// K.2-B lot 2a — `.generator` bascule la popup en mode générateur,
    /// pré-rempli avec la `searchQuery` courante. La transition de view
    /// + resize est pilotée par `.onChange(of: state.generatorPhase)`.
    private func activate(_ item: PopupItem) {
        switch item {
        case .sectionHeader:
            break // non sélectionnable, n'arrive jamais
        case .action(let action):
            state.runAction(action)
        case .generator:
            state.enterGeneratorMode(prefilled: state.searchQuery)
        }
    }

    private var mainView: some View {
        // spacing: 0 (comme resultView) pour que la zone basse colle directement
        // au Divider sous la preview, sans gap visuel dû au spacing du VStack.
        VStack(alignment: .leading, spacing: 0) {
            // Phase 6.18-fix-2 (2026-04-28) : top bar TOUJOURS visible.
            // Si selection : preview à gauche + logo à droite (alignment
            // .top pour que le logo soit aligné avec la première ligne du
            // preview). Si pas de selection : Spacer à gauche + logo à
            // droite.
            // Point 2 pre-V1 (2026-05-07) : le logo devient passif —
            // élément d'identité visuelle uniquement. Réglages reste
            // accessible via ⌘, (raccourci, monitor NSEvent — K.4-lot1 a
            // retiré son affichage du footer) ou via l'item « 🔑 Configure
            // une clé API » en empty state.
            HStack(alignment: .top, spacing: 8) {
                if textManager.hasSelection {
                    Text(textManager.capturedText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }

                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)
            // Q.1.b : bande header = zone d'accent (overlay translucide sur la
            // vibrancy). Permanente — appliquée même sans texte sélectionné
            // (logo seul). La différenciation de zone remplace le Divider retiré.
            .polishAccentBackground()

            // 2026-05-07 : empty state quand le provider courant n'a pas de
            // clé API configurée (cf. `ActionsStore.hasUsableProvider`).
            // Évite la liste d'actions « cassée » qui afficherait un message
            // d'erreur LLM à la première utilisation. Le bouton logo en top
            // bar reste fonctionnel (deuxième chemin vers Réglages).
            if !store.hasUsableProvider {
                emptyStateView
            } else {
                actionsListView
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .main)
        // K.0 : `.onKeyPress(phases:.down)` retiré. La saisie de recherche
        // est gérée nativement par le vrai TextField (cf. actionsListView) ;
        // la navigation ↑/↓/↵, Esc et ⌘,/⌘D sont centralisées dans le
        // monitor NSEvent (cf. installSlotMonitorIfNeeded) — capture fiable
        // indépendante du focus, y compris quand le TextField est focalisé.
        // Reset l'index sélectionné quand la liste filtrée change, sinon on peut
        // pointer hors-bornes après filtrage.
        // Point 2 pre-V1 (2026-05-08) : redimensionne aussi la popup pour
        // qu'elle s'adapte dynamiquement au nombre d'actions visibles
        // après filtrage (search à 1 résultat → popup compacte ; clear
        // search → popup retrouve sa pleine hauteur).
        .onChange(of: state.searchQuery) { _, newValue in
            state.selectedIndex = 0
            globalAppDelegate?.resizePopover(to: .list, searchQuery: newValue)
            // M.2.5-fix-3/4 — coche « search » à partir de 3 caractères tapés
            // (option permissive : quel que soit le texte). No-op ailleurs.
            if state.tutorialMode && newValue.count >= 3 { state.tutorialSearchHandler?() }
        }
        // 2026-05-07 : recalcule la taille de la fenêtre quand le provider
        // bascule de « pas utilisable » à « utilisable » (ou inverse) sans
        // que la popup ait été fermée entre-temps. Cas d'usage : utilisateur
        // ouvre popup empty state → garde popup ouverte → ouvre Réglages →
        // configure une clé → ferme Réglages → la popup se redimensionne
        // automatiquement vers le mode liste (et inverse si suppression de
        // la clé). Sans ce hook, la NSWindow resterait figée à la taille
        // d'ouverture.
        .onChange(of: store.hasUsableProvider) { _, _ in
            globalAppDelegate?.resizePopover(to: .list, searchQuery: state.searchQuery)
        }
    }

    // MARK: - Actions list (ex-zone basse de mainView)

    /// Zone basse de la popup en mode normal : search bar, liste d'actions,
    /// updateRow conditionnel, footer nav 2 lignes. Extrait de `mainView`
    /// le 2026-05-07 (Point 1 pre-V1) pour permettre la bascule avec
    /// `emptyStateView` sans dupliquer la top bar. Footer 2 lignes adopté
    /// le même jour (Point 2 pre-V1) en remplacement du `settingsRow` fixe.
    private var actionsListView: some View {
        // Phase 1.4i : zone basse de la popup (liste + footer nav) en
        // controlBackgroundColor, légèrement distincte du chrome supérieur.
        VStack(spacing: 0) {
            // K.0 : vrai TextField (remplace le hack Text + Rectangle
            // clignotant + capture .onKeyPress). Le curseur, la sélection,
            // ⌘C/V/A, ←/→, ⌫ et l'IME sont gérés nativement. Le focus est
            // re-armé à chaque ouverture en mode liste (NSWindow préchargée)
            // via `isSearchFocused` (cf. onAppear / onChange openCounter).
            // Q.1.b-bis : champ Rechercher aligné sur une ligne d'action virtuelle.
            // spacing 10 + loupe en boîte 20 (largeur) à 14pt = mirror de
            // selectableItemRow (ActionIconView boxSize 20 + spacing 10) → le
            // placeholder démarre au même x que les titres d'action. `.frame(width:)`
            // seul : pas de croissance verticale de la barre (popoverChromeHeight
            // inchangé).
            HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    TextField("Rechercher", text: $state.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        // Q.1.b : curseur d'accent loucedé sur champ sans contour.
                        .tint(PolishTokens.cursorColor)
                        .focused($isSearchFocused)
                        // K.0-fix-1 : navigation liste + Esc 2-temps gérés
                        // ici (vue focalisée → couche SwiftUI fiable, vs
                        // NSEvent monitor inadapté avec field editor actif).
                        // ↑/↓ : déplacent la sélection sans bouger le focus
                        // (le TextField mono-ligne n'a pas d'usage propre
                        // pour ↑/↓). ↵ : lance l'action sélectionnée.
                        // K.1 : navigation sur `selectableItems` (les
                        // en-têtes de section sont sautés automatiquement
                        // — ils ne sont pas dans `selectableItems`).
                        .onKeyPress(.upArrow) {
                            state.selectedIndex = max(0, state.selectedIndex - 1)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            let count = selectableItems.count
                            guard count > 0 else { return .handled }
                            state.selectedIndex = min(count - 1, state.selectedIndex + 1)
                            return .handled
                        }
                        .onKeyPress(.return) {
                            // Renfort anti-timing : si l'overlay trial est
                            // affiché, laisser ⏎ filer vers son bouton par
                            // défaut (« Acheter ») plutôt que de l'avaler.
                            if state.showTrialExpiredModal { return .ignored }
                            let sel = selectableItems
                            if sel.indices.contains(state.selectedIndex) {
                                activate(sel[state.selectedIndex])
                            }
                            return .handled
                        }
                        // Esc 2-temps : 1er = clear la recherche (geste
                        // familier macOS) ; 2e (recherche vide) = ferme le
                        // popup. `.handled` dans les deux cas pour empêcher
                        // le field editor de traiter Esc (cancelOperation).
                        .onKeyPress(.escape) {
                            if !state.searchQuery.isEmpty {
                                state.searchQuery = ""
                            } else {
                                state.endStream()
                                onClose()
                            }
                            return .handled
                        }
                }
                // Q.1.b : champ recherche flottant — pilule de fond retirée (le
                // champ flotte sur la vibrancy, pattern Things). Paddings verticaux
                // conservés pour la respiration. Divider au-dessus (sous la top bar)
                // et en dessous retirés : différenciation par ton, pas par bordure.
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                // Point 2 pre-V1 (2026-05-07) : popup à hauteur dynamique
                // (cf. AppDelegate.calculatedPopoverHeight). Le ScrollView
                // s'adapte à l'espace alloué par la NSWindow. K.unify.3 :
                // en vue par défaut la fenêtre est volontairement plus
                // courte que le contenu (hauteur « peek » → cue scroll),
                // donc le ScrollView défile pour explorer FAVORIS +
                // catégories. En recherche, hauteur adaptative au contenu.
                //
                // K.unify.3.4 — scroll auto : `ScrollViewReader` permet de
                // garder la ligne sélectionnée visible lors de la nav ↑/↓
                // (pattern Spotlight). La nav modifie `state.selectedIndex`
                // (cf. `.onKeyPress` du TextField, hors scope du proxy) ;
                // le `.onChange` ci-dessous, dans le scope du reader,
                // défile vers l'item sélectionné.
                ScrollViewReader { proxy in
                    ScrollView {
                        let rows = renderedRows
                        if rows.isEmpty {
                            // Cas rare : recherche vide ET aucune action
                            // visible (tout supprimé ou tout masqué).
                            Text("Aucune action")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 24)
                                .frame(maxWidth: .infinity)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                // Q.1.b-bis : PolishDivider entre catégories — inséré
                                // avant chaque en-tête de section sauf le 1er. Compté
                                // dans `listContentHeight` (loucedeApp) pour le fit
                                // exact en mode recherche.
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                    if index > 0, case .sectionHeader = row.item {
                                        PolishDivider()
                                    }
                                    popupRow(row)
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                    .onChange(of: state.selectedIndex) { _, newIndex in
                        // K.unify.3-fix-1 — pattern Spotlight : scroll MINIMAL.
                        // `scrollTo` sans anchor (anchor nil) ne défile que le
                        // strict nécessaire pour rendre la cible visible : rien
                        // si elle est déjà dans le viewport, sinon il l'amène
                        // au bord (en bas quand on descend, en haut quand on
                        // remonte). Remplace `anchor: .center` qui re-centrait
                        // à chaque déplacement → tout le contenu bougeait
                        // (ressenti « saccadé / la liste remonte »). Fiable
                        // ici car le VStack est NON-lazy : toutes les lignes
                        // existent, donc `scrollTo` trouve toujours sa cible.
                        // `selectableItems[newIndex].id` == l'id ForEach de la
                        // `RenderedRow` correspondante → cible scrollTo valide.
                        let sel = selectableItems
                        guard sel.indices.contains(newIndex) else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(sel[newIndex].id)
                        }
                    }
                }

                // Phase 6.3 : ligne « Mise à jour disponible » conditionnelle
                // au-dessus du footer quand UpdateChecker détecte une version
                // plus récente. Point 2 pre-V1 (2026-05-07) : settingsRow
                // retiré, Réglages accessible via ⌘, (raccourci ; K.4-lot1 a
                // retiré son affichage du footer).
                // Q.1.b-bis : Dividers retirés (au-dessus de l'updateRow et du
                // footer) — la séparation se fait par le ton (footer accent vs
                // zone neutre), pas par bordure.
                if updateChecker.updateAvailable {
                    updateRow()
                        .padding(.horizontal, 8)
                        .padding(.top, 2)
                }

                // Footer 1 ligne (K.4-lot1, 2026-05-22) : navigation popup
                // (↑↓ ↵ esc). La ligne 2 (⌘, Réglages / ⌘D Doc) a été retirée
                // — l'onboarding configure tout, la doc rejoindra les Réglages
                // (Phase F), et la popup priorise la vue d'actions. Les
                // raccourcis ⌘,/⌘D restent FONCTIONNELS (cf. monitor NSEvent
                // `installSlotMonitorIfNeeded`) — seul l'affichage disparaît.
                HStack(spacing: 8) {
                    // Phase 1.4e : mêmes dimensions typographiques que les
                    // boutons de la fenêtre résultat (13pt, taille .body
                    // par défaut) pour cohérence visuelle.
                    KeyboardKey("↑")
                    KeyboardKey("↓")
                    Text("Naviguer").font(.system(size: 13)).foregroundStyle(.primary)
                    Spacer()
                    KeyboardKey("↵")
                    Text("Valider").font(.system(size: 13)).foregroundStyle(.primary)
                    Spacer()
                    KeyboardKey("esc")
                    Text("Fermer").font(.system(size: 13)).foregroundStyle(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                // Q.1.b : footer raccourcis = zone d'accent (overlay translucide).
                .polishAccentBackground()
            }
            // Q.1.b : zone liste/recherche = neutre (vibrancy pure). L'ancien fond
            // opaque `controlBackgroundColor` est retiré — il masquerait le blur.
    }

    // MARK: - Empty state (pas de clé API configurée — 2026-05-07)

    /// Vue alternative à `actionsListView` quand `store.hasUsableProvider`
    /// est `false`. Affiche un texte contextuel + un seul item
    /// « 🔑 Configure une clé API » (toujours rendu en état sélectionné
    /// pour que ↵ ouvre Réglages directement) + un footer nav simplifié.
    /// Le bouton logo en top bar reste fonctionnel (deuxième chemin
    /// vers Réglages).
    private var emptyStateView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text("Pour utiliser loucedé, configure une clé API")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                configureAPIKeyRow()
                    .padding(.horizontal, 8)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            // Q.1.b-bis : Divider retiré — séparation par le ton (footer accent).

            // Footer nav simplifié : pas de ↑↓ (un seul item, rien à
            // naviguer). Layout symétrique avec Spacer central —
            // à valider runtime selon le ressenti (potentielle
            // flottaison sur footer si court ; à reposer en ferrage
            // à gauche « ↵ Valider · esc Fermer » si nécessaire).
            HStack(spacing: 8) {
                KeyboardKey("↵")
                Text("Valider").font(.system(size: 13)).foregroundStyle(.primary)
                Spacer()
                KeyboardKey("esc")
                Text("Fermer").font(.system(size: 13)).foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Q.1.b : footer = zone d'accent, symétrique avec actionsListView.
            .polishAccentBackground()
        }
        // Q.1.b : corps empty state = neutre (vibrancy). Fond opaque retiré.
    }

    /// Item unique de l'empty state — clic ou ↵ ouvre Réglages → Général.
    /// Toujours rendu en état « sélectionné » (couleur #3F84F7 + texte
    /// blanc) pour que ↵ marche directement et que l'utilisateur visualise
    /// immédiatement l'action par défaut. Pas de raccourci ⌘+touche
    /// affiché à droite : c'est une action contextuelle, pas une action
    /// utilisateur.
    private func configureAPIKeyRow() -> some View {
        HStack(spacing: 10) {
            Text("🔑")
                .font(.system(size: 14))
                .frame(width: 20, height: 20)
            Text("Configure une clé API")
                .font(.system(size: 13))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .foregroundStyle(Color.white)
        .background(PolishTokens.selectionBackground)
        // K.4-lot1 (P3) : radius 8, concentrique (popup 16 − inset 8pt) —
        // aligné sur la barre de sélection (même inset latéral 8pt).
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { onOpenSettings() }
        .pointerCursor()
    }

    // MARK: - K.1 : rendu de la liste unifiée 3 sections

    /// Ligne rendue = item + son index de sélection (nil pour les
    /// en-têtes, non navigables). Identifiable pour `ForEach`.
    private struct RenderedRow: Identifiable {
        let id: String
        let item: PopupItem
        let selIndex: Int?
    }

    /// Mappe `popupItems` → lignes rendues, en attribuant un index de
    /// sélection croissant aux seuls items sélectionnables (les
    /// en-têtes reçoivent `nil` → sautés par ↑/↓).
    private var renderedRows: [RenderedRow] {
        var out: [RenderedRow] = []
        var sel = 0
        for item in popupItems {
            if item.isSelectable {
                out.append(RenderedRow(id: item.id, item: item, selIndex: sel))
                sel += 1
            } else {
                out.append(RenderedRow(id: item.id, item: item, selIndex: nil))
            }
        }
        return out
    }

    @ViewBuilder
    private func popupRow(_ row: RenderedRow) -> some View {
        switch row.item {
        case .sectionHeader(let title):
            sectionHeaderRow(title)
        case .action(let action):
            selectableItemRow(icon: action.icon, name: action.name,
                              selIndex: row.selIndex, item: row.item)
        case .generator:
            selectableItemRow(icon: "✨", name: "Générer cette action",
                              selIndex: row.selIndex, item: row.item)
        }
    }

    /// K.1.4 — en-tête de section. Note : la sidebar doc utilise les
    /// `Section()` natives de `List` (non réutilisables dans ce
    /// `ScrollView` custom). Style aligné sur les conventions loucedé :
    /// petit, majuscules, gris secondaire, discret.
    private func sectionHeaderRow(_ title: SectionTitle) -> some View {
        Text(title.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    /// Ligne sélectionnable unifiée (action custom / modèle /
    /// générateur). Conserve le style historique de la liste
    /// (emoji + nom + surbrillance #3F84F7).
    private func selectableItemRow(icon: String, name: String,
                                   selIndex: Int?, item: PopupItem) -> some View {
        let isSelected = selIndex != nil && selIndex == state.selectedIndex
        return HStack(spacing: 10) {
            ActionIconView(icon: icon, boxSize: 20, fontSize: 14)
            Text(name)
                .font(.system(size: 13))
            Spacer()
            // Indice de découvrabilité : ⏎ déclenche l'item sélectionné.
            // Affiché sur la seule row sélectionnée (action ou Générateur).
            if isSelected {
                KeyboardKey("↵", onAccent: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // Phase 1.4j : sélection #3F84F7, texte blanc pour contraste.
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(isSelected ? PolishTokens.selectionBackground : Color.clear)
        // K.4-lot1 (P3) : radius 6 → 8, concentrique avec la popup :
        // radius_barre = radius_popup (16) − inset latéral (8pt, le
        // `.padding(.horizontal, 8)` du VStack de la liste) = 8.
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { activate(item) }
        .onHover { hovering in
            if hovering, let s = selIndex { state.selectedIndex = s }
        }
    }

    /// Ligne « Mise à jour disponible » (Phase 6.3). Visible uniquement quand
    /// `UpdateChecker.shared.updateAvailable == true`. Orange #F59E0B pour se
    /// distinguer du bouton Réglages (bleu). Clic → ouvre l'onglet Mises à jour.
    private func updateRow() -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 14))
                .frame(width: 20, height: 20)
                .foregroundStyle(updateOrange)
            Text("Mise à jour disponible")
                .font(.system(size: 13))
                .foregroundStyle(updateOrange)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundStyle(updateOrange.opacity(0.5))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(updateOrange.opacity(0.10))
        // K.4-lot1 (P3) : radius 8, concentrique (popup 16 − inset 8pt) —
        // aligné sur la barre de sélection (même inset latéral 8pt).
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { onOpenUpdates() }
        .pointerCursor()
    }

    private var updateOrange: Color {
        Color(red: 0.976, green: 0.620, blue: 0.043) // #F59E0B
    }

    // MARK: - Generator (K.2-B lot 2a + lot 2b)

    /// Vue racine du mode Générateur. Top bar commune + zone contenu
    /// variable selon `state.generatorPhase`. Largeur identique au popup
    /// liste (400pt, posée par le `.frame(width:)` du `body` racine) ;
    /// hauteur pilotée par `resizePopover(to: .generator(...))` côté
    /// AppDelegate. 4 phases : compact (saisie), loading, resultEditable
    /// (lot 2b — 4 champs éditables + Regénérer + catégorie + barre
    /// Annuler/Valider), error (compact + message).
    @ViewBuilder
    private var generatorView: some View {
        VStack(spacing: 0) {
            generatorTopBar
            Divider()
            if let phase = state.generatorPhase {
                switch phase {
                case .compact:
                    generatorCompactContent(error: nil)
                case .loading:
                    generatorLoadingContent
                case .resultEditable:
                    // K.2-B lot 2b — popover éditable + bottom bar
                    // Annuler/Valider en bas (en dehors du ScrollView).
                    generatorEditableContent
                    Divider()
                    generatorEditableBottomBar
                case .error(let message):
                    generatorCompactContent(error: message)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .generator)
    }

    /// Top bar commune à toutes les phases du générateur : titre à gauche
    /// + logo loucedé à droite (cohérent avec la top bar de `mainView`).
    private var generatorTopBar: some View {
        HStack(spacing: 8) {
            Text("🆕 Générer une nouvelle action")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(12)
    }

    /// Contenu compact : label + helper d'exemple + TextField + bouton.
    /// `error` non-nil → affiche le message d'erreur sous le champ
    /// (phase `.error` réutilise cette vue avec le message).
    ///
    /// K.2-B lot 2a — Ajustement 2 : pas de placeholder dans le TextField
    /// (le champ est pré-rempli avec `searchQuery` au moment de l'entrée
    /// en mode générateur, le placeholder ne serait quasi jamais visible).
    /// L'exemple « Ex. : traduis en russe » est affiché au-DESSUS du
    /// champ, toujours visible quel que soit l'état de saisie.
    @ViewBuilder
    private func generatorCompactContent(error: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Action à générer")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Ex. : traduis en russe")
                    .font(.system(size: 11))
                    .italic()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("", text: $state.generatorInputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .focused($isGeneratorFocused)
                    .onSubmit { state.runGeneration() }

                Button(action: { state.runGeneration() }) {
                    HStack(spacing: 6) {
                        Text("Générer")
                            .font(.system(size: 13))
                        KeyboardKey("↵")
                    }
                    .padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.generatorInputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    /// Phase loading : TextField désactivé + spinner.
    private var generatorLoadingContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Action à générer")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("", text: .constant(state.generatorInputText))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                )
                .disabled(true)

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Génération en cours… 30 sec. de patience max 🙏")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    /// Phase resultEditable (K.2-B lot 2b) : popover ÉDITABLE complet.
    /// - Section A : champ « Action à générer » (toujours visible) + bouton
    ///   « Regénérer » (relance la génération, écrase les éditions
    ///   manuelles, décision actée).
    /// - Section B : 4 champs éditables (Titre/Emoji/Description mono-lignes,
    ///   Prompt multi-ligne plafonné à 200pt scrollable).
    /// - Section C : sélecteur de catégorie (« Sans catégorie » par défaut
    ///   + 6 catégories réelles, `.custom` DEPRECATED exclu).
    /// Wrappé dans un ScrollView pour safety si l'écran est très petit.
    /// La bottom bar Annuler/Valider est en dehors (côté `generatorView`),
    /// pour rester fixée en bas.
    private var generatorEditableContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // --- Section A : Action à générer + Regénérer ---
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Action à générer")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Ex. : traduis en russe")
                            .font(.system(size: 11))
                            .italic()
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        TextField("", text: $state.generatorInputText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.primary.opacity(0.06))
                            )
                            .focused($isGeneratorFocused)

                        // K.2-B lot 2b — Regénérer est SECONDAIRE dans ce
                        // contexte (l'action principale est Valider de la
                        // bottom bar). Style discret `.bordered`, pas
                        // `.borderedProminent` qui inverserait la hiérarchie
                        // visuelle. Pas de raccourci dédié (Faab a tranché).
                        Button(action: { state.runGeneration() }) {
                            Text("Regénérer")
                                .font(.system(size: 13))
                                .padding(.horizontal, 6)
                                // Épouse la hauteur du TextField voisin (le
                                // .bordered intrinsèque est plus court). Pas
                                // de nombre magique : s'aligne sur la hauteur
                                // du HStack = celle du champ.
                                .frame(maxHeight: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(state.generatorInputText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                // --- Section B : 4 champs éditables ---
                // Emoji + Titre sur la MÊME ligne. EmojiPickerButton à
                // gauche (carré 36×36, identique à l'éditeur de Réglages
                // → Actions — pattern unifié), Titre prend tout le reste.
                // alignment: .top → les 2 labels alignés en haut ; les 2
                // champs (carré 36pt + TextField forcé à 36pt via
                // .frame(height: 36)) alignés top ET bottom, pas de
                // déséquilibre visuel.
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Emoji")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        // Composant réutilisable de IconPickerView.swift :
                        // clic ouvre la palette emoji système macOS (cf.
                        // ActionsView.swift:855 pour l'usage modèle).
                        //
                        // K.2-B lot 2b fix — `onPaletteOpen` suspend le
                        // monitor de clic extérieur du KeyablePanel le
                        // temps que l'utilisateur sélectionne un emoji
                        // dans la palette. Sans ça, le clic dans la
                        // palette ferme le popover → contexte d'édition
                        // perdu. Filet de sécurité 15s ; réinstallation
                        // anticipée via .onChange(editableEmoji) plus
                        // bas dès qu'un emoji est choisi.
                        EmojiPickerButton(icon: $state.editableEmoji,
                                          boxSize: 36,
                                          fontSize: 24,
                                          onPaletteOpen: {
                                              globalAppDelegate?
                                                  .suspendOutsideClickMonitor(for: 15)
                                          })
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Titre")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        TextField("", text: $state.editableTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.primary.opacity(0.06))
                            )
                            .focused($isEditableTitleFocused)
                    }
                }
                editableSingleLineField(label: "Description",
                                        text: $state.editableDescription)
                editablePromptField

                // --- Section C : sélecteur de catégorie ---
                editableCategoryPicker
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        // K.2-B lot 2b fix — réinstallation anticipée du monitor de clic
        // extérieur dès que l'emoji change. Deux scénarios :
        // 1. L'utilisateur vient de choisir un emoji dans la palette
        //    système (monitor suspendu par `onPaletteOpen` ci-dessus) →
        //    `resumeOutsideClickMonitorIfSuspended()` réinstalle
        //    immédiatement, le clic extérieur reprend sans attendre
        //    les 15s du filet de sécurité.
        // 2. Génération/regénération qui peuple `editableEmoji` par code
        //    (cf. `runGeneration` success branch dans PopoverState) →
        //    le monitor n'est pas suspendu, la méthode est no-op grâce
        //    au guard `outsideClickMonitorSuspended` côté AppDelegate.
        // Idempotence assumée — pas de test côté call-site.
        .onChange(of: state.editableEmoji) { _, _ in
            globalAppDelegate?.resumeOutsideClickMonitorIfSuspended()
        }
    }

    /// Champ éditable mono-ligne (utilisé pour Description). Label 12pt
    /// secondary + TextField primary sur fond `Color.primary.opacity(0.06)`
    /// radius 8 (cohérent avec le champ de recherche du popup, V3 du
    /// brief). Le champ Titre est inliné dans `generatorEditableContent`
    /// car il partage sa ligne avec EmojiPickerButton (hauteur forcée à
    /// 36pt pour alignement).
    private func editableSingleLineField(label: String,
                                         text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.06))
                )
        }
    }

    /// Champ Prompt — multi-ligne via TextEditor. Plafonné à 250pt
    /// (au-delà, scroll interne natif). Plafond augmenté de 200 → 250
    /// dans le fignolage 2b post-fusion Emoji+Titre (espace vertical
    /// libéré reversé au Prompt — champ de loin le plus long en usage).
    /// ↵ insère un saut de ligne — pas de risque de validation
    /// accidentelle, la validation passe par ⌘↵ sur la bottom bar.
    private var editablePromptField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prompt")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextEditor(text: $state.editablePrompt)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxHeight: 250)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.06))
                )
        }
    }

    /// Sélecteur de catégorie. Première option = « Sans catégorie » (nil,
    /// choix valide). Suit avec les 6 catégories réelles ; `.custom`
    /// (« Mes modèles ») est DEPRECATED depuis K.unify.2 et exclu.
    private var editableCategoryPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Catégorie")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Picker("", selection: $state.editableCategory) {
                Text("Sans catégorie").tag(PromptCategory?.none)
                ForEach(PromptCategory.allCases.filter { $0 != .custom }, id: \.self) { cat in
                    Text(cat.rawValue).tag(PromptCategory?.some(cat))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    /// Barre inférieure du popover éditable. Esc Annuler à gauche, ⌘↵
    /// Valider à droite (convention macOS : action principale à droite).
    /// Modèle visuel : `resultView` (mêmes `.buttonStyle(.plain)` +
    /// `KeyboardKey` + `Text`).
    ///
    /// ⌘↵ binding via `.keyboardShortcut(.return, modifiers: .command)` —
    /// ↵ seul n'est PAS un raccourci de validation, pour ne pas entrer en
    /// conflit avec la saisie multi-ligne du Prompt. `.disabled(!canValidate)`
    /// désactive aussi le raccourci.
    ///
    /// Esc côté clavier est intercepté par le NSEvent monitor — ce bouton
    /// reste actionnable à la souris pour découvrabilité.
    private var generatorEditableBottomBar: some View {
        HStack(spacing: 8) {
            Button {
                state.exitGeneratorMode()
            } label: {
                HStack(spacing: 6) {
                    KeyboardKey("esc")
                    Text("Annuler")
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                state.validateAndRun()
            } label: {
                HStack(spacing: 6) {
                    KeyboardKey("⌘↵")
                    Text("Valider")
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!state.canValidate)
        }
        .padding(12)
    }

    // MARK: - Result

    private func resultView(for action: Action) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // Phase 6.4 : emoji via ActionIconView dans le header résultat
                ActionIconView(icon: action.icon, boxSize: 20, fontSize: 14)
                Text(action.name).font(.system(size: 13, weight: .semibold))
                Spacer()
                if state.isProcessing {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(12)

            Divider()

            // Phase 1.4i : zone basse du résultat (texte + footer boutons).
            VStack(spacing: 0) {
                ScrollView {
                    // Phase 6.5 (2026-04-23) : rendu Markdown via MarkdownUI
                    // (gonzalezreal/swift-markdown-ui, MIT). L'action
                    // "Extrais la recette" produit du Markdown structuré
                    // (titres `#`/`##`, listes, gras, code…) — l'afficher
                    // en texte brut rendait les marques visibles. Le bouton
                    // Copier continue de coller le Markdown brut
                    // (cf. `state.resultText` préservé).
                    //
                    // Phase 6.14-fix (2026-04-26) : on revient au rendu
                    // Markdown live pendant le streaming (préférence UX).
                    // Le crash AppKit qui motivait la Phase 6.14 était en
                    // fait causé par les transitions de fenêtre (touche F)
                    // qui mutaient `resultText` pendant un layout en cours,
                    // pas par le re-parse Markdown lui-même. Le vrai fix
                    // est dans `PopoverState.suspendFlush()` appelé pendant
                    // les animations de resize (cf. `toggleResultExpanded`
                    // et `onChange(of: state.activeAction)` plus haut).
                    Markdown(state.resultText)
                        .markdownTextStyle(\.text) {
                            FontSize(13)
                        }
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                // Phase 1.4b : en format agrandi, le scrollview flex pour remplir
                // la hauteur disponible. En format compact, plafonné à 300.
                // Valeur finie (2000) plutôt que .infinity pour permettre à SwiftUI
                // d'interpoler la hauteur sous withAnimation (depuis/vers .infinity
                // produit un saut abrupt, surtout à la réduction).
                .frame(maxHeight: resultExpanded ? 2000 : 300)

                Divider()

                HStack(spacing: 8) {
                    // Phase 1.4 : boutons en .plain pour retirer le chrome bordered
                    // macOS — cohérence visuelle avec le footer nav de la liste et
                    // allègement de l'interface.
                    // Phase 1.4d : pas de picto SF Symbol, KeyboardKey avant le Text
                    // (même ordre que le footer nav de la liste : touche → libellé).
                    //
                    // Phase 6.15 (2026-04-26) : réarrangement et inversion.
                    // - Esc Fermer (anciennement « Retour ») et F Agrandir
                    //   à GAUCHE = actions contextuelles secondaires.
                    // - ⌘⏎ Coller et ⏎ Copier à DROITE = actions principales,
                    //   convention macOS (action par défaut à droite, comme
                    //   Save dialog).
                    // - Inversion ⌘⏎ ↔ ⏎ : ⏎ est désormais Copier (action par
                    //   défaut, non-destructive, fréquence d'usage la plus
                    //   élevée). ⌘⏎ devient Coller (action engagée qui
                    //   remplace le texte source — destructive).

                    // Esc Fermer — géré par le NSEvent monitor pour le clavier ;
                    // ce bouton reste actionnable à la souris pour découvrabilité.
                    Button {
                        state.endStream()
                        onClose()
                    } label: {
                        HStack(spacing: 6) {
                            KeyboardKey("esc")
                            Text("Fermer")
                        }
                    }
                    .buttonStyle(.plain)

                    // Phase 1.4b : indicateur F Agrandir / F Réduire. Clic souris
                    // bascule aussi pour cohérence (sinon seule la touche F marcherait).
                    Button { toggleResultExpanded() } label: {
                        HStack(spacing: 6) {
                            KeyboardKey("F")
                            Text(resultExpanded ? "Réduire" : "Agrandir")
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Coller : ⌘↵ — colle dans l'app précédente (ferme le popup).
                    // On attend que le toast "Collé" soit visible ~300 ms avant
                    // d'appeler performPasteInPreviousApp (qui orderOut le popup).
                    Button {
                        if state.tutorialMode {
                            // M.2.3 — paste tuto : injection JS dans le
                            // contenteditable (pas de Cmd+V système). Ferme le
                            // popover puis injecte (la fenêtre tuto reprend key).
                            let text = state.resultText
                            showConfirmation("Collé", duration: 0.3) {
                                globalAppDelegate?.hidePopover()
                                state.tutorialPasteHandler?(text)
                            }
                        } else {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(state.resultText, forType: .string)
                            showConfirmation("Collé", duration: 0.3) {
                                globalAppDelegate?.performPasteInPreviousApp()
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            KeyboardKey("⌘↵")
                            Text("Coller")
                        }
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)

                    // Copier : ↵ — copie le résultat dans le presse-papier
                    // (popup reste ouvert pour relire ou recopier).
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.resultText, forType: .string)
                        showConfirmation("Copié")
                        if state.tutorialMode { state.tutorialCopyHandler?() }  // M.2.5-fix — coche « copy »
                    } label: {
                        HStack(spacing: 6) {
                            KeyboardKey("↵")
                            Text("Copier")
                        }
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])
                }
                .padding(12)
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .result)
        // Handler clavier vue résultat : F (bascule taille).
        // Phase 6.15 (2026-04-26) : Esc retiré d'ici, désormais géré
        // globalement par le NSEvent monitor (cf. installSlotMonitorIfNeeded).
        // Centralisation = comportement uniforme et fiable sur tout le popup.
        .onKeyPress(phases: .down) { press in
            // F / f → bascule format. lowercased() pour accepter caps lock.
            if press.characters.lowercased() == "f" {
                toggleResultExpanded()
                return .handled
            }
            return .ignored
        }
        // Overlay du toast de confirmation (copie / collage). S'affiche brièvement
        // au centre de la vue résultat et se dissipe automatiquement.
        .overlay(alignment: .center) {
            if let msg = confirmation {
                ConfirmationToast(message: msg)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Keyboard Key

struct KeyboardKey: View {
    let text: String
    /// Variante posée sur un fond d'accent (row sélectionnée bleue
    /// #3F84F7) : blanc translucide pour contraste, au lieu du gris
    /// `.secondary` sur fond `controlBackgroundColor`.
    var onAccent: Bool = false

    init(_ text: String, onAccent: Bool = false) {
        self.text = text
        self.onAccent = onAccent
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(onAccent ? .white : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(onAccent ? Color.white.opacity(0.2) : Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(onAccent ? Color.white.opacity(0.4) : Color.gray.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - Confirmation Toast (✓ Copié / ✓ Collé)

struct ConfirmationToast: View {
    let message: String

    // Phase 1.4a : toutes les dimensions ×3 (+200 %).
    // Picto 14→42, texte 13→39, padding 14/10→42/30, spacing 8→24, shadow 8→24.
    // Si trop grand visuellement sur écran, diviser par 1.5 pour retomber à ×2.
    var body: some View {
        HStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 42))
            Text(message)
                .font(.system(size: 39, weight: .medium))
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 30)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.gray.opacity(0.2), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 24, y: 6)
    }
}

// MARK: - Trial Expired Modal (Phase 6.2 Étape 9)

/// Modal présenté en overlay sur le popup quand l'utilisateur tente de
/// lancer une action LLM mais qu'il a épuisé ses 12 essais gratuits
/// sans avoir activé de licence (`LicenseManager.canRunAction == false`).
/// Reste dans la fenêtre du popup (pas une sheet macOS séparée) — un
/// fond semi-transparent assombrit le contenu derrière, le contenu
/// du modal est centré.
private struct TrialExpiredOverlay: View {
    let onDismiss: () -> Void
    let onPurchase: () -> Void

    var body: some View {
        ZStack {
            // Fond semi-transparent — tap pour fermer (équivalent
            // « Plus tard »).
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            // Carte centrée
            VStack(spacing: 14) {
                Text("😱 12 - 12 = 0")
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("Pour continuer à utiliser loucedé en douce, c'est \(LicenseConfig.priceLabel) 💸")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(action: { onDismiss() }) {
                        HStack(spacing: 6) {
                            Text("Plus tard")
                            KeyboardKey("esc")
                        }
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                    Button(action: { onPurchase() }) {
                        HStack(spacing: 6) {
                            Text("Acheter")
                            KeyboardKey("↵")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 6)
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        }
    }
}
