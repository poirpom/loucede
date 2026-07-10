//
//  CaptureTextWindowController.swift
//  loucede
//
//  O.2 (Snapshot OCR) — fenêtre « Capture de texte », intercalée entre la
//  capture/OCR et l'injection dans le cartouche du popup. WindowController
//  dédié (décision B, cf. details/snapshot-ocr.md) — PAS un mode du popup.
//
//  DEUX états (décidés à la construction par le résultat OCR — pas de flip
//  runtime, pas d'ObservableObject ; l'état lecture/spinner a été écarté au
//  test runtime, cf. O.2.b) :
//   • NOMINAL (O.2.a) : fenêtre pré-remplie du texte OCR, éditable. ⌘↵ valide
//     (injection cartouche + popup), Esc/Annuler annulent le flow.
//   • AUCUN-TEXTE (O.2.c) : OCR sans résultat → icône + message + Réessayer
//     (relance un cycle de capture) / Fermer (retour app source).
//
//  Surface calquée sur la grammaire du générateur via les composants/modifiers
//  partagés (KeyboardKey, PolishTokens, KeyablePanel) — sans toucher PopoverView.
//  Header et boutons footer extraits (CaptureHeader / CapturePrimaryButton /
//  CaptureSecondaryButton), partagés par les deux états.
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
    /// Actions selon l'état. La secondaire (Annuler / Fermer / Esc) est commune
    /// aux deux états (fermeture + retour app source). La primaire diffère
    /// (Valider(texte) en nominal, Réessayer en aucun-texte).
    private let onValidate: ((String) -> Void)?
    private let onRetry: (() -> Void)?
    private let onSecondary: () -> Void

    private init(onValidate: ((String) -> Void)?,
                 onRetry: (() -> Void)?,
                 onSecondary: @escaping () -> Void) {
        self.onValidate = onValidate
        self.onRetry = onRetry
        self.onSecondary = onSecondary
    }

    /// NOMINAL — ouvre la fenêtre pré-remplie du texte OCR (non vide).
    static func present(ocrText: String,
                        onValidate: @escaping (String) -> Void,
                        onCancel: @escaping () -> Void) {
        if let existing = current {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = CaptureTextWindowController(
            onValidate: onValidate, onRetry: nil, onSecondary: onCancel
        )
        controller.showEditing(ocrText: ocrText)
        current = controller
    }

    /// AUCUN-TEXTE — ouvre la fenêtre sur l'état « aucun texte détecté ».
    static func presentEmpty(onRetry: @escaping () -> Void,
                             onClose: @escaping () -> Void) {
        if let existing = current {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = CaptureTextWindowController(
            onValidate: nil, onRetry: onRetry, onSecondary: onClose
        )
        controller.showEmpty()
        current = controller
    }

    /// Annulation externe (Esc capté par le monitor local de l'AppDelegate) —
    /// couvre les deux états via l'action secondaire commune.
    func cancel() {
        finish { $0.onSecondary() }
    }

    /// Largeur fixe de la fenêtre (comportement #1).
    private static let windowWidth: CGFloat = 600
    /// Plancher confortable même pour un texte court (nominal).
    private static let windowFloor: CGFloat = 400
    /// Hauteur fixe compacte de l'état aucun-texte (icône + 2 lignes + footer).
    private static let windowEmptyHeight: CGFloat = 280

    /// Hauteur calculée UNE FOIS à l'ouverture (nominal) selon la quantité de
    /// texte OCR, bornée `[plancher, plafond]`. Plafond = celui de la fenêtre
    /// de réponse du popup (`resultPlafondHeight`, surface sœur → cohérence,
    /// zéro nouveau token). Au-delà, le TextEditor scrolle. Pas de live-grow.
    private static func computeWindowHeight(for text: String) -> CGFloat {
        let textWidth = windowWidth - 24 - 12 - 10
        let font = NSFont.systemFont(ofSize: PolishTokens.resultBodyFontSize)
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let textHeight = ceil(bounding.height * 1.3)
        let chrome: CGFloat = 180
        let plafond = AppDelegate.resultPlafondHeight()
        return min(max(windowFloor, chrome + textHeight), plafond)
    }

    private func showEditing(ocrText: String) {
        let height = Self.computeWindowHeight(for: ocrText)
        let root = CaptureTextView(
            ocrText: ocrText,
            windowHeight: height,
            onValidate: { [weak self] text in self?.finish { $0.onValidate?(text) } },
            onCancel: { [weak self] in self?.finish { $0.onSecondary() } }
        )
        showPanel(root: root, height: height)
    }

    private func showEmpty() {
        let root = CaptureEmptyView(
            onRetry: { [weak self] in self?.finish { $0.onRetry?() } },
            onClose: { [weak self] in self?.finish { $0.onSecondary() } }
        )
        showPanel(root: root, height: Self.windowEmptyHeight)
    }

    /// Montage commun du panneau (calqué sur createPopoverWindow) : KeyablePanel
    /// borderless (canBecomeKey → focus TextEditor garanti), fond clair + hosting
    /// cornerRadius + polishVibrancy côté SwiftUI.
    private func showPanel<V: View>(root: V, height: CGFloat) {
        let width = Self.windowWidth
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

    /// Sortie UNIQUE idempotente : ferme la fenêtre puis exécute `action`.
    /// Garde `didClose` → un seul teardown, un seul callback quel que soit le
    /// chemin (⌘↵, Valider/Réessayer, Annuler/Fermer, Esc via monitor).
    private func finish(_ action: (CaptureTextWindowController) -> Void) {
        guard !didClose else { return }
        didClose = true
        window?.orderOut(nil)
        window = nil
        CaptureTextWindowController.current = nil
        action(self)
    }
}

// MARK: - Composants partagés (header + boutons footer)

/// Header commun aux deux états : badge OCR + titre + logo é (calqué
/// generatorTopBar).
private struct CaptureHeader: View {
    var body: some View {
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
}

/// Bouton PRIMAIRE (bleu plein = token action loucedé, texte blanc, capsule de
/// raccourci onAccent). Le `.keyboardShortcut` est posé par l'appelant (diffère
/// selon l'usage : ⌘↵ Valider / ⌘R Réessayer).
private struct CapturePrimaryButton: View {
    let keycap: String
    let label: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                KeyboardKey(keycap, onAccent: true)
                Text(label).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(PolishTokens.selectionBackground)
        .controlSize(.large)
        .disabled(disabled)
    }
}

/// Bouton SECONDAIRE (fond transparent + bordure neutre adaptative, capsule de
/// raccourci standard). Esc clavier est géré par le monitor local (pas de
/// keyboardShortcut ici) ; ce bouton reste cliquable.
private struct CaptureSecondaryButton: View {
    let keycap: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                KeyboardKey(keycap)
                Text(label).font(.system(size: 13))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - État NOMINAL (texte éditable)

/// Vue de l'état nominal — grammaire générateur reprise (header / corps
/// éditable / footer boutons).
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
            CaptureHeader()
            bodyEditor
            footer
        }
        .frame(width: 600, height: windowHeight)
        .polishVibrancy()
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

    // Footer : Annuler (secondaire) / Valider (primaire, ⌘↵, grisé si vide).
    private var footer: some View {
        HStack(spacing: 8) {
            CaptureSecondaryButton(keycap: "esc", label: "Annuler") { onCancel() }
            Spacer()
            CapturePrimaryButton(keycap: "⌘↵", label: "Valider", disabled: isEmpty) {
                onValidate(text)
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(12)
        .polishAccentBackground()
    }
}

// MARK: - État AUCUN-TEXTE

/// Vue de l'état « aucun texte détecté » (O.2.c) — icône + message + footer
/// Fermer / Réessayer (⌘R).
private struct CaptureEmptyView: View {
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CaptureHeader()
            emptyBody
            footer
        }
        .frame(width: 600, height: 280)
        .polishVibrancy()
    }

    private var emptyBody: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 64, height: 64)
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            }
            Text("Aucun texte détecté")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Réessaie en cadrant une zone contenant du texte lisible.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            CaptureSecondaryButton(keycap: "esc", label: "Fermer") { onClose() }
            Spacer()
            CapturePrimaryButton(keycap: "⌘R", label: "Réessayer") { onRetry() }
                .keyboardShortcut("r", modifiers: .command)
        }
        .padding(12)
        .polishAccentBackground()
    }
}
