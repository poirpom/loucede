//
//  CaptureTextWindowController.swift
//  loucede
//
//  O.2 (Snapshot OCR) — fenêtre « Capture de texte », intercalée entre la
//  capture et l'injection dans le cartouche du popup. WindowController dédié
//  (décision B, cf. details/snapshot-ocr.md) — PAS un mode du popup.
//
//  DEUX états internes (pilotés par CaptureTextModel) :
//   • .loading (O.2.b) : la fenêtre s'ouvre AVANT l'OCR → spinner « Lecture du
//     texte à l'écran… » (tue le temps mort silencieux repéré en O.1).
//   • .editing (O.2.a) : à la fin de l'OCR, bascule sèche → texte pré-rempli,
//     éditable ; ⌘↵ valide (injection cartouche + popup), Esc annule le flow.
//  État 3 « aucun texte détecté » = O.2.c (ici, texte vide → fermeture
//  silencieuse via fail()).
//
//  Surface calquée sur la grammaire du générateur (header badge + titre + logo
//  é, corps, footer boutons) via les composants/modifiers partagés (KeyboardKey,
//  PolishTokens, KeyablePanel, GenerationProgressIndicator) — sans toucher
//  PopoverView.
//

import AppKit
import Combine
import SwiftUI

/// État partagé controller ↔ vue : permet au controller d'alimenter la vue
/// APRÈS présentation (fin de l'OCR async) — lecture → édition.
final class CaptureTextModel: ObservableObject {
    enum Phase { case loading, editing }
    @Published var phase: Phase = .loading
    @Published var text: String = ""
}

final class CaptureTextWindowController {
    /// Instance active — rétention + GARDE anti-re-trigger (⌥& no-op tant
    /// qu'elle existe, dès la lecture ; cf. details/snapshot-ocr.md).
    static private(set) var current: CaptureTextWindowController?
    static var isPresented: Bool { current != nil }

    private let model = CaptureTextModel()
    private var window: NSWindow?
    private var didClose = false
    private let onValidate: (String) -> Void
    private let onCancel: () -> Void

    private init(onValidate: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onValidate = onValidate
        self.onCancel = onCancel
    }

    /// Ouvre la fenêtre en état LECTURE (spinner). Le texte est fourni ensuite
    /// par `setText(_:)` (OCR OK) ou la fenêtre est fermée par `fail()` (vide).
    /// Dédupe (pattern Tutorial/Purchase). Renvoie l'instance pour l'alimenter.
    @discardableResult
    static func present(onValidate: @escaping (String) -> Void,
                        onCancel: @escaping () -> Void) -> CaptureTextWindowController {
        if let existing = current {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return existing
        }
        let controller = CaptureTextWindowController(onValidate: onValidate, onCancel: onCancel)
        controller.show()
        current = controller
        return controller
    }

    /// OCR terminé avec du texte → bascule LECTURE → ÉDITION : pré-remplit,
    /// active Valider, et resize la fenêtre à la hauteur du texte (bascule
    /// sèche, sans animation).
    func setText(_ text: String) {
        model.text = text
        model.phase = .editing
        resizeForText(text)
    }

    /// OCR terminé sans texte → fermeture silencieuse (retour app source, comme
    /// onCancel). L'état 3 « aucun texte détecté » remplacera ça en O.2.c.
    func fail() {
        finish { $0.onCancel() }
    }

    /// Annulation externe (Esc capté par le monitor local de l'AppDelegate,
    /// qui intercepte le keyDown avant la fenêtre — même schéma que l'overlay).
    func cancel() {
        finish { $0.onCancel() }
    }

    /// Largeur fixe de la fenêtre (comportement #1).
    private static let windowWidth: CGFloat = 600
    /// Plancher confortable — aussi la hauteur de l'état LECTURE (le spinner
    /// n'a pas besoin de la hauteur calculée du texte).
    private static let windowFloor: CGFloat = 400

    /// Hauteur calculée UNE FOIS à la bascule vers l'édition, selon la quantité
    /// de texte OCR, bornée `[plancher, plafond]`. Plafond = celui de la fenêtre
    /// de réponse du popup (`resultPlafondHeight`, surface sœur → cohérence,
    /// zéro nouveau token). Au-delà, le TextEditor scrolle en interne. Pas de
    /// live-grow (compromis assumé, aligné calculatedPopoverHeight).
    private static func computeWindowHeight(for text: String) -> CGFloat {
        // Largeur utile : fenêtre − padding body (12×2) − padding field (6×2) −
        // inset interne du TextEditor (~10).
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

    private func show() {
        let width = Self.windowWidth
        let height = Self.windowFloor   // état LECTURE : plancher
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
            model: model,
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

    /// Resize sec (sans animation) vers la hauteur du texte, recentré.
    private func resizeForText(_ text: String) {
        guard let window else { return }
        let w = Self.windowWidth
        let h = Self.computeWindowHeight(for: text)
        if let r = (window.screen ?? NSScreen.main)?.visibleFrame {
            window.setFrame(NSRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h),
                            display: true)
        } else {
            window.setContentSize(NSSize(width: w, height: h))
        }
    }

    /// Sortie UNIQUE idempotente : ferme la fenêtre puis exécute `action`
    /// (validate/cancel). Garde `didClose` → un seul teardown, un seul callback
    /// quel que soit le chemin (⌘↵, clic Annuler, Esc via monitor, fail vide).
    private func finish(_ action: (CaptureTextWindowController) -> Void) {
        guard !didClose else { return }
        didClose = true
        window?.orderOut(nil)
        window = nil
        CaptureTextWindowController.current = nil
        action(self)
    }
}

/// Vue SwiftUI de la fenêtre — deux états (lecture / édition), grammaire
/// générateur reprise via les composants partagés.
private struct CaptureTextView: View {
    @ObservedObject var model: CaptureTextModel
    let onValidate: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    private var isEmpty: Bool {
        model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    /// Valider n'est actif qu'en édition avec du texte (grisé en lecture ET si
    /// champ vide — comportement #3).
    private var canValidate: Bool { model.phase == .editing && !isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            switch model.phase {
            case .loading: loadingBody
            case .editing: bodyEditor
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // remplit le panel
        .polishVibrancy()
    }

    // Header : badge OCR + titre + logo é (calqué generatorTopBar). Identique
    // dans les deux états (seul le corps change).
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

    // État LECTURE : spinner (GenerationProgressIndicator réutilisé tel quel) +
    // libellé. Calqué sur generatorLoadingContent du générateur.
    private var loadingBody: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            GenerationProgressIndicator()
            Spacer(minLength: 0)
            Text("Lecture du texte à l'écran…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }

    // État ÉDITION : hint + TextEditor multiligne (calqué editablePromptField).
    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vérifie et corrige si besoin, puis valide")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextEditor(text: $model.text)
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
        // Focus auto à la bascule (le corps n'apparaît qu'en édition ; async :
        // la fenêtre doit être key d'abord).
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    // Footer : boutons (l'OCR est un geste souris). Annuler toujours actif ;
    // Valider actif seulement en édition avec du texte.
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
            Button { onValidate(model.text) } label: {
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
            .disabled(!canValidate)
        }
        .padding(12)
        .polishAccentBackground()
    }
}
