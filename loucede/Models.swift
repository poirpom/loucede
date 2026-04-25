//
//  Models.swift
//  loucede
//

import Foundation
import Combine
import Carbon.HIToolbox

// MARK: - String emoji detection (Phase 6.4, 2026-04-23)

extension String {
    /// `true` si la chaîne est composée exclusivement de scalars emoji
    /// (y compris modificateurs de teinte, variation selectors et ZWJ
    /// pour les emojis composés type famille / drapeaux régionaux).
    /// Utilisé pour distinguer un `Action.icon` emoji d'un SF Symbol
    /// legacy non migré (ex. `"text.cursor"`) afin d'afficher un
    /// placeholder gris en fallback dans la UI.
    var isEmojiOnly: Bool {
        guard !isEmpty else { return false }
        return unicodeScalars.allSatisfy { scalar in
            scalar.properties.isEmoji
                || scalar.properties.isEmojiModifier
                || scalar.properties.isEmojiModifierBase
                || scalar.value == 0x200D  // Zero-Width Joiner
                || scalar.value == 0xFE0F  // Variation Selector-16
                || (0x1F1E6...0x1F1FF).contains(scalar.value)  // Regional indicators (drapeaux)
        }
    }
}

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
    /// Position du raccourci clavier dans le popup : 0 = touche 1/&, 1 = touche 2/é, …, 9 = touche 0/à.
    /// `nil` = l'action n'a pas de raccourci rapide (accessible seulement via ↑↓↵ ou clic).
    /// La sélection se fait par keycode physique (18-29) — fonctionne en AZERTY et QWERTY.
    var slotIndex: Int?
    var actionType: ActionType

    init(id: UUID = UUID(), name: String, icon: String, prompt: String, slotIndex: Int? = nil, actionType: ActionType = .ai) {
        self.id = id
        self.name = name
        self.icon = icon
        self.prompt = prompt
        self.slotIndex = slotIndex
        self.actionType = actionType
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, icon, prompt, slotIndex, actionType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        prompt = try container.decode(String.self, forKey: .prompt)
        slotIndex = try container.decodeIfPresent(Int.self, forKey: .slotIndex)
        actionType = try container.decodeIfPresent(ActionType.self, forKey: .actionType) ?? .ai
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encode(prompt, forKey: .prompt)
        try container.encodeIfPresent(slotIndex, forKey: .slotIndex)
        try container.encode(actionType, forKey: .actionType)
    }
}

class ActionsStore: ObservableObject {
    @Published var actions: [Action] = []
    @Published var apiKeys: [AIProvider: String] = [:]
    @Published var selectedProvider: AIProvider = .openai
    @Published var selectedModelIds: [AIProvider: String] = [:]
    /// Set d'IDs de modèles retournés par `GET /v1/models` du provider. Si
    /// présent pour un provider, la Réglages UI filtre `AIModel.allModels`
    /// dessus. Absent = pas encore vérifié = on garde la liste hard-codée.
    @Published var verifiedModelIds: [AIProvider: Set<String>] = [:]
    /// Providers en cours de vérif live (spinner UI).
    @Published var verifyingProviders: Set<AIProvider> = []
    @Published var mainShortcut: String = "W"
    @Published var mainShortcutModifiers: [String] = ["^", "\u{2325}"]
    // Keycode Carbon de la touche physique. Source de vérité pour RegisterEventHotKey,
    // car les dictionnaires lettre→keycode sont QWERTY-only (cassait en AZERTY).
    // Défaut = 6 (touche "W" sur AZERTY FR, touche "Z" sur QWERTY US).
    @Published var mainShortcutKeyCode: UInt16 = 6

    private let actionsKey = "loucede_actions"
    private let apiKeysKey = "loucede_api_keys"
    private let providerKey = "loucede_provider"
    private let modelIdsKey = "loucede_model_ids"
    private let mainShortcutKey = "loucede_main_shortcut"
    private let mainShortcutModifiersKey = "loucede_main_shortcut_modifiers"
    private let mainShortcutKeyCodeKey = "loucede_main_shortcut_keycode"
    private let seed26MigrationKey = "loucede_migration_seed_26_done"
    private let iconsEmojiMigrationKey = "loucede_migration_icons_emoji_done"
    // Note : l'ancienne clé `loucede_migration_seed_27_done` (action
    // "Expliquer", Phase 2.7) n'est plus utilisée depuis la Phase 6.7 où
    // "Expliquer" a été retirée du seed. On ne supprime pas la clé
    // UserDefaults côté users (no-op défensif), on arrête juste de la poser
    // et de s'appuyer dessus.

    /// Mapping SF Symbols → emoji pour les icônes du seed (Phase 6.4).
    /// Appliqué par `migrateIconsToEmojiIfNeeded()` aux configs existantes.
    /// Toute icône non présente dans cette table sera affichée en
    /// placeholder gris (fallback UI) — l'utilisateur pourra alors
    /// rouvrir l'action et choisir un emoji dans le picker système.
    private static let sfToEmojiMapping: [String: String] = [
        "character.book.closed": "🇫🇷",
        "globe": "🇬🇧",
        "face.smiling": "😀",
        "text.cursor": "✍️",
        "text.append": "🤏",
        "bubble.left": "💬",
        "fork.knife": "🍳",
    ]

    // MARK: - Raccourcis par position (Phase 6.8d-bis, 2026-04-25)

    /// Nombre maximum d'actions qu'un utilisateur peut créer. Au-delà, il
    /// n'y a plus de touche libre dans la table `positionShortcuts` ci-dessous
    /// pour assigner un raccourci ⌘+touche unique. Cap appliqué dans
    /// `addAction` et dans la UI Réglages.
    static let maxActions = 15

    /// Mapping position dans la liste → (keycode physique Carbon, label
    /// affiché). Les 10 premiers slots utilisent la rangée de chiffres
    /// (1/& à 0/à) ; les 5 suivants la rangée des lettres AZERTY (A, Z,
    /// E, R, T).
    ///
    /// Les keycodes sont stables AZERTY ↔ QWERTY (position physique de la
    /// touche). Les labels sont AZERTY-first : sur QWERTY US, les positions
    /// 10 et 11 sont en réalité Q et W — choix volontaire, loucedé est
    /// French-first (cohérent avec le raccourci principal ⌘^⌥W qui suit
    /// déjà ce pattern).
    static let positionShortcuts: [(keyCode: UInt16, label: String)] = [
        (18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"),
        (22, "6"), (26, "7"), (28, "8"), (25, "9"), (29, "0"),
        (12, "A"), (13, "Z"), (14, "E"), (15, "R"), (17, "T"),
    ]

    /// Raccourci pour la position donnée dans la liste, ou nil si hors
    /// limites (>= 15).
    static func shortcut(forPosition position: Int) -> (keyCode: UInt16, label: String)? {
        guard positionShortcuts.indices.contains(position) else { return nil }
        return positionShortcuts[position]
    }

    /// Position d'une action dans la liste — sa position détermine son
    /// raccourci ⌘+touche. nil si l'action n'est pas (plus) dans le store.
    func position(of action: Action) -> Int? {
        actions.firstIndex { $0.id == action.id }
    }

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
            migrateLegacySeedIfNeeded()
            migrateSeed26IfNeeded()
            migrateIconsToEmojiIfNeeded()
        } else {
            actions = Self.defaultActions
            saveActions()
            // Premier lancement : le seed contient déjà les actions 2.6 et les
            // emojis 6.4 ; on pose les deux flags pour ne pas re-déclencher
            // les migrations si l'utilisateur vide sa config plus tard.
            UserDefaults.standard.set(true, forKey: seed26MigrationKey)
            UserDefaults.standard.set(true, forKey: iconsEmojiMigrationKey)
        }
    }

    /// Migration one-shot (Phase 2, 2026-04-22) : si l'utilisateur n'a que
    /// l'ancien seed unique "Corriger les fautes" (version sans slotIndex),
    /// remplace-le par les 5 nouveaux prompts FR. Très restrictif pour ne pas
    /// toucher à une config custom d'un utilisateur qui aurait *vraiment* créé
    /// un prompt de ce nom.
    private func migrateLegacySeedIfNeeded() {
        guard actions.count == 1,
              let only = actions.first,
              only.name == "Corriger les fautes",
              only.slotIndex == nil else {
            return
        }
        actions = Self.defaultActions
        saveActions()
    }

    /// Migration one-shot (Phase 2.6, 2026-04-23) : pour les utilisateurs
    /// ayant déjà une config persistée avant l'ajout des actions 2.6a/2.6b
    /// au seed :
    /// - renomme « Réponds à ce post LinkedIn » → « Commente ce post LinkedIn »
    ///   si l'action existe (évite le doublon si l'utilisateur avait créé
    ///   l'ancienne version manuellement)
    /// - ajoute « Extrais la recette » si absente, sur le premier slot libre
    /// Les actions custom de l'utilisateur ne sont pas touchées. Après
    /// exécution, le flag `seed26MigrationKey` empêche toute ré-exécution.
    private func migrateSeed26IfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seed26MigrationKey) else { return }

        var changed = false

        // a) Renommage LinkedIn (si l'ancienne existe)
        if let idx = actions.firstIndex(where: { $0.name == "Réponds à ce post LinkedIn" }) {
            actions[idx].name = "Commente ce post LinkedIn"
            changed = true
        }

        // b) Ajout recette (si absente)
        if !actions.contains(where: { $0.name == "Extrais la recette" }) {
            let usedSlots = Set(actions.compactMap { $0.slotIndex })
            let freeSlot = (0..<10).first { !usedSlots.contains($0) }
            actions.append(Action(
                name: "Extrais la recette",
                icon: "🍳",
                prompt: Self.recipeExtractionPrompt,
                slotIndex: freeSlot
            ))
            changed = true
        }

        if changed {
            saveActions()
        }
        UserDefaults.standard.set(true, forKey: seed26MigrationKey)
    }

    /// Migration one-shot (Phase 6.4, 2026-04-23) : convertit les icônes
    /// SF Symbols des actions persistées en emojis pour les 7 icônes du
    /// seed historique (table `sfToEmojiMapping`). Les icônes non-mappées
    /// (actions custom avec SF exotique) sont laissées telles quelles —
    /// la UI détectera que ce n'est pas un emoji via `isEmojiOnly` et
    /// affichera un placeholder gris. L'utilisateur pourra rouvrir
    /// l'action et choisir un emoji via le picker système.
    private func migrateIconsToEmojiIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: iconsEmojiMigrationKey) else { return }

        var changed = false
        for idx in actions.indices {
            let currentIcon = actions[idx].icon
            if let emoji = Self.sfToEmojiMapping[currentIcon] {
                actions[idx].icon = emoji
                changed = true
            }
        }

        if changed {
            saveActions()
        }
        UserDefaults.standard.set(true, forKey: iconsEmojiMigrationKey)
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

    /// Identifiant Keychain par provider — "openai", "anthropic", "mistral".
    private func keychainAccount(for provider: AIProvider) -> String {
        provider.rawValue.lowercased()
    }

    func loadApiKeys() {
        // Migration silencieuse (Phase 4.1a, 2026-04-22) : si des clés existent
        // encore dans UserDefaults (legacy), on les copie vers Keychain et on
        // vide l'entrée UserDefaults. Exécutée une seule fois car la clé est
        // supprimée juste après.
        migrateLegacyApiKeysIfNeeded()

        // Source de vérité : Keychain. Pour chaque provider, on tente une lecture.
        for provider in AIProvider.allCases {
            if let value = KeychainService.read(account: keychainAccount(for: provider)),
               !value.isEmpty {
                apiKeys[provider] = value
            }
        }
    }

    /// Migration one-shot UserDefaults → Keychain. Silencieuse, appelée à chaque
    /// `loadApiKeys()` mais no-op dès que l'entrée UserDefaults a été supprimée.
    private func migrateLegacyApiKeysIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: apiKeysKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data),
              !decoded.isEmpty else {
            return
        }
        for (key, value) in decoded {
            guard let provider = AIProvider(rawValue: key), !value.isEmpty else { continue }
            KeychainService.save(account: keychainAccount(for: provider), value: value)
        }
        // Purge définitive du stockage en clair.
        UserDefaults.standard.removeObject(forKey: apiKeysKey)
    }

    func saveApiKey(_ key: String, for provider: AIProvider? = nil) {
        let targetProvider = provider ?? selectedProvider
        apiKeys[targetProvider] = key
        let account = keychainAccount(for: targetProvider)
        if key.isEmpty {
            KeychainService.delete(account: account)
        } else {
            KeychainService.save(account: account, value: key)
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

    // MARK: - Vérification live des modèles (Phase 4.3)

    /// Interroge `GET /v1/models` du provider pour savoir quels modèles de
    /// `AIModel.allModels` sont réellement servis. Silencieuse : si la clé
    /// est vide ou l'appel échoue, `verifiedModelIds[provider]` reste nil
    /// et la UI garde la liste hard-codée complète.
    ///
    /// Si le modèle actuellement sélectionné pour ce provider n'est plus
    /// servi, bascule automatiquement vers le premier modèle disponible
    /// parmi ceux hard-codés.
    @MainActor
    func verifyAvailableModels(for provider: AIProvider) async {
        // Dédoublonne : si une vérif est déjà en cours pour ce provider, pas de doublon.
        guard !verifyingProviders.contains(provider) else { return }
        let key = apiKey(for: provider)
        guard !key.isEmpty else {
            // Pas de clé = pas de filtrage → on retire un éventuel résultat obsolète.
            verifiedModelIds.removeValue(forKey: provider)
            return
        }

        verifyingProviders.insert(provider)
        let serverIds = await AIService.shared.listAvailableModelIds(provider: provider, apiKey: key)
        verifyingProviders.remove(provider)

        guard let serverIds else {
            // Échec (offline, 401, 403…) → conserver la liste hard-codée.
            return
        }
        verifiedModelIds[provider] = serverIds

        // Auto-heal : si le modèle persisté n'est plus servi, bascule vers
        // le premier hard-codé qui l'est encore.
        let storedId = selectedModelIds[provider] ?? provider.defaultModelId
        let available = AIModel.models(for: provider).filter { serverIds.contains($0.id) }
        if !serverIds.contains(storedId), let first = available.first {
            saveModel(first.id, for: provider)
        }
    }

    func loadMainShortcut() {
        if let key = UserDefaults.standard.string(forKey: mainShortcutKey) {
            mainShortcut = key
        }
        if let mods = UserDefaults.standard.stringArray(forKey: mainShortcutModifiersKey) {
            mainShortcutModifiers = mods
        }
        // Le keycode n'était pas persisté avant ; si absent, laisse la valeur par défaut.
        let storedKeyCode = UserDefaults.standard.integer(forKey: mainShortcutKeyCodeKey)
        if storedKeyCode > 0 {
            mainShortcutKeyCode = UInt16(storedKeyCode)
        }
    }

    func saveMainShortcut() {
        UserDefaults.standard.set(mainShortcut, forKey: mainShortcutKey)
        UserDefaults.standard.set(mainShortcutModifiers, forKey: mainShortcutModifiersKey)
        UserDefaults.standard.set(Int(mainShortcutKeyCode), forKey: mainShortcutKeyCodeKey)
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

    // MARK: - Export / Import JSON (Phase 2.4)

    /// Enveloppe stable pour les fichiers d'export/import. Versionnée via `schema`
    /// pour pouvoir faire évoluer le format sans casser les anciens exports.
    struct ExportEnvelope: Codable {
        let schema: String
        let exportedAt: Date
        let actions: [Action]
    }

    /// Identifiant de schéma courant. À incrémenter si `Action` change de façon
    /// incompatible (renommage/suppression de champ obligatoire).
    static let currentExportSchema = "loucede-actions-v1"

    enum ImportStrategy {
        /// Remplace intégralement la liste actuelle par les actions importées.
        case replace
        /// Ajoute les actions importées à la fin de la liste existante.
        /// Les `id` en collision sont régénérés pour éviter les doublons.
        case append
    }

    enum ImportError: LocalizedError {
        case unsupportedSchema(String)
        case duplicateIdsInFile
        case decodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedSchema(let s):
                return "Format de fichier non reconnu : \(s). Attendu : \(ActionsStore.currentExportSchema)."
            case .duplicateIdsInFile:
                return "Le fichier contient des identifiants d'action en double."
            case .decodingFailed(let msg):
                return "Impossible de lire le fichier : \(msg)"
            }
        }
    }

    /// Sérialise toutes les actions dans un `Data` JSON prêt à écrire sur disque.
    func exportActionsData() -> Data? {
        let envelope = ExportEnvelope(
            schema: Self.currentExportSchema,
            exportedAt: Date(),
            actions: actions
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(envelope)
    }

    /// Charge un fichier JSON précédemment exporté et fusionne ou remplace la liste.
    /// Lève une `ImportError` si le schéma ne correspond pas ou si le JSON est invalide.
    func importActions(from data: Data, strategy: ImportStrategy) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope: ExportEnvelope
        do {
            envelope = try decoder.decode(ExportEnvelope.self, from: data)
        } catch {
            throw ImportError.decodingFailed(error.localizedDescription)
        }
        guard envelope.schema == Self.currentExportSchema else {
            throw ImportError.unsupportedSchema(envelope.schema)
        }
        // Validation : pas de doublons d'id dans le fichier lui-même.
        let fileIds = Set(envelope.actions.map(\.id))
        guard fileIds.count == envelope.actions.count else {
            throw ImportError.duplicateIdsInFile
        }
        switch strategy {
        case .replace:
            actions = envelope.actions
        case .append:
            // Régénère les id en collision avec l'existant pour garantir l'unicité.
            let existingIds = Set(actions.map(\.id))
            let remapped = envelope.actions.map { imported -> Action in
                var copy = imported
                if existingIds.contains(imported.id) {
                    copy.id = UUID()
                }
                return copy
            }
            actions.append(contentsOf: remapped)
        }
        saveActions()
    }

    // Prompts par défaut français (Phase 2, 2026-04-22). Chaque prompt est associé
    // à un slot clavier (0 = touche 1/&, 1 = touche 2/é, …) via son `slotIndex`.
    // Les keycodes physiques 18-29 sont mappés aux slots 0-9 dans PopoverView,
    // ce qui fonctionne identiquement en AZERTY FR et QWERTY US.
    static let defaultActions: [Action] = [
        Action(
            name: "Traduis en français",
            icon: "🇫🇷",
            prompt: """
            Tu es un traducteur professionnel. Traduis le texte suivant en français.
            Règles :
            - Détecte automatiquement la langue source
            - Adopte un français naturel et courant (ni trop littéral, ni trop libre)
            - Conserve le ton et le registre de l'original (formel, informel, technique, etc.)
            - Conserve les noms propres, marques et acronymes tels quels
            - Si un mot ou une expression n'a pas d'équivalent naturel en français, garde le terme original entre guillemets avec une courte explication entre parenthèses
            - Conserve exactement la mise en forme du texte original : titres, sous-titres, listes, citations, sauts de ligne, etc.
            - Si un passage semble incohérent avec le reste (publicité, référence hors-sujet, légende d'image), supprime-le
            - Réponds uniquement avec la traduction, sans introduction, sans commentaire, sans explication
            """,
            slotIndex: 0
        ),
        Action(
            name: "Traduis en emoji",
            icon: "😀",
            prompt: "Traduis le texte suivant en une séquence d'emojis. Veille à respecter la structure des phrases et du texte, en incluant la ponctuation. Réponds uniquement avec les emojis, sans texte, sans explication.",
            slotIndex: 1
        ),
        Action(
            name: "Corrige les fautes",
            icon: "✍️",
            prompt: """
            Tu es un correcteur professionnel. Corrige les fautes d'orthographe, de grammaire et de typographie du texte suivant.
            Règles :
            - Ne modifie pas le sens, le style ni le ton
            - Conserve exactement la mise en forme originale
            - Réponds uniquement avec le texte corrigé, sans commentaire
            """,
            slotIndex: 2
        ),
        Action(
            name: "Résume ce texte",
            icon: "🤏",
            prompt: """
            Tu es un rédacteur professionnel. Résume le texte suivant en français.
            Règles :
            - Conserve toutes les idées essentielles sans en altérer le sens
            - Vise une longueur d'environ 30% du texte original
            - Respecte la structure du texte original : titres, sous-titres, listes, etc.
            - Conserve le ton et le registre de l'original
            - Réponds uniquement avec le résumé, sans introduction, sans commentaire, sans explication
            """,
            slotIndex: 3
        ),
        Action(
            name: "Extrais la recette",
            icon: "🍳",
            prompt: recipeExtractionPrompt,
            slotIndex: 4
        ),
    ]

    /// Prompt partagé entre le seed `defaultActions` (nouveaux utilisateurs)
    /// et la migration `migrateSeed26IfNeeded()` (utilisateurs existants)
    /// pour garantir que les deux chemins produisent strictement la même
    /// action "Extrais la recette".
    static let recipeExtractionPrompt: String = """
    Tu extrais une recette de cuisine depuis le texte fourni et la restitues en français, au système métrique.
    Règles :
    - Détecte automatiquement la langue source
    - Traduis intégralement en français naturel
    - Convertis toutes les mesures au système métrique :
      - Volumes en millilitres (ml) ou litres (l)
      - Poids en grammes (g) ou kilogrammes (kg)
      - Températures en degrés Celsius (°C)
      - Tasses US (cups), cuillères à soupe/café, onces → équivalents métriques
    - Structure la sortie en Markdown avec :
      - Titre en `#`
      - `## Ingrédients` (liste à puces, quantité + unité + ingrédient)
      - `## Préparation` (liste numérotée, une étape par ligne)
      - Optionnel : `## Notes` si le texte contient astuces/variantes
    - Ignore le contenu hors-recette (publicité, anecdotes, commentaires, histoire personnelle du blogueur)
    - Réponds uniquement avec la recette structurée, sans introduction
    """
}
