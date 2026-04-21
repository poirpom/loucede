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
        guard let keyCode = keyCodeForCharacter(store.mainShortcut.uppercased()) else { return }

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        print("Hotkey registered: \(store.mainShortcutModifiers.joined()) + \(store.mainShortcut)")
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
                globalAppDelegate?.showPopover()
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
        // Cerrar cualquier popup existente primero (excepto si skipCapture, ya que estamos reabriendo)
        if !skipCapture {
            hidePopover()
        }

        // Guardar la app activa antes de mostrar el popup
        // Skip if reopening from main popup (preserves original previousActiveApp)
        if !skipCapture {
            previousActiveApp = NSWorkspace.shared.frontmostApplication
            // Capturar texto seleccionado antes de mostrar el popup
            captureSelectedText()
        }

        // Recrear la ventana con la acción pendiente
        popoverWindow = nil
        createPopoverWindow(withAction: pendingAction)

        // Posicionar cerca del cursor o centro de pantalla - ventana más grande para acciones
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let windowWidth: CGFloat = 560
            let windowHeight: CGFloat = 600
            let x = (screenRect.width - windowWidth) / 2 + screenRect.minX
            let y = (screenRect.height - windowHeight) / 2 + screenRect.minY

            popoverWindow?.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
        }

        popoverWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Cerrar al hacer click fuera
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePopover()
        }

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
        // Cerrar cualquier popup existente primero
        hidePopover()

        // Guardar la app activa antes de mostrar el popup
        previousActiveApp = NSWorkspace.shared.frontmostApplication

        // Capturar texto seleccionado antes de mostrar el popup
        captureSelectedText()

        // Recrear la ventana para que tome el nuevo texto
        popoverWindow = nil
        createPopoverWindow()

        // Posicionar cerca del cursor o centro de pantalla
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let windowWidth: CGFloat = 320
            let windowHeight: CGFloat = 500
            let x = (screenRect.width - windowWidth) / 2 + screenRect.minX
            let y = (screenRect.height - windowHeight) / 2 + screenRect.minY

            popoverWindow?.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
        }

        popoverWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Cerrar al hacer click fuera
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
        popoverWindow?.orderOut(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func hidePopoverAndRestoreFocus() {
        popoverWindow?.orderOut(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

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

    func createPopoverWindow(withAction action: Action? = nil) {
        let contentView = PopoverView(onClose: { [weak self] in
            self?.hidePopover()
        }, onOpenSettings: { [weak self] in
            self?.hidePopover()
            self?.openSettings()
        }, initialAction: action)

        // Tamaño más grande para acciones directas
        let width: CGFloat = action != nil ? 560 : 320
        let height: CGFloat = action != nil ? 600 : 500

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
