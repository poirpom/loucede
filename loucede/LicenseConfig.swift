//
//  LicenseConfig.swift
//  loucede
//
//  Phase 6.2 (2026-04-27) : configuration statique du système de licence
//  Polar.sh.
//
//  Architecture :
//  loucedé ──[X-Loucede-App-Key]──▶ proxy Scaleway ──[Bearer POLAR_TOKEN]──▶ api.polar.sh
//
//  Toutes les clés sensibles (POLAR_TOKEN, POLAR_ORGANIZATION_ID) vivent
//  côté Scaleway en variables d'env chiffrées. L'app n'a que :
//    - l'URL publique du proxy
//    - le secret partagé pour authentifier les requêtes (header
//      `X-Loucede-App-Key` rejeté en 401 par le proxy si absent/invalide)
//    - l'URL de checkout Polar publique
//

import Foundation

enum LicenseConfig {
    /// URL du proxy Scaleway Functions qui relaie les calls vers Polar.sh
    /// et garde POLAR_TOKEN + POLAR_ORGANIZATION_ID côté serveur.
    static let proxyBaseURL = URL(string: "https://loucedelicenseproxyejpzefpl-polar-bridge.functions.fnc.fr-par.scw.cloud")!

    /// Secret partagé loucedé ↔ proxy Scaleway, envoyé dans le header
    /// `X-Loucede-App-Key` à chaque requête. Le proxy rejette en 401 si
    /// absent ou différent.
    ///
    /// IMPORTANT : valeur shipped dans le binaire (décompilable). Si
    /// compromis, rotate côté Scaleway env var puis pousser une release.
    /// Le risque est borné : pas de fuite du token Polar (qui reste côté
    /// serveur), juste possibilité de spammer le proxy — mitigeable via
    /// rate limit Scaleway si ça arrivait jamais.
    ///
    /// Plus stocké en clair dans le code source : injecté au build depuis
    /// `Secrets.xcconfig` (gitignoré, cf. `Secrets.xcconfig.example`) →
    /// `Info.plist` (clé `LoucedeAppSecret = $(LOUCEDE_APP_SECRET)`) → lu
    /// ici via `Bundle.main`. Si la clé est absente (pas de
    /// `Secrets.xcconfig`), on retombe sur `""` que `assertConfigured()`
    /// rejette dès le premier appel réseau.
    static let appSecret: String =
        (Bundle.main.object(forInfoDictionaryKey: "LoucedeAppSecret") as? String) ?? ""

    /// URL de checkout Polar.sh publique pour le produit loucedé.
    /// Ouverte dans une WKWebView embarquée (`LicenseCheckoutView`,
    /// à venir). L'utilisateur paye, Polar génère une clé licence,
    /// puis l'utilisateur l'active depuis Réglages → Licence (soit via
    /// auto-extraction depuis la page de confirmation, soit en collant
    /// la clé manuellement).
    static let productCheckoutURL = URL(string: "https://buy.polar.sh/polar_cl_NyddnsIaqM7gVRKFinwyIhM8iHqzoRrJaZfDi2HN0SO")!

    /// Prix de la licence loucedé en euros (valeur entière). Source unique
    /// pour tout affichage de prix dans l'app — évite les littéraux prix
    /// dispersés (cf. ancien « 8€ » en dur dans `TrialExpiredOverlay`).
    static let price: Int = 10

    /// Libellé prêt à afficher (« 10€ »), dérivé de `price`.
    static var priceLabel: String { "\(price)€" }

    /// Détection de l'achat réussi (mode A — récupération clé par email).
    /// Après paiement, Polar redirige vers une page Carrd
    /// `https://<successURLHost>/#<successURLFragment>`. La WKWebView (D.3)
    /// intercepte cette navigation via le **host** (`successURLHost`) dans
    /// `WKNavigationDelegate.decidePolicyFor` ; le fragment sert la page
    /// Carrd côté web, pas la logique Swift. Externalisés ici car le slug
    /// peut bouger sans toucher à la logique de détection — les mettre à
    /// jour ici si le slug de retour Polar change.
    static let successURLHost: String = "checkout.loucede.app"
    static let successURLFragment: String = "tcheam"

    /// Filet de sécurité côté dev : si quelqu'un oublie de remplacer
    /// `appSecret` avant de build pour la prod, on lève dès le premier
    /// appel réseau. À appeler en début de chaque méthode de
    /// `LicenseService`.
    ///
    /// Check robuste à la longueur du secret + détection d'un éventuel
    /// placeholder textuel (mots-clés du genre « REMPLACER », « TODO »,
    /// espaces…). On ne compare pas à une string magique — sinon dès
    /// qu'on remplace l'une, l'autre se désynchronise.
    static func assertConfigured() {
        let s = appSecret
        let lower = s.lowercased()
        precondition(
            s.count >= 32
                && !s.contains(" ")
                && !lower.contains("remplacer")
                && !lower.contains("todo")
                && !lower.contains("xxx"),
            "LicenseConfig.appSecret semble invalide ou non renseigné. Crée `Secrets.xcconfig` à la racine (cf. `Secrets.xcconfig.example`) avec `LOUCEDE_APP_SECRET = <openssl rand -hex 32>` (la même valeur que côté Scaleway LOUCEDE_APP_SECRET)."
        )
    }
}
