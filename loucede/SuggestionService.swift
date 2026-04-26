//
//  SuggestionService.swift
//  loucede
//
//  Service réseau pour l'envoi de suggestions utilisateur vers le
//  webhook Zapier (Phase 6.16, 2026-04-26). Le webhook reroute vers
//  une base Notion côté admin pour traitement.
//
//  Risque connu : l'URL du webhook est publique (repo GPL v3) → spam
//  potentiel. Atténué par : (1) le bouton est license-gated (cf.
//  `LicenseManager`), (2) si spam, régénération de l'URL côté Zapier
//  + nouvelle release.
//

import Foundation

@MainActor
final class SuggestionService {
    static let shared = SuggestionService()

    /// URL du webhook Zapier qui forward vers la Notion admin.
    private let webhookURL = URL(string: "https://hooks.zapier.com/hooks/catch/2601524/uv27zmx/")!

    /// Erreur typée pour distinguer les cas d'échec côté UI.
    enum SuggestionError: LocalizedError {
        case networkUnavailable
        case serverError(Int)
        case encodingFailed
        case unknown(Error)

        var errorDescription: String? {
            switch self {
            case .networkUnavailable: return "Réseau indisponible"
            case .serverError(let code): return "Erreur serveur (\(code))"
            case .encodingFailed: return "Encodage du message impossible"
            case .unknown(let error): return error.localizedDescription
            }
        }
    }

    private init() {}

    /// Envoie une suggestion utilisateur au webhook. Le payload inclut
    /// version + build + platform + locale pour faciliter le tri côté
    /// admin (ex. filtrer les suggestions par version de loucedé).
    /// Throws `SuggestionError` en cas d'échec.
    func sendSuggestion(email: String, suggestion: String) async throws {
        // Métadonnées pour contextualiser la suggestion côté Notion.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let platform = "macOS \(osVersion.majorVersion).\(osVersion.minorVersion)"
        let locale = Locale.current.identifier

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let payload: [String: Any] = [
            "email": email,
            "suggestion": suggestion,
            "version": version,
            "build": build,
            "platform": platform,
            "locale": locale,
            "submittedAt": isoFormatter.string(from: Date())
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            throw SuggestionError.encodingFailed
        }

        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SuggestionError.networkUnavailable
            }
            // Zapier renvoie 200 OK ou 200 avec body `{ "status": "success" }`.
            // 4xx/5xx → erreur côté serveur (Zapier down, webhook supprimé…).
            guard (200..<300).contains(http.statusCode) else {
                throw SuggestionError.serverError(http.statusCode)
            }
        } catch let error as SuggestionError {
            throw error
        } catch let error as URLError where error.code == .notConnectedToInternet
            || error.code == .networkConnectionLost
            || error.code == .timedOut {
            throw SuggestionError.networkUnavailable
        } catch {
            throw SuggestionError.unknown(error)
        }
    }
}
