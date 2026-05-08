//
//  DocumentationView.swift
//  loucede
//
//  Point 4 pre-V1 (2026-05-08) : webview interne pour la documentation
//  Notion. Remplace l'ouverture browser externe (Point 2 temporaire).
//
//  Architecture :
//  - `DocumentationView` (SwiftUI) : conteneur léger, rend juste la
//    `DocumentationWebView` en plein espace.
//  - `DocumentationWebView` (NSViewRepresentable) : wrap un `WKWebView`
//    qui charge l'URL passée en paramètre.
//  - `Coordinator` (WKNavigationDelegate) : intercepte les clics
//    utilisateur pour distinguer navigation interne (reste dans la
//    webview) vs externe (ouvre le browser par défaut).
//
//  La fenêtre qui héberge cette vue est créée par
//  `AppDelegate.openDocumentation()` avec `setFrameAutosaveName` pour
//  persister position/taille entre sessions (mécanisme natif AppKit).
//
//  V2 (post-V1) : remplacer cette webview par un rendu natif via
//  Notion API + proxy Scaleway + swift-markdown-ui (déjà en deps).
//  Cf. `vision-doc-integration.md` pour la roadmap progressive.
//

import SwiftUI
import WebKit

// MARK: - Container SwiftUI

/// Conteneur SwiftUI minimaliste : rend la webview en plein espace.
/// Pas de loader ni d'état d'erreur custom V1 — Notion gère ses propres
/// états (loading skeleton + erreur réseau) côté CSS, on ne re-implémente
/// pas. Si feedback utilisateur en V1.x, on ajoutera ici.
struct DocumentationView: View {
    let url: URL

    var body: some View {
        DocumentationWebView(url: url)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - WKWebView wrapper

/// `NSViewRepresentable` autour de `WKWebView`. Le WKWebView est créé
/// une seule fois (`makeNSView`) et son URL est rechargée par
/// `AppDelegate.openDocumentation()` avant chaque re-show de la fenêtre
/// (cf. décision produit : retour à l'URL d'accueil à chaque ouverture).
/// `updateNSView` est volontairement no-op : aucune réaction aux
/// changements de `url` après création (le rechargement passe par la
/// référence WKWebView stockée côté AppDelegate).
struct DocumentationWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Magnification permet à l'utilisateur de zoomer/dézoomer la doc
        // via les pinches ou ⌘+/⌘- — bonus accessibilité gratuit.
        webView.allowsMagnification = true
        webView.load(URLRequest(url: url))
        // Mémorise la référence côté AppDelegate pour permettre les
        // reloads ultérieurs sans recréer le WKWebView (préserve les
        // sessions / cookies / cache Notion).
        globalAppDelegate?.docWebView = webView
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No-op : l'URL est rechargée à la demande par AppDelegate.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Intercepte les clics utilisateur pour ouvrir les liens externes
    /// dans le browser par défaut, tout en laissant passer toute la
    /// navigation interne (rendering Notion, redirects, ressources CDN).
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Liens INTERNES à la doc loucedé (sous-domaine `loucede.notion.site`)
            // restent dans la webview. Cohérent avec la promesse « doc dans
            // loucedé, sans changer d'app ».
            if url.host == "loucede.notion.site" {
                decisionHandler(.allow)
                return
            }

            // Clics utilisateur sur liens HORS loucede.notion.site → browser
            // par défaut. `linkActivated` distingue un clic explicite d'un
            // simple chargement de ressource (CDN images Notion, fonts,
            // iframes preview, etc.) qu'on doit laisser passer.
            if navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            // Redirections internes Notion + ressources externes
            // (notion-static.com, fonts.gstatic.com, etc.) → laisser passer
            // pour que le rendu fonctionne.
            decisionHandler(.allow)
        }
    }
}

// MARK: - Preview

#Preview {
    DocumentationView(url: URL(string: "https://loucede.notion.site/")!)
        .frame(width: 900, height: 700)
}
