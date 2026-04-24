//
//  OpenAIService.swift
//  loucede
//
//  Service d'appel aux API IA.
//  Providers supportés : OpenAI, Anthropic, Mistral.
//  Mistral utilise une API compatible OpenAI (endpoint différent).
//

import Foundation

// MARK: - Model Specs

struct ModelSpecs: Hashable, Codable {
    let speed: Int          // 1-5
    let intelligence: Int   // 1-5
    let tokenUsage: Int     // 1-5 (plus bas = moins cher)
    let description: String

    static let `default` = ModelSpecs(speed: 3, intelligence: 3, tokenUsage: 3, description: "Modèle IA standard")
}

// MARK: - AI Model

struct AIModel: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let provider: AIProvider
    let specs: ModelSpecs

    static let allModels: [AIModel] = [
        // OpenAI
        AIModel(id: "gpt-4o", name: "GPT-4o", provider: .openai,
                specs: ModelSpecs(speed: 4, intelligence: 5, tokenUsage: 3,
                                  description: "Modèle multimodal le plus capable")),
        AIModel(id: "gpt-4o-mini", name: "GPT-4o Mini", provider: .openai,
                specs: ModelSpecs(speed: 5, intelligence: 4, tokenUsage: 5,
                                  description: "Rapide et économique")),
        AIModel(id: "gpt-4-turbo", name: "GPT-4 Turbo", provider: .openai,
                specs: ModelSpecs(speed: 3, intelligence: 5, tokenUsage: 2,
                                  description: "Large fenêtre de contexte")),
        AIModel(id: "o1-mini", name: "o1 Mini", provider: .openai,
                specs: ModelSpecs(speed: 2, intelligence: 4, tokenUsage: 2,
                                  description: "Modèle de raisonnement compact")),

        // Anthropic
        AIModel(id: "claude-opus-4-5-20251101", name: "Claude Opus 4.5", provider: .anthropic,
                specs: ModelSpecs(speed: 2, intelligence: 5, tokenUsage: 1,
                                  description: "Claude le plus avancé, raisonnement exceptionnel")),
        AIModel(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", provider: .anthropic,
                specs: ModelSpecs(speed: 4, intelligence: 5, tokenUsage: 2,
                                  description: "Excellent rapport qualité/prix")),
        // Claude 3.5 Sonnet + Haiku (20241022) ont été retirés par Anthropic en 2025.
        // Les remplacements (Claude Haiku 4.5+) devront être ajoutés ici quand
        // les IDs exacts seront confirmés — cf. backlog projet.

        // Mistral
        AIModel(id: "mistral-large-latest", name: "Mistral Large", provider: .mistral,
                specs: ModelSpecs(speed: 3, intelligence: 5, tokenUsage: 2,
                                  description: "Modèle phare de Mistral")),
        AIModel(id: "mistral-medium-latest", name: "Mistral Medium", provider: .mistral,
                specs: ModelSpecs(speed: 4, intelligence: 4, tokenUsage: 3,
                                  description: "Équilibré pour la plupart des usages")),
        AIModel(id: "mistral-small-latest", name: "Mistral Small", provider: .mistral,
                specs: ModelSpecs(speed: 5, intelligence: 3, tokenUsage: 5,
                                  description: "Rapide et abordable")),
        AIModel(id: "codestral-latest", name: "Codestral", provider: .mistral,
                specs: ModelSpecs(speed: 4, intelligence: 4, tokenUsage: 3,
                                  description: "Spécialisé pour le code")),
        AIModel(id: "ministral-8b-latest", name: "Ministral 8B", provider: .mistral,
                specs: ModelSpecs(speed: 5, intelligence: 3, tokenUsage: 5,
                                  description: "Modèle compact, très rapide")),
        AIModel(id: "ministral-3b-latest", name: "Ministral 3B", provider: .mistral,
                specs: ModelSpecs(speed: 5, intelligence: 2, tokenUsage: 5,
                                  description: "Ultra-léger pour tâches simples")),
    ]

    static func models(for provider: AIProvider) -> [AIModel] {
        allModels.filter { $0.provider == provider }
    }

    static func defaultModel(for provider: AIProvider) -> AIModel {
        models(for: provider).first ?? AIModel(id: provider.defaultModelId, name: provider.defaultModelId, provider: provider, specs: .default)
    }
}

// MARK: - AI Provider

enum AIProvider: String, CaseIterable, Codable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case mistral = "Mistral"

    var baseURL: String {
        switch self {
        case .openai:    return "https://api.openai.com/v1/chat/completions"
        case .anthropic: return "https://api.anthropic.com/v1/messages"
        case .mistral:   return "https://api.mistral.ai/v1/chat/completions"
        }
    }

    var defaultModelId: String {
        switch self {
        case .openai:    return "gpt-4o-mini"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .mistral:   return "mistral-small-latest"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .openai:    return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .mistral:   return "..."
        }
    }

    var websiteURL: String {
        switch self {
        case .openai:    return "platform.openai.com/api-keys"
        case .anthropic: return "console.anthropic.com/settings/keys"
        case .mistral:   return "console.mistral.ai/api-keys"
        }
    }

    var iconName: String {
        switch self {
        case .openai:    return "openai"
        case .anthropic: return "claude"
        case .mistral:   return "mistral"
        }
    }
}

// MARK: - AI Service

class AIService {
    static let shared = AIService()

    // MARK: - Single-shot text processing
    func processText(prompt: String, text: String, apiKey: String, provider: AIProvider, model: AIModel) async throws -> String {
        guard !apiKey.isEmpty else {
            return "Aucune clé API renseignée. Rendez-vous dans les réglages (dans la barre de menus) pour arranger ça :)"
        }

        switch provider {
        case .anthropic:
            return try await callAnthropic(prompt: prompt, text: text, apiKey: apiKey, model: model)
        case .openai, .mistral:
            return try await callOpenAICompatible(prompt: prompt, text: text, apiKey: apiKey, provider: provider, model: model)
        }
    }

    // MARK: - Multi-turn chat
    func chat(messages: [(role: String, content: String)], apiKey: String, provider: AIProvider, model: AIModel) async throws -> String {
        guard !apiKey.isEmpty else {
            return "Aucune clé API renseignée. Rendez-vous dans les réglages (dans la barre de menus) pour arranger ça :)"
        }

        switch provider {
        case .anthropic:
            return try await callAnthropicChat(messages: messages, apiKey: apiKey, model: model)
        case .openai, .mistral:
            return try await callOpenAICompatibleChat(messages: messages, apiKey: apiKey, provider: provider, model: model)
        }
    }

    // MARK: - Streaming chat
    func chatStream(
        messages: [(role: String, content: String)],
        apiKey: String,
        provider: AIProvider,
        model: AIModel,
        onChunk: @escaping (String) -> Void
    ) async throws {
        guard !apiKey.isEmpty else {
            onChunk("Aucune clé API renseignée. Rendez-vous dans les réglages (dans la barre de menus) pour arranger ça :)")
            return
        }

        switch provider {
        case .anthropic:
            try await streamAnthropicChat(messages: messages, apiKey: apiKey, model: model, onChunk: onChunk)
        case .openai, .mistral:
            try await streamOpenAICompatibleChat(messages: messages, apiKey: apiKey, provider: provider, model: model, onChunk: onChunk)
        }
    }

    // MARK: - OpenAI-compatible streaming (OpenAI + Mistral)
    private func streamOpenAICompatibleChat(
        messages: [(role: String, content: String)],
        apiKey: String,
        provider: AIProvider,
        model: AIModel,
        onChunk: @escaping (String) -> Void
    ) async throws {
        let url = URL(string: provider.baseURL)!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: String]] = [
            ["role": "system", "content": "Tu es un assistant IA utile. Sois concis et pertinent. Utilise le formatage markdown lorsque c'est approprié."]
        ]
        for message in messages {
            apiMessages.append(["role": message.role, "content": message.content])
        }

        let body: [String: Any] = [
            "model": model.id,
            "messages": apiMessages,
            "max_tokens": 4000,
            "temperature": 0.7,
            "stream": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: errorData) {
                throw AIError.apiError(errorResponse.error.message)
            }
            throw AIError.httpError(httpResponse.statusCode)
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let data = String(line.dropFirst(6))
            if data == "[DONE]" { break }
            guard let jsonData = data.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let delta = firstChoice["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }
            await MainActor.run { onChunk(content) }
        }
    }

    // MARK: - Anthropic streaming
    private func streamAnthropicChat(
        messages: [(role: String, content: String)],
        apiKey: String,
        model: AIModel,
        onChunk: @escaping (String) -> Void
    ) async throws {
        let url = URL(string: AIProvider.anthropic.baseURL)!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: String]] = []
        for message in messages {
            apiMessages.append(["role": message.role, "content": message.content])
        }

        let body: [String: Any] = [
            "model": model.id,
            "max_tokens": 4000,
            "system": "Tu es un assistant IA utile. Sois concis et pertinent. Utilise le formatage markdown lorsque c'est approprié.",
            "messages": apiMessages,
            "stream": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            if let errorResponse = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: errorData) {
                throw AIError.apiError(errorResponse.error.message)
            }
            throw AIError.httpError(httpResponse.statusCode)
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let data = String(line.dropFirst(6))
            guard let jsonData = data.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }
            let eventType = json["type"] as? String
            if eventType == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                await MainActor.run { onChunk(text) }
            }
            if eventType == "message_stop" { break }
        }
    }

    // MARK: - OpenAI-compatible chat (non-streaming)
    private func callOpenAICompatibleChat(messages: [(role: String, content: String)], apiKey: String, provider: AIProvider, model: AIModel) async throws -> String {
        let url = URL(string: provider.baseURL)!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: String]] = [
            ["role": "system", "content": "Tu es un assistant IA utile. Sois concis et pertinent. Utilise le formatage markdown lorsque c'est approprié."]
        ]
        for message in messages {
            apiMessages.append(["role": message.role, "content": message.content])
        }

        let body: [String: Any] = [
            "model": model.id,
            "messages": apiMessages,
            "max_tokens": 4000,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw AIError.apiError(errorResponse.error.message)
            }
            throw AIError.httpError(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw AIError.noContent
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Anthropic chat (non-streaming)
    private func callAnthropicChat(messages: [(role: String, content: String)], apiKey: String, model: AIModel) async throws -> String {
        let url = URL(string: AIProvider.anthropic.baseURL)!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: String]] = []
        for message in messages {
            apiMessages.append(["role": message.role, "content": message.content])
        }

        let body: [String: Any] = [
            "model": model.id,
            "max_tokens": 4000,
            "system": "Tu es un assistant IA utile. Sois concis et pertinent. Utilise le formatage markdown lorsque c'est approprié.",
            "messages": apiMessages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data) {
                throw AIError.apiError(errorResponse.error.message)
            }
            throw AIError.httpError(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let content = decoded.content.first?.text else {
            throw AIError.noContent
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - OpenAI-compatible single-shot
    private func callOpenAICompatible(prompt: String, text: String, apiKey: String, provider: AIProvider, model: AIModel) async throws -> String {
        let url = URL(string: provider.baseURL)!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model.id,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": 2000,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw AIError.apiError(errorResponse.error.message)
            }
            throw AIError.httpError(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw AIError.noContent
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Anthropic single-shot
    private func callAnthropic(prompt: String, text: String, apiKey: String, model: AIModel) async throws -> String {
        let url = URL(string: AIProvider.anthropic.baseURL)!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model.id,
            "max_tokens": 2000,
            "system": prompt,
            "messages": [
                ["role": "user", "content": text]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data) {
                throw AIError.apiError(errorResponse.error.message)
            }
            throw AIError.httpError(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let content = decoded.content.first?.text else {
            throw AIError.noContent
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Model listing (Phase 4.3)

extension AIService {
    /// Interroge `GET /v1/models` du provider pour obtenir la liste des
    /// modèles réellement disponibles avec la clé fournie. Utilisé par la
    /// vérification live dans les Réglages pour retirer les modèles
    /// hard-codés qui ne sont plus servis (ex. Claude 3.5 retirés).
    ///
    /// Retourne `nil` si :
    /// - la clé est vide,
    /// - l'appel HTTP échoue (offline, 401, 403, etc.).
    ///
    /// Côté appelant, `nil` signifie « pas d'info → conserver la liste
    /// hard-codée complète ».
    ///
    /// Phase 4.6 (2026-04-23) : Anthropic supporte aussi `GET /v1/models`
    /// (pagination cursor `first_id`/`last_id`, headers `x-api-key` +
    /// `anthropic-version`). Même format de réponse (`{"data": [...]}`),
    /// seuls les headers diffèrent. Pour l'usage loucedé (~10 modèles
    /// Claude), la première page par défaut suffit largement.
    func listAvailableModelIds(provider: AIProvider, apiKey: String) async -> Set<String>? {
        guard !apiKey.isEmpty else { return nil }

        let endpoint: String
        switch provider {
        case .openai:    endpoint = "https://api.openai.com/v1/models"
        case .mistral:   endpoint = "https://api.mistral.ai/v1/models"
        case .anthropic: endpoint = "https://api.anthropic.com/v1/models"
        }

        guard let url = URL(string: endpoint) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Auth headers : Anthropic utilise `x-api-key` + `anthropic-version`,
        // OpenAI et Mistral utilisent `Authorization: Bearer …`.
        if provider == .anthropic {
            request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["data"] as? [[String: Any]] else {
                return nil
            }
            let ids = models.compactMap { $0["id"] as? String }
            return Set(ids)
        } catch {
            return nil
        }
    }
}

// MARK: - Response models

struct OpenAIResponse: Codable {
    let choices: [Choice]
    struct Choice: Codable { let message: Message }
    struct Message: Codable { let content: String }
}

struct OpenAIErrorResponse: Codable {
    let error: ErrorDetail
    struct ErrorDetail: Codable { let message: String }
}

struct AnthropicResponse: Codable {
    let content: [ContentBlock]
    struct ContentBlock: Codable { let text: String }
}

struct AnthropicErrorResponse: Codable {
    let error: ErrorDetail
    struct ErrorDetail: Codable { let message: String }
}

// MARK: - Errors

enum AIError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .invalidResponse:       return "Réponse invalide du serveur"
        case .httpError(let code):   return "Erreur HTTP : \(code)"
        case .apiError(let message): return message
        case .noContent:             return "Aucun contenu dans la réponse"
        }
    }
}
