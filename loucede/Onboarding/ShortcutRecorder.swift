//
//  ShortcutRecorder.swift
//  loucede
//
//  Phase R : helper réutilisable encapsulant l'enregistrement du raccourci
//  principal (monitor NSEvent local). Logique levée verbatim de l'ancien
//  ShortcutStep pour être consommée par l'écran accordéon « Configure
//  loucedé ». Écrit dans ActionsStore (source de vérité partagée) — ne
//  touche pas au manager. Le re-register du hotkey Carbon est assuré par
//  le publisher Combine de loucedeApp (debounce 500 ms).
//
//  Dette connue : GeneralSettingsView porte encore sa propre copie du
//  recorder → dédup notée backlog Tech (hors périmètre Phase R).
//

import SwiftUI
import AppKit
import Combine

final class ShortcutRecorder: ObservableObject {
    /// `true` pendant la capture (la boîte raccourci passe en mode « écoute »).
    @Published var isRecording = false
    /// Touches affichées en temps réel pendant la capture (modifiers puis touche).
    @Published var liveKeys: [String] = []

    private var eventMonitor: Any?
    private let store = ActionsStore.shared

    func start() {
        stop() // Clean up any existing monitor
        isRecording = true
        liveKeys = []

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }

            let modifiers = event.modifierFlags
            var currentModifiers: [String] = []
            if modifiers.contains(.control) { currentModifiers.append("^") }
            if modifiers.contains(.option)  { currentModifiers.append("\u{2325}") }
            if modifiers.contains(.shift)   { currentModifiers.append("\u{21E7}") }
            if modifiers.contains(.command) { currentModifiers.append("\u{2318}") }

            if event.type == .flagsChanged {
                // Met à jour l'affichage des modifiers en temps réel.
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    self.liveKeys = currentModifiers
                }
                return event
            }

            if event.type == .keyDown {
                // Doit contenir Command ou Option pour valider.
                let hasCommand = modifiers.contains(.command)
                let hasOption  = modifiers.contains(.option)
                guard hasCommand || hasOption else { return event }

                let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
                if !key.isEmpty && key.count == 1 {
                    var finalKeys = currentModifiers
                    finalKeys.append(key)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        self.liveKeys = finalKeys
                    }

                    // Persiste dans ActionsStore (source unique) puis enregistre ;
                    // le publisher Combine re-register le hotkey Carbon.
                    let capturedKey = key
                    let capturedModifiers = currentModifiers
                    let capturedKeyCode = event.keyCode
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.store.mainShortcutModifiers = capturedModifiers
                        self.store.mainShortcut = capturedKey
                        self.store.mainShortcutKeyCode = capturedKeyCode
                        self.store.saveMainShortcut()
                        withAnimation { self.isRecording = false }
                        self.stop()
                    }
                    return nil
                }
            }
            return event
        }
    }

    func stop() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
