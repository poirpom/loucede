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
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var eventMonitor: Any?
    var localEventMonitor: Any?
    /// K.2-B lot 2b fix (2026-05-27) — état de la suspension du monitor
    /// de clic extérieur. Activé pendant la fenêtre où l'utilisateur
    /// interagit avec une fenêtre système secondaire (ex. palette emoji
    /// via `NSApp.orderFrontCharacterPalette`) — sinon le clic dans
    /// cette fenêtre serait perçu comme « clic hors popup → fermer ».
    /// Géré par `suspendOutsideClickMonitor(for:)` et
    /// `resumeOutsideClickMonitorIfSuspended()`.
    private var outsideClickMonitorSuspended: Bool = false
    /// Timer de réinstallation automatique du monitor (filet de
    /// sécurité). `DispatchWorkItem` plutôt que `Task` pour annulation
    /// synchrone fiable (ex. réinstallation anticipée déclenchée par
    /// `.onChange(editableEmoji)` côté PopoverView au choix d'un emoji).
    private var outsideClickMonitorResumeTask: DispatchWorkItem?
    var hotKeyRef: EventHotKeyRef?
    var pendingAction: Action?
    var cancellables = Set<AnyCancellable>()
    var previousActiveApp: NSRunningApplication?

    /// O.1.c (Snapshot OCR) — overlay de sélection de zone actif, s'il y en a
    /// un. Sert aussi de GARDE anti-double-overlay : `startOCRCapture()` est
    /// no-op tant que cette référence est non-nil (vigilance « ⌥& pendant
    /// overlay/fenêtre OCR actif → ignoré », cf. details/snapshot-ocr.md).
    var captureOverlayController: CaptureOverlayController?
    var menuBarMenuController = MenuBarMenuWindowController()

    /// M.2.3 — en mode tuto, le handler hotkey Carbon délègue ici (lecture
    /// de la sélection via JS + ouverture programmatique du popover) au lieu
    /// de la capture Cmd+C. Posé/retiré par `TutorialWindowController`.
    var tutorialShortcutHandler: (() -> Void)?

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
            switchToAccessory()
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

    /// Bascule l'app en app menu-bar (hors Dock). Isolé de setupApp pour
    /// pouvoir DIFFÉRER la sortie du Dock à la fin du tuto (Bug 2 : sinon
    /// .accessory + fenêtre onboarding fermée = instant sans fenêtre visible
    /// = « quit perçu »).
    func switchToAccessory() {
        NSApp.setActivationPolicy(.accessory)
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

        // Ré-enregistre le raccourci principal quand il change
        ActionsStore.shared.$mainShortcut
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                // setupGlobalHotkey est désormais idempotent (Unregister avant
                // Register, cf. L9-FN-002) → plus besoin d'unregister ici.
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

        // Phase H.2 (Sparkle-first) : vérification des mises à jour au
        // démarrage, silencieuse (pas d'UI sur erreur réseau). Premier accès
        // à LoucedeUpdater.shared → instancie aussi SPUStandardUpdaterController
        // (startingUpdater: true + scheduler natif via SUEnableAutomaticChecks).
        // La popup et l'onglet Mises à jour réagissent via @Published.
        Task {
            LoucedeUpdater.shared.checkForUpdatesInBackground()
        }
    }

    func showOnboarding() {
        // Finalisation commune : persiste AVANT toute autre action (si
        // setupApp() plante, la complétion est quand même enregistrée et
        // l'onboarding ne se réaffichera pas au prochain lancement).
        let finalize: () -> Void = { [weak self] in
            OnboardingManager.shared.completeOnboarding()
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.setupApp()
        }

        let onboardingView = OnboardingView(
            onComplete: { [weak self] in finalize(); self?.switchToAccessory() },
            // M.2.7 / Bug 2 : « Faire le tuto » ouvre et fronte la fenêtre tuto
            // AVANT de fermer l'onboarding et sans basculer en .accessory —
            // l'app reste .regular (Dock + fenêtre) pendant tout le tuto, et ne
            // sort du Dock qu'à sa fermeture (hook onClose → switchToAccessory).
            onStartTutorial: { [weak self] in
                TutorialWindowController.present(onClose: { self?.switchToAccessory() })
                finalize()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
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
                // O.1.c — si un overlay de capture est actif, Esc l'annule
                // (le monitor intercepte le keyDown avant la vue overlay).
                if let overlay = self?.captureOverlayController {
                    overlay.cancel()
                    return nil
                }
                self?.hidePopoverAndRestoreFocus()
                return nil // Consume el evento
            }
            return event
        }
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            #if DEBUG
            let iconName = "MenuBarIcon-Debug"
            #else
            let iconName = "MenuBarIcon"
            #endif
            if let menuBarIcon = NSImage(named: iconName) {
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

        // L9-FN-002 : Unregister systématique avant Register → idempotence.
        // setupGlobalHotkey est appelé au lancement, par resumeHotkeys() et par
        // le publisher Combine (changement de raccourci) ; sans ce nettoyage,
        // les appels successifs empilaient des hotkeys (leak + double-register).
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
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

    func showPopover(requireSelection: Bool) {
        // M.2.3 — branchement tuto : le hotkey Carbon fire normalement (et
        // consomme ⌥&), mais en mode tuto on délègue au flow tuto (sélection
        // lue via JS, pas de capture Cmd+C) plutôt que la voie standard.
        if PopoverState.shared.tutorialMode, let handler = tutorialShortcutHandler {
            handler()
            return
        }

        // Mémoriser l'app active avant d'afficher le popup
        previousActiveApp = NSWorkspace.shared.frontmostApplication

        // Capturer le texte sélectionné
        captureSelectedText()

        // O.1 (Snapshot OCR) — ⌥& SANS sélection : au lieu d'abandonner
        // silencieusement (ancien comportement : ouvrir un popup vide n'avait
        // pas de sens), on bascule sur le flow Snapshot OCR (capture d'écran →
        // OCR → cartouche). C'est le point d'accroche unique de la
        // généralisation de l'entrée (cf. details/snapshot-ocr.md).
        if requireSelection && !CapturedTextManager.shared.hasSelection {
            startOCRCapture()
            return
        }

        presentPopoverWindow()
    }

    /// O.1 (Snapshot OCR) — entrée du flow « ⌥& sans sélection ».
    ///
    /// O.1.e (Snapshot OCR) — flow de production NU : présente l'overlay de
    /// sélection de zone, puis CAPTURE la zone (ScreenCaptureKit) et l'OCR
    /// (Vision, 100 % local) → injecte le texte dans le cartouche → présente le
    /// popup (flow d'actions normal, comme si le texte avait été sélectionné).
    /// **Zéro fichier sur disque** (décision A).
    ///
    /// À ce stade (nu), les cas non-nominaux sont **abandonnés silencieusement** :
    /// - Esc / clic sans drag → annulation ;
    /// - capture impossible (souvent permission Screen Recording manquante) ;
    /// - zone sans texte reconnu.
    /// Les UX dédiées arrivent en habillage : gestion permission + toast (O.4),
    /// fenêtre « Capture de texte » avec états lecture / édition / aucun-texte (O.2).
    ///
    /// GARDE anti-double-overlay : no-op si un overlay est déjà actif.
    /// `previousActiveApp` est déjà mémorisé par `showPopover` AVANT la bascule
    /// → le paste ⌘↵ vers l'app source reste fonctionnel malgré le vol de focus.
    func startOCRCapture() {
        guard captureOverlayController == nil else { return }

        let overlay = CaptureOverlayController { [weak self] rect, screen in
            guard let self else { return }
            self.captureOverlayController = nil

            // Annulation (Esc / clic sans drag).
            guard let rect, let screen else { return }

            Task { @MainActor in
                let image: CGImage
                do {
                    image = try await ScreenCaptureService.captureImage(
                        globalRect: rect, screen: screen
                    )
                } catch {
                    // Capture impossible (permission manquante, etc.) → abandon.
                    // Gestion propre (toast + lien Réglages Système) en O.4.
                    return
                }

                let text = await OCRService.recognizeText(in: image)
                // Zone sans texte → abandon. Fenêtre « aucun texte détecté »
                // (état 3) en O.2.c.
                guard !text.isEmpty else { return }

                CapturedTextManager.shared.capturedText = text
                CapturedTextManager.shared.hasSelection = true
                self.presentPopoverWindow()
            }
        }
        captureOverlayController = overlay
        overlay.present()
    }

    /// Queue commune d'affichage du popover (reset état + positionnement +
    /// présentation + monitor). Factorisé (M.2.3) pour être réutilisé par le
    /// flow tuto (`presentPopoverForTutorial`), qui pose lui-même la sélection.
    /// O.1 (Snapshot OCR) : exposé (`internal`) pour être appelé aussi par le
    /// flow OCR (`startOCRCapture`), qui pose son texte dans `CapturedTextManager`
    /// avant présentation — même contrat que le flow tuto.
    func presentPopoverWindow() {
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

    /// M.2.3 — ouverture du popover en mode tuto. La sélection a déjà été
    /// posée dans `CapturedTextManager` par le handler tuto (lue via JS dans
    /// la WKWebView). Pas de capture Cmd+C, pas de dépendance à l'app active.
    func presentPopoverForTutorial() {
        presentPopoverWindow()
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

    // MARK: - Hauteur dynamique du popup (Phase 6.9b, 2026-04-25)

    /// Hauteur d'une ligne d'action (icône emoji 20pt + padding vertical 8+8).
    /// Doit rester synchro avec `actionRow` dans PopoverView.swift.
    static let popoverActionRowHeight: CGFloat = 36
    /// Spacing entre lignes dans le `VStack(spacing: 2)` de la liste.
    static let popoverActionRowSpacing: CGFloat = 2
    /// K.unify.3 (2026-05-21) : hauteur d'un en-tête de section dans la
    /// liste popup (`sectionHeaderRow` : Text 10pt + padding top 10
    /// + bottom 2). Plus court qu'une ligne d'action — doit être compté
    /// distinctement dans `calculatedPopoverHeight`. Doit rester synchro
    /// avec `sectionHeaderRow` (PopoverView.swift). Valeur empirique à
    /// calibrer runtime.
    static let popoverSectionHeaderHeight: CGFloat = 25
    /// K.unify.3 (2026-05-21) : hauteur « peek » de la vue par défaut
    /// (champ de recherche vide). Calculée pour montrer FAVORIS (en-tête
    /// + 5 favoris) + l'en-tête de la catégorie suivante + ½ ligne
    /// d'action — un cue visuel « il y a plus à explorer » (scroll). En
    /// mode champ vide la fenêtre prend `min(contenu réel, cette valeur)`.
    static let popoverDefaultPeekHeight: CGFloat =
        popoverSectionHeaderHeight                 // en-tête FAVORIS
        + 5 * popoverActionRowHeight               // 5 favoris
        + popoverSectionHeaderHeight               // en-tête catégorie suivante
        + 0.5 * popoverActionRowHeight             // ½ ligne (cue « scroll »)
        + 7 * popoverActionRowSpacing              // spacings inter-éléments
    /// Hauteur du chrome qui entoure la liste (top bar logo + search bar
    /// + dividers + footer nav 1 ligne). Ne dépend pas du nombre
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
    /// K.4-lot1 (2026-05-22, P1) : 162 → 131 (−31pt). Retrait de la
    /// ligne 2 du footer (⌘, Réglages / ⌘D Doc) + son Divider central
    /// (ligne 2 ≈ 30pt + Divider 1pt = 31pt). Valeur à recalibrer
    /// runtime si le bord inférieur mord à nouveau le highlight.
    static let popoverChromeHeight: CGFloat = 131
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

    // MARK: - Fenêtre de réponse — géométrie live-grow (Phase S — C3)

    /// Chrome FIXE de la fenêtre de réponse = header (≈44) + footer (≈44) +
    /// marge. Mesuré empiriquement (= ancien `popoverResultCompactHeight` 394
    /// − 300 de scroll). La barre d'actions (⌘S/⌘E, +32) s'y ajoute quand visible.
    static let resultChromeHeight: CGFloat = 94
    /// Hauteur minimale de la zone de contenu (plancher de la fenêtre avant le
    /// 1er token / réponse très courte). Abaissé à 90 (C3 calage runtime) pour
    /// une fenêtre snug sur réponse minuscule sans paraître vide.
    static let resultMinContentHeight: CGFloat = 90
    /// Pas minimal de croissance (≈1 interligne) — throttle des `setFrame`
    /// instantanés pendant le stream (anti-saccade / anti-spam).
    static let resultGrowThrottle: CGFloat = 24
    /// Plafond de hauteur = fraction de l'écran visible. Au-delà, la fenêtre
    /// se fige et le ScrollView interne prend le relais.
    static let resultPlafondRatio: CGFloat = 0.7

    /// Hauteur de scroll maximale (= plafond − chrome). Plancher à
    /// `resultMinContentHeight` (garde-fou petits écrans).
    static func resultMaxScrollHeight(screen: NSScreen? = NSScreen.main) -> CGFloat {
        let h = (screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let plafond = h * resultPlafondRatio
        let chrome = resultChromeHeight
            + (PopoverState.shared.showsResultActionsBar ? PolishTokens.resultActionsBarHeight : 0)
        return max(resultMinContentHeight, plafond - chrome)
    }

    /// Hauteur cible de la fenêtre de réponse = chrome + contenu mesuré
    /// (clampé entre minimal et maxScroll). Source unique consommée par
    /// l'entrée animée (`resizePopover .resultCompact`) ET la croissance
    /// instantanée (`growResultWindow`).
    static func resultTargetHeight(screen: NSScreen? = NSScreen.main) -> CGFloat {
        let chrome = resultChromeHeight
            + (PopoverState.shared.showsResultActionsBar ? PolishTokens.resultActionsBarHeight : 0)
        let content = min(max(PopoverState.shared.measuredResultContentHeight, resultMinContentHeight),
                          resultMaxScrollHeight(screen: screen))
        return chrome + content
    }

    /// Phase T (C2) — hauteur PLEINE de la fenêtre de réponse (= plafond, la
    /// hauteur max qu'une réponse longue atteint). Source unique consommée par
    /// la fiche d'édition du Générateur (`.generator(.resultEditable)`), qui
    /// s'ouvre directement à hauteur pleine (décision : un prompt généré est
    /// toujours long → offrir l'espace plutôt que scroller). Même `resultPlafondRatio`
    /// que la croissance de D → D et E partagent exactement la même hauteur max.
    static func resultPlafondHeight(screen: NSScreen? = NSScreen.main) -> CGFloat {
        let h = (screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        return h * resultPlafondRatio
    }

    /// Frame ancrée de la fenêtre de réponse pour une hauteur donnée : largeur
    /// fixe, **bord HAUT fixe** (croissance vers le bas, sans saut du contenu
    /// déjà rendu — précédent F.4). Top calé sur la ligne du haut d'une fenêtre
    /// plafond CENTRÉE → une fenêtre pleine est centrée à l'écran et rien ne
    /// déborde jamais ; une réponse courte s'affiche en zone haute (compromis
    /// « pas de saut » > « centrage »). La hauteur est passée EXPLICITEMENT
    /// (pas relue) pour éviter toute race avec une mesure transitoire.
    static func resultWindowFrame(height: CGFloat, screen: NSScreen) -> NSRect {
        let r = screen.visibleFrame
        let plafond = r.height * resultPlafondRatio
        let w = PolishTokens.resultWindowWidth
        return NSRect(x: r.midX - w / 2, y: r.midY + plafond / 2 - height,
                      width: w, height: height)
    }

    // K.2-B lot 2a (2026-05-26) — Mode Générateur, hauteurs par phase.
    /// Hauteur du popover générateur en mode compact (saisie / loading /
    /// erreur). Top bar + label + TextField + bouton/spinner/erreur.
    /// Dimensionnée pour accueillir un message d'erreur 2 lignes 13pt
    /// (cas `noApiKey`) sans animation — stabilité visuelle sur les 3
    /// phases (compact / loading / error). Léger espace vide en bas en
    /// saisie normale, accepté (prix de la stabilité).
    static let popoverGeneratorCompactHeight: CGFloat = 200
    // Phase T (C2) : la hauteur de `.resultEditable` n'est plus une constante
    // (l'ancien `popoverGeneratorEditableHeight = 680`). La fiche d'édition
    // s'ouvre à hauteur pleine, alignée sur le plafond de la fenêtre de réponse
    // — cf. `resultPlafondHeight(screen:)` consommé dans `resizePopover`.

    /// Phase du popover générateur, sert à dimensionner la fenêtre.
    /// Compact couvre `.compact`, `.loading`, `.error` de PopoverState ;
    /// `.resultEditable` couvre `.resultEditable` (K.2-B lot 2b).
    enum GeneratorPopupPhase {
        case compact
        case resultEditable
    }

    /// Mode d'affichage du popup principal — détermine ses dimensions.
    /// Transitions résolues par `resizePopover(to:)` avec animation 250 ms.
    enum PopoverMode {
        /// Liste d'actions (entrée du popup). Hauteur dynamique via
        /// `calculatedPopoverHeight()` selon `actions.count` + selection.
        case list
        /// Vue résultat (fenêtre unique). Hauteur = chrome + 300pt scroll.
        case resultCompact
        /// K.2-B lot 2a — mode Générateur d'actions AI. Largeur identique
        /// à `.list` (400pt), hauteur fonction de la phase courante.
        case generator(GeneratorPopupPhase)
    }

    /// Hauteur idéale du popup en fonction de l'état courant.
    /// Point 2 pre-V1 (2026-05-08) : popup à hauteur DYNAMIQUE.
    /// K.unify.3 (2026-05-21) : le paramètre `searchQuery` (recherche
    /// courante) sert à reconstruire la liste via `PopupItemBuilder` pour
    /// mesurer la hauteur réelle (en-têtes + lignes). Champ vide → hauteur
    /// « peek » (cue scroll, `popoverDefaultPeekHeight`) ; recherche →
    /// hauteur adaptative au contenu. Capée par `popoverMaxHeight`.
    static func calculatedPopoverHeight(searchQuery: String = "") -> CGFloat {
        // Empty state : popup minimaliste (texte contextuel + 1 item
        // « Configure une clé API » + footer nav simplifié). Pas de
        // search bar, pas de liste, pas de settingsRow. Hauteur fixe
        // + delta selection éventuel. Le paramètre searchQuery est
        // ignoré dans cette branche.
        if !ActionsStore.shared.hasUsableProvider {
            let withSelection = CapturedTextManager.shared.hasSelection
            return popoverEmptyStateHeight + (withSelection ? popoverPreviewHeight : 0)
        }

        // K.unify.3.5 : la liste mêle des en-têtes de section (hauteur
        // réduite) et des lignes d'action (popoverActionRowHeight). On
        // reconstruit les items via le builder unifié (source de vérité
        // partagée avec PopoverView) pour mesurer la hauteur réelle.
        let items = PopupItemBuilder.build(actions: ActionsStore.shared.actions,
                                           searchQuery: searchQuery)
        let isSearching = !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty

        let listHeight: CGFloat
        if items.isEmpty {
            // Champ vide ET aucune action visible → message « Aucune action ».
            listHeight = popoverEmptyListHeight
        } else {
            let contentHeight = listContentHeight(for: items)
            // Champ vide (vue par défaut) : hauteur « peek » fixe (cue
            // scroll), bornée par le contenu réel pour ne pas laisser de
            // vide quand il y a peu d'actions.
            // Recherche : hauteur adaptative au contenu réel (feedback saisie).
            listHeight = isSearching ? contentHeight
                                     : min(contentHeight, popoverDefaultPeekHeight)
        }

        let withSelection = CapturedTextManager.shared.hasSelection
        // Phase 6.3 : ajout conditionnel de la ligne « Mise à jour disponible »
        // (+ 1 Divider = ~1pt, absorbé dans la marge empirique de la constante).
        let withUpdate = LoucedeUpdater.shared.updateAvailable
        let contentHeight = popoverChromeHeight
             + listHeight
             + (withSelection ? popoverPreviewHeight : 0)
             + (withUpdate ? popoverUpdateRowHeight : 0)
        return min(popoverMaxHeight, contentHeight)
    }

    /// K.unify.3.5 — hauteur réelle du contenu de la liste popup :
    /// en-têtes de section (`popoverSectionHeaderHeight`) + lignes d'action
    /// (`popoverActionRowHeight`) + spacings du `VStack(spacing: 2)`.
    /// Q.1.b-bis : + PolishDivider entre catégories (avant chaque en-tête sauf
    /// le 1er) — comptés ici pour le fit exact en mode recherche.
    private static func listContentHeight(for items: [PopupItem]) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        var h: CGFloat = 0
        var dividerCount = 0
        for (i, item) in items.enumerated() {
            switch item {
            case .sectionHeader:
                h += popoverSectionHeaderHeight
                if i > 0 { dividerCount += 1 }   // mirror du rendu PopoverView
            case .action, .generator, .quickAccess:
                h += popoverActionRowHeight
            }
        }
        // Empreinte des dividers (0.5pt) + 1 enfant VStack chacun (→ +1 spacing).
        h += CGFloat(dividerCount) * PolishTokens.dividerHeight
        h += CGFloat(max(0, items.count + dividerCount - 1)) * popoverActionRowSpacing
        return h
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
    func resizePopover(to mode: PopoverMode, searchQuery: String = "",
                       duration: Double = PolishTokens.popoverResizeDuration,
                       animated: Bool = true) {
        guard let screen = NSScreen.main, let window = popoverWindow else { return }
        let screenRect = screen.visibleFrame
        let width: CGFloat
        let height: CGFloat
        switch mode {
        case .list:
            width = Self.popoverDefaultWidth
            // Point 2 pre-V1 (2026-05-08) / K.unify.3 : passe la recherche
            // courante (cf. PopoverView .onChange(of: searchQuery)) pour que
            // la popup se redimensionne dynamiquement pendant la frappe — le
            // builder reconstruit la liste (en-têtes + lignes) pour mesurer.
            height = Self.calculatedPopoverHeight(searchQuery: searchQuery)
        case .resultCompact:
            // Phase S (C2/C3) : largeur fixe lecture (618). Hauteur
            // CONTENT-AWARE (chrome + contenu mesuré clampé) → à l'entrée le
            // contenu est vide/minimal donc la fenêtre arrive minimale, puis
            // `growResultWindow` la fait grandir avec le stream (live-grow).
            // Même source (`resultTargetHeight`) que la croissance → cohérence.
            width = PolishTokens.resultWindowWidth
            height = Self.resultTargetHeight(screen: screen)
        case .generator(let phase):
            // K.2-B lot 2a — Mode Générateur. `.compact` (saisie / loading /
            // erreur) garde la largeur liste (scan). Phase T : `.resultEditable`
            // (fiche d'édition) s'aligne sur la fenêtre de réponse (618, lecture)
            // — même source que `.resultCompact`, pour la cohérence D↔E.
            switch phase {
            case .compact:
                width = Self.popoverDefaultWidth
                height = Self.popoverGeneratorCompactHeight
            case .resultEditable:
                width = PolishTokens.resultWindowWidth
                height = Self.resultPlafondHeight(screen: screen)
            }
        }
        let x = (screenRect.width - width) / 2 + screenRect.minX
        var y = (screenRect.height - height) / 2 + screenRect.minY
        // Phase S (C3) : la fenêtre de réponse est ancrée par le HAUT (bord
        // haut fixe, croissance vers le bas) — cohérent avec `growResultWindow`
        // pour qu'aucun saut de contenu n'apparaisse au 1er pas de croissance.
        // Phase T (C2) : la fiche d'édition du Générateur (`.resultEditable`)
        // partage cet ancrage haut → la transition D↔E (618 des deux côtés) ne
        // déplace pas la fenêtre, seul le bord bas descend. Les autres modes
        // (liste, générateur compact) restent centrés verticalement.
        let anchoredTop: Bool
        switch mode {
        case .resultCompact:               anchoredTop = true
        case .generator(.resultEditable):  anchoredTop = true
        default:                           anchoredTop = false
        }
        if anchoredTop {
            let plafond = screenRect.height * Self.resultPlafondRatio
            y = screenRect.midY + plafond / 2 - height
        }
        let newFrame = NSRect(x: x, y: y, width: width, height: height)
        // Q.2.g (A.1) : ne pas (ré)animer un resize qui ne change pas la fenêtre.
        // compact / loading / error mappent tous vers la MÊME taille (.compact) :
        // animer la KeyablePanel vers son frame courant relançait une
        // NSAnimationContext pendant que le TimelineView du spinner (Q.3)
        // redessinait le hosting view → boucle « Update Constraints in Window
        // pass » → NSGenericException (crash 6.14 réactivé en contexte veille +
        // réseau mort). Skip du no-op = suppression du chevauchement d'animations.
        let cur = window.frame
        let e: CGFloat = 0.5   // tolérance sub-pixel
        if abs(cur.minX - newFrame.minX) < e, abs(cur.minY - newFrame.minY) < e,
           abs(cur.width - newFrame.width) < e, abs(cur.height - newFrame.height) < e {
            return
        }
        // Phase T (C3) : transition instantanée (setFrame sans NSAnimationContext)
        // pour le round-trip d'édition D↔E (⌘E / Esc) — principe Phase S « real-time
        // or not at all », même mécanique que `growResultWindow`. Aucune animation
        // concurrente d'une mutation de contenu → hors terrain crash 6.14/Q.2.g.
        guard animated else {
            window.setFrame(newFrame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }

    /// Phase S (C3) — croissance LIVE de la fenêtre de réponse pendant le
    /// stream. `setFrame(animate: false)` INSTANTANÉ → AUCUNE `NSAnimationContext`
    /// concurrente de la mutation de `resultText` (la cause racine du crash
    /// 6.14/Q.2.g est supprimée, pas mitigée). Ancrage par le haut (frame
    /// partagée avec l'entrée animée). Garde no-op sub-pixel (Q.2.g). Le call
    /// site (PopoverView) garantit : mode résultat, hors suspension de flush
    /// (= hors animation), et throttle ≥ 1 interligne.
    func growResultWindow(toHeight target: CGFloat) {
        guard let screen = NSScreen.main, let window = popoverWindow else { return }
        let newFrame = Self.resultWindowFrame(height: target, screen: screen)
        let cur = window.frame
        let e: CGFloat = 0.5
        if abs(cur.minX - newFrame.minX) < e, abs(cur.minY - newFrame.minY) < e,
           abs(cur.width - newFrame.width) < e, abs(cur.height - newFrame.height) < e {
            return
        }
        window.setFrame(newFrame, display: true)
    }

    private func installOutsideClickMonitor() {
        // Un seul monitor à la fois — on retire l'ancien si présent.
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePopoverAndRestoreFocus()
        }
    }

    // MARK: - K.2-B lot 2b fix — suspension temporaire du monitor

    /// Lecture seule de l'état de suspension. Utile pour debug / variantes
    /// (le call-site PopoverView n'en a pas besoin grâce à l'idempotence
    /// de `resumeOutsideClickMonitorIfSuspended()`).
    var isOutsideClickMonitorSuspended: Bool {
        outsideClickMonitorSuspended
    }

    /// Suspend le monitor de clic extérieur pendant `seconds` secondes.
    /// Appelé par le call-site du `EmojiPickerButton` dans le popover
    /// éditable du Générateur (PopoverView.swift) juste après
    /// `NSApp.orderFrontCharacterPalette(nil)` — sans suspension, le clic
    /// dans la palette emoji serait interprété par le monitor global
    /// comme « clic hors popup → fermer », faisant disparaître tout le
    /// contexte d'édition.
    ///
    /// Idempotence au double-tap : un nouvel appel reset le timer
    /// (annule l'ancien, programme un nouveau). Pas d'addition.
    func suspendOutsideClickMonitor(for seconds: TimeInterval) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        outsideClickMonitorResumeTask?.cancel()
        outsideClickMonitorSuspended = true

        let task = DispatchWorkItem { [weak self] in
            self?.resumeOutsideClickMonitorIfSuspended()
        }
        outsideClickMonitorResumeTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
    }

    /// Réinstalle le monitor de clic extérieur SI une suspension est
    /// active. No-op sinon — idempotence assumée (nom explicite).
    /// Appelé par 2 chemins :
    /// 1. Le timer programmé par `suspendOutsideClickMonitor(for:)` (filet
    ///    de sécurité après 15s — cas « palette ouverte mais rien choisi »).
    /// 2. Le `.onChange(state.editableEmoji)` côté PopoverView quand
    ///    l'utilisateur choisit un emoji (réinstallation anticipée → le
    ///    clic extérieur reprend immédiatement, pas d'attente).
    func resumeOutsideClickMonitorIfSuspended() {
        guard outsideClickMonitorSuspended else { return }
        outsideClickMonitorResumeTask?.cancel()
        outsideClickMonitorResumeTask = nil
        outsideClickMonitorSuspended = false
        installOutsideClickMonitor()
    }

    /// Lecture directe (synchrone) de la sélection courante via l'API
    /// Accessibility : élément focus du système → `kAXSelectedTextAttribute`.
    /// L9-FN-001 — voie privilégiée car elle n'implique PAS le presse-papiers
    /// (donc aucun clobber, aucun `usleep`) et reflète l'état réel même sur
    /// les apps lentes. Renvoie `nil` si l'AX est indisponible (permission
    /// non accordée, app sans support AX, type inattendu) → le caller
    /// retombe alors sur le ⌘C synthétique.
    private func readSelectionViaAX() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide,
                                            kAXFocusedUIElementAttribute as CFString,
                                            &focusedRef) == .success,
              let focused = focusedRef,
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        // swiftlint:disable:next force_cast
        let element = focused as! AXUIElement

        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,
                                            kAXSelectedTextAttribute as CFString,
                                            &selectedRef) == .success,
              let selected = selectedRef as? String
        else { return nil }
        return selected
    }

    func captureSelectedText() {
        // Snapshot du presse-papiers AVANT toute manipulation, pour pouvoir le
        // restaurer si on doit passer par le ⌘C synthétique (fallback).
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        let oldChangeCount = pasteboard.changeCount

        // L9-FN-001 — voie 1 (privilégiée) : lecture Accessibility. Si on
        // obtient une sélection réelle (non vide après trim), on a terminé sans
        // jamais toucher le presse-papiers → contenu utilisateur (y compris
        // non-string : image, fichiers) intégralement préservé.
        if let axText = readSelectionViaAX(),
           !axText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            CapturedTextManager.shared.hasSelection = true
            CapturedTextManager.shared.capturedText = axText
            return
        }

        // L9-FN-001 — voie 2 (fallback) : ⌘C synthétique pour les apps où l'AX
        // n'expose pas la sélection (ou la renvoie vide). On restaure ENSUITE
        // `oldContents` dans tous les cas via `defer` : c'est la seule branche
        // qui salit le presse-papiers, donc la seule à devoir le restaurer.
        defer {
            pasteboard.clearContents()
            if let oldContents { pasteboard.setString(oldContents, forType: .string) }
        }

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

    // K.0 : `showQuickPrompt()` + `QuickPromptView` supprimés — feature
    // morte héritée de TextAd (jamais appelée au runtime : aucun hotkey,
    // menu ou bouton ne l'ouvrait).

    func hidePopover() {
        // Annule tout stream LLM en cours et nettoie le contenu transitoire
        // (mode résultat + générateur) pour qu'il ne flashe pas à la
        // réouverture. Dispatché en Task @MainActor (async) : tombe donc
        // APRÈS l'orderOut synchrone ci-dessous → fenêtre déjà masquée, pas
        // de flash-liste avant disparition.
        Task { @MainActor in
            PopoverState.shared.clearTransientContent()
        }
        popoverWindow?.orderOut(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        // K.2-B lot 2b fix — annule le timer de réinstallation si une
        // suspension de monitor était en cours au moment de la fermeture
        // (cas Esc/Valider avec palette emoji encore ouverte). Sans ça,
        // le timer tenterait de réinstaller un monitor sur une fenêtre
        // déjà ordered out.
        outsideClickMonitorResumeTask?.cancel()
        outsideClickMonitorResumeTask = nil
        outsideClickMonitorSuspended = false

        // M.2.5-fix-2 — coche « close » côté tuto (Esc → fermeture popover ;
        // no-op gracieux sur les écrans sans data-tick="close").
        if PopoverState.shared.tutorialMode { PopoverState.shared.tutorialClosedHandler?() }
    }

    func hidePopoverAndRestoreFocus() {
        hidePopover()
        // Restaure le focus de l'app source à la fermeture (dismissal).
        // Gardes : app source encore vivante, et jamais loucedé lui-même
        // (sinon on perpétue le frontmost erroné — cf. bug réouverture popup).
        if let previousApp = previousActiveApp,
           !previousApp.isTerminated,
           previousApp != NSRunningApplication.current {
            previousApp.activate()
        }
    }

    func performPasteInPreviousApp() {
        // Cerrar el popup
        popoverWindow?.orderOut(nil)
        // Même nettoyage qu'à la fermeture normale : ce chemin (⌘↵ Coller)
        // ne passe pas par hidePopover(), donc sans ça l'état résultat
        // resterait en mémoire et flasherait à la réouverture suivante.
        Task { @MainActor in
            PopoverState.shared.clearTransientContent()
        }
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
                self?.hidePopoverAndRestoreFocus()
            },
            onOpenSettings: { [weak self] in
                self?.hidePopover()
                self?.openSettings()
            },
            onOpenUpdates: { [weak self] in
                // Phase 6.3 : ferme le popup et ouvre les Réglages directement
                // sur l'onglet Mises à jour. K.unify.3 : index 4 → 3 (onglet
                // Modèles retiré, renumérotation des onglets suivants).
                self?.hidePopover()
                self?.openSettings(tab: 3)
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
        // K.4-lot1 (P3) : radius 12 → 16. Q.1.d : source unique via
        // `PolishTokens.cornerRadius` — synchro garantie avec le clip du body
        // SwiftUI (PopoverView, `.polishVibrancy()`) pour aligner coins fenêtre
        // et contenu.
        hostingView.layer?.cornerRadius = PolishTokens.cornerRadius
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

        // F.4 : taille initiale = taille cible de l'onglet demandé
        // (⌘, → Général 800×540, ⌘D → Doc 860×700) — création directe à
        // la bonne taille, sans animation parasite.
        let initialSize = SettingsView.size(forTab: tab)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        let hosting = NSHostingView(rootView: SettingsView(initialTab: tab))
        // F.4 : pilotage UNIQUE de la frame fenêtre par
        // resizeSettingsWindow — la hosting view ne redimensionne pas la
        // fenêtre d'elle-même (sinon double animation quand le .frame
        // SwiftUI change en même temps que l'animator AppKit).
        hosting.sizingOptions = []
        window.contentView = hosting
        window.center()
        window.isReleasedWhenClosed = false

        settingsWindow = window
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Redimensionne la fenêtre Réglages vers la taille cible de
    /// l'onglet actif (F.4, resize dynamique style Things 3). Ancrage :
    /// bord HAUT fixe + centre horizontal préservé — la fenêtre grandit
    /// vers le bas et symétriquement en largeur. Appelée par le
    /// `.onChange(of: selectedTab)` de SettingsView (couvre clics ET
    /// deeplinks ⌘D / notification).
    ///
    /// `contentSize` == frame size ici : styleMask `.fullSizeContentView`
    /// + titlebar transparente, la hosting view couvre toute la fenêtre.
    func resizeSettingsWindow(to contentSize: CGSize, duration: Double = 0.25) {
        guard let window = settingsWindow else { return }
        let cur = window.frame
        let newFrame = NSRect(
            x: cur.midX - contentSize.width / 2,
            y: cur.maxY - contentSize.height,
            width: contentSize.width,
            height: contentSize.height
        )
        // Discipline Q.2.g : ne pas (ré)animer un resize no-op (re-clic
        // sur l'onglet courant, deeplink vers l'onglet déjà affiché,
        // transitions 800×540 → 800×540) — évite les NSAnimationContext
        // concurrentes sur la même fenêtre.
        let e: CGFloat = 0.5
        if abs(cur.minX - newFrame.minX) < e, abs(cur.minY - newFrame.minY) < e,
           abs(cur.width - newFrame.width) < e, abs(cur.height - newFrame.height) < e {
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }

    // F.3 (2026-06-12) : `openDocumentation()` et la fenêtre doc dédiée
    // (`docWindow`, ex-Point 4 pre-V1) ont été supprimées — la doc vit
    // dans l'onglet « Doc » des Réglages (index 5), ⌘D passe par
    // `openSettings(tab: 5)`. Le fetch liste est porté par le `.task`
    // de `DocumentationView` (le fix B.3 « trigger AppKit » n'avait plus
    // d'objet : la vue est recréée à chaque entrée dans l'onglet).
    // La clé d'autosave « NSWindow Frame loucede.documentation » reste
    // orpheline en UserDefaults (inoffensif — backlog clés orphelines).

    func suspendHotkeys() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            // L9-FN-002 : nil le ref → un 2ᵉ suspend devient un no-op (pas de
            // double-unregister sur ref obsolète) et resume/register repart propre.
            hotKeyRef = nil
        }
    }

    func resumeHotkeys() {
        setupGlobalHotkey()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
