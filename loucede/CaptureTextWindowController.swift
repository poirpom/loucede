//
//  CaptureTextWindowController.swift
//  loucede
//
//  O.2 (Snapshot OCR) — fenêtre « Capture de texte », intercalée entre la
//  capture/OCR et l'injection dans le cartouche du popup. WindowController
//  dédié (décision B, cf. details/snapshot-ocr.md) — PAS un mode du popup.
//
//  État NOMINAL (état 2 du proto) : la fenêtre s'ouvre pré-remplie du texte OCR
//  (non vide, garanti par l'appelant). L'utilisateur vérifie/corrige puis ⌘↵
//  valide (→ injection cartouche + popup) ; Esc annule le flow.
//  (L'état lecture/spinner O.2.b a été retiré — jugé sans valeur sur un OCR
//  quasi instantané ; la fermeture du gap de re-trigger, elle, est conservée
//  côté AppDelegate via isOCRFlowActive.) État 3 « aucun texte détecté » =
//  O.2.c (ici, texte vide = fermeture silencieuse en amont, sans fenêtre).
//
//  Surface calquée sur la grammaire du générateur (header badge + titre + logo
//  é, corps éditable, footer boutons) via les composants/modifiers partagés
//  (KeyboardKey, PolishTokens, KeyablePanel) — sans toucher PopoverView.
//

import AppKit
import SwiftUI

final class CaptureTextWindowController {
    /// Instance active — rétention + GARDE anti-re-trigger : `startOCRCapture()`
    /// est no-op tant qu'elle existe (vigilance ⌥&-pendant-fenêtre).
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

    /// Ouvre la fenêtre pré-remplie du texte OCR (non vide). Si déjà ouverte →
    /// ramenée au premier plan (dédupe, pattern Tutorial/Purchase).
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

    /// Largeur fixe de la fenêtre (comportement #1).
    private static let windowWidth: CGFloat = 600
    /// Plancher confortable même pour un texte court.
    private static let windowFloor: CGFloat = 400

    /// Hauteur calculée UNE FOIS à l'ouverture selon la quantité de texte OCR,
    /// bornée `[plancher, plafond]`. Plafond = celui de la fenêtre de réponse
    /// du popup (`resultPlafondHeight`, surface sœur → cohérence, zéro nouveau
    /// token). Au-delà, le TextEditor scrolle en interne. Pas de live-grow
    /// (cf. details/snapshot-ocr.md — compromis assumé, aligné calculatedPopoverHeight).
    private static func computeWindowHeight(for text: String) -> CGFloat {
        // Largeur utile du texte : fenêtre − padding body (12×2) − padding
        // field (6×2) − inset interne du TextEditor (~10).
        let textWidth = windowWidth - 24 - 12 - 10
        let font = NSFont.systemFont(ofSize: PolishTokens.resultBodyFontSize)
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        // Fudge : la lineSpacing SwiftUI (~0.3em) n'entre pas dans boundingRect.
        let textHeight = ceil(bounding.height * 1.3)
        // Chrome (header + hint + paddings + footer) — légèrement surestimé pour
        // ne jamais couper la dernière ligne à l'ouverture.
        let chrome: CGFloat = 180
        let plafond = AppDelegate.resultPlafondHeight()
        return min(max(windowFloor, chrome + textHeight), plafond)
    }

    private func show(ocrText: String) {
        let width = Self.windowWidth
        let height = Self.computeWindowHeight(for: ocrText)
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
            windowHeight: height,
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
/// éditable / footer boutons), via les composants partagés.
private struct CaptureTextView: View {
    let ocrText: String
    let windowHeight: CGFloat
    let onValidate: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(ocrText: String,
         windowHeight: CGFloat,
         onValidate: @escaping (String) -> Void,
         onCancel: @escaping () -> Void) {
        self.ocrText = ocrText
        self.windowHeight = windowHeight
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
        .frame(width: 600, height: windowHeight)
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

    // Footer : VRAIS boutons (l'OCR est un geste souris → boutons cliquables
    // naturels). Raccourci affiché DANS le bouton. Secondaire Annuler (stroké,
    // transparent) à gauche · Primaire Valider (bleu plein = token action
    // loucedé) à droite ; ⌘↵ conservé + grisé si vide (comportement #3).
    private var footer: some View {
        HStack(spacing: 8) {
            // Secondaire : fond transparent + bordure neutre adaptative.
            Button { onCancel() } label: {
                HStack(spacing: 6) {
                    KeyboardKey("esc")
                    Text("Annuler").font(.system(size: 13))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            // Primaire : bleu plein (PolishTokens.selectionBackground = le bleu
            // d'action déjà en prod) + texte blanc + capsule ⌘↵ onAccent.
            Button { onValidate(text) } label: {
                HStack(spacing: 6) {
                    KeyboardKey("⌘↵", onAccent: true)
                    Text("Valider").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(PolishTokens.selectionBackground)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(isEmpty)
        }
        .padding(12)
        .polishAccentBackground()
    }
}
