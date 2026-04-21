//
//  Models.swift
//  loucede
//

import Foundation
import Combine
import Carbon.HIToolbox

// MARK: - Action Type

enum ActionType: String, Codable, CaseIterable {
    case ai = "ai"
}

// MARK: - Action

struct Action: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var icon: String
    var prompt: String
    var shortcut: String
    var shortcutModifiers: [String]
    var actionType: ActionType

    init(id: UUID = UUID(), name: String, icon: String, prompt: String, shortcut: String = "", shortcutModifiers: [String] = ["\u{2318}", "\u{21E7}"], actionType: ActionType = .ai) {
        self.id = id
        self.name = name
        self.icon = icon
        self.prompt = prompt
        self.shortcut = shortcut
        self.shortcutModifiers = shortcutModifiers
        self.actionType = actionType
    }

    /// Convert stored modifier symbols to Carbon modifier flags
    var carbonModifiers: UInt32 {
        var mods: UInt32 = 0
        for m in shortcutModifiers {
            switch m {
            case "\u{2318}": mods |= UInt32(cmdKey)
            case "\u{21E7}": mods |= UInt32(shiftKey)
            case "\u{2325}": mods |= UInt32(optionKey)
            case "^":        mods |= UInt32(controlKey)
            default: break
            }
        }
        return mods
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, icon, prompt, shortcut, shortcutModifiers, actionType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        prompt = try container.decode(String.self, forKey: .prompt)
        shortcut = try container.decodeIfPresent(String.self, forKey: .shortcut) ?? ""
        shortcutModifiers = try container.decodeIfPresent([String].self, forKey: .shortcutModifiers) ?? ["\u{2318}", "\u{21E7}"]
        actionType = try container.decodeIfPresent(ActionType.self, forKey: .actionType) ?? .ai
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(shortcut, forKey: .shortcut)
        try container.encode(shortcutModifiers, forKey: .shortcutModifiers)
        try container.encode(actionType, forKey: .actionType)
    }
}

class ActionsStore: ObservableObject {
    @Published var actions: [Action] = []
    @Published var apiKeys: [AIProvider: String] = [:]
    @Published var selectedProvider: AIProvider = .openai
    @Published var selectedModelIds: [AIProvider: String] = [:]
    @Published var mainShortcut: String = "A"
    @Published var mainShortcutModifiers: [String] = ["\u{21E7}", "\u{2325}"]

    private let actionsKey = "loucede_actions"
    private let apiKeysKey = "loucede_api_keys"
    private let providerKey = "loucede_provider"
    private let modelIdsKey = "loucede_model_ids"
    private let mainShortcutKey = "loucede_main_shortcut"
    private let mainShortcutModifiersKey = "loucede_main_shortcut_modifiers"

    static let shared = ActionsStore()

    var apiKey: String {
        apiKeys[selectedProvider] ?? ""
    }

    var selectedModelId: String {
        selectedModelIds[selectedProvider] ?? selectedProvider.defaultModelId
    }

    var selectedModel: AIModel {
        if let model = AIModel.models(for: selectedProvider).first(where: { $0.id == selectedModelId }) {
            return model
        }
        return AIModel.defaultModel(for: selectedProvider)
    }

    // V1 personal : création de prompts illimitée.
    // L'architecture de licence commerciale est prévue mais inactive en V1.
    var canCreateAction: Bool { true }

    var mainCarbonModifiers: UInt32 {
        var mods: UInt32 = 0
        for m in mainShortcutModifiers {
            switch m {
            case "\u{2318}": mods |= UInt32(cmdKey)
            case "\u{21E7}": mods |= UInt32(shiftKey)
            case "\u{2325}": mods |= UInt32(optionKey)
            case "^":        mods |= UInt32(controlKey)
            default: break
            }
        }
        return mods
    }

    init() {
        loadActions()
        loadApiKeys()
        loadProvider()
        loadModelIds()
        loadMainShortcut()
    }

    func loadActions() {
        if let data = UserDefaults.standard.data(forKey: actionsKey),
           let decoded = try? JSONDecoder().decode([Action].self, from: data),
           !decoded.isEmpty {
            actions = decoded
        } else {
            actions = Self.defaultActions
            saveActions()
        }
    }

    func saveActions() {
        if let encoded = try? JSONEncoder().encode(actions) {
            UserDefaults.standard.set(encoded, forKey: actionsKey)
        }
    }

    func clearAllActions() {
        actions = []
        saveActions()
    }

    func loadApiKeys() {
        if let data = UserDefaults.standard.data(forKey: apiKeysKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            for (key, value) in decoded {
                if let provider = AIProvider(rawValue: key) {
                    apiKeys[provider] = value
                }
            }
        }
    }

    func saveApiKey(_ key: String, for provider: AIProvider? = nil) {
        let targetProvider = provider ?? selectedProvider
        apiKeys[targetProvider] = key
        let stringKeyed = Dictionary(uniqueKeysWithValues: apiKeys.map { ($0.key.rawValue, $0.value) })
        if let encoded = try? JSONEncoder().encode(stringKeyed) {
            UserDefaults.standard.set(encoded, forKey: apiKeysKey)
        }
    }

    func apiKey(for provider: AIProvider) -> String {
        apiKeys[provider] ?? ""
    }

    func loadProvider() {
        if let providerRaw = UserDefaults.standard.string(forKey: providerKey),
           let provider = AIProvider(rawValue: providerRaw) {
            selectedProvider = provider
        }
    }

    func saveProvider(_ provider: AIProvider) {
        selectedProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: providerKey)
    }

    func loadModelIds() {
        if let data = UserDefaults.standard.data(forKey: modelIdsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            for (key, value) in decoded {
                if let provider = AIProvider(rawValue: key) {
                    selectedModelIds[provider] = value
                }
            }
        }
    }

    func saveModel(_ modelId: String, for provider: AIProvider? = nil) {
        let targetProvider = provider ?? selectedProvider
        selectedModelIds[targetProvider] = modelId
        let stringKeyed = Dictionary(uniqueKeysWithValues: selectedModelIds.map { ($0.key.rawValue, $0.value) })
        if let encoded = try? JSONEncoder().encode(stringKeyed) {
            UserDefaults.standard.set(encoded, forKey: modelIdsKey)
        }
    }

    func modelId(for provider: AIProvider) -> String {
        selectedModelIds[provider] ?? provider.defaultModelId
    }

    func loadMainShortcut() {
        if let key = UserDefaults.standard.string(forKey: mainShortcutKey) {
            mainShortcut = key
        }
        if let mods = UserDefaults.standard.stringArray(forKey: mainShortcutModifiersKey) {
            mainShortcutModifiers = mods
        }
    }

    func saveMainShortcut() {
        UserDefaults.standard.set(mainShortcut, forKey: mainShortcutKey)
        UserDefaults.standard.set(mainShortcutModifiers, forKey: mainShortcutModifiersKey)
    }

    func addAction(_ action: Action) {
        actions.append(action)
        saveActions()
    }

    func updateAction(_ action: Action) {
        if let index = actions.firstIndex(where: { $0.id == action.id }) {
            actions[index] = action
            saveActions()
        }
    }

    func deleteAction(_ action: Action) {
        actions.removeAll { $0.id == action.id }
        saveActions()
    }

    // Les prompts par défaut français seront réintroduits en Phase 2
    // avec le modèle Prompt enrichi (emoji + slot).
    static let defaultActions: [Action] = [
        Action(
            name: "Corriger les fautes",
            icon: "text.cursor",
            prompt: "Corrige les fautes d'orthographe et de grammaire du texte suivant. Réponds uniquement avec le texte corrigé, sans commentaire.",
            shortcut: ""
        )
    ]
}
