//
//  TutorialWindowController.swift
//  loucede
//
//  Phase M.2 — Tuto interactif post-onboarding.
//
//  M.2.1 (coquille) : fenêtre native in-process hébergeant la page tuto
//  (`Resources/Tutorial/index.html`) dans une WKWebView. Pattern auto-contenu
//  aligné sur `PurchaseWindowController` (D.3) : rétention statique, dédupe,
//  point de sortie unique `windowWillClose`. La fenêtre est recréée à chaque
//  `present()` (état coches in-memory → reset gratuit, cf. décision M.2.0).
//
//  À venir : bridge JS (M.2.2), orchestration mode tuto (M.2.3), layout +
//  contenu (M.2.4/M.2.5), coches auto (M.2.6), entry points réels (M.2.7).
//

import Cocoa
import WebKit

final class TutorialWindowController: NSWindowController, NSWindowDelegate {
    /// Instance active (rétention le temps de vie de la fenêtre).
    private static var current: TutorialWindowController?

    private let onClose: (() -> Void)?

    /// Ouvre le tuto (ou ramène l'existant au premier plan). Recréé à chaque
    /// appel → page rechargée à neuf (reset des coches).
    static func present(onClose: (() -> Void)? = nil) {
        if let existing = current {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = TutorialWindowController(onClose: onClose)
        current = controller
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(onClose: (() -> Void)?) {
        self.onClose = onClose

        // Fenêtre native, level .normal (le popover loucedé .floating passe
        // au-dessus naturellement — cf. diag M.2).
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Tuto loucedé"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.level = .normal
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.center()

        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        window.contentView = webView

        super.init(window: window)
        window.delegate = self

        // Chargement de la page bundlée. Folder reference `Tutorial` →
        // sous-répertoire préservé dans le bundle ; fallback flat au cas où.
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Tutorial")
            ?? Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.loadHTMLString(
                "<body style='font:14px -apple-system;padding:40px'>⚠️ Tutorial/index.html introuvable dans le bundle.</body>",
                baseURL: nil
            )
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // MARK: NSWindowDelegate — point de sortie unique
    func windowWillClose(_ notification: Notification) {
        onClose?()
        TutorialWindowController.current = nil
    }
}
