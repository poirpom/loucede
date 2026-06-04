//
//  PurchasePopupView.swift
//  loucede
//
//  Phase D.3 (2026-06-04) : fenêtre d'achat Polar embarquée.
//
//  L'utilisateur paye dans une WKWebView qu'on contrôle, pointée sur
//  `LicenseConfig.productCheckoutURL`. À la fin du paiement, Polar redirige
//  vers `https://<successURLHost>/#<fragment>` : on intercepte cette
//  navigation sur le **host** (`LicenseConfig.successURLHost`) via le
//  `WKNavigationDelegate`, on annule la navigation (`.cancel` — pas besoin
//  que le DNS du domaine soit résolu) et on déclenche `onSuccess`.
//
//  Architecture : `PurchaseWindowController` (auto-contenu, pattern
//  `MenuBarMenuWindowController`) possède une `NSWindow` 800×600 native et
//  héberge `PurchasePopupView` (NSViewRepresentable + Coordinator). Le
//  point de sortie unique est `windowWillClose`, qui aiguille vers
//  `onSuccess` (achat détecté) ou `onClose` (fermeture utilisateur) selon
//  le flag `didSucceed`.
//

import SwiftUI
import WebKit
import AppKit

// MARK: - WKWebView wrapper

/// Wrappe la `WKWebView` du checkout Polar et son délégué de navigation.
/// `onSuccessDetected` est **interne** : il prévient le window controller
/// que la success URL a été interceptée (le controller gère la fermeture
/// et le callback public `onSuccess`).
struct PurchasePopupView: NSViewRepresentable {
    let onSuccessDetected: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: LicenseConfig.productCheckoutURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSuccessDetected: onSuccessDetected)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let onSuccessDetected: () -> Void

        init(onSuccessDetected: @escaping () -> Void) {
            self.onSuccessDetected = onSuccessDetected
        }

        // Interception de la navigation de retour Polar via le host.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               url.host == LicenseConfig.successURLHost {
                // Achat réussi : on stoppe la navigation (pas besoin que le
                // domaine de retour soit résolu) et on remonte l'info.
                decisionHandler(.cancel)
                onSuccessDetected()
                return
            }
            decisionHandler(.allow)
        }

        // Liens `target="_blank"` / `window.open` (ex. « Conditions »,
        // « Confidentialité » de Polar) : ouvrir dans Safari pour ne pas
        // faire perdre à l'utilisateur son contexte de paiement, et
        // retourner `nil` (pas de nouvelle WKWebView).
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        #if DEBUG
        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            print("⚠️ [D.3] échec de navigation checkout : \(error.localizedDescription)")
        }
        #endif
    }
}

// MARK: - Window controller (auto-contenu)

/// Possède et présente la fenêtre d'achat Polar. Auto-contenu : se retient
/// lui-même via `current` (libéré à la fermeture). Pattern aligné sur
/// `MenuBarMenuWindowController`.
final class PurchaseWindowController: NSWindowController, NSWindowDelegate {
    /// Instance active (rétention statique tant que la fenêtre est ouverte).
    private static var current: PurchaseWindowController?

    private let onSuccess: () -> Void
    private let onClose: (() -> Void)?
    /// `true` une fois la success URL interceptée → `windowWillClose`
    /// déclenche `onSuccess` (et pas `onClose`).
    private var didSucceed = false

    /// Ouvre la fenêtre d'achat (ou ramène l'existante au premier plan).
    /// - `onSuccess` : appelé après détection de la success URL Polar
    ///   (la fenêtre est alors fermée).
    /// - `onClose` : appelé si l'utilisateur ferme la fenêtre sans avoir
    ///   acheté (croix rouge / Cmd+W).
    static func present(onSuccess: @escaping () -> Void, onClose: (() -> Void)? = nil) {
        if let existing = current {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = PurchaseWindowController(onSuccess: onSuccess, onClose: onClose)
        current = controller
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Ouvre le checkout Polar avec le **flux post-achat standard** de
    /// l'app : à la détection du succès → Réglages → Licence (onglet 2) +
    /// demande de focus du champ de saisie de clé. Point d'entrée unique
    /// des 3 boutons « Acheter » (overlay trial + Réglages → Licence).
    static func presentCheckout() {
        present(
            onSuccess: {
                // `openSettings` puis flag, sur le main : pour une fenêtre
                // neuve ou un switch d'onglet, le flag est posé avant que
                // `.onAppear` (tick suivant) ne le lise ; pour l'onglet déjà
                // actif, `.onChange` le capte.
                DispatchQueue.main.async {
                    globalAppDelegate?.openSettings(tab: 2)   // 2 = onglet Licence
                    LicenseManager.shared.focusKeyFieldRequest = true
                    LicenseManager.shared.postPurchaseHintActive = true
                }
            },
            onClose: {
                #if DEBUG
                print("✋ [D.4] checkout fermé sans achat")
                #endif
            }
        )
    }

    private init(onSuccess: @escaping () -> Void, onClose: (() -> Void)?) {
        self.onSuccess = onSuccess
        self.onClose = onClose

        // Fenêtre native 800×600, taille fixe (pas de `.resizable`).
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Acheter loucedé"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        // Le NSViewRepresentable est hébergé via NSHostingView ; son
        // `onSuccessDetected` rappelle ce controller.
        let content = PurchasePopupView(onSuccessDetected: { [weak self] in
            self?.handleSuccessDetected()
        })
        window.contentView = NSHostingView(rootView: content)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    /// Success URL interceptée → on ferme la fenêtre. Le callback public
    /// `onSuccess` part depuis `windowWillClose` (point de sortie unique).
    private func handleSuccessDetected() {
        didSucceed = true
        window?.close()
    }

    // MARK: NSWindowDelegate — point de sortie unique

    func windowWillClose(_ notification: Notification) {
        if didSucceed {
            onSuccess()
        } else {
            onClose?()
        }
        // Libère l'instance (déclenche le dealloc via la fin de rétention).
        PurchaseWindowController.current = nil
    }
}
