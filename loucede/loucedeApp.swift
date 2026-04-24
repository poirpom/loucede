//
//  typoApp.swift
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

        // Phase 6.7 (2026-04-24) : initialise NSApp.appearance selon le thème
        // utilisateur (`appTheme` AppStorage) AVANT de créer la popup window.
        // Sans ça, `NSApp.appearance` reste nil tant que GeneralSettingsView
        // n'a pas été ouverte, et `@Environment(\.colorScheme)` de la popup
        // hérite du système au lieu du choix user. Résultat : popup affichée
        // en palette sombre alors que le user a choisi « Clair » (ou vice
        // versa). Cet appel se propage via l'observer KVO installé juste
        // après, pour suivre les changements live depuis les Réglages.
        applyAppTheme()
        observeAppThemeChanges()

        if !OnboardingManager.shared.hasCompletedOnboarding {
            showOnboarding()
        } else {
            setupApp()
        }
    }

    /// Lit la préférence `appTheme` (System/Light/Dark) depuis UserDefaults
    /// et applique l'NSAppearance correspondante à NSApp. Miroir de
    /// `GeneralSettingsView.applyTheme(_:)`, mais appelé dès le démarrage
    /// pour que la popup préchargée hérite du bon colorScheme.
    func applyAppTheme() {
        let themeString = UserDefaults.standard.string(forKey: "appTheme") ?? "System"
        switch themeString {
        case "Light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "Dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil // suit le système
        }
    }

    /// Observe les changements de `appTheme` via UserDefaults (KVO) pour
    /// maintenir `NSApp.appearance` synchronisée quand le user change de
    /// thème depuis les Réglages. Sans ça, seule la fenêtre Réglages
    /// voyait le changement immédiat (via `onAppear → applyTheme`), et la
    /// popup préchargée restait figée sur l'ancien thème.
    private func observeAppThemeChanges() {
        UserDefaults.standard.addObserver(
            self,
            forKeyPath: "appTheme",
            options: [.new],
            context: nil
        )
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "appTheme" {
            applyAppTheme()
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
    }

    func showOnboarding() {
        let onboardingView = OnboardingView(onComplete: { [weak self] in
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
            if let catIcon = NSImage(named: "MenuBarIcon") {
                catIcon.isTemplate = true
                button.image = catIcon
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

        // Centrer + afficher (fenêtre déjà créée au démarrage)
        positionPopoverCentered(width: Self.popoverDefaultWidth, height: Self.popoverDefaultHeight)
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

        positionPopoverCentered(width: Self.popoverDefaultWidth, height: Self.popoverDefaultHeight)
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
    static let popoverDefaultWidth: CGFloat = 400
    static let popoverDefaultHeight: CGFloat = 540
    /// Phase 1.4b : format « agrandi » (touche F sur la vue résultat).
    /// Largeur fixe ; hauteur = 70 % de la visibleFrame de l'écran (15 % de
    /// marge haut + 15 % bas). Recentré à chaque resize pour rester équilibré.
    static let popoverExpandedWidth: CGFloat = 500

    /// Bascule la fenêtre popup entre format normal et format agrandi avec
    /// animation fluide (NSAnimationContext). Recalcule le centrage pour
    /// compenser le changement de dimensions. Appelé depuis PopoverView
    /// sur appui de la touche F quand la vue résultat est affichée.
    func resizePopover(expanded: Bool) {
        guard let screen = NSScreen.main, let window = popoverWindow else { return }
        let screenRect = screen.visibleFrame
        let width: CGFloat = expanded ? Self.popoverExpandedWidth : Self.popoverDefaultWidth
        let height: CGFloat = expanded ? (screenRect.height * 0.7) : Self.popoverDefaultHeight
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
        Task { @MainActor in
            PopoverState.shared.streamTask?.cancel()
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
        let contentView = PopoverView(onClose: { [weak self] in
            self?.hidePopover()
        }, onOpenSettings: { [weak self] in
            self?.hidePopover()
            self?.openSettings()
        })

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
        // Reuse existing window if it's still open
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.isReleasedWhenClosed = false

        settingsWindow = window
        settingsWindow?.makeKeyAndOrderFront(nil)
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
