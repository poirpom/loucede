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
    var actionType: ActionType
    /// Description courte (≤80 signes) éditée par l'utilisateur pour l'affichage
    /// dans le catalogue Modèles si l'action est publiée (`isInTemplates == true`).
    /// Si nil ou vide, le catalogue affiche les 80 premiers caractères du prompt.
    /// Visible UNIQUEMENT dans l'éditeur d'action (pas dans la popup, pas dans
    /// la sidebar liste). Correctif 2026-04-28.
    var shortDescription: String?
    /// `true` si l'utilisateur a coché « Ajouter aux Modèles » dans l'éditeur.
    /// L'action apparaît alors dans l'onglet Modèles, catégorie « Mes modèles ».
    /// Correctif 2026-04-28.
    var isInTemplates: Bool
    /// Nom du template d'origine si l'action a été ajoutée depuis l'onglet
    /// Modèles. Utilisé pour afficher la coche verte « déjà ajoutée » sur
    /// la card du template correspondant (cf. `TemplatesView.TemplateCard`).
    /// Le lien est par ORIGINE (nom du template au moment de l'ajout), pas
    /// par état actuel — donc préservé même si l'utilisateur renomme l'action,
    /// modifie son prompt ou son emoji. `nil` pour les actions du seed et
    /// pour les actions créées avant le 2026-05-08 (mini-session catalogue).
    var originTemplateName: String?

    init(id: UUID = UUID(), name: String, icon: String, prompt: String, actionType: ActionType = .ai, shortDescription: String? = nil, isInTemplates: Bool = false, originTemplateName: String? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
        self.prompt = prompt
        self.actionType = actionType
        self.shortDescription = shortDescription
        self.isInTemplates = isInTemplates
        self.originTemplateName = originTemplateName
    }

    private enum CodingKeys: String, CodingKey {
        // `slotIndex` retiré en K.0 (legacy raccourcis ⌘1-⌘N supprimés).
        // Les actions déjà sérialisées avec une clé `slotIndex` se décodent
        // sans erreur : la clé orpheline est ignorée (CodingKeys restreint).
        case id, name, icon, prompt, actionType, shortDescription, isInTemplates, originTemplateName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        prompt = try container.decode(String.self, forKey: .prompt)
        actionType = try container.decodeIfPresent(ActionType.self, forKey: .actionType) ?? .ai
        shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription)
        isInTemplates = try container.decodeIfPresent(Bool.self, forKey: .isInTemplates) ?? false
        originTemplateName = try container.decodeIfPresent(String.self, forKey: .originTemplateName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(actionType, forKey: .actionType)
        try container.encodeIfPresent(shortDescription, forKey: .shortDescription)
        try container.encode(isInTemplates, forKey: .isInTemplates)
        try container.encodeIfPresent(originTemplateName, forKey: .originTemplateName)
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
    @Published var mainShortcut: String = "&"
    @Published var mainShortcutModifiers: [String] = ["\u{2325}"]
    // Keycode Carbon de la touche physique. Source de vérité pour RegisterEventHotKey,
    // car les dictionnaires lettre→keycode sont QWERTY-only (cassait en AZERTY).
    // Défaut = 18 (touche "&" sur AZERTY FR, touche "1" sur QWERTY US — Option seul,
    // main gauche, pas de conflit avec le shortcut système Delete Word ⌃⌥W).
    // Bascule depuis ⌃⌥W (keyCode 6) le 2026-05-05 suite au conflit Delete Word
    // découvert lors du test build notarisé.
    @Published var mainShortcutKeyCode: UInt16 = 18

    private let actionsKey = "loucede_actions"
    private let apiKeysKey = "loucede_api_keys"
    private let providerKey = "loucede_provider"
    private let modelIdsKey = "loucede_model_ids"
    private let mainShortcutKey = "loucede_main_shortcut"
    private let mainShortcutModifiersKey = "loucede_main_shortcut_modifiers"
    private let mainShortcutKeyCodeKey = "loucede_main_shortcut_keycode"
    private let seed26MigrationKey = "loucede_migration_seed_26_done"
    private let iconsEmojiMigrationKey = "loucede_migration_icons_emoji_done"
    private let seed69cMigrationKey = "loucede_migration_seed_69c_done"
    private let planActionsEmojiMigrationKey = "loucede_migration_plan_actions_emoji_done"
    private let planToTodoMigrationKey = "loucede_migration_plan_to_todo_done"
    private let summarizeV2MigrationKey = "loucede_migration_summarize_v2_done"
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

    // MARK: - Cap du nombre d'actions

    /// Nombre maximum d'actions qu'un utilisateur peut créer. Cap conservé
    /// en K.0 (décision F) pour rester cohérent avec le dimensionnement
    /// actuel de la popup (≈ 740 pt pour 15 lignes sans scroll). À
    /// rediscuter en V1.x si besoin. Les raccourcis ⌘1-⌘N positionnels
    /// (ex-`positionShortcuts`, Phase 6.8d-bis) ont été supprimés en K.0 :
    /// navigation flèches + ↵ uniquement.
    static let maxActions = 15

    static let shared = ActionsStore()

    var apiKey: String {
        apiKeys[selectedProvider] ?? ""
    }

    /// `true` si le provider courant a au moins de quoi fonctionner :
    /// vérifie la PRÉSENCE d'une clé API non-vide pour `selectedProvider`.
    /// Pas d'appel réseau — uniquement une vérification de présence.
    ///
    /// Future-proof Apple Intelligence (V1.x) : une fois le provider
    /// `.appleIntelligence` ajouté à l'enum, étendre le check en
    /// `|| selectedProvider == .appleIntelligence` (la disponibilité
    /// runtime est gérée à l'intérieur du provider lui-même, pas de
    /// clé utilisateur requise).
    var hasUsableProvider: Bool {
        !apiKey.isEmpty
        // V1.x Apple Intelligence : || selectedProvider == .appleIntelligence
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
            migrateSeed26IfNeeded()
            migrateIconsToEmojiIfNeeded()
            migrateSeed69cIfNeeded()
            migratePlanActionsEmojiIfNeeded()
            migratePlanToTodoIfNeeded()
            migrateSummarizePromptV2IfNeeded()
        } else {
            actions = Self.defaultActions
            saveActions()
            // Premier lancement : le seed contient déjà la version courante
            // des prompts + les emojis 6.4 ; on pose tous les flags de
            // migration pour ne jamais re-déclencher si l'utilisateur vide
            // sa config.
            UserDefaults.standard.set(true, forKey: seed26MigrationKey)
            UserDefaults.standard.set(true, forKey: iconsEmojiMigrationKey)
            UserDefaults.standard.set(true, forKey: seed69cMigrationKey)
            UserDefaults.standard.set(true, forKey: planActionsEmojiMigrationKey)
            UserDefaults.standard.set(true, forKey: planToTodoMigrationKey)
            UserDefaults.standard.set(true, forKey: summarizeV2MigrationKey)
        }
    }

    /// Migration one-shot (Phase 2.6, 2026-04-23) : pour les utilisateurs
    /// ayant déjà une config persistée avant l'ajout des actions 2.6a/2.6b
    /// au seed :
    /// - renomme « Réponds à ce post LinkedIn » → « Commente ce post LinkedIn »
    ///   si l'action existe (évite le doublon si l'utilisateur avait créé
    ///   l'ancienne version manuellement)
    /// - ajoute « Extrais la recette de cuisine » si absente, sur le premier slot libre
    /// Les actions custom de l'utilisateur ne sont pas touchées. Après
    /// exécution, le flag `seed26MigrationKey` empêche toute ré-exécution.
    ///
    /// Phase 6.9c : on injecte directement le nom et le prompt 6.9c (les
    /// utilisateurs encore en attente de cette migration sont rarissimes —
    /// le seed26 a été shipped en avril 2026 — autant leur fournir la
    /// version courante plutôt que celle de Phase 2.6 qui sera à nouveau
    /// remigrée par `migrateSeed69cIfNeeded`).
    private func migrateSeed26IfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seed26MigrationKey) else { return }

        var changed = false

        // a) Renommage LinkedIn (si l'ancienne existe)
        if let idx = actions.firstIndex(where: { $0.name == "Réponds à ce post LinkedIn" }) {
            actions[idx].name = "Commente ce post LinkedIn"
            changed = true
        }

        // b) Ajout recette (si absente). On accepte les deux noms historiques
        // pour ne pas créer de doublon chez un utilisateur déjà migré 6.9c
        // mais qui aurait perdu son flag seed26 (cas pathologique improbable).
        let recipePresent = actions.contains { name in
            name.name == "Extrais la recette" || name.name == "Extrais la recette de cuisine"
        }
        if !recipePresent && actions.count < ActionsStore.maxActions {
            actions.append(Action(
                name: "Extrais la recette de cuisine",
                icon: "🍳",
                prompt: Self.recipeExtractionPrompt
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

    /// Migration one-shot (Phase 6.9c, 2026-04-25) — « migration douce » des
    /// prompts du seed vers leurs nouvelles versions :
    /// - Pour chaque action dont le nom ET le prompt correspondent EXACTEMENT
    ///   à la version pré-6.9c, on remplace le prompt (et le nom pour la
    ///   recette qui devient « Extrais la recette de cuisine »).
    /// - Si l'utilisateur a édité son prompt, on ne touche RIEN — le match
    ///   exact garantit qu'on ne réécrase jamais une personnalisation.
    /// - On AJOUTE « Sois concis » ✂️ à la fin de la liste si elle n'y est
    ///   pas, dans la limite des 15 actions (cap Phase 6.8d-bis).
    /// - « Traduis en emoji » et toute action custom sont préservées telles
    ///   quelles — cette action sort du seed mais reste chez ceux qui l'ont.
    private func migrateSeed69cIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seed69cMigrationKey) else { return }

        var changed = false

        // Tuples (nom à matcher, ancien prompt à matcher, nouveau nom, nouveau prompt).
        // L'icône n'est jamais touchée par la migration : si l'utilisateur a
        // changé l'icône, il la garde ; sinon l'ancienne icône (déjà l'emoji
        // post-Phase 6.4) reste cohérente avec le nouveau prompt.
        let updates: [(matchName: String, oldPrompt: String, newName: String, newPrompt: String)] = [
            ("Traduis en français", Self.legacyTranslateFrPrompt_pre69c, "Traduis en français", Self.translateFrPrompt),
            ("Résume ce texte",     Self.legacySummarizePrompt_pre69c,  "Résume ce texte",     Self.summarizePrompt),
            ("Corrige les fautes",  Self.legacyCorrectPrompt_pre69c,    "Corrige les fautes",  Self.correctPrompt),
            ("Extrais la recette",  Self.legacyRecipePrompt_pre69c,     "Extrais la recette de cuisine", Self.recipeExtractionPrompt),
        ]

        for update in updates {
            if let idx = actions.firstIndex(where: { $0.name == update.matchName && $0.prompt == update.oldPrompt }) {
                actions[idx].name = update.newName
                actions[idx].prompt = update.newPrompt
                changed = true
            }
        }

        // B.2.d-fix-1 (2026-05-18) : le bloc qui injectait « Sois concis »
        // (constante `concisePrompt`) a été retiré. L'action a été supprimée
        // du catalogue (test runtime décevant, redondante avec « Résume ce
        // texte ») — plus aucune raison de l'injecter chez les installs
        // antérieures à 6.9c. Le reste de la migration (renames + reprompt
        // des 4 actions historiques) reste actif et inchangé.

        if changed {
            saveActions()
        }
        UserDefaults.standard.set(true, forKey: seed69cMigrationKey)
    }

    /// Migration one-shot (correctif 2026-04-27) : remplace l'emoji
    /// 🗺️ par ✅ pour les actions « Génère un plan d'actions » qui ont
    /// gardé l'icône d'origine. Le modèle correspondant dans l'onglet
    /// Modèles a aussi été mis à jour (cf. `TemplatesView.swift`).
    ///
    /// Match minimal sur (name + ancienne icône) : si l'utilisateur a
    /// changé le nom OU l'icône, on ne touche pas — on suppose que
    /// c'est une personnalisation volontaire. Le prompt n'est pas pris
    /// en compte (l'icône est un visuel, pas du contenu — un user qui
    /// a customisé son prompt mais gardé l'icône d'origine bénéficie
    /// quand même de la mise à jour visuelle).
    private func migratePlanActionsEmojiIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: planActionsEmojiMigrationKey) else { return }

        var changed = false
        for idx in actions.indices {
            if actions[idx].name == "Génère un plan d'actions" && actions[idx].icon == "🗺️" {
                actions[idx].icon = "✅"
                changed = true
            }
        }

        if changed {
            saveActions()
        }
        UserDefaults.standard.set(true, forKey: planActionsEmojiMigrationKey)
    }

    /// Migration one-shot (correctif 2026-04-28) : renomme le modèle
    /// « Génère un plan d'actions » en « Génère une Todo list ». Le
    /// modèle correspondant dans `TemplatesView.swift` (seed des
    /// Modèles) a aussi été renommé.
    ///
    /// Match minimal sur le nom exact « Génère un plan d'actions ».
    /// Si l'utilisateur a customisé le nom, on ne touche pas. Le prompt
    /// et l'icône ne sont pas modifiés (l'utilisateur garde son
    /// éventuel custom). Doit tourner APRÈS `migratePlanActionsEmojiIfNeeded`
    /// pour que le match du nom fonctionne correctement (sinon les
    /// deux migrations courraient sur le même nom dans des ordres
    /// différents selon les flags déjà posés).
    private func migratePlanToTodoIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: planToTodoMigrationKey) else { return }

        var changed = false
        for idx in actions.indices {
            if actions[idx].name == "Génère un plan d'actions" {
                actions[idx].name = "Génère une Todo list"
                changed = true
            }
        }

        if changed {
            saveActions()
        }
        UserDefaults.standard.set(true, forKey: planToTodoMigrationKey)
    }

    /// Migration one-shot (correctif 2026-04-28) : remplace le prompt
    /// « Résume ce texte » version 6.9c (cap 5 pts, max 18 mots, pas
    /// d'intro/conclusion) par sa version mise à jour (cap 7 pts, max 20
    /// mots, intro/conclusion optionnelles si nécessaires).
    ///
    /// Match BIT-EXACT sur (name + ancien prompt) : si l'utilisateur a
    /// édité son prompt depuis le seed, on ne touche RIEN — l'égalité
    /// stricte garantit qu'on ne réécrase jamais une personnalisation.
    private func migrateSummarizePromptV2IfNeeded() {
        guard !UserDefaults.standard.bool(forKey: summarizeV2MigrationKey) else { return }

        var changed = false
        for idx in actions.indices {
            if actions[idx].name == "Résume ce texte" && actions[idx].prompt == Self.legacySummarizePrompt_v2 {
                actions[idx].prompt = Self.summarizePrompt
                changed = true
            }
        }

        if changed {
            saveActions()
        }
        UserDefaults.standard.set(true, forKey: summarizeV2MigrationKey)
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

    /// Réordonne une action de `sourceIndex` vers `destinationIndex` dans
    /// `actions`. Sémantique « drop BEFORE target » : l'action draggée
    /// atterrit JUSTE AU-DESSUS de la row à `destinationIndex` (avant
    /// shift). Cohérent avec l'indicateur visuel « ligne bleue au top edge
    /// de la targeted row » introduit en suivi du Point 3 (2026-05-08).
    ///
    /// Cas particulier « drop at end » : appeler avec
    /// `destinationIndex == actions.count` (= une position au-delà du
    /// dernier index valide). Le clamp interne envoie l'item à la fin de
    /// l'array post-removal.
    ///
    /// Détail de l'ajustement d'index : si `sourceIndex < destinationIndex`,
    /// après removal les indices >= sourceIndex shiftent de 1 vers le bas,
    /// donc `destinationIndex` doit aussi être décrémenté pour pointer sur
    /// la même row. Si `sourceIndex > destinationIndex`, removal n'affecte
    /// pas les indices < sourceIndex, donc destinationIndex reste valide.
    ///
    /// L'ordre étant intrinsèque à l'array Swift, l'autosave dans
    /// UserDefaults persiste le nouvel ordre sans clé supplémentaire.
    /// (K.0 : les raccourcis ⌘1-⌘N positionnels ont été supprimés —
    /// `moveAction` ne sert plus qu'à l'ordre d'affichage de la liste.)
    /// Point 3 pre-V1 (2026-05-08, ajusté en suivi pour cohérence
    /// indicateur ↔ moveAction).
    func moveAction(from sourceIndex: Int, to destinationIndex: Int) {
        guard actions.indices.contains(sourceIndex),
              destinationIndex >= 0,
              destinationIndex <= actions.count,
              sourceIndex != destinationIndex else { return }
        let action = actions.remove(at: sourceIndex)
        let adjustedDest: Int
        if sourceIndex < destinationIndex {
            adjustedDest = destinationIndex - 1
        } else {
            adjustedDest = destinationIndex
        }
        let clampedDest = min(max(adjustedDest, 0), actions.count)
        actions.insert(action, at: clampedDest)
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

    // MARK: - Export Markdown (Phase 6.13, 2026-04-25)

    /// Sérialise toutes les actions au format Markdown lisible humain.
    /// Contrairement à `exportActionsData()` (JSON, ré-importable), ce format
    /// est non ré-importable mais joliment formaté pour archivage / partage /
    /// lecture dans n'importe quel renderer Markdown (Bear, Notion, Obsidian,
    /// GitHub, TextEdit avec preview, etc.). Les prompts multi-lignes sont
    /// préservés avec leur structure originale (listes, indentations).
    func exportActionsMarkdown() -> Data? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .long
        let dateString = formatter.string(from: Date())

        var md = "# Actions loucedé\n\n"
        md += "_Exporté le \(dateString) — \(actions.count) action\(actions.count > 1 ? "s" : "")._\n\n"
        md += "---\n\n"

        for (index, action) in actions.enumerated() {
            // Titre : « 1. 🇫🇷 Traduis en français »
            let icon = action.icon.isEmojiOnly ? "\(action.icon) " : ""
            md += "## \(index + 1). \(icon)\(action.name)\n\n"

            // K.0 : ligne « Raccourci ⌘+touche » retirée de l'export
            // (raccourcis positionnels supprimés — navigation flèches + ↵).

            // Le prompt brut, ligne par ligne. Pas de bloc code (```) car
            // les prompts contiennent souvent eux-mêmes du Markdown qu'on
            // veut voir rendu (titres, listes…). On entoure d'un blockquote
            // (`> `) pour visuellement distinguer le prompt du chrome.
            md += "> "
            md += action.prompt.replacingOccurrences(of: "\n", with: "\n> ")
            md += "\n\n"

            md += "---\n\n"
        }

        return md.data(using: .utf8)
    }

    // MARK: - Prompts du seed (Phase 6.9c, 2026-04-25)

    // Réécriture complète des 4 prompts historiques + ajout de « Sois concis »
    // basée sur des templates structurés (Rôle / Tâche / Procédure / Règles /
    // Contraintes / Sortie). Plus longs mais nettement plus déterministes
    // côté LLM (tests utilisateur).

    /// Prompt « Traduis en français » — Phase 6.9c.
    static let translateFrPrompt: String = """
    Rôle : traducteur professionnel.

    Tâche : traduire le texte fourni en français.

    Procédure :
    1. Détecte automatiquement la langue source.
    2. Comprends le sens global avant de traduire.
    3. Produis une traduction fidèle, claire et naturelle en français.

    Règles de traduction :
    - Français fluide et naturel (éviter la traduction mot à mot).
    - Conserver le sens exact, le ton et le registre de l'original (formel, informel, technique, etc.).
    - Conserver les noms propres, marques, acronymes et termes techniques standard.
    - Adapter les expressions idiomatiques vers leur équivalent naturel en français.
    - Si aucun équivalent naturel n'existe, conserver le terme original entre guillemets avec une brève explication entre parenthèses.
    - Éviter les ajouts ou interprétations non présents dans le texte.

    Mise en forme :
    - Conserver strictement la structure originale : titres, sous-titres, listes, citations, paragraphes, sauts de ligne, etc.
    - Conserver l'ordre des phrases et des sections.

    Filtrage :
    - Si un passage est manifestement hors contexte (publicité, référence externe, légende d'image isolée), le supprimer.

    Sortie attendue :
    - Répondre uniquement avec la traduction.
    - Ne rien ajouter avant ou après la traduction.
    """

    /// Prompt « Résume ce texte » — Phase B.2.b-fix (2026-05-13, restauration
    /// contraintes numériques). Conserve la structure CSV (Rôle / Tâche /
    /// Procédure / Règles / Sortie attendue) mais réinjecte les contraintes
    /// numériques de l'ancien prompt Phase 6.9c (10-20 mots/point, style
    /// neutre, intro/conclusion optionnelles 10-18 mots) — la version CSV
    /// pure produisait des résumés quasi aussi longs que le texte source
    /// (test runtime Faab post-B.2.b). Le CSV Notion sera réaligné sur
    /// cette version.
    ///
    /// B.2.d-fix-2 (2026-05-18) : bascule « langue source » → « français ».
    /// Le résumé est une action de PRODUCTION (nouveau livrable) → suit la
    /// règle V1 francophone « production = français par défaut » (cf.
    /// decisions.md). Tout le reste du prompt B.2.b-fix est préservé
    /// (structure + 10-20 mots/point + intro/conclusion 10-18 mots).
    /// Source : `actions-audit/modèles de prompts*.csv` (Notion → CSV).
    static let summarizePrompt: String = """
    Rôle : expert en synthèse de texte.

    Tâche : produire un résumé clair et fidèle du texte fourni, rédigé en français.

    Procédure :
    1. Identifie les idées essentielles du texte.
    2. Hiérarchise les informations par importance.
    3. Reformule de manière concise et synthétique.

    Règles :
    - Produire un résumé de 3 à 7 points clés sous forme de liste à puces.
    - 1 idée principale par point, 10 à 20 mots maximum par point.
    - Style neutre et informatif.
    - Préserver le sens exact des idées originales (ne pas inventer, ne pas interpréter).
    - Conserver le ton et le registre du texte (factuel, opinion, narratif, etc.).
    - Ne pas reproduire l'introduction ou la conclusion du texte original telles quelles.
    - Si nécessaire à la compréhension, une courte introduction et une conclusion de 10 à 18 mots chacune peuvent encadrer la liste.
    - Rédiger le résumé en français, quelle que soit la langue du texte source.

    Sortie attendue :
    - Répondre uniquement avec le résumé (liste à puces, éventuellement encadrée d'une intro/conclusion courte conformément aux règles).
    - Ne rien ajouter d'autre avant ou après.
    """

    /// Prompt « Corrige les fautes » — Phase B.2.b (2026-05-13, version CSV).
    /// Reseed brutal accepté : remplace la version Phase 6.9c. Plus concis et
    /// plus respectueux des choix stylistiques volontaires de l'auteur
    /// (répétitions, néologismes, oralité).
    /// Source : `actions-audit/modèles de prompts*.csv` (Notion → CSV).
    static let correctPrompt: String = """
    Rôle : correcteur professionnel.

    Tâche : corriger toutes les fautes du texte fourni sans en modifier le sens ni le style, dans la même langue que le texte original.

    Procédure :
    1. Identifier toutes les fautes d'orthographe, de grammaire, de conjugaison et de typographie.
    2. Corriger chaque faute en préservant strictement le sens et le ton du texte.
    3. Ne pas reformuler les tournures correctes, même si elles te paraissent imparfaites.

    Règles :
    - Corriger uniquement les fautes avérées (orthographe, grammaire, conjugaison, accord, typographie).
    - Préserver le style, le ton et le registre de l'auteur.
    - Préserver la structure du texte (paragraphes, listes, ponctuation expressive, etc.).
    - Conserver les choix stylistiques volontaires (répétitions, phrases courtes, néologismes, oralité, etc.).
    - Ne pas ajouter, ne pas supprimer, ne pas reformuler.

    Sortie attendue :
    - Répondre uniquement avec le texte corrigé.
    - Pas d'introduction, pas de commentaire, pas de liste des corrections effectuées.
    """

    /// Prompt « Améliore le style » — Phase B.2.b (2026-05-13, nouvelle action
    /// Top 5 V1). Cohabitation logique avec `correctPrompt` : correction des
    /// fautes vs amélioration stylistique sans toucher au sens.
    /// Source : `actions-audit/modèles de prompts*.csv` (Notion → CSV).
    static let improveStylePrompt: String = """
    Rôle : éditeur littéraire.

    Tâche : améliorer le style du texte fourni pour le rendre plus fluide et agréable à lire, dans la même langue que le texte original.

    Procédure :
    1. Identifier les lourdeurs, répétitions et transitions maladroites.
    2. Reformuler ces passages avec des tournures plus élégantes.
    3. Préserver strictement le sens, les idées et les informations du texte original.

    Règles :
    - Améliorer la fluidité des phrases et la qualité des transitions entre paragraphes.
    - Réduire les répétitions de mots et les lourdeurs syntaxiques.
    - Préserver le ton et le registre de l'auteur (formel, informel, technique, etc.).
    - Préserver la structure du texte (paragraphes, listes, etc.).
    - Ne pas modifier le sens, ne pas ajouter d'informations, ne pas supprimer d'idées.
    - Ne pas rallonger ni raccourcir significativement le texte.

    Sortie attendue :
    - Répondre uniquement avec la version améliorée du texte.
    - Pas d'introduction, pas de commentaire.
    """

    /// Prompt « Extrais la recette de cuisine » — Phase 6.9c (renomme l'ancienne
    /// « Extrais la recette »). Partagé entre le seed et la migration douce.
    static let recipeExtractionPrompt: String = """
    Rôle : expert en extraction et normalisation de recettes de cuisine.

    Tâche : extraire et reformater une recette de cuisine à partir du texte fourni, puis la présenter en français clair et standardisé.

    Procédure :
    1. Identifier automatiquement la langue source.
    2. Isoler uniquement le contenu utile à la recette (ingrédients, étapes, astuces culinaires).
    3. Traduire en français naturel si nécessaire.
    4. Reformater la recette de manière structurée et cohérente.

    Normalisation obligatoire :
    - Convertir toutes les unités au système métrique :
      - Poids → grammes (g) ou kilogrammes (kg)
      - Volume → millilitres (ml) ou litres (l)
      - Températures → degrés Celsius (°C)
      - Tasses (cups), cuillères, onces → équivalents métriques précis ou estimés cohérents
    - Uniformiser les quantités (éviter les approximations multiples)

    Filtrage du contenu :
    - Supprimer tout contenu non essentiel à la recette :
      anecdotes, histoire personnelle, publicité, commentaires, digressions.
    - Ne conserver que ce qui est utile à la réalisation du plat.

    Structure de sortie (Markdown obligatoire) :

    # [Nom de la recette]

    ## Ingrédients
    - Liste à puces
    - Format : quantité + unité + ingrédient

    ## Préparation
    1. Étape claire et actionnable
    2. Une seule action principale par étape
    3. Ordre chronologique respecté

    ## Notes (optionnel)
    - Astuces
    - Variantes
    - Conseils de cuisson ou de conservation

    Règles finales :
    - Traduction fluide et naturelle en français
    - Aucune information ajoutée inventée
    - Aucune explication ou commentaire hors recette
    - Répondre uniquement avec la recette structurée
    """

    // Prompt « Sois concis » (constante `concisePrompt`) supprimé en
    // B.2.d-fix-1 (2026-05-18) : action retirée du catalogue (test runtime
    // décevant, redondante avec « Résume ce texte »). Le bloc de migration
    // 6.9c qui l'injectait a aussi été retiré (cf. migrateSeed69cIfNeeded).

    /// Prompt « Génère une Todo list » — Phase B.2.b (2026-05-13, nouvelle
    /// action Top 5 V1). Structure des notes brutes en phases + cases à
    /// cocher Markdown. Rentre dans la catégorie « Structurer » côté UI
    /// catalogue, mais le seed des actions par défaut ne porte pas de
    /// catégorie (Action n'a pas ce champ — la catégorisation est dans
    /// `promptSuggestions` de TemplatesView.swift).
    ///
    /// B.2.d-fix-2 (2026-05-18) : bascule « langue source » → « français »
    /// (action de PRODUCTION, règle V1 francophone — cf. decisions.md) +
    /// clauses anti-backticks (le modèle encapsulait la sortie dans un
    /// bloc de code ```...``` au lieu d'un rendu Markdown direct).
    /// Source : `actions-audit/modèles de prompts*.csv` (Notion → CSV).
    static let todoListPrompt: String = """
    Rôle : expert en gestion de projet et en organisation.

    Tâche : transformer le texte fourni — qui peut être des notes brutes, désorganisées ou incomplètes — en un plan d'actions structuré et progressif, rédigé en français.

    Procédure :
    1. Identifier les actions, tâches et objectifs mentionnés dans le texte.
    2. Regrouper les tâches similaires en phases logiques.
    3. Ordonner les phases dans une progression cohérente.
    4. Formaliser le plan en Markdown avec cases à cocher.

    Règles :
    - Organiser les actions en phases logiques et séquentielles, chacune avec un titre clair en Markdown (## Phase 1 — Nom, etc.).
    - Sous chaque phase, lister les tâches sous forme de cases à cocher Markdown (- [ ] Tâche).
    - Si une phase comporte des risques, prérequis ou points d'attention, les ajouter sous un intitulé ⚠️ Points d'attention en liste à puces.
    - Regrouper les tâches similaires dans la même phase, même si elles apparaissent éparpillées dans le texte.
    - Ne supprimer aucune information utile du texte original.
    - Si une information est ambiguë, formuler la tâche correspondante avec un ? en fin de ligne pour signaler qu'une clarification est nécessaire.
    - Rédiger la sortie en français, quelle que soit la langue du texte source.
    - Rédiger directement en Markdown brut, sans encapsuler la réponse dans un bloc de code ```...```.

    Sortie attendue :
    - Répondre uniquement avec le plan en Markdown.
    - Réponds avec le contenu Markdown directement, pas de délimiteurs ```...``` ni de mention de format de code.
    - Pas d'introduction, pas de commentaire.
    """

    // MARK: - Anciens prompts (référentiels pour la migration douce 6.9c)
    //
    // Copies BIT-EXACT des prompts livrés entre Phase 2 et Phase 6.9b.
    // Servent à détecter si l'utilisateur a édité son action depuis le seed
    // initial : si `action.prompt == legacyXxx_pre69c`, on sait que c'est
    // l'original et on peut remplacer par la nouvelle version sans risquer
    // d'écraser une personnalisation. NE PAS modifier ces strings, sinon
    // la migration ne matchera plus chez les utilisateurs existants.

    fileprivate static let legacyTranslateFrPrompt_pre69c: String = """
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
    """

    fileprivate static let legacySummarizePrompt_pre69c: String = """
    Tu es un rédacteur professionnel. Résume le texte suivant en français.
    Règles :
    - Conserve toutes les idées essentielles sans en altérer le sens
    - Vise une longueur d'environ 30% du texte original
    - Respecte la structure du texte original : titres, sous-titres, listes, etc.
    - Conserve le ton et le registre de l'original
    - Réponds uniquement avec le résumé, sans introduction, sans commentaire, sans explication
    """

    /// Version 6.9c du prompt « Résume ce texte », snapshot BIT-EXACT pris
    /// avant la mise à jour 2026-04-28 (cap 5 points + max 18 mots + pas
    /// d'intro/conclusion). Référencée par `migrateSummarizePromptV2IfNeeded`
    /// pour propager la nouvelle version aux utilisateurs existants qui
    /// ont gardé le prompt seed non-modifié. NE PAS modifier — sinon la
    /// migration ne matchera plus.
    fileprivate static let legacySummarizePrompt_v2: String = """
    Ta tâche : extraire uniquement les idées essentielles du texte.

    Instructions :
    1. Identifie les concepts principaux du texte.
    2. Supprime les exemples, anecdotes, répétitions et détails secondaires.
    3. Reformule les idées de façon claire et concise.

    Contraintes strictes :
    - 3 à 5 points maximum
    - 1 idée principale par point
    - 10 à 18 mots maximum par point
    - Style neutre et informatif
    - Pas d'introduction ni de conclusion

    Format de sortie :
    - Liste à puces uniquement

    Vérification avant réponse :
    - Chaque point doit représenter une idée essentielle du texte.
    - Supprimer tout point redondant ou secondaire.
    """

    fileprivate static let legacyCorrectPrompt_pre69c: String = """
    Tu es un correcteur professionnel. Corrige les fautes d'orthographe, de grammaire et de typographie du texte suivant.
    Règles :
    - Ne modifie pas le sens, le style ni le ton
    - Conserve exactement la mise en forme originale
    - Réponds uniquement avec le texte corrigé, sans commentaire
    """

    fileprivate static let legacyRecipePrompt_pre69c: String = """
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

    // MARK: - Seed des nouveaux utilisateurs (Phase B.2.c, 2026-05-13)

    /// 5 actions installées au premier lancement, dans l'ordre. La position
    /// dans le tableau = ordre d'affichage dans la popup. (K.0 : les
    /// raccourcis ⌘1-⌘N positionnels et le champ `slotIndex` ont été
    /// supprimés — navigation flèches + ↵ uniquement.)
    ///
    /// Phase B.2.c (2026-05-13) — refonte Top 5 V1 :
    /// - Sortent du seed (restent au catalogue Modèles via TemplatesView) :
    ///   « Extrais la recette de cuisine » 🍳, « Sois concis » ✂️ (→ « Raccourcis »
    ///   en B.2.d).
    /// - Entrent dans le seed (déjà au catalogue, montent au seed) :
    ///   « Améliore le style » ✨, « Génère une Todo list » ✅.
    /// - Ordre : Résume monte en ⌘1, Traduis FR descend en ⌘4.
    ///
    /// Reseed brutal accepté : les installs existantes conservent leur tableau
    /// d'actions stocké en UserDefaults. Seuls les nouveaux installs (ou
    /// `actions.isEmpty` après reset) reçoivent ce Top 5.
    static let defaultActions: [Action] = [
        Action(
            name: "Résume ce texte",
            icon: "🤏",
            prompt: summarizePrompt
        ),
        Action(
            name: "Corrige les fautes",
            icon: "✍️",
            prompt: correctPrompt
        ),
        Action(
            name: "Améliore le style",
            icon: "✨",
            prompt: improveStylePrompt
        ),
        Action(
            name: "Traduis en français",
            icon: "🇫🇷",
            prompt: translateFrPrompt
        ),
        Action(
            name: "Génère une Todo list",
            icon: "✅",
            prompt: todoListPrompt
        ),
    ]
}
