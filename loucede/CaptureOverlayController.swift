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
//  Curseur : grand crosshair custom (dessiné par code, mode-agnostique via
//  liseré sombre) POUSSÉ sur la pile NSCursor à la présentation et DÉPILÉ à la
//  fermeture — les cursor-rects et `cursorUpdate + .set()` sont écrasés par le
//  système pour cette fenêtre borderless .screenSaver en app .accessory (pas
//  propriétaire du curseur) ; seul push/pop persiste de bout en bout.
//

import AppKit

final class CaptureOverlayController {
    /// Zone sélectionnée en coordonnées GLOBALES AppKit (origine bas-gauche),
    /// ou `nil` si l'utilisateur a annulé (Esc / clic sans drag). `screen` =
    /// l'écran actif sur lequel la capture a eu lieu (fourni à O.1.d).
    private let onComplete: (CGRect?, NSScreen?) -> Void
    private let screen: NSScreen
    private var window: NSWindow?
    /// Garde d'idempotence : `finish()` peut être atteint par plusieurs chemins
    /// (relâchement, clic sans drag, Esc via le monitor local). On garantit un
    /// `NSCursor.pop()` EXACTEMENT UNE FOIS (pas de curseur fantôme, pas de
    /// double-pop qui dépilerait un curseur étranger).
    private var didFinish = false

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
        // Persiste le grand crosshair custom sur la pile de curseurs (tient de
        // l'ouverture au drag, quel que soit le « propriétaire » système).
        Self.captureCursor.push()
        window = win
    }

    /// Annulation externe (ex. Esc capté par le monitor local de l'AppDelegate,
    /// qui intercepte le keyDown avant que la vue ne le reçoive).
    func cancel() {
        finish(rectInView: nil)
    }

    private func finish(rectInView: NSRect?) {
        guard !didFinish else { return }
        didFinish = true
        NSCursor.pop()   // dépile le curseur poussé dans present()

        var globalRect: CGRect?
        if let r = rectInView, r.width > 2, r.height > 2, let win = window {
            // vue → fenêtre → écran (coords globales AppKit, origine bas-gauche).
            globalRect = win.convertToScreen(r)
        }
        window?.orderOut(nil)
        window = nil
        onComplete(globalRect, screen)
    }

    // MARK: - Grand curseur crosshair custom

    /// Grand crosshair compact dessiné par code (aucun asset) : deux traits
    /// blancs ~66×2px à liseré sombre + repère central en anneau. Le liseré
    /// garantit la lisibilité sur TOUT fond (contenu clair comme sombre survolé)
    /// indépendamment du mode système. `hotSpot` = centre exact = intersection
    /// des traits = repère central (sinon cadrage décalé de la visée).
    static let captureCursor: NSCursor = {
        let dim: CGFloat = 72
        let size = NSSize(width: dim, height: dim)
        let image = NSImage(size: size, flipped: false) { _ in
            let c = dim / 2
            let arm: CGFloat = 33      // demi-longueur (trait total 66)
            let gap: CGFloat = 5       // trou central autour du repère
            let whiteW: CGFloat = 2
            let darkW: CGFloat = 4     // 1px de liseré de chaque côté du blanc
            let white = NSColor.white
            let dark = NSColor.black.withAlphaComponent(0.9)

            func hSeg(_ x0: CGFloat, _ x1: CGFloat, _ t: CGFloat, _ color: NSColor) {
                color.setFill()
                NSRect(x: x0, y: c - t / 2, width: x1 - x0, height: t).fill()
            }
            func vSeg(_ y0: CGFloat, _ y1: CGFloat, _ t: CGFloat, _ color: NSColor) {
                color.setFill()
                NSRect(x: c - t / 2, y: y0, width: t, height: y1 - y0).fill()
            }

            // Liseré sombre (dessous, plus large), puis blanc (dessus).
            for (t, color) in [(darkW, dark), (whiteW, white)] {
                hSeg(c - arm, c - gap, t, color)   // gauche
                hSeg(c + gap, c + arm, t, color)   // droite
                vSeg(c - arm, c - gap, t, color)   // bas
                vSeg(c + gap, c + arm, t, color)   // haut
            }

            // Repère central : anneau (centre blanc + contour sombre).
            let ringR: CGFloat = 3
            let ringRect = NSRect(x: c - ringR, y: c - ringR, width: ringR * 2, height: ringR * 2)
            let ring = NSBezierPath(ovalIn: ringRect)
            white.setFill(); ring.fill()
            dark.setStroke(); ring.lineWidth = 1; ring.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: dim / 2, y: dim / 2))
    }()
}

/// Vue de tracking : assombrit l'écran, laisse la zone en cours claire + une
/// bordure, et remonte la sélection au relâchement. Le curseur est géré par le
/// contrôleur (push/pop) — la vue ne touche pas au curseur.
private final class CaptureOverlayView: NSView {
    var onSelect: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }   // origine bas-gauche (cohérent AppKit)

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
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
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
