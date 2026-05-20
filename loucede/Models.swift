//
//  Models.swift
//  loucede
//

import Foundation
import Combine
import Carbon.HIToolbox
import SwiftUI  // K.unify.1 : PromptCategory utilise Color (déplacé depuis TemplatesView)

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

// MARK: - PromptCategory (K.unify.1 — déplacé depuis TemplatesView.swift)

/// Phase 6.12 (2026-04-25) : refonte complète des catégories. Anglais
/// generic-coding → catégories français orientées texte. Ordre figé
/// (Traduire, Analyser, Extraire, Transformer, Structurer, Proposer) imposé
/// par l'utilisateur — `CaseIterable` itère dans l'ordre de déclaration, donc
/// l'ordre des `case` ci-dessous est la source de vérité pour la UI.
///
/// Phase B.2.a (2026-05-13) : ajout de `.extract` (« Extraire ») entre
/// `.analyze` et `.transform` pour accueillir les modèles d'extraction
/// (recette, données structurées, entités) du nouveau catalogue 25 actions.
///
/// K.unify.1 (2026-05-20) : enum déplacé de `TemplatesView.swift` vers
/// `Models.swift` car `Action` l'utilise désormais (`category` field).
enum PromptCategory: String, CaseIterable, Codable {
    case translate = "Traduire"
    case analyze = "Analyser"
    case extract = "Extraire"
    case transform = "Transformer"
    case structure = "Structurer"
    case propose = "Proposer"
    /// DEPRECATED — case unused since K.unify.2 (2026-05-20). Le concept
    /// « Mes modèles » (publication user → catalogue) a disparu avec la
    /// refonte unifiée Actions/Modèles. Conservé dans l'enum pour ne pas
    /// casser les `switch` exhaustifs (icon/color) et le décodage Codable
    /// de valeurs historiques. Évaluer suppression post-V1.
    case custom = "Mes modèles"

    /// Icône SF Symbol associée — pas affichée dans `TemplateCard` (qui
    /// montre désormais l'emoji du modèle Phase 6.12), mais conservée pour
    /// future use éventuel (ex. pill avec icône, navigation latérale).
    var icon: String {
        switch self {
        case .translate: return "globe"
        case .analyze:   return "chart.bar.xaxis"
        case .extract:   return "doc.text.magnifyingglass"
        case .transform: return "arrow.triangle.2.circlepath"
        case .structure: return "list.bullet.rectangle"
        case .propose:   return "lightbulb"
        case .custom:    return "person.crop.circle"
        }
    }

    /// Couleur d'accent par catégorie. Palette douce, mappée 1-pour-1 sur
    /// les anciennes couleurs pour ne pas tout chambouler visuellement.
    var color: Color {
        switch self {
        case .translate: return Color(red: 0.45, green: 0.55, blue: 0.70) // Soft slate blue
        case .analyze:   return Color(red: 0.60, green: 0.52, blue: 0.58) // Dusty rose
        case .extract:   return Color(red: 0.65, green: 0.55, blue: 0.40) // Ambre/cuivre (Phase B.2.a, validé Faab) — distinct de transform (sage) et analyze (rose)
        case .transform: return Color(red: 0.50, green: 0.60, blue: 0.55) // Sage green
        case .structure: return Color(red: 0.55, green: 0.50, blue: 0.65) // Muted lavender
        case .propose:   return Color(red: 0.65, green: 0.55, blue: 0.50) // Warm taupe
        case .custom:    return Color(red: 0.40, green: 0.45, blue: 0.55) // Cool charcoal — neutre, distinct des 5 catégories
        }
    }
}

// MARK: - Action

struct Action: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var icon: String
    var prompt: String
    var actionType: ActionType
    /// Description courte (≤80 signes) reprise du seed `defaultActions`
    /// (K.unify.1) ou éditée par l'utilisateur. Visible dans l'éditeur
    /// d'action ; en K.unify.3 pourra alimenter la popup principale.
    var shortDescription: String?
    /// K.unify.2 (2026-05-20) : champ `isInTemplates` supprimé (concept
    /// « Mes modèles » caduque avec le modèle unifié). Les Codable existants
    /// avec une clé `isInTemplates` se décodent sans erreur (clé orpheline
    /// ignorée par CodingKeys restreint).
    /// Nom du template d'origine si l'action a été ajoutée depuis l'onglet
    /// Modèles. Utilisé pour afficher la coche verte « déjà ajoutée » sur
    /// la card du template correspondant (cf. `TemplatesView.TemplateCard`).
    /// Le lien est par ORIGINE (nom du template au moment de l'ajout), pas
    /// par état actuel — donc préservé même si l'utilisateur renomme l'action,
    /// modifie son prompt ou son emoji. `nil` pour les actions du seed et
    /// pour les actions créées avant le 2026-05-08 (mini-session catalogue).
    var originTemplateName: String?

    // MARK: - K.unify.1 (2026-05-20) — modèle unifié Actions/Modèles/Favoris

    /// Action mise en avant en haut de la popup principale. Les 5 actions
    /// du Top V1 sont `isFavorite = true` dans `defaultActions`. Champ
    /// piloté par l'utilisateur (drag-n-drop favoris en K.unify.2).
    var isFavorite: Bool
    /// Action masquée de la popup principale. Reste visible dans Réglages
    /// (filtre « Masquées ») pour réactivation. Toggle par l'utilisateur
    /// en K.unify.2.
    var isHidden: Bool
    /// Ordre d'affichage personnalisé (drag-n-drop K.unify.2). Initialisé
    /// à l'index dans `defaultActions` pour les seeds ; les actions
    /// custom existantes décodées sans `displayOrder` reçoivent `0` par
    /// défaut (le tri courant `actions.firstIndex` reste équivalent).
    var displayOrder: Int
    /// Catégorie sémantique (héritée de `PromptSuggestion`). `nil` pour
    /// les actions custom non catégorisées (créées par l'utilisateur sans
    /// classification). Les 24 seeds ont tous une catégorie.
    var category: PromptCategory?

    init(id: UUID = UUID(),
         name: String,
         icon: String,
         prompt: String,
         actionType: ActionType = .ai,
         shortDescription: String? = nil,
         originTemplateName: String? = nil,
         isFavorite: Bool = false,
         isHidden: Bool = false,
         displayOrder: Int = 0,
         category: PromptCategory? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
        self.prompt = prompt
        self.actionType = actionType
        self.shortDescription = shortDescription
        self.originTemplateName = originTemplateName
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        self.displayOrder = displayOrder
        self.category = category
    }

    private enum CodingKeys: String, CodingKey {
        // K.0 : `slotIndex` retiré (legacy raccourcis ⌘1-⌘N).
        // K.unify.1 : ajout de `isFavorite/isHidden/displayOrder/category`.
        // K.unify.2 : `isInTemplates` retiré (concept Mes modèles caduque).
        // Les actions déjà sérialisées avec ces clés orphelines se décodent
        // sans erreur (CodingKeys restreint → clé ignorée).
        case id, name, icon, prompt, actionType, shortDescription, originTemplateName
        case isFavorite, isHidden, displayOrder, category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        prompt = try container.decode(String.self, forKey: .prompt)
        actionType = try container.decodeIfPresent(ActionType.self, forKey: .actionType) ?? .ai
        shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription)
        originTemplateName = try container.decodeIfPresent(String.self, forKey: .originTemplateName)
        // K.unify.1 : migration graceful des installs antérieures.
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        displayOrder = try container.decodeIfPresent(Int.self, forKey: .displayOrder) ?? 0
        category = try container.decodeIfPresent(PromptCategory.self, forKey: .category)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(actionType, forKey: .actionType)
        try container.encodeIfPresent(shortDescription, forKey: .shortDescription)
        try container.encodeIfPresent(originTemplateName, forKey: .originTemplateName)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encode(displayOrder, forKey: .displayOrder)
        try container.encodeIfPresent(category, forKey: .category)
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
    private let unify2MigrationKey = "loucede_migration_unify2_done"
    /// K.unify.2-fix-1 (2026-05-20) : flag distinct pour la passe 2
    /// (ajout des seeds manquants). `unify2MigrationKey` étant déjà posé
    /// chez les utilisateurs ayant tourné K.unify.2 initial, on ne peut
    /// pas réutiliser le même flag — sinon la passe 2 ne se déclencherait
    /// jamais chez eux.
    private let unify2SeedsAddedKey = "loucede_migration_unify2_seeds_added"
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

    // K.unify.2 (2026-05-20) : `maxActions = 15` supprimé. Le cap n'a plus
    // de sens avec le modèle unifié (favoris/catégories/filtres) — la
    // popup affichera principalement les FAVORIS (+ exploration par
    // catégorie en K.unify.3), pas la liste complète, donc le scroll d'une
    // liste >15 n'est plus un problème UX. Code de cap/compteur retiré
    // côté UI Réglages (ActionsView).

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
            migrateUnify2IfNeeded()
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
            UserDefaults.standard.set(true, forKey: unify2MigrationKey)
            UserDefaults.standard.set(true, forKey: unify2SeedsAddedKey)
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
        // K.unify.2 : cap `maxActions` supprimé, guard count retiré.
        if !recipePresent {
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

    /// Migration K.unify.2 (2026-05-20) — modèle unifié Actions/Modèles/
    /// Favoris. Deux passes :
    ///
    /// 1. **Enrichissement** : pour chaque action custom existante dont
    ///    le `name` correspond exactement à un seed `defaultActions`,
    ///    copie `category` et `isFavorite` du seed. Préserve `prompt`,
    ///    `icon`, `displayOrder`, `shortDescription` custom.
    ///
    /// 2. **Ajout des seeds manquants** (K.unify.2-fix-1) : pour chaque
    ///    seed de `defaultActions` absent de `store.actions` (match par
    ///    `name`), ajoute le seed entier. Sans cette passe, les 16-17
    ///    actions du catalogue unifié K.unify.1 (déplacées depuis
    ///    `promptSuggestions`) restaient invisibles dans Réglages →
    ///    Actions chez les utilisateurs existants qui n'avaient que les
    ///    5 Top V1 en UserDefaults.
    ///
    /// One-shot via `unify2MigrationKey`.
    private func migrateUnify2IfNeeded() {
        // Indexer les seeds par nom (lookup O(1)). Utile aux 2 passes.
        var seedByName: [String: Action] = [:]
        for seed in Self.defaultActions {
            seedByName[seed.name] = seed
        }

        var changed = false

        // Passe 1 — enrichissement des actions existantes (one-shot via
        // `unify2MigrationKey`). Copie `category` + `isFavorite` du seed
        // matché par `name`. Préserve `prompt`/`icon`/`displayOrder`/
        // `shortDescription` custom.
        if !UserDefaults.standard.bool(forKey: unify2MigrationKey) {
            for idx in actions.indices {
                guard let seed = seedByName[actions[idx].name] else { continue }
                if actions[idx].category == nil && seed.category != nil {
                    actions[idx].category = seed.category
                    changed = true
                }
                if !actions[idx].isFavorite && seed.isFavorite {
                    actions[idx].isFavorite = true
                    changed = true
                }
            }
            UserDefaults.standard.set(true, forKey: unify2MigrationKey)
        }

        // Passe 2 — ajout des seeds manquants (K.unify.2-fix-1, one-shot
        // via `unify2SeedsAddedKey`). Sans cette passe, les 16-17 actions
        // du catalogue unifié K.unify.1 (déplacées depuis
        // `promptSuggestions`) restaient invisibles chez les utilisateurs
        // qui n'avaient que les 5 Top V1 stockés en UserDefaults.
        if !UserDefaults.standard.bool(forKey: unify2SeedsAddedKey) {
            let existingNames = Set(actions.map { $0.name })
            for seed in Self.defaultActions where !existingNames.contains(seed.name) {
                // Copie complète du seed (nouvelle UUID via init implicite
                // — pas le même id que l'instance Swift `Action` du seed).
                actions.append(Action(
                    name: seed.name,
                    icon: seed.icon,
                    prompt: seed.prompt,
                    actionType: seed.actionType,
                    shortDescription: seed.shortDescription,
                    originTemplateName: nil,  // seed direct, pas dérivé
                    isFavorite: seed.isFavorite,
                    isHidden: seed.isHidden,
                    displayOrder: seed.displayOrder,
                    category: seed.category
                ))
                changed = true
            }
            UserDefaults.standard.set(true, forKey: unify2SeedsAddedKey)
        }

        if changed {
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

    // MARK: - Seed des nouveaux utilisateurs (K.unify.1, 2026-05-20)

    /// 24 actions installées au premier lancement (les 5 Top V1 + les 19
    /// modèles du catalogue). K.unify.1 unifie ce qui était auparavant
    /// `defaultActions` (5 Top V1) + `promptSuggestions` (19 autres) en
    /// une source de vérité unique.
    ///
    /// Champs structurants K.unify.1 :
    /// - `isFavorite` : `true` pour les 5 Top V1 (afficher en tête de
    ///   popup en K.unify.3) ; `false` pour les 19 autres.
    /// - `displayOrder` : 0-4 pour les Top 5 (ordre Résume / Corrige /
    ///   Améliore / Traduis FR / Génère Todo), puis 5-23 pour les 19
    ///   autres groupés par catégorie dans l'ordre de l'enum
    ///   `PromptCategory` (translate / analyze / extract / transform /
    ///   structure / propose).
    /// - `category` : héritée du `PromptSuggestion` d'origine, toujours
    ///   non-nil pour les seeds.
    /// - `shortDescription` : description courte (≤80 signes) reprise
    ///   du `PromptSuggestion` d'origine (champ analogue, fusionné).
    ///
    /// Reseed brutal accepté : les installs existantes conservent leur
    /// tableau d'actions stocké en UserDefaults (décodage graceful via
    /// `decodeIfPresent` sur les 4 nouveaux champs). Seuls les nouveaux
    /// installs (ou `actions.isEmpty` après reset) reçoivent ces 24
    /// seeds.
    static let defaultActions: [Action] = [
        Action(
            name: "Résume ce texte",
            icon: "🤏",
            prompt: ActionsStore.summarizePrompt,
            actionType: .ai,
            shortDescription: "Extraire les idées essentielles en quelques points clés",
            isFavorite: true,
            displayOrder: 0,
            category: .analyze
        ),
        Action(
            name: "Corrige les fautes",
            icon: "✍️",
            prompt: ActionsStore.correctPrompt,
            actionType: .ai,
            shortDescription: "Corriger orthographe grammaire et typographie",
            isFavorite: true,
            displayOrder: 1,
            category: .transform
        ),
        Action(
            name: "Améliore le style",
            icon: "✨",
            prompt: ActionsStore.improveStylePrompt,
            actionType: .ai,
            shortDescription: "Améliorer la fluidité sans changer le sens",
            isFavorite: true,
            displayOrder: 2,
            category: .transform
        ),
        Action(
            name: "Traduis en français",
            icon: "🇫🇷",
            prompt: ActionsStore.translateFrPrompt,
            actionType: .ai,
            shortDescription: "Traduire en français naturel et idiomatique",
            isFavorite: true,
            displayOrder: 3,
            category: .translate
        ),
        Action(
            name: "Génère une Todo list",
            icon: "✅",
            prompt: ActionsStore.todoListPrompt,
            actionType: .ai,
            shortDescription: "Structurer des notes brutes en plan d'actions",
            isFavorite: true,
            displayOrder: 4,
            category: .structure
        ),
        Action(
            name: "Traduis en anglais",
            icon: "🇬🇧",
            prompt: """
        Role: professional translator.

        Task: translate the provided text into English.

        Procedure:
        1. Automatically detect the source language.
        2. Understand the overall meaning before translating.
        3. Produce a faithful, clear and natural English translation.

        Translation rules:
        - Use natural and fluent English (avoid word-for-word translation).
        - Preserve the exact meaning, tone and register of the original (formal, informal, technical, etc.).
        - Preserve proper names, brands, acronyms and standard technical terms.
        - Adapt idiomatic expressions to natural English equivalents.
        - If no natural equivalent exists, keep the original term in quotes with a brief explanation in parentheses.
        - Do not add or omit information.

        Formatting:
        - Strictly preserve the original structure: titles, subtitles, lists, quotations, paragraphs and line breaks.
        - Keep the order of sentences and sections.

        Filtering:
        - If a passage is clearly out of context (advertising, external reference, isolated image caption), remove it.

        Expected output:
        - Reply only with the translation.
        - Do not add anything before or after the translation.
        """,
            actionType: .ai,
            shortDescription: "Traduire en anglais naturel et idiomatique",
            isFavorite: false,
            displayOrder: 5,
            category: .translate
        ),
        Action(
            name: "Traduis en espagnol",
            icon: "🇪🇸",
            prompt: """
        Rol: traductor profesional.

        Tarea: traducir el texto proporcionado al español neutro internacional.

        Procedimiento:
        1. Detecta automáticamente el idioma de origen.
        2. Comprende el sentido global del texto antes de traducir.
        3. Produce una traducción fiel, clara y natural en español neutro internacional.

        Reglas de traducción:
        - Utiliza un español neutro comprensible en todo el mundo hispanohablante.
        - Evita regionalismos propios de un país específico (España o América Latina).
        - Prioriza un vocabulario estándar ampliamente comprendido.
        - Usa el tratamiento de "tú" por defecto, salvo que el texto original requiera un registro formal.
        - Conserva el sentido exacto, el tono y el registro del texto original (formal, informal, técnico, etc.).
        - Conserva los nombres propios, marcas, acrónimos y términos técnicos estándar.
        - Adapta las expresiones idiomáticas a un equivalente natural y universal en español.
        - Si no existe un equivalente natural, conserva el término original entre comillas con una breve explicación entre paréntesis.
        - No añadas ni elimines información.

        Formato:
        - Conserva estrictamente la estructura original: títulos, subtítulos, listas, citas, párrafos y saltos de línea.
        - Mantén el orden de las frases y de las secciones.

        Salida esperada:
        - Responde únicamente con la traducción.
        - No añadas nada antes ni después de la traducción.
        """,
            actionType: .ai,
            shortDescription: "Traduire en espagnol neutre international",
            isFavorite: false,
            displayOrder: 6,
            category: .translate
        ),
        Action(
            name: "Traduis en portugais",
            icon: "🇵🇹",
            prompt: """
        Papel: tradutor profissional.

        Tarefa: traduzir o texto fornecido para português.

        Procedimento:
        1. Detecta automaticamente o idioma de origem.
        2. Compreende o sentido global antes de traduzir.
        3. Produz uma tradução fiel, natural e fluida em português.

        Regras de tradução:
        - Usar português natural e corrente (evitar tradução literal ou excessivamente livre).
        - Manter o tom, o registo e o nível de formalidade do texto original (formal, informal, técnico, etc.).
        - Preservar nomes próprios, marcas e acrónimos sem alteração.
        - Adaptar expressões idiomáticas para equivalentes naturais em português.
        - Se não existir equivalente natural, manter o termo original entre aspas com uma breve explicação entre parênteses.
        - Não acrescentar nem omitir informações.

        Formatação:
        - Manter rigorosamente a estrutura original: títulos, subtítulos, listas, citações, parágrafos e quebras de linha.
        - Respeitar a ordem do texto original.

        Saída:
        - Responder apenas com a tradução.
        - Sem introdução, sem comentários, sem explicações.
        """,
            actionType: .ai,
            shortDescription: "Traduire en portugais naturel et idiomatique",
            isFavorite: false,
            displayOrder: 7,
            category: .translate
        ),
        Action(
            name: "Traduis en allemand",
            icon: "🇩🇪",
            prompt: """
        Rolle: professioneller Übersetzer.

        Aufgabe: den bereitgestellten Text ins Deutsche übersetzen.

        Vorgehen:
        1. Erkenne automatisch die Ausgangssprache.
        2. Verstehe den Gesamtsinn, bevor du übersetzt.
        3. Erstelle eine treue, klare und natürliche deutsche Übersetzung.

        Übersetzungsregeln:
        - Verwende natürliches und flüssiges Deutsch (vermeide Wort-für-Wort-Übersetzungen).
        - Bewahre den genauen Sinn, den Ton und das Register des Originals (formell, informell, technisch, etc.).
        - Bewahre Eigennamen, Marken, Akronyme und gängige Fachbegriffe.
        - Passe idiomatische Ausdrücke an ihre natürlichen deutschen Entsprechungen an.
        - Wenn keine natürliche Entsprechung existiert, behalte den Originalbegriff in Anführungszeichen mit einer kurzen Erklärung in Klammern.
        - Füge nichts hinzu, lasse nichts aus.

        Formatierung:
        - Bewahre strikt die ursprüngliche Struktur: Titel, Untertitel, Listen, Zitate, Absätze und Zeilenumbrüche.
        - Behalte die Reihenfolge der Sätze und Abschnitte bei.

        Ausgabe:
        - Antworte nur mit der Übersetzung.
        - Füge nichts vor oder nach der Übersetzung hinzu.
        """,
            actionType: .ai,
            shortDescription: "Traduire en allemand naturel et idiomatique",
            isFavorite: false,
            displayOrder: 8,
            category: .translate
        ),
        Action(
            name: "Traduis en italien",
            icon: "🇮🇹",
            prompt: """
        Ruolo: traduttore professionale.

        Compito: tradurre il testo fornito in italiano.

        Procedura:
        1. Rileva automaticamente la lingua di origine.
        2. Comprendi il senso globale prima di tradurre.
        3. Produci una traduzione fedele, chiara e naturale in italiano.

        Regole di traduzione:
        - Usa un italiano naturale e fluente (evita la traduzione parola per parola).
        - Mantieni il senso esatto, il tono e il registro dell'originale (formale, informale, tecnico, ecc.).
        - Conserva i nomi propri, marchi, acronimi e termini tecnici standard.
        - Adatta le espressioni idiomatiche a equivalenti naturali in italiano.
        - Se non esiste un equivalente naturale, mantieni il termine originale tra virgolette con una breve spiegazione tra parentesi.
        - Non aggiungere né omettere informazioni.

        Formattazione:
        - Mantieni rigorosamente la struttura originale: titoli, sottotitoli, elenchi, citazioni, paragrafi e a capo.
        - Rispetta l'ordine delle frasi e delle sezioni.

        Uscita:
        - Rispondi solo con la traduzione.
        - Senza introduzione, commenti o spiegazioni.
        """,
            actionType: .ai,
            shortDescription: "Traduire en italien naturel et idiomatique",
            isFavorite: false,
            displayOrder: 9,
            category: .translate
        ),
        Action(
            name: "Identifie l'idée principale",
            icon: "🎯",
            prompt: """
        Rôle : analyste de texte.

        Tâche : identifier l'idée principale du texte fourni et l'exprimer en 1 ou 2 phrases claires, dans la même langue que le texte original.

        Procédure :
        1. Lis le texte intégralement pour en saisir le sens global.
        2. Distingue l'idée centrale des idées secondaires et illustratives.
        3. Reformule l'idée principale en une à deux phrases denses.

        Règles :
        - L'idée principale est la thèse, le message ou le propos central du texte.
        - Si le texte est argumentatif : énonce la thèse défendue.
        - Si le texte est narratif : énonce le sujet principal ou la situation centrale.
        - Si le texte est informatif : énonce l'information clé.
        - Ne pas inclure d'exemples, d'illustrations ou de détails secondaires.
        - Ne pas reproduire la phrase d'ouverture du texte telle quelle.
        - Rédiger la sortie en français, quelle que soit la langue du texte source.

        Sortie attendue :
        - Répondre uniquement avec l'idée principale, en 1 ou 2 phrases.
        - Pas d'introduction, pas de commentaire, pas de liste.
        """,
            actionType: .ai,
            shortDescription: "Identifier la thèse centrale en 1 à 2 phrases",
            isFavorite: false,
            displayOrder: 10,
            category: .analyze
        ),
        Action(
            name: "Explique simplement",
            icon: "🧩",
            prompt: """
        Rôle : vulgarisateur expérimenté.

        Tâche : expliquer simplement le texte fourni pour un lecteur non-spécialiste, dans la même langue que le texte original.

        Procédure :
        1. Identifie les concepts complexes ou techniques du texte.
        2. Reformule-les avec des mots courants et des phrases courtes.
        3. Préserve les idées essentielles, élimine les détails accessoires.

        Règles :
        - Remplacer le vocabulaire technique ou complexe par des mots courants.
        - Raccourcir les phrases longues, simplifier les structures grammaticales.
        - Supprimer le jargon sans valeur ajoutée.
        - Utiliser des comparaisons ou analogies du quotidien si elles aident à comprendre.
        - Conserver toutes les idées essentielles sans les dénaturer.
        - Conserver la structure du texte (paragraphes, listes, etc.).
        - Rédiger la sortie en français, quelle que soit la langue du texte source.

        Sortie attendue :
        - Répondre uniquement avec la version vulgarisée du texte.
        - Pas d'introduction, pas de commentaire.
        """,
            actionType: .ai,
            shortDescription: "Vulgariser le texte pour un lecteur non-spécialiste",
            isFavorite: false,
            displayOrder: 11,
            category: .analyze
        ),
        Action(
            name: "Extrais la recette de cuisine",
            icon: "🍳",
            prompt: ActionsStore.recipeExtractionPrompt,
            actionType: .ai,
            shortDescription: "Extraire et reformater une recette en système métrique",
            isFavorite: false,
            displayOrder: 12,
            category: .extract
        ),
        Action(
            name: "Extrais les noms propres",
            icon: "🏷️",
            prompt: """
        Rôle : expert en extraction d'entités nommées.

        Tâche : extraire tous les noms propres du texte fourni et les regrouper par type, dans la même langue que le texte original.

        Procédure :
        1. Repère tous les noms propres : personnes, lieux, organisations.
        2. Classe chaque nom dans sa catégorie.
        3. Présente les résultats sous forme de liste structurée par type.

        Règles d'extraction :
        - **Personnes** : prénoms, noms de famille, personnages, fonctions nommées (le président Macron, etc.).
        - **Lieux** : villes, pays, régions, lieux-dits, monuments, adresses.
        - **Organisations** : entreprises, institutions, associations, marques, partis politiques.
        - Ne pas inclure les noms communs même importants (le ministre, l'entreprise).
        - Dédupliquer les occurrences multiples (un même nom n'apparaît qu'une fois par catégorie).
        - Rédiger la sortie en français, quelle que soit la langue du texte source.

        Format de sortie (Markdown) :

        ## Personnes
        - Nom 1
        - Nom 2

        ## Lieux
        - Lieu 1
        - Lieu 2

        ## Organisations
        - Organisation 1
        - Organisation 2

        Cas particuliers :
        - Si une catégorie est vide, l'omettre du résultat.
        - Si aucun nom propre n'est trouvé, répondre uniquement : "Aucun nom propre identifié dans le texte."

        Sortie attendue :
        - Répondre uniquement avec la liste structurée par catégorie.
        - Pas d'introduction, pas de commentaire.
        """,
            actionType: .ai,
            shortDescription: "Lister les personnes lieux et organisations mentionnés",
            isFavorite: false,
            displayOrder: 13,
            category: .extract
        ),
        Action(
            name: "Extrais les dates",
            icon: "📅",
            prompt: """
        Rôle : expert en extraction d'information.

        Tâche : extraire toutes les dates mentionnées dans le texte fourni avec leur contexte, dans la même langue que le texte original.

        Procédure :
        1. Repère toutes les références temporelles précises du texte (dates, mois, années, périodes).
        2. Pour chaque date, identifie l'événement ou le contexte associé.
        3. Présente les résultats sous forme de liste structurée.

        Règles d'extraction :
        - Inclure les dates explicites (15 mars 2024, mars 2024, 2024).
        - Inclure les dates relatives explicites (la semaine dernière, dans 3 mois) si le texte donne une date de référence.
        - Ignorer les références temporelles vagues sans valeur informative (un jour, parfois, autrefois).
        - Présenter les dates au format le plus précis disponible.
        - Rédiger la sortie en français, quelle que soit la langue du texte source.

        Format de sortie (Markdown) :
        - Liste à puces, une ligne par date.
        - Format : **[date]** — [contexte ou événement associé].
        - Ordre chronologique ascendant si possible.

        Cas particulier :
        - Si aucune date n'est trouvée dans le texte, répondre uniquement : "Aucune date identifiée dans le texte."

        Sortie attendue :
        - Répondre uniquement avec la liste des dates et leur contexte.
        - Pas d'introduction, pas de commentaire.
        """,
            actionType: .ai,
            shortDescription: "Lister toutes les dates mentionnées avec leur contexte",
            isFavorite: false,
            displayOrder: 14,
            category: .extract
        ),
        Action(
            name: "Reformule",
            icon: "🔄",
            prompt: """
        Rôle : éditeur expérimenté.

        Tâche : reformuler le texte fourni avec des tournures différentes en préservant strictement son sens, dans la même langue que le texte original.

        Procédure :
        1. Comprendre le sens exact de chaque phrase du texte.
        2. Reformuler chaque idée avec un vocabulaire et une syntaxe différents.
        3. Préserver le ton, le registre et la longueur globale.

        Règles :
        - Modifier les tournures de phrases, le vocabulaire et l'ordre des éléments.
        - Préserver intégralement le sens et les informations du texte.
        - Préserver le ton et le registre (formel, informel, technique, neutre, etc.).
        - Conserver une longueur équivalente (±10 %).
        - Préserver la structure du texte (paragraphes, listes, etc.).
        - Ne pas ajouter d'idées, ne pas supprimer d'informations.
        - Conserver la langue d'origine du texte source.

        Sortie attendue :
        - Répondre uniquement avec la version reformulée.
        - Pas d'introduction, pas de commentaire.
        """,
            actionType: .ai,
            shortDescription: "Paraphraser en préservant le sens et le registre",
            isFavorite: false,
            displayOrder: 15,
            category: .transform
        ),
        Action(
            name: "Rends plus formel",
            icon: "🕴️",
            prompt: """
        Rôle : éditeur professionnel.

        Tâche : réécrire le texte fourni dans un registre formel et soigné, dans la même langue que le texte original.

        Procédure :
        1. Identifier les tournures familières, relâchées ou ambiguës.
        2. Les remplacer par des formulations soutenues et précises.
        3. Préserver strictement le sens et les informations du texte.

        Règles :
        - Adopter un registre formel, soigné et bienveillant.
        - Remplacer les tournures familières, l'argot, les contractions et les expressions relâchées.
        - Préférer les formulations complètes et précises aux raccourcis.
        - Préserver intégralement le sens et les informations du texte.
        - Préserver la structure du texte (paragraphes, listes, etc.).
        - Ne pas alourdir inutilement le texte (formel ≠ pompeux).
        - Conserver la langue d'origine du texte source.

        Sortie attendue :
        - Répondre uniquement avec la version réécrite.
        - Pas d'introduction, pas de commentaire.
        """,
            actionType: .ai,
            shortDescription: "Réécrire dans un registre formel et soigné",
            isFavorite: false,
            displayOrder: 16,
            category: .transform
        ),
        Action(
            name: "Rends plus convivial",
            icon: "😊",
            prompt: """
        Rôle : rédacteur conversationnel.

        Tâche : réécrire le texte fourni dans un registre chaleureux et accessible, dans la même langue que le texte original.

        Procédure :
        1. Identifier les tournures rigides, formelles ou distantes.
        2. Les remplacer par des formulations naturelles et engageantes.
        3. Préserver strictement le sens et les informations du texte.

        Règles :
        - Adopter un ton chaleureux, accessible et engageant.
        - Utiliser le tutoiement si pertinent dans la langue cible.
        - Remplacer les tournures rigides ou jargonnantes par des formulations simples.
        - Privilégier les phrases courtes et directes.
        - Préserver intégralement le sens et les informations du texte.
        - Préserver la structure du texte (paragraphes, listes, etc.).
        - Ne pas tomber dans le familier excessif ou l'oralité forcée.
        - Conserver la langue d'origine du texte source.

        Sortie attendue :
        - Répondre uniquement avec la version réécrite.
        - Pas d'introduction, pas de commentaire.
        """,
            actionType: .ai,
            shortDescription: "Réécrire dans un registre chaleureux et accessible",
            isFavorite: false,
            displayOrder: 17,
            category: .transform
        ),
        Action(
            name: "Réponds à cet email",
            icon: "📧",
            prompt: """
        Rôle : assistant de rédaction professionnelle.

        Tâche : rédiger une réponse appropriée à l'email fourni, dans la même langue que l'email original.

        Procédure :
        1. Identifie le ton, le registre et l'objet de l'email reçu.
        2. Détermine les points qui appellent une réponse (questions, demandes, propositions).
        3. Rédige une réponse cohérente, structurée et adaptée au contexte.

        Règles :
        - Adopter le même registre que l'email reçu (formel, informel, professionnel, amical).
        - Répondre point par point aux questions ou demandes explicites.
        - Structurer la réponse : salutation, corps, formule de politesse adaptée.
        - Rester concis et clair, éviter les longueurs inutiles.
        - Si certains points nécessitent une information manquante, formuler une question de clarification.
        - Préserver la langue de l'email original.
        - Conserver la langue d'origine du texte source.

        Cas particuliers :
        - Si l'email contient des informations sensibles ou ambiguës, signaler les points à clarifier sans inventer de réponse.
        - Si le ton est conflictuel, adopter une réponse mesurée et professionnelle.

        Sortie attendue :
        - Répondre uniquement avec le texte de l'email de réponse complet (salutation incluse, formule de politesse incluse).
        - Pas d'introduction, pas de commentaire.
        """,
            actionType: .ai,
            shortDescription: "Rédiger une réponse adaptée au contenu reçu",
            isFavorite: false,
            displayOrder: 18,
            category: .transform
        ),
        Action(
            name: "Convertis en tableau",
            icon: "📊",
            prompt: """
        Rôle : expert en structuration de données.

        Tâche : transformer les informations du texte fourni en tableau Markdown structuré, dans la même langue que le texte original.

        Procédure :
        1. Analyser le contenu pour identifier les éléments comparables.
        2. Déterminer les colonnes les plus pertinentes selon le contenu.
        3. Construire le tableau Markdown avec ces colonnes et les données extraites.

        Règles :
        - Déterminer les colonnes les plus pertinentes selon le contenu (ex. Concept / Description / Exemple, ou Critère / Avantages / Inconvénients, etc.).
        - Chaque ligne du tableau correspond à un élément, une idée ou une entrée distincte.
        - Conserver toutes les informations importantes du texte original.
        - Privilégier des en-têtes de colonnes courts et explicites.
        - Si une cellule serait vide, indiquer "—" (tiret cadratin).
        - Rédiger la sortie en français, quelle que soit la langue du texte source.
        - Rédiger directement en Markdown brut, sans encapsuler la réponse dans un bloc de code ```...```.

        Cas particulier :
        - Si le texte ne se prête pas à un tableau, répondre uniquement : "Ce texte ne peut pas être converti en tableau de manière pertinente."

        Sortie attendue :
        - Répondre uniquement avec le tableau en Markdown.
        - Réponds avec le contenu Markdown directement, pas de délimiteurs ```...``` ni de mention de format de code.
        - Pas d'introduction, pas de commentaire.
        """,
            actionType: .ai,
            shortDescription: "Transformer les informations en tableau Markdown",
            isFavorite: false,
            displayOrder: 19,
            category: .structure
        ),
        Action(
            name: "Propose un plan structuré",
            icon: "🗂️",
            prompt: """
        Rôle : expert en structuration de contenu.

        Tâche : transformer le texte fourni en plan hiérarchique numéroté, dans la même langue que le texte original.

        Procédure :
        1. Identifier les grandes idées du texte (parties principales).
        2. Identifier les idées secondaires associées à chaque grande idée.
        3. Construire un plan hiérarchique I / A / 1 / a en Markdown.

        Règles :
        - Utiliser une numérotation hiérarchique claire : I / II / III pour les parties, A / B / C pour les sous-parties, 1 / 2 / 3 pour les sous-sous-parties, a / b / c pour les détails.
        - Regrouper les idées similaires sous des parties cohérentes.
        - Les intitulés doivent être courts et explicites (5 à 10 mots maximum).
        - N'inclure que les intitulés du plan, pas le contenu détaillé du texte.
        - Utiliser le format Markdown pour la mise en forme (listes imbriquées ou numérotation manuelle).
        - Maximum 4 niveaux hiérarchiques.
        - Rédiger la sortie en français, quelle que soit la langue du texte source.
        - Rédiger directement en Markdown brut, sans encapsuler la réponse dans un bloc de code ```...```.

        Sortie attendue :
        - Répondre uniquement avec le plan hiérarchique.
        - Réponds avec le contenu Markdown directement, pas de délimiteurs ```...``` ni de mention de format de code.
        - Pas d'introduction, pas de commentaire.
        """,
            actionType: .ai,
            shortDescription: "Transformer le texte en plan hiérarchique numéroté",
            isFavorite: false,
            displayOrder: 20,
            category: .structure
        ),
        Action(
            name: "Propose des titres",
            icon: "📰",
            prompt: """
        Rôle : rédacteur en chef.

        Tâche : proposer 5 titres pertinents et accrocheurs pour le texte fourni, dans la même langue que le texte original.

        Procédure :
        1. Identifier le sujet central et l'angle dominant du texte.
        2. Imaginer plusieurs façons de présenter ce sujet avec des angles variés.
        3. Formuler 5 propositions distinctes.

        Règles :
        - Chaque titre doit être court (5 à 12 mots), clair et accrocheur.
        - Refléter fidèlement le contenu du texte (pas de clickbait trompeur).
        - Varier les approches : informatif, intrigant, direct, question, accroche émotionnelle, etc.
        - Numéroter les titres de 1 à 5.
        - Les titres doivent être distincts et non redondants entre eux.
        - Rédiger la sortie en français, quelle que soit la langue du texte source.

        Sortie attendue :
        - Répondre uniquement avec la liste numérotée des 5 titres.
        - Pas d'introduction, pas de commentaire, pas d'explication des choix.
        """,
            actionType: .ai,
            shortDescription: "Proposer plusieurs titres accrocheurs aux angles variés",
            isFavorite: false,
            displayOrder: 21,
            category: .propose
        ),
        Action(
            name: "Propose des questions",
            icon: "❓",
            prompt: """
        Rôle : facilitateur de réflexion.

        Tâche : proposer une liste de questions pertinentes à partir du texte fourni, dans la même langue que le texte original.

        Procédure :
        1. Identifier les zones d'ombre, les hypothèses implicites et les points discutables du texte.
        2. Formuler des questions qui permettent d'approfondir la compréhension ou d'ouvrir le débat.
        3. Varier les types de questions (compréhension, approfondissement, critique).

        Règles :
        - Proposer entre 3 et 10 questions selon la richesse du texte.
        - Varier les types : questions de compréhension (que dit le texte ?), d'approfondissement (pourquoi ? comment ?), critiques (et si ? quelles limites ?).
        - Chaque question doit être claire, ouverte (pas oui/non) et appeler une réflexion.
        - Présenter les questions sous forme de liste numérotée en Markdown.
        - Les questions doivent être distinctes et non redondantes.
        - Rédiger la sortie en français, quelle que soit la langue du texte source.

        Sortie attendue :
        - Répondre uniquement avec la liste numérotée des questions.
        - Pas d'introduction, pas de commentaire.
        """,
            actionType: .ai,
            shortDescription: "Proposer des questions pour approfondir ou ouvrir le débat",
            isFavorite: false,
            displayOrder: 22,
            category: .propose
        ),
        Action(
            name: "Propose des angles différents",
            icon: "🔍",
            prompt: """
        Rôle : penseur multi-perspectives.

        Tâche : proposer 3 angles ou perspectives alternatives sur le sujet du texte fourni, dans la même langue que le texte original.

        Procédure :
        1. Identifier le sujet central et l'angle dominant adopté par le texte.
        2. Imaginer d'autres façons d'aborder ce même sujet (autres disciplines, autres parties prenantes, autres échelles temporelles, etc.).
        3. Formuler 3 angles distincts qui enrichissent ou contrastent avec l'angle initial.

        Règles :
        - Proposer exactement 3 angles distincts.
        - Chaque angle doit ouvrir une perspective réellement différente (pas une simple variation de formulation).
        - Sources possibles d'angles alternatifs : autre discipline (économique vs sociologique, technique vs humain), autre échelle (individuel vs collectif, court terme vs long terme), autre partie prenante (utilisateur vs producteur, expert vs novice).
        - Présenter chaque angle avec un titre court (## Angle 1 — Nom) suivi d'un paragraphe de 2 à 4 phrases expliquant la perspective.
        - Les angles ne sont pas des opinions à défendre, ce sont des points de vue à expliciter.
        - Rédiger la sortie en français, quelle que soit la langue du texte source.

        Sortie attendue :
        - Répondre uniquement avec les 3 angles structurés en Markdown.
        - Pas d'introduction, pas de commentaire.
        """,
            actionType: .ai,
            shortDescription: "Proposer plusieurs perspectives alternatives sur le sujet",
            isFavorite: false,
            displayOrder: 23,
            category: .propose
        ),
    ]
}
