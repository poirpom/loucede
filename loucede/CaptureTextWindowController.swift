//
//  CaptureTextWindowController.swift
//  loucede
//
//  O.2.a (Snapshot OCR) — fenêtre « Capture de texte », intercalée entre la
//  capture/OCR et l'injection dans le cartouche du popup. WindowController
//  dédié (décision B, cf. details/snapshot-ocr.md) — PAS un mode du popup.
//
//  État NOMINAL uniquement (état 2 du proto) : on suppose un texte OCR non
//  vide. L'utilisateur vérifie/corrige puis ⌘↵ valide (→ injection cartouche
//  + popup) ; Esc annule tout le flow. Les états 1 (lecture/spinner) et 3
//  (aucun texte) arrivent en O.2.b / O.2.c.
//
//  Surface calquée sur la grammaire du générateur (header badge + titre + logo
//  é, corps éditable, footer capsules neutres) via les composants/modifiers
//  partagés (KeyboardKey, PolishTokens, KeyablePanel) — sans toucher PopoverView.
//

import AppKit
import SwiftUI

final class CaptureTextWindowController {
    /// Instance active — rétention le temps de vie de la fenêtre + sert de
    /// GARDE anti-re-trigger : `startOCRCapture()` est no-op tant qu'elle
    /// existe (vigilance ⌥&-pendant-fenêtre, cf. details/snapshot-ocr.md).
    static private(set) var current: CaptureTextWindowController?
    static var isPresented: Bool { current != nil }

    private var window: NSWindow?
    private var didClose = false
    private let onValidate: (String) -> Void
    private let onCancel: () -> Void

    private init(onValidate: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onValidate = onValidate
        self.onCancel = onCancel
    }

    /// Ouvre la fenêtre pré-remplie du texte OCR. Si déjà ouverte → ramenée au
    /// premier plan (dédupe, pattern Tutorial/Purchase).
    static func present(ocrText: String,
                        onValidate: @escaping (String) -> Void,
                        onCancel: @escaping () -> Void) {
        if let existing = current {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = CaptureTextWindowController(onValidate: onValidate, onCancel: onCancel)
        controller.show(ocrText: ocrText)
        current = controller
    }

    /// Annulation externe (Esc capté par le monitor local de l'AppDelegate,
    /// qui intercepte le keyDown avant la fenêtre — même schéma que l'overlay).
    func cancel() {
        finish { $0.onCancel() }
    }

    private func show(ocrText: String) {
        let width: CGFloat = 600, height: CGFloat = 400
        // Réutilise KeyablePanel (canBecomeKey/Main) → focus TextEditor garanti,
        // une seule façon de faire les fenêtres-surfaces loucedé. Montage calqué
        // sur createPopoverWindow.
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false

        let root = CaptureTextView(
            ocrText: ocrText,
            onValidate: { [weak self] text in self?.finish { $0.onValidate(text) } },
            onCancel: { [weak self] in self?.finish { $0.onCancel() } }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = PolishTokens.cornerRadius
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = panel
    }

    /// Sortie UNIQUE idempotente : ferme la fenêtre puis exécute `action`
    /// (validate/cancel). Garde `didClose` → un seul teardown, un seul callback
    /// quel que soit le chemin (⌘↵, clic Annuler, Esc via monitor).
    private func finish(_ action: (CaptureTextWindowController) -> Void) {
        guard !didClose else { return }
        didClose = true
        window?.orderOut(nil)
        window = nil
        CaptureTextWindowController.current = nil
        action(self)
    }
}

/// Vue SwiftUI de la fenêtre — grammaire générateur reprise (header / corps
/// éditable / footer capsules), via les composants partagés.
private struct CaptureTextView: View {
    let ocrText: String
    let onValidate: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(ocrText: String,
         onValidate: @escaping (String) -> Void,
         onCancel: @escaping () -> Void) {
        self.ocrText = ocrText
        self.onValidate = onValidate
        self.onCancel = onCancel
        _text = State(initialValue: ocrText)
    }

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            bodyEditor
            footer
        }
        .frame(width: 600, height: 400)
        .polishVibrancy()
    }

    // Header : badge OCR + titre + logo é (calqué generatorTopBar).
    private var header: some View {
        HStack(spacing: 8) {
            Text("OCR")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(PolishTokens.cursorColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(PolishTokens.cursorColor.opacity(0.15)))
            Text("Capture de texte")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(12)
        .polishAccentBackground()
    }

    // Corps : hint + TextEditor multiligne (calqué editablePromptField).
    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vérifie et corrige si besoin, puis valide")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(size: PolishTokens.resultBodyFontSize))
                .lineSpacing(PolishTokens.resultBodyFontSize * PolishTokens.resultLineSpacingEm)
                .foregroundStyle(.primary)
                .tint(PolishTokens.cursorColor)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxHeight: .infinity)
                .polishFieldFill()
                .focused($focused)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity)
        // Focus auto à l'ouverture (async : la fenêtre doit être key d'abord).
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    // Footer : esc Annuler (clic ; Esc clavier via monitor AppDelegate) /
    // ⌘↵ Valider (calqué generatorEditableBottomBar). ⌘↵ grisé si vide.
    private var footer: some View {
        HStack(spacing: 8) {
            Button { onCancel() } label: {
                HStack(spacing: 6) {
                    KeyboardKey("esc")
                    Text("Annuler").font(.system(size: 13))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button { onValidate(text) } label: {
                HStack(spacing: 6) {
                    KeyboardKey("⌘↵")
                    Text("Valider").font(.system(size: 13))
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(isEmpty)
        }
        .padding(12)
        .polishAccentBackground()
    }
}
