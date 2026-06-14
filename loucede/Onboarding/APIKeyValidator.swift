//
//  APIKeyValidator.swift
//  loucede
//
//  Phase R : helpers purs de détection de fournisseur et de validation
//  légère de clé API (1 token), levés verbatim de l'ancien APIKeyStep pour
//  l'écran accordéon. Aucune dépendance vue — détection par préfixe + appel
//  réseau qui throw en cas d'échec.
//

import Foundation

enum APIKeyValidator {
    /// Détection silencieuse par préfixe : `sk-ant-` → Anthropic, `sk-` →
    /// OpenAI. `nil` = format non reconnu (présumé Mistral à la validation).
    static func detectProvider(from key: String) -> AIProvider? {
        if key.hasPrefix("sk-ant-") { return .anthropic }
        if key.hasPrefix("sk-")     { return .openai }
        return nil
    }

    /// Validation légère (1 token, timeout 10 s). Throw si la clé est
    /// invalide ou si le réseau échoue.
    static func validate(_ key: String, for provider: AIProvider) async throws {
        let urlString: String
        let headers: [(String, String)]
        let body: [String: Any]

        switch provider {
        case .anthropic:
            urlString = "https://api.anthropic.com/v1/messages"
            headers = [
                ("x-api-key",          key),
                ("anthropic-version",  "2023-06-01"),
                ("Content-Type",       "application/json"),
            ]
            body = [
                "model":      "claude-haiku-4-5-20251001",
                "max_tokens": 1,
                "messages":   [["role": "user", "content": "Hi"]],
            ]
        case .openai:
            urlString = "https://api.openai.com/v1/chat/completions"
            headers = [
                ("Authorization", "Bearer \(key)"),
                ("Content-Type",  "application/json"),
            ]
            body = [
                "model":      "gpt-4o-mini",
                "max_tokens": 1,
                "messages":   [["role": "user", "content": "Hi"]],
            ]
        case .mistral:
            urlString = "https://api.mistral.ai/v1/chat/completions"
            headers = [
                ("Authorization", "Bearer \(key)"),
                ("Content-Type",  "application/json"),
            ]
            body = [
                "model":      "ministral-3b-latest",
                "max_tokens": 1,
                "messages":   [["role": "user", "content": "Hi"]],
            ]
        }

        var req = URLRequest(url: URL(string: urlString)!, timeoutInterval: 10)
        req.httpMethod = "POST"
        for (field, value) in headers { req.setValue(value, forHTTPHeaderField: field) }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
