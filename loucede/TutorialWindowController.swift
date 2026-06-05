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

/// Proxy léger pour le message handler JS → évite le cycle de rétention
/// `WKUserContentController → handler`. Forwarde au controller en faible.
private final class TutorialBridge: NSObject, WKScriptMessageHandler {
    var onMessage: (([String: Any]) -> Void)?
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any] { onMessage?(body) }
    }
}

final class TutorialWindowController: NSWindowController, NSWindowDelegate {
    /// Instance active (rétention le temps de vie de la fenêtre).
    private static var current: TutorialWindowController?

    private let onClose: (() -> Void)?
    private let bridge = TutorialBridge()
    private weak var webView: WKWebView?

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

        // Bridge JS ↔ Swift : handler "tutoBridge".
        let config = WKWebViewConfiguration()
        config.userContentController.add(bridge, name: "tutoBridge")
        let webView = WKWebView(frame: .zero, configuration: config)
        window.contentView = webView
        self.webView = webView

        super.init(window: window)
        window.delegate = self

        bridge.onMessage = { [weak self] body in self?.handleBridgeMessage(body) }

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

    // MARK: - Bridge JS → Swift

    /// Reçoit les messages de la page (`window.webkit.messageHandlers.tutoBridge`).
    /// M.2.2 : log + démonstration round-trip (tick). L'orchestration réelle
    /// (ouverture popover, modèle, paste) arrive en M.2.3.
    private func handleBridgeMessage(_ body: [String: Any]) {
        let type = body["type"] as? String ?? "?"
        #if DEBUG
        print("📩 [tutoBridge] \(body)")
        #endif
        switch type {
        case "ready":
            tick("ready")
        case "shortcutPressed":
            // Démo round-trip M.2.2 : on coche « raccourci ». (M.2.3 ouvrira
            // réellement le popover avec `body["selection"]`.)
            tick("shortcut")
        default:
            break
        }
    }

    // MARK: - Swift → JS (helpers `window.tuto.*`)

    /// Coche une étape côté page.
    func tick(_ step: String) {
        webView?.evaluateJavaScript("window.tuto && window.tuto.tick('\(step)')", completionHandler: nil)
    }

    /// Injecte le résultat IA dans le contenteditable actif (remplace le paste
    /// système — utilisé en M.2.3). Texte échappé via JSON.
    func injectResult(_ text: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
              let json = String(data: data, encoding: .utf8) else { return }
        // json = ["..."] → on prend l'élément 0 pour une string JS échappée.
        webView?.evaluateJavaScript("window.tuto && window.tuto.injectResult((\(json))[0])", completionHandler: nil)
    }

    /// Restaure le focus du contenteditable après fermeture du popover.
    func refocusEdit() {
        webView?.evaluateJavaScript("window.tuto && window.tuto.refocusEdit()", completionHandler: nil)
    }

    // MARK: NSWindowDelegate — point de sortie unique
    func windowWillClose(_ notification: Notification) {
        // Retire le handler (rompt proprement la chaîne ucc → bridge).
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "tutoBridge")
        onClose?()
        TutorialWindowController.current = nil
    }
}
