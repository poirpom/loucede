//
//  CaptureOverlayController.swift
//  loucede
//
//  O.1.c (Snapshot OCR) — overlay maison plein écran pour la sélection de la
//  zone à capturer. 100 % IN-PROCESS (décision A, cf. details/snapshot-ocr.md) :
//  aucun `screencapture -i`, aucun sous-process, aucun fichier temporaire —
//  la privacy 100 % local est le différenciateur produit.
//
//  L'overlay couvre l'écran ACTIF (celui du curseur souris ; décision « écran
//  actif uniquement », multi-écran = V3). L'utilisateur trace une zone au
//  drag ; à la fin du drag la zone est renvoyée en coordonnées GLOBALES AppKit
//  (origine bas-gauche). Esc annule. La conversion vers le référentiel de la
//  capture (ScreenCaptureKit) est à la charge de O.1.d.
//

import AppKit

final class CaptureOverlayController {
    /// Zone sélectionnée en coordonnées GLOBALES AppKit (origine bas-gauche),
    /// ou `nil` si l'utilisateur a annulé (Esc / clic sans drag). `screen` =
    /// l'écran actif sur lequel la capture a eu lieu (fourni à O.1.d).
    private let onComplete: (CGRect?, NSScreen?) -> Void
    private let screen: NSScreen
    private var window: NSWindow?

    init(onComplete: @escaping (CGRect?, NSScreen?) -> Void) {
        self.onComplete = onComplete
        // Écran actif = celui qui contient le curseur souris (fallback main).
        let mouse = NSEvent.mouseLocation
        self.screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    func present() {
        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .screenSaver          // au-dessus de tout le reste
        win.ignoresMouseEvents = false
        win.setFrame(screen.frame, display: true)

        let view = CaptureOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onSelect = { [weak self] rectInView in self?.finish(rectInView: rectInView) }
        view.onCancel = { [weak self] in self?.finish(rectInView: nil) }
        win.contentView = view

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        win.makeFirstResponder(view)
        // Force le crosshair dès la présentation (cursorUpdate ne se déclenche
        // qu'au 1er mouvement souris ; sans ça, curseur flèche tant qu'on ne
        // bouge pas).
        NSCursor.crosshair.set()
        window = win
    }

    /// Annulation externe (ex. Esc capté par le monitor local de l'AppDelegate,
    /// qui intercepte le keyDown avant que la vue ne le reçoive).
    func cancel() {
        finish(rectInView: nil)
    }

    private func finish(rectInView: NSRect?) {
        var globalRect: CGRect?
        if let r = rectInView, r.width > 2, r.height > 2, let win = window {
            // vue → fenêtre → écran (coords globales AppKit, origine bas-gauche).
            globalRect = win.convertToScreen(r)
        }
        window?.orderOut(nil)
        window = nil
        onComplete(globalRect, screen)
    }
}

/// Vue de tracking : assombrit l'écran, laisse la zone en cours claire + une
/// bordure, et remonte la sélection au relâchement.
private final class CaptureOverlayView: NSView {
    var onSelect: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var cursorTrackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }   // origine bas-gauche (cohérent AppKit)

    // Curseur crosshair via NSTrackingArea + cursorUpdate (les cursor-rects
    // legacy ne s'engagent pas sur une fenêtre borderless .screenSaver en app
    // .accessory : le système ne traite pas l'agent-app comme propriétaire du
    // curseur → la flèche persiste).
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = cursorTrackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        cursorTrackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSColor.black.withAlphaComponent(0.28)
        dim.setFill()

        // Pas de sélection en cours → on assombrit tout.
        guard currentRect.width >= 1, currentRect.height >= 1 else {
            bounds.fill()
            return
        }

        // Assombrit tout SAUF la zone sélectionnée (4 bandes autour — robuste,
        // pas de compositing .clear). La zone reste à sa luminosité réelle.
        let b = bounds
        NSRect(x: b.minX, y: b.minY, width: b.width, height: currentRect.minY - b.minY).fill()             // bas
        NSRect(x: b.minX, y: currentRect.maxY, width: b.width, height: b.maxY - currentRect.maxY).fill()   // haut
        NSRect(x: b.minX, y: currentRect.minY, width: currentRect.minX - b.minX, height: currentRect.height).fill()   // gauche
        NSRect(x: currentRect.maxX, y: currentRect.minY, width: b.maxX - currentRect.maxX, height: currentRect.height).fill()  // droite

        NSColor.white.setStroke()
        let path = NSBezierPath(rect: currentRect)
        path.lineWidth = 1.5
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        // cursorUpdate n'est pas rappelé bouton enfoncé → on ré-assère ici.
        NSCursor.crosshair.set()
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.crosshair.set()
        guard let s = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(s.x, p.x), y: min(s.y, p.y),
            width: abs(p.x - s.x), height: abs(p.y - s.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let r = currentRect
        startPoint = nil
        currentRect = .zero
        needsDisplay = true
        // Zone trop petite (simple clic) = annulation.
        if r.width > 2, r.height > 2 { onSelect?(r) } else { onCancel?() }
    }

    // Fallback Esc (le monitor local de l'AppDelegate le capte normalement en
    // premier ; conservé au cas où le monitor serait absent).
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
}
