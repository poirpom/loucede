//
//  LicenseService.swift
//  loucede
//
//  Phase 6.2 (2026-04-27) : couche réseau du système de licence Polar.sh.
//  3 méthodes async qui appellent le proxy Scaleway (cf. LicenseConfig)
//  qui relaie vers `api.polar.sh/v1/license-keys/{op}`.
//
//  La classe ne gère AUCUN état : c'est une API stateless. La gestion
//  d'état (Keychain, status, trial counter) est dans `LicenseManager`.
//

import Foundation

// MARK: - Date formatters (file-level, nonisolated)

/// Formatters partagés au niveau fichier pour être accessibles depuis le
/// `Sendable` closure du `JSONDecoder.dateDecodingStrategy` sans warning
/// d'isolation MainActor. `ISO8601DateFormatter` est thread-safe pour la
/// lecture (formatOptions immutables après init), donc safe en concurrent.

private let iso8601WithFractions: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let iso8601Standard: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

@MainActor
final class LicenseService {
    static let shared = LicenseService()

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        // Pas de cache HTTP — les calls licence doivent toujours toucher Polar
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config)

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        // Polar peut renvoyer des dates ISO8601 avec OU sans fractions de
        // secondes. La stratégie `.iso8601` standard ne gère que sans —
        // d'où ce custom strategy qui essaie les deux formats. Les
        // formatters sont file-level (nonisolated) pour rester accessibles
        // depuis cette closure Sendable sans warning d'isolation.
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = iso8601WithFractions.date(from: str) {
                return date
            }
            if let date = iso8601Standard.date(from: str) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unparseable ISO8601 date: \(str)"
            )
        }
        self.decoder = dec
    }

    // MARK: - Public API

    /// Active une clé sur cet appareil. Le proxy injecte `organization_id`
    /// côté serveur — l'app ne l'envoie jamais.
    /// `label` = nom lisible identifiant l'appareil dans le dashboard
    /// Polar (ex. nom de la machine). Renvoie l'`id` de l'activation à
    /// stocker en Keychain pour les futures `validate` / `deactivate`.
    func activate(key: String, label: String) async throws -> PolarActivation {
        LicenseConfig.assertConfigured()
        return try await postExpectingJSON(
            path: "activate",
            body: ["key": key, "label": label]
        )
    }

    /// Vérifie qu'une clé + activation_id sont toujours valides côté
    /// Polar. Le `status` retourné peut être `"granted"` (OK),
    /// `"revoked"` (admin a coupé) ou `"disabled"` (paiement annulé,
    /// chargeback, etc.). Si la clé est expirée, c'est l'`expiresAt`
    /// qu'il faut consulter en plus du status.
    func validate(key: String, activationId: String?) async throws -> PolarValidatedLicenseKey {
        LicenseConfig.assertConfigured()
        var body: [String: String] = ["key": key]
        if let activationId {
            body["activation_id"] = activationId
        }
        return try await postExpectingJSON(path: "validate", body: body)
    }

    /// Libère un slot d'activation côté Polar. Permet à l'utilisateur
    /// d'utiliser sa licence sur un autre appareil quand il a atteint
    /// la limite (typiquement 3-5 devices/licence).
    /// Polar renvoie 204 No Content en cas de succès — pas de body.
    func deactivate(key: String, activationId: String) async throws {
        LicenseConfig.assertConfigured()
        try await postExpectingNoContent(
            path: "deactivate",
            body: ["key": key, "activation_id": activationId]
        )
    }

    // MARK: - Helpers réseau

    private func postExpectingJSON<R: Decodable>(path: String, body: [String: String]) async throws -> R {
        let request = try buildRequest(path: path, body: body)
        let (data, response) = try await sendOrThrow(request: request)
        try validateStatusCode(response, body: data)
        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            throw LicenseError.decodingFailed
        }
    }

    private func postExpectingNoContent(path: String, body: [String: String]) async throws {
        let request = try buildRequest(path: path, body: body)
        let (data, response) = try await sendOrThrow(request: request)
        try validateStatusCode(response, body: data)
    }

    private func buildRequest(path: String, body: [String: String]) throws -> URLRequest {
        let url = LicenseConfig.proxyBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(LicenseConfig.appSecret, forHTTPHeaderField: "X-Loucede-App-Key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func sendOrThrow(request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .timedOut,
                 .dataNotAllowed,
                 .internationalRoamingOff:
                throw LicenseError.networkUnavailable
            case .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed:
                throw LicenseError.proxyUnreachable
            default:
                throw LicenseError.unknown(error.localizedDescription)
            }
        } catch {
            throw LicenseError.unknown(error.localizedDescription)
        }
    }

    /// Mappe le status code HTTP vers une `LicenseError` typée.
    /// 200 et 204 sont des succès. Pour les autres codes, on tente de
    /// lire le détail Polar dans le body pour faciliter le debug.
    private func validateStatusCode(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.unknown("Réponse non-HTTP")
        }
        switch http.statusCode {
        case 200, 204:
            return
        case 401:
            // Le proxy a rejeté — soit le secret partagé est mauvais
            // (config dev), soit le proxy Scaleway a été redéployé avec
            // un nouveau secret et l'app n'a pas été mise à jour.
            throw LicenseError.invalidAppSecret
        case 403:
            // Polar : "Activation not supported or limit reached"
            throw LicenseError.activationLimitReached
        case 404:
            // Polar : "License key not found" — clé invalide ou inexistante
            throw LicenseError.keyNotFound
        case 422:
            // Polar : Validation error sur le body envoyé
            throw LicenseError.invalidKey
        case 502:
            // Le proxy a renvoyé 502 (Polar injoignable)
            throw LicenseError.proxyUnreachable
        case 500...599:
            throw LicenseError.serverError(http.statusCode)
        default:
            throw LicenseError.serverError(http.statusCode)
        }
    }
}

// MARK: - Réponses Polar

/// Activation d'une clé de licence sur un appareil (réponse de
/// `POST /v1/license-keys/activate`). L'`id` est ce que Polar appelle
/// l'`activation_id` dans les autres endpoints — à stocker en Keychain.
struct PolarActivation: Decodable {
    let id: String
    let licenseKeyId: String
    let label: String
    let licenseKey: PolarLicenseKey
}

/// Validation d'une clé existante (réponse de
/// `POST /v1/license-keys/validate`). Contient l'état actuel + une
/// `activation` optionnelle si on a passé un `activation_id` en input.
struct PolarValidatedLicenseKey: Decodable {
    let id: String
    let key: String
    let displayKey: String
    let status: PolarLicenseStatus
    let limitActivations: Int?
    let usage: Int
    let limitUsage: Int?
    let validations: Int
    let lastValidatedAt: Date?
    let expiresAt: Date?
    let customer: PolarCustomer?
    let activation: PolarActivationBase?
}

/// Sous-objet `license_key` retourné par `/activate` (et imbriqué dans
/// d'autres réponses).
struct PolarLicenseKey: Decodable {
    let id: String
    let key: String
    let displayKey: String
    let status: PolarLicenseStatus
    let limitActivations: Int?
    let usage: Int
    let limitUsage: Int?
    let validations: Int
    let lastValidatedAt: Date?
    let expiresAt: Date?
    let customer: PolarCustomer?
}

/// Forme courte d'une activation (sans la `license_key` parente),
/// imbriquée dans `PolarValidatedLicenseKey` quand on valide en passant
/// un `activation_id`.
struct PolarActivationBase: Decodable {
    let id: String
    let label: String?
}

/// Customer associé à la licence — email utile pour afficher dans
/// Réglages → Licence (« Activé pour faab@poirpom.com »).
struct PolarCustomer: Decodable {
    let id: String
    let email: String?
    let name: String?
}

/// Status d'une licence côté Polar. Mappe le string brut vers un enum
/// pour qu'on puisse switcher dessus côté Swift sans risque de typo.
/// `unknown` couvre les futurs status que Polar pourrait introduire
/// (forward-compat).
enum PolarLicenseStatus: String, Decodable {
    case granted
    case revoked
    case disabled
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PolarLicenseStatus(rawValue: raw) ?? .unknown
    }
}

// MARK: - Erreurs

/// Erreurs typées du système de licence. Exposées au LicenseManager
/// qui les traduit ensuite en états UI (status .revoked, message
/// d'erreur dans le formulaire d'activation, etc.).
enum LicenseError: LocalizedError, Equatable {
    /// La requête a été rejetée par Polar : clé non conforme au format
    /// (422) ou body invalide.
    case invalidKey

    /// La clé envoyée n'existe pas chez Polar (404).
    case keyNotFound

    /// La licence a atteint sa limite d'activations (403). L'utilisateur
    /// doit désactiver une autre instance ou upgrade.
    case activationLimitReached

    /// La licence a été révoquée (status `revoked`). Pas une erreur
    /// HTTP en soi — c'est le LicenseManager qui mappe ça quand le
    /// `status` du body retourné est revoked.
    case revoked

    /// Idem mais status `disabled` (paiement annulé, chargeback, etc.).
    case disabled

    /// `expiresAt < now()` — la licence a une date d'expiration
    /// dépassée. Pas un cas Polar par défaut (les achats one-shot ne
    /// sont pas censés expirer), mais protection au cas où.
    case expired

    /// Le proxy Scaleway a rejeté en 401 : le secret partagé
    /// `LicenseConfig.appSecret` ne matche pas le `LOUCEDE_APP_SECRET`
    /// côté env vars Scaleway. Probable config oubliée ou rotation
    /// côté serveur sans release de l'app.
    case invalidAppSecret

    /// Le device n'a pas de connexion (Wi-Fi off, mode avion…).
    case networkUnavailable

    /// DNS / connexion impossible vers le proxy Scaleway, ou le proxy
    /// a renvoyé 502 (Polar injoignable depuis le proxy).
    case proxyUnreachable

    /// Erreur HTTP 5xx générique non couverte.
    case serverError(Int)

    /// Le body retourné n'est pas du JSON parseable au schéma attendu.
    case decodingFailed

    /// Cas non classé — log le détail pour diagnostic.
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "Clé de licence invalide."
        case .keyNotFound:
            return "Cette clé n'existe pas."
        case .activationLimitReached:
            return "Limite d'activations atteinte. Désactive un autre appareil pour libérer un emplacement."
        case .revoked:
            return "Cette licence a été révoquée."
        case .disabled:
            return "Cette licence est désactivée."
        case .expired:
            return "Cette licence a expiré."
        case .invalidAppSecret:
            return "Configuration interne invalide. Si ça persiste, contacte le support."
        case .networkUnavailable:
            return "Pas de connexion réseau. Réessaie une fois connecté."
        case .proxyUnreachable:
            return "Service de licence injoignable. Réessaie dans un instant."
        case .serverError(let code):
            return "Erreur serveur (\(code)). Réessaie plus tard."
        case .decodingFailed:
            return "Réponse serveur incompréhensible."
        case .unknown(let detail):
            return detail
        }
    }
}
