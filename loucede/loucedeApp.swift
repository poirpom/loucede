//
//  loucedeApp.swift
//  loucede
//

import SwiftUI
import AppKit
import Carbon.HIToolbox
import Combine

@main
struct loucedeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

// Puntero global para el callback de Carbon
var globalAppDelegate: AppDelegate?

// Custom NSPanel that can become key window and is draggable
class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        // Allow the panel to be moved by dragging its background
        self.isMovableByWindowBackground = true
    }
}

// Manager para compartir el texto capturado
class CapturedTextManager: ObservableObject {
    static let shared = CapturedTextManager()
    @Published var capturedText: String = ""
    @Published var hasSelection: Bool = false
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popoverWindow: NSWindow?
    var quickPromptWindow: NSWindow?
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    /// Fenêtre dédiée à la documentation (Point 4 pre-V1, 2026-05-08).
    /// Phase de transition : héberge actuellement un placeholder
    /// « En construction » (cf. `DocumentationView`), en attendant
    /// l'intégration native Notion API + Scaleway proxy + swift-markdown-ui
    /// développée en 4 incréments (A → D).
    /// Créée à la première ouverture, mise au front à chaque ⌘D suivant.
    /// Persistance position/taille via `setFrameAutosaveName` (mécanisme
    /// natif AppKit, pas de UserDefaults manuel).
    var docWindow: NSWindow?
    var eventMonitor: Any?
    var localEventMonitor: Any?
    var hotKeyRef: EventHotKeyRef?
    var pendingAction: Action?
    var cancellables = Set<AnyCancellable>()
    var previousActiveApp: NSRunningApplication?
    var menuBarMenuController = MenuBarMenuWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        globalAppDelegate = self

        // URL scheme handler (loucede:// — réservé aux automations, pas d'OAuth)
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // Phase 6.7b revertée (2026-04-29) : loucedé respecte le mode
        // système macOS (light et dark). NSApp.appearance n'est plus
        // forcée à darkAqua — SwiftUI hérite automatiquement du
        // colorScheme système via @Environment(\.colorScheme).

        if !OnboardingManager.shared.hasCompletedOnboarding {
            showOnboarding()
        } else {
            setupApp()
        }
    }

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }

        // Placeholder : automations futures via loucede://
        // Ex: loucede://run?action=... à implémenter en Phase 3+
        if url.scheme == "loucede" {
            print("URL reçue : \(url)")
        }
    }

    func setupApp() {
        setupMenuBar()
        setupGlobalHotkey()
        setupHotkeyEventHandler()
        setupLocalEscapeMonitor()

        // Préchargement : on crée la fenêtre du popup UNE SEULE FOIS
        // au démarrage. À chaque show on fera juste orderFront + reset
        // de l'état via PopoverState.shared.reset(). L'ancien code
        // détruisait/recréait la fenêtre à chaque hotkey → latence
        // perceptible et instanciation complète de l'arbre SwiftUI.
        createPopoverWindow()

        // Menu bar uniquement, app cachée du dock
        NSApp.setActivationPolicy(.accessory)

        // Ré-enregistre le raccourci principal quand il change
        ActionsStore.shared.$mainShortcut
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                if let ref = self?.hotKeyRef {
                    UnregisterEventHotKey(ref)
                }
                self?.setupGlobalHotkey()
            }
            .store(in: &cancellables)

        // Phase 6.2 Étape 8 (2026-04-27) : validation passive de la
        // licence au démarrage de l'app. Async non-bloquant — le
        // démarrage ne dépend pas du résultat. Le `silent: true` évite
        // le flicker `.active (depuis cache Keychain) → .validating →
        // .active` ; le pré-status restauré par `loadFromKeychain`
        // reste affiché tant que la vraie réponse Polar n'est pas
        // tombée.
        //
        // Le cache offline est géré dans `validate()` lui-même : si
        // l'erreur est réseau et qu'on a un cache < 7 jours avec
        // dernier status `granted`, on bascule en `.offline` (qui
        // counts as `hasLicense`).
        Task { @MainActor in
            await LicenseManager.shared.validate(silent: true)
        }

        // Phase 6.3 (2026-04-28) : vérification des mises à jour au
        // démarrage, en arrière-plan, non-bloquante. Le résultat met à
        // jour UpdateChecker.shared (ObservableObject) ; la popup et
        // l'onglet Mises à jour réagissent automatiquement via @Published.
        Task {
            UpdateChecker.shared.checkForUpdates()
        }
    }

    func showOnboarding() {
        let onboardingView = OnboardingView(onComplete: { [weak self] in
            // Persiste AVANT toute autre action : si setupApp() plante,
            // la complétion est quand même enregistrée et l'onboarding
            // ne se réaffichera pas au prochain lancement.
            OnboardingManager.shared.completeOnboarding()
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.setupApp()
        })

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()

        // Hide minimize and zoom buttons, keep only close button
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false

        onboardingWindow = window
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setupLocalEscapeMonitor() {
        // Monitor local para ESC dentro de la app
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // 53 = Escape
                self?.hidePopover()
                return nil // Consume el evento
            }
            return event
        }
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if let menuBarIcon = NSImage(named: "MenuBarIcon") {
                menuBarIcon.isTemplate = true
                button.image = menuBarIcon
            } else {
                button.image = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "loucedé")
            }
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        // Mostrar menú personalizado animado (para clic izquierdo y derecho)
        if menuBarMenuController.isMenuVisible {
            menuBarMenuController.closeMenu()
        } else {
            guard let statusItem = statusItem else { return }
            menuBarMenuController.showMenu(
                relativeTo: statusItem,
                onOpenLoucede: { [weak self] in
                    self?.showPopover()
                },
                onSettings: { [weak self] in
                    self?.openSettings()
                },
                onQuit: { [weak self] in
                    self?.quitApp()
                }
            )
        }
    }

    func setupGlobalHotkey() {
        let store = ActionsStore.shared
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x4C434544) // "LCED"
        hotKeyID.id = 1

        let modifiers = store.mainCarbonModifiers
        // On utilise le keycode physique stocké (fiable cross-layout) plutôt que
        // de reconvertir la lettre — le dictionnaire lettre→keycode est QWERTY-only
        // et produit le mauvais keycode sur un clavier AZERTY.
        let keyCode = UInt32(store.mainShortcutKeyCode)

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        print("Hotkey registered: \(store.mainShortcutModifiers.joined()) + \(store.mainShortcut) (keycode \(keyCode))")
    }

    func setupHotkeyEventHandler() {
        // Handler global pour le raccourci principal (ID 1).
        // Les prompts sont sélectionnés via les touches numériques dans la popup,
        // pas via des hotkeys globaux distincts.
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)

        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

            if hotKeyID.id == 1 {
                globalAppDelegate?.pendingAction = nil
                globalAppDelegate?.showPopover(requireSelection: true)
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    func keyCodeForCharacter(_ char: String) -> UInt32? {
        let keyMap: [String: UInt32] = [
            "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7,
            "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15,
            "Y": 16, "T": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "O": 31, "U": 32, "[": 33, "I": 34, "P": 35, "L": 37,
            "J": 38, "'": 39, "K": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
            "N": 45, "M": 46, ".": 47
        ]
        return keyMap[char]
    }

    func showPopoverWithAction(skipCapture: Bool = false) {
        // Si skipCapture = on réouvre depuis le popup principal, on ne
        // recapture pas le texte (préserve previousActiveApp original).
        if !skipCapture {
            previousActiveApp = NSWorkspace.shared.frontmostApplication
            captureSelectedText()
        }

        // Reset de l'état + pré-remplissage de l'action demandée.
        // Le runAction() sera exécuté dès que la fenêtre est affichée.
        let action = pendingAction
        Task { @MainActor in
            PopoverState.shared.reset()
            if let action {
                PopoverState.shared.runAction(action)
            }
        }

        // Centrer + afficher (fenêtre déjà créée au démarrage). Phase 6.9b :
        // hauteur calculée dynamiquement selon actions.count + selection.
        positionPopoverCentered(width: Self.popoverDefaultWidth, height: Self.calculatedPopoverHeight())
        popoverWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        installOutsideClickMonitor()
        pendingAction = nil
    }

    @objc func togglePopover() {
        if popoverWindow?.isVisible == true {
            hidePopover()
        } else {
            showPopover()
        }
    }

    @objc func showPopover() {
        showPopover(requireSelection: false)
    }

    func showPopover(requireSelection: Bool) {
        // Mémoriser l'app active avant d'afficher le popup
        previousActiveApp = NSWorkspace.shared.frontmostApplication

        // Capturer le texte sélectionné
        captureSelectedText()

        // Si le raccourci clavier exige une sélection et qu'il n'y en a pas,
        // on abandonne silencieusement — ouvrir un popup vide n'a pas de sens.
        if requireSelection && !CapturedTextManager.shared.hasSelection {
            return
        }

        // Reset de l'état (active action, result, selection, stream en cours)
        // — la fenêtre elle-même reste la même, préchargée au démarrage.
        Task { @MainActor in
            PopoverState.shared.reset()
        }

        // Phase 6.9b : hauteur calculée dynamiquement selon actions.count + selection.
        positionPopoverCentered(width: Self.popoverDefaultWidth, height: Self.calculatedPopoverHeight())
        popoverWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        installOutsideClickMonitor()
    }

    private func positionPopoverCentered(width: CGFloat, height: CGFloat) {
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let x = (screenRect.width - width) / 2 + screenRect.minX
        let y = (screenRect.height - height) / 2 + screenRect.minY
        popoverWindow?.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    /// Dimensions par défaut du popup (format « petit »), utilisées au premier
    /// affichage et au retour à la taille normale depuis l'agrandissement.
    /// Phase 6.7 (2026-04-24) : hauteur portée de 500 à 540 pour loger la ligne
    /// « Réglages » (fixe sous la liste) + les 10 slots d'actions + l'aperçu
    /// texte sans que le contenu ne dépasse de la fenêtre.
    /// Phase 6.9b (2026-04-25) : la hauteur n'est plus une constante figée.
    /// `calculatedPopoverHeight()` renvoie la hauteur idéale en fonction de
    /// `actions.count` (cap à 10 visibles) et de la présence d'un aperçu de
    /// texte capturé. `popoverDefaultHeight` reste comme borne haute (10
    /// actions + selection) pour la création initiale de la fenêtre.
    static let popoverDefaultWidth: CGFloat = 400
    static let popoverDefaultHeight: CGFloat = 540
    /// Phase 1.4b : format « agrandi » (touche F sur la vue résultat).
    /// Largeur fixe ; hauteur = 70 % de la visibleFrame de l'écran (15 % de
    /// marge haut + 15 % bas). Recentré à chaque resize pour rester équilibré.
    static let popoverExpandedWidth: CGFloat = 500

    // MARK: - Hauteur dynamique du popup (Phase 6.9b, 2026-04-25)

    /// Hauteur d'une ligne d'action (icône emoji 20pt + padding vertical 8+8).
    /// Doit rester synchro avec `actionRow` dans PopoverView.swift.
    static let popoverActionRowHeight: CGFloat = 36
    /// Spacing entre lignes dans le `VStack(spacing: 2)` de la liste.
    static let popoverActionRowSpacing: CGFloat = 2
    /// Hauteur du chrome qui entoure la liste (top bar logo + search bar
    /// + dividers + footer nav 2 lignes). Ne dépend pas du nombre
    /// d'actions. Mesure empirique validée à ±2pt sur Sequoia 15.x.
    /// Phase 6.18-fix-2 (2026-04-28) : 108 → 161 (+53). Le logo loucedé
    /// est désormais TOUJOURS visible dans la top bar (28pt + paddings
    /// 12+12 = 52pt + divider 1pt = 53pt), même sans selection. Quand
    /// selection, le preview cohabite avec le logo dans la même top bar
    /// — voir `popoverPreviewHeight` pour le delta.
    /// Point 2 pre-V1 (2026-05-08) : 165 → 158 (−7pt). Retrait du
    /// `settingsRow` fixe (−38pt) + footer passé de 1 à 2 lignes avec
    /// Divider central (+31pt : ligne 1 padding vertical 8pt = 34pt
    /// + Divider 1pt + ligne 2 padding vertical 6pt = 30pt vs ancien
    /// single row 33pt).
    /// Point 2 calibration bug (2026-05-08) : 158 → 162 (+4pt).
    /// Le radius inférieur du highlight bleu de la dernière action
    /// était mordu de ~2-5px par le bord inférieur du viewport. Cause
    /// non diagnostiquée précisément (probable padding.bottom interne
    /// non comptabilisé OU radius/shadow item débordant la rowHeight
    /// déclarée). Calage empirique : à monter à 164 si 162 insuffisant.
    static let popoverChromeHeight: CGFloat = 162
    /// Hauteur maximale du popup en mode liste (Point 2 pre-V1, 2026-05-08).
    /// La popup est désormais à hauteur DYNAMIQUE — elle s'adapte au nombre
    /// d'actions visibles jusqu'à ce plafond. Avec V1 (limite 15 actions),
    /// 744pt couvre le pire cas (15 actions + selection preview) :
    ///   chrome (162) + 15 actions × 36pt + 14 spacings × 2pt = 162 + 568 = 730pt
    ///   + 12pt selection preview = 742pt → arrondi à 744pt (2pt de marge)
    /// Calage : 740 → 744 (2026-05-08, suite au bump chrome 158 → 162 qui
    /// poussait contentHeight au-delà du cap dans le cas 15 actions + preview).
    /// Si la limite d'actions augmente en V1.x (>15), il faudra réintroduire
    /// un ScrollViewReader + auto-scroll vers l'item sélectionné lors de la
    /// nav clavier (cf. backlog).
    static let popoverMaxHeight: CGFloat = 744
    /// Delta de hauteur ADDITIONNEL quand un aperçu de texte est affiché
    /// (= différence entre top bar avec preview vs top bar logo seul).
    /// Phase 6.18-fix-2 : 67 → 12. Avant, popoverPreviewHeight était la
    /// hauteur ABSOLUE de la zone preview. Maintenant, c'est juste le
    /// delta entre 64pt (preview 3 lignes + paddings) et 52pt (logo
    /// seul), soit 12pt — la top bar pousse de 12pt en présence d'une
    /// selection.
    static let popoverPreviewHeight: CGFloat = 12
    /// Hauteur du message « Aucune action trouvée » quand la liste est vide.
    static let popoverEmptyListHeight: CGFloat = 61
    /// Hauteur du popup en mode « empty state » (pas de clé API configurée
    /// pour le provider courant). Top bar + texte contextuel + 1 item
    /// « Configure une clé API » + footer nav simplifié. Mesure à
    /// calibrer runtime — valeur initiale empirique (2026-05-07).
    static let popoverEmptyStateHeight: CGFloat = 210
    /// Phase 6.3 : hauteur de la ligne « Mise à jour disponible » dans le popup.
    /// Même structure et padding qu'une action row standard → identique à
    /// `popoverActionRowHeight`. Note : `settingsRow` qui partageait
    /// historiquement la même hauteur a été retiré au Point 2 pre-V1.
    static let popoverUpdateRowHeight: CGFloat = 36
    /// Hauteur du popup en mode résultat compact (header action + ScrollView
    /// 300pt + footer boutons). Mesurée empiriquement.
    static let popoverResultCompactHeight: CGFloat = 394

    /// Mode d'affichage du popup principal — détermine ses dimensions.
    /// Transitions résolues par `resizePopover(to:)` avec animation 250 ms.
    enum PopoverMode {
        /// Liste d'actions (entrée du popup). Hauteur dynamique via
        /// `calculatedPopoverHeight()` selon `actions.count` + selection.
        case list
        /// Vue résultat en format compact. Hauteur fixe (= chrome + 300pt scroll).
        case resultCompact
        /// Vue résultat en format agrandi (touche F). 70 % de la hauteur écran.
        case resultExpanded
    }

    /// Hauteur idéale du popup en fonction de l'état courant.
    /// Point 2 pre-V1 (2026-05-08) : popup à hauteur DYNAMIQUE — elle
    /// s'adapte au nombre d'actions visibles, capée par `popoverMaxHeight`.
    /// Le paramètre `actionCount` permet aux call-sites qui connaissent
    /// le nombre d'actions filtrées (ex. `PopoverView` après recherche)
    /// de passer cette valeur ; sinon on retombe sur `actions.count` pour
    /// l'ouverture initiale (search vide à ce moment-là, cf. `reset()`).
    static func calculatedPopoverHeight(actionCount: Int? = nil) -> CGFloat {
        // Empty state : popup minimaliste (texte contextuel + 1 item
        // « Configure une clé API » + footer nav simplifié). Pas de
        // search bar, pas de liste, pas de settingsRow. Hauteur fixe
        // + delta selection éventuel. Le paramètre actionCount est
        // ignoré dans cette branche.
        if !ActionsStore.shared.hasUsableProvider {
            let withSelection = CapturedTextManager.shared.hasSelection
            return popoverEmptyStateHeight + (withSelection ? popoverPreviewHeight : 0)
        }

        let count = actionCount ?? ActionsStore.shared.actions.count

        let listHeight: CGFloat
        if count == 0 {
            listHeight = popoverEmptyListHeight
        } else {
            listHeight = CGFloat(count) * popoverActionRowHeight
                       + CGFloat(count - 1) * popoverActionRowSpacing
        }

        let withSelection = CapturedTextManager.shared.hasSelection
        // Phase 6.3 : ajout conditionnel de la ligne « Mise à jour disponible »
        // (+ 1 Divider = ~1pt, absorbé dans la marge empirique de la constante).
        let withUpdate = UpdateChecker.shared.updateAvailable
        let contentHeight = popoverChromeHeight
             + listHeight
             + (withSelection ? popoverPreviewHeight : 0)
             + (withUpdate ? popoverUpdateRowHeight : 0)
        return min(popoverMaxHeight, contentHeight)
    }

    /// Bascule la fenêtre popup vers le mode demandé avec animation fluide
    /// (NSAnimationContext, 250 ms). Recalcule le centrage pour compenser
    /// le changement de dimensions.
    ///
    /// Phase 6.9b (2026-04-25) : remplace l'ancienne API `resizePopover(expanded:)`
    /// qui était ambiguë (le `false` signifiait tantôt « retour liste »
    /// tantôt « retour résultat compact »). Le mode explicite est désormais
    /// une `PopoverMode`, ce qui empêche le call site de prendre la mauvaise
    /// décision pour la hauteur cible.
    func resizePopover(to mode: PopoverMode, actionCount: Int? = nil) {
        guard let screen = NSScreen.main, let window = popoverWindow else { return }
        let screenRect = screen.visibleFrame
        let width: CGFloat
        let height: CGFloat
        switch mode {
        case .list:
            width = Self.popoverDefaultWidth
            // Point 2 pre-V1 (2026-05-08) : passe le compte filtré quand
            // disponible (cf. PopoverView .onChange(of: searchQuery)) pour
            // que la popup se redimensionne dynamiquement pendant la frappe.
            height = Self.calculatedPopoverHeight(actionCount: actionCount)
        case .resultCompact:
            width = Self.popoverDefaultWidth
            height = Self.popoverResultCompactHeight
        case .resultExpanded:
            width = Self.popoverExpandedWidth
            height = screenRect.height * 0.7
        }
        let x = (screenRect.width - width) / 2 + screenRect.minX
        let y = (screenRect.height - height) / 2 + screenRect.minY
        let newFrame = NSRect(x: x, y: y, width: width, height: height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }

    private func installOutsideClickMonitor() {
        // Un seul monitor à la fois — on retire l'ancien si présent.
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePopover()
        }
    }

    func captureSelectedText() {
        // Guardar el contenido actual del clipboard
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        let oldChangeCount = pasteboard.changeCount

        // Simular Cmd+C para copiar el texto seleccionado
        let source = CGEventSource(stateID: .combinedSessionState)

        // Key down C con Cmd
        let cDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // C
        cDown?.flags = .maskCommand

        // Key up C
        let cUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        cUp?.flags = .maskCommand

        // Ejecutar
        cDown?.post(tap: .cgSessionEventTap)
        cUp?.post(tap: .cgSessionEventTap)

        // Esperar un poco para que el sistema procese la copia
        usleep(100000) // 100ms

        // Detectar si realmente hubo una selección
        // changeCount cambia = Cmd+C copió algo = hay texto seleccionado
        // changeCount igual = Cmd+C no copió nada = no hay selección
        let newContents = pasteboard.string(forType: .string) ?? ""
        let clipboardChanged = pasteboard.changeCount != oldChangeCount
        let hasRealContent = !newContents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        CapturedTextManager.shared.hasSelection = clipboardChanged && hasRealContent

        // Guardar el texto capturado (usar clipboard existente como fallback para actions)
        CapturedTextManager.shared.capturedText = newContents
        if CapturedTextManager.shared.capturedText.isEmpty {
            CapturedTextManager.shared.capturedText = oldContents ?? ""
        }
    }

    func showQuickPrompt() {
        let quickPromptView = QuickPromptView(onClose: { [weak self] in
            self?.quickPromptWindow?.orderOut(nil)
        })

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: quickPromptView)
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false

        // Center on screen
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = (screenRect.width - 420) / 2 + screenRect.minX
            let y = (screenRect.height - 300) / 2 + screenRect.minY
            panel.setFrame(NSRect(x: x, y: y, width: 420, height: 300), display: true)
        }

        quickPromptWindow = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hidePopover() {
        // Annule tout stream LLM en cours (le résultat ne sera plus visible)
        // et libère le timer de flush des chunks (Phase 6.8g).
        Task { @MainActor in
            PopoverState.shared.endStream()
        }
        popoverWindow?.orderOut(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func hidePopoverAndRestoreFocus() {
        hidePopover()
        // Restaurar el foco a la app anterior
        if let previousApp = previousActiveApp {
            previousApp.activate()
        }
    }

    func performPasteInPreviousApp() {
        // Cerrar el popup
        popoverWindow?.orderOut(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        // Restaurar el foco a la app anterior y pegar
        if let previousApp = previousActiveApp {
            previousApp.activate()

            // Esperar a que la app anterior tenga el foco
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // Verificar permisos de accesibilidad
                guard AXIsProcessTrusted() else {
                    print("Accessibility permissions not granted")
                    return
                }

                // Simular Cmd+V para pegar
                let source = CGEventSource(stateID: .hidSystemState)

                if let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) {
                    vDown.flags = .maskCommand
                    vDown.post(tap: .cghidEventTap)
                }

                usleep(10000) // 10ms

                if let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
                    vUp.flags = .maskCommand
                    vUp.post(tap: .cghidEventTap)
                }
            }
        }
    }

    func createPopoverWindow() {
        // Créé une seule fois au démarrage. L'action initiale passe
        // désormais par PopoverState.shared (voir showPopoverWithAction).
        let contentView = PopoverView(
            onClose: { [weak self] in
                self?.hidePopover()
            },
            onOpenSettings: { [weak self] in
                self?.hidePopover()
                self?.openSettings()
            },
            onOpenUpdates: { [weak self] in
                // Phase 6.3 : ferme le popup et ouvre les Réglages directement
                // sur l'onglet Mises à jour (index 4).
                self?.hidePopover()
                self?.openSettings(tab: 4)
            }
        )

        let width: CGFloat = Self.popoverDefaultWidth
        let height: CGFloat = Self.popoverDefaultHeight

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView
        panel.hasShadow = true  // Native shadow since we mask corners at AppKit level
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false

        popoverWindow = panel
    }

    @objc func openSettings() {
        openSettings(tab: 0)
    }

    /// Ouvre les Réglages sur l'onglet `tab` (0 = Général par défaut).
    /// Phase 6.3 : si la fenêtre est déjà ouverte, envoie une notification
    /// pour naviguer vers l'onglet demandé sans recréer la fenêtre.
    func openSettings(tab: Int) {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // Deeplink vers l'onglet cible si ce n'est pas le défaut neutre
            if tab > 0 {
                NotificationCenter.default.post(
                    name: .loucedeSwitchSettingsTab,
                    object: tab
                )
            }
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: SettingsView(initialTab: tab))
        window.center()
        window.isReleasedWhenClosed = false

        settingsWindow = window
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Ouvre (ou ramène au front) la fenêtre de documentation.
    /// Point 4 pre-V1 (2026-05-08) — appelée par le shortcut ⌘D du popup.
    ///
    /// Phase de transition (cf. `DocumentationView`) : la fenêtre héberge
    /// actuellement un placeholder « En construction » statique, donc
    /// pas de logique de reload — `existing.makeKeyAndOrderFront` suffit.
    /// Quand l'intégration native Notion API + swift-markdown-ui sera
    /// branchée (incréments A → D), c'est `DocumentationView` qui
    /// récupérera son propre cycle de chargement / refresh.
    ///
    /// Comportement :
    /// - Si la fenêtre n'existe pas encore → la crée (900×700, centrée,
    ///   resizable, position/taille auto-persistées via
    ///   `setFrameAutosaveName`).
    /// - Si la fenêtre existe (visible ou cachée par ⌘W précédent) →
    ///   la met / ramène au front.
    @objc func openDocumentation() {
        if let existing = docWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Documentation loucedé"
        // Pivot UX (2026-05-09) : titlebar transparente sans titre
        // visible. Cohérent avec les fenêtres Settings et Onboarding
        // du projet (mêmes 2 lignes plus haut dans ce fichier). Évite
        // que le bouton de toggle sidebar `NavigationSplitView` (qui
        // « voyage » selon l'état de la sidebar) ne chevauche le titre
        // AppKit centré — bug observé en B.2 et qu'on n'a pas réussi
        // à fixer côté SwiftUI via `.toolbar(removing: .sidebarToggle)`
        // (ne fonctionne pas fiablement avec NSHostingView wrap).
        // `window.title = "..."` est conservé pour rester visible dans
        // le Dock, Cmd+Tab et le menu Window — c'est uniquement
        // l'affichage dans la titlebar qui est masqué.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 600, height: 400)
        window.contentView = NSHostingView(rootView: DocumentationView())
        window.center()
        // Persistance native AppKit : la frame est sauvegardée auto
        // dans UserDefaults sous la clé « NSWindow Frame loucede.documentation »
        // et restaurée au prochain lancement (override le `center()` ci-dessus
        // dès le 2e open).
        window.setFrameAutosaveName("loucede.documentation")
        window.isReleasedWhenClosed = false

        docWindow = window
        docWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func suspendHotkeys() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
    }

    func resumeHotkeys() {
        setupGlobalHotkey()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
