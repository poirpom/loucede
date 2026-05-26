//
//  ActionGenerator.swift
//  loucede
//
//  K.2-B lot 1 (2026-05-26) — Moteur de génération d'actions AI.
//
//  À partir d'une demande utilisateur en texte libre (ex. « traduis en
//  russe »), appelle l'IA via `AIService.chat` (non-streaming) avec un
//  méta-prompt strict + 3 examples few-shot, et retourne une action
//  structurée `GeneratedAction` (title/emoji/description/prompt) — ou
//  un `GeneratorError` exploitable. JAMAIS de throw : toute erreur est
//  capturée et convertie en `Result.failure`.
//
//  Périmètre lot 1 : la couture popup→Générateur (UI, conversion en
//  `Action`, ajout au store) est faite en lot 2. Ici on s'arrête au
//  `GeneratedAction` brut.
//
//  Cadrage détaillé : `loucede-private/details/action-generator.md`
//  (section « Cadrage K.2 »).
//

import Foundation

// MARK: - Types

/// Résultat brut d'une génération AI : les 4 champs du JSON tels que
/// renvoyés par l'IA. Non encore converti en `Action` (la conversion +
/// ajout au store sont faits en K.2-B lot 2). `Codable` pour décoder
/// directement la réponse JSON.
struct GeneratedAction: Codable, Equatable {
    let title: String
    let emoji: String
    let description: String
    let prompt: String
}

/// Cas d'échec exploitables par le caller (UI lot 2 ou logs de test).
/// Le moteur ne crashe jamais : toute erreur est convertie en l'un de
/// ces cas.
enum GeneratorError: LocalizedError {
    /// Aucune clé API configurée pour le provider courant. Aligné sur
    /// `ActionsStore.hasUsableProvider` (même gating que l'emptyState
    /// du popup).
    case noApiKey
    /// Erreur réseau / HTTP / provider — wrap du message d'`AIError`.
    case providerUnavailable(String)
    /// L'IA a renvoyé une réponse vide ou whitespace-seul.
    case emptyResponse
    /// JSON invalide après nettoyage défensif (impossible à parser ou
    /// à localiser dans la réponse). `rawResponse` conservé pour debug.
    case invalidJSON(rawResponse: String)
    /// JSON parsable mais 1+ champs manquants/vides/invalides.
    /// `fields` = liste des champs en défaut (ex. `["emoji", "prompt"]`).
    case incompleteFields([String])

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "Aucune clé API configurée pour le provider sélectionné."
        case .providerUnavailable(let detail):
            return "Provider indisponible : \(detail)"
        case .emptyResponse:
            return "Réponse IA vide."
        case .invalidJSON(let raw):
            let preview = raw.prefix(1000)
            return "JSON invalide. Longueur totale : \(raw.count) chars. Brut (1000 premiers chars) :\n\(preview)"
        case .incompleteFields(let fields):
            return "Champ(s) manquant(s) ou invalide(s) : \(fields.joined(separator: ", "))"
        }
    }
}

// MARK: - ActionGenerator

enum ActionGenerator {

    // MARK: Génération

    /// Génère une action structurée depuis une demande utilisateur en
    /// texte libre. Pipeline : few-shot pick → méta-prompt build →
    /// `AIService.chat` (non-streaming) → parsing JSON défensif →
    /// validation des 4 champs → `Result`.
    ///
    /// **Provider + modèle COURANTS** de l'utilisateur
    /// (`ActionsStore.shared.selectedProvider` / `selectedModel`),
    /// exactement comme une action normale — pas de modèle spécifique
    /// pour la génération.
    ///
    /// **Gating** : aligné sur l'emptyState du popup (même check que
    /// `store.hasUsableProvider`). Pas de gating trial
    /// (`LicenseManager.canRunAction`) — la génération fabrique un
    /// outil, elle ne consomme pas d'essai. Seule l'exécution
    /// ultérieure de l'action générée consomme un trial.
    ///
    /// **Ne throw JAMAIS** : toutes les erreurs (réseau, parsing,
    /// format) sont converties en `GeneratorError` et retournées via
    /// `Result.failure`.
    @MainActor
    static func generate(userRequest: String) async -> Result<GeneratedAction, GeneratorError> {
        let store = ActionsStore.shared

        // Gating aligné sur l'emptyState du popup (même check que
        // `hasUsableProvider`). Cohérent : si l'utilisateur ne peut pas
        // lancer une action, il ne peut pas non plus en générer une.
        guard store.hasUsableProvider else {
            return .failure(.noApiKey)
        }

        // Provider + modèle COURANTS de l'utilisateur (comme une action
        // normale — cf. PopoverState.runAction pour le même pattern).
        let provider = store.selectedProvider
        let model = store.selectedModel
        let apiKey = store.apiKey

        let examples = pickFewShotExamples()
        let metaPrompt = buildMetaPrompt(userRequest: userRequest, examples: examples)

        // Appel non-streaming : on attend le JSON complet pour le parser
        // une seule fois (cf. cadrage K.2 — streaming visuel écarté en V1).
        let raw: String
        do {
            raw = try await AIService.shared.chat(
                messages: [(role: "user", content: metaPrompt)],
                apiKey: apiKey,
                provider: provider,
                model: model
            )
        } catch {
            return .failure(.providerUnavailable(error.localizedDescription))
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.emptyResponse)
        }

        guard let jsonData = extractJSONData(from: trimmed) else {
            return .failure(.invalidJSON(rawResponse: trimmed))
        }

        let generated: GeneratedAction
        do {
            generated = try JSONDecoder().decode(GeneratedAction.self, from: jsonData)
        } catch {
            return .failure(.invalidJSON(rawResponse: trimmed))
        }

        let missing = validateFields(generated)
        guard missing.isEmpty else {
            return .failure(.incompleteFields(missing))
        }

        return .success(generated)
    }

    // MARK: Test à sec (lot 1 uniquement)

    /// Point d'entrée de TEST à sec — log tout (demande, prompt envoyé,
    /// réponse brute si succès, erreur si échec) puis retourne le
    /// `Result`. Appelé en lot 1 via le hook ⌘G temporaire de
    /// `PopoverView.installSlotMonitorIfNeeded`. À RETIRER en K.2-B
    /// lot 2 quand le câblage UI réel le remplace.
    @MainActor
    static func testGenerate(userRequest: String) async -> Result<GeneratedAction, GeneratorError> {
        print("══════════════════════════════════════════════════════")
        print("[ActionGenerator] testGenerate — début")
        print("[ActionGenerator] Demande utilisateur : \(userRequest)")

        let examples = pickFewShotExamples()
        let metaPrompt = buildMetaPrompt(userRequest: userRequest, examples: examples)
        print("[ActionGenerator] Méta-prompt envoyé (\(metaPrompt.count) chars) :")
        print(metaPrompt)
        print("──────────────────────────────────────────────────────")

        let result = await generate(userRequest: userRequest)

        switch result {
        case .success(let action):
            print("[ActionGenerator] ✅ SUCCÈS")
            print("  title       : \(action.title)")
            print("  emoji       : \(action.emoji)")
            print("  description : \(action.description)")
            print("  prompt (\(action.prompt.count) chars) :")
            print(action.prompt)
        case .failure(let error):
            print("[ActionGenerator] ❌ ÉCHEC : \(error.localizedDescription)")
        }
        print("══════════════════════════════════════════════════════")

        return result
    }

    // MARK: Few-shot

    /// Pioche 3 actions de `ActionsStore.defaultActions` dans 3
    /// catégories différentes, aléatoirement (tirage neuf à chaque
    /// appel). Fallback hardcodé si la pioche dégradée n'aboutit pas
    /// — ne devrait jamais arriver avec les 24 seeds par défaut.
    private static func pickFewShotExamples() -> [(request: String, action: GeneratedAction)] {
        let categories = PromptCategory.allCases
            .filter { $0 != .custom }
            .shuffled()
            .prefix(3)

        let picked: [(request: String, action: GeneratedAction)] = categories.compactMap { category in
            let candidates = ActionsStore.defaultActions.filter { $0.category == category }
            guard let pick = candidates.randomElement() else { return nil }
            // K.2-B lot 1 — approche (a) cadrée : on utilise `action.name`
            // comme « demande utilisateur plausible ». Les noms du
            // catalogue sont à l'impératif, ce qui correspond naturellement
            // à comment un user tape sa demande. Risque accepté : le
            // modèle peut sur-apprendre à recopier la demande dans le
            // title — souvent le bon comportement, à surveiller runtime.
            return (
                request: pick.name,
                action: GeneratedAction(
                    title: pick.name,
                    emoji: pick.icon,
                    description: pick.shortDescription ?? "",
                    prompt: pick.prompt
                )
            )
        }

        return picked.count == 3 ? picked : hardcodedFallbackExamples
    }

    /// Fallback défensif si `pickFewShotExamples()` n'aboutit pas pour
    /// une raison quelconque (3 catégories distinctes attendues).
    /// 3 examples représentatifs couvrant 3 catégories : Traduire,
    /// Analyser, Transformer.
    private static let hardcodedFallbackExamples: [(request: String, action: GeneratedAction)] = [
        (request: "Traduis en français",
         action: GeneratedAction(
            title: "Traduis en français",
            emoji: "🇫🇷",
            description: "Traduire le texte fourni en français naturel et fluide",
            prompt: """
            Rôle : traducteur expert vers le français.

            Tâche : traduire le texte fourni en français naturel et fluide.

            Règles :
            - Préserver le sens et le ton du texte original.
            - Adapter les expressions idiomatiques au français.
            - Si le texte est déjà en français, le retourner tel quel.

            Sortie attendue : uniquement la traduction en français, sans commentaire.
            """
         )),
        (request: "Résume ce texte",
         action: GeneratedAction(
            title: "Résume ce texte",
            emoji: "🤏",
            description: "Extraire les idées essentielles en quelques points clés",
            prompt: """
            Rôle : synthétiste expert.

            Tâche : extraire les idées essentielles du texte fourni en quelques points clés, en français.

            Règles :
            - Identifier les 3 à 7 idées principales.
            - Préserver le sens et l'angle du texte original.
            - Réponse concise.

            Sortie attendue : liste à puces Markdown des idées principales, en français, sans encapsuler la réponse dans un bloc de code ```...```.
            """
         )),
        (request: "Reformule ce texte",
         action: GeneratedAction(
            title: "Reformule ce texte",
            emoji: "🔄",
            description: "Reformuler le texte avec un autre angle tout en préservant le sens",
            prompt: """
            Rôle : rédacteur expert.

            Tâche : reformuler le texte fourni en français, avec un angle différent tout en préservant le sens.

            Règles :
            - Varier le vocabulaire et la structure des phrases.
            - Préserver l'intention, le sens et le registre de langue.

            Sortie attendue : uniquement le texte reformulé, sans commentaire ni introduction.
            """
         )),
    ]

    // MARK: Méta-prompt

    /// Construit le méta-prompt complet à envoyer à l'IA :
    /// instructions + format JSON strict + 3 examples few-shot
    /// (encodés via JSONEncoder pretty-printed) + demande utilisateur.
    private static func buildMetaPrompt(userRequest: String,
                                        examples: [(request: String, action: GeneratedAction)]) -> String {
        let examplesBlock = examples.enumerated().map { idx, example in
            let json = encodePretty(example.action)
            return """
            EXEMPLE \(idx + 1) — Demande de l'utilisateur : "\(example.request)"
            Réponse attendue :
            \(json)
            """
        }.joined(separator: "\n\n")

        return """
        Tu es un assistant qui aide à créer des actions pour loucedé, une application macOS qui transforme du texte via IA.

        L'utilisateur exprime une demande en texte libre. Ta tâche : transformer cette demande en une action loucedé structurée, prête à être ajoutée au catalogue de l'utilisateur.

        Réponds UNIQUEMENT par un objet JSON valide avec ces 4 clés exactes, sans aucun texte avant ou après, sans bloc de code Markdown ```...```, sans commentaire :

        {
          "title": "...",
          "emoji": "...",
          "description": "...",
          "prompt": "..."
        }

        Règles JSON strictes :
        - N'insère AUCUN saut de ligne littéral à l'intérieur des valeurs de chaîne JSON. Tout saut de ligne à l'intérieur d'une valeur DOIT être échappé en \\n (deux caractères : un backslash suivi de la lettre n). Les valeurs longues doivent rester sur une seule ligne logique, avec \\n pour les retours.
        - Les guillemets internes doivent être échappés en \\".

        Description précise de chaque champ :

        - title : nom court de l'action, 2 à 6 mots. Le title commence TOUJOURS par un verbe conjugué à l'impératif 2ᵉ personne du singulier (« Résume », « Traduis », « Extrais », « Génère », « Analyse », « Corrige », « Propose »…). JAMAIS un verbe à l'infinitif. Pas de point final. Exemples corrects : « Résume ce texte », « Extrais les dates ». Exemple INCORRECT : « Extraire les idées » (infinitif — à proscrire).
        - emoji : un seul emoji représentatif (1 grapheme cluster, ex. 🤏, 🇫🇷, 📝). Pas de texte, juste l'emoji.
        - description : courte description à l'infinitif, 5 à 12 mots, qui explique ce que l'action fait. Exemples du style attendu : « Extraire les idées essentielles en quelques points clés », « Reformuler le texte avec un autre angle ». Pas de point final.
        - prompt : le prompt complet que loucedé enverra à l'IA quand l'utilisateur exécutera cette action. Il doit :
          • Être TOUJOURS rédigé en français, y compris quand l'action est une traduction vers une autre langue. Ne jamais rédiger le prompt dans la langue cible. Seule la SORTIE produite par l'action, une fois exécutée, sera dans la langue cible — jamais le prompt lui-même. Exemple : une action « Traduis en russe » a un prompt entièrement en français qui instruit de produire la traduction en russe.
          • Être structuré de manière claire (par exemple : Rôle / Tâche / Règles / Sortie attendue), en adaptant le niveau de détail à la complexité de l'action — une action simple n'a pas besoin d'un prompt sur-structuré.
          • Inclure une clause de langue de sortie : produire la sortie en français par défaut, SAUF si l'action concerne explicitement une autre langue (ex. traduction vers une autre langue).
          • Clause anti-encapsulation Markdown — règle précise : si l'action produit une sortie comportant le moindre formatage Markdown (titres ##, listes à puces, listes numérotées, tableaux, cases à cocher — y compris une simple liste), alors inclure dans le prompt généré la clause : « Rédiger directement en Markdown brut, sans encapsuler la réponse dans un bloc de code ```...```. ». Si l'action produit une sortie en prose pure (paragraphes de texte continu, sans aucune liste ni titre — ex. une traduction, une reformulation, un résumé en prose), NE PAS inclure cette clause.
          • Ton clair, instructions actionnables.

        Voici 3 exemples d'actions existantes du catalogue loucedé pour calibrage du style et du niveau de détail attendu :

        \(examplesBlock)

        Maintenant, voici la demande de l'utilisateur :
        "\(userRequest)"

        Réponds uniquement avec l'objet JSON décrit ci-dessus.
        """
    }

    /// Sérialise une `GeneratedAction` en JSON pretty-printed pour
    /// inclusion dans le méta-prompt. `JSONEncoder` gère l'échappement
    /// natif des newlines et quotes dans les prompts existants.
    /// `.sortedKeys` garantit l'ordre {description, emoji, prompt, title}
    /// — cosmétique, lisibilité du méta-prompt.
    private static func encodePretty(_ action: GeneratedAction) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(action),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"  // ne devrait jamais arriver — actions internes contrôlées
        }
        return str
    }

    // MARK: Parsing défensif

    /// Extrait l'objet JSON d'une réponse texte potentiellement
    /// enveloppée. Stratégie en 3 passes :
    /// 1. Strip ` ```json ` / ` ``` ` de tête et de queue si présents
    ///    (cas le plus fréquent : modèle qui ignore l'instruction
    ///    anti-encapsulation).
    /// 2. Sous-chaîne du PREMIER `{` au DERNIER `}` — couvre les cas
    ///    « Voici le JSON : {…} » avec texte parasite avant/après.
    /// 3. Échappement défensif des caractères de contrôle littéraux
    ///    (\n, \r, \t) qui se trouvent À L'INTÉRIEUR d'une valeur de
    ///    chaîne JSON (cf. `escapeUnescapedControlChars`). Travers LLM
    ///    classique sur les réponses longues — diagnostiqué K.2-B lot 1.
    /// `nil` si pas de `{…}` repérable.
    private static func extractJSONData(from raw: String) -> Data? {
        var s = raw

        // Strip ```json (ou ```) en tête, suivi optionnellement d'un
        // newline.
        if let range = s.range(of: "^```(json)?[ \t]*\n?", options: [.regularExpression]) {
            s.removeSubrange(range)
        }
        // Strip ``` en queue.
        if let range = s.range(of: "\n?[ \t]*```[ \t]*$", options: [.regularExpression]) {
            s.removeSubrange(range)
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extraire du premier { au dernier }.
        guard let firstBrace = s.firstIndex(of: "{"),
              let lastBrace = s.lastIndex(of: "}"),
              firstBrace <= lastBrace else {
            return nil
        }
        let extracted = String(s[firstBrace...lastBrace])
        // K.2-B lot 1-ter — échappement défensif des newlines/CR/tabs
        // littéraux dans les valeurs JSON (le LLM les insère parfois
        // au lieu de \\n, ce qui fait rejeter JSONDecoder).
        let escaped = escapeUnescapedControlChars(in: extracted)
        return escaped.data(using: .utf8)
    }

    /// K.2-B lot 1-ter — parser d'état minimal qui parcourt un blob JSON
    /// caractère par caractère et **échappe les caractères de contrôle
    /// littéraux** (newline `\n`, carriage return `\r`, tab `\t`)
    /// trouvés À L'INTÉRIEUR des valeurs de chaîne (`"..."`).
    ///
    /// Travers LLM classique : le modèle insère de vrais sauts de ligne
    /// au lieu de les échapper en `\\n`. La RFC 8259 interdit les
    /// caractères de contrôle non échappés dans les chaînes →
    /// `JSONDecoder` rejette. Cette fonction normalise.
    ///
    /// Approche : track l'état `inString` (booléen) en parcourant les
    /// `Unicode.Scalar`. Dans une chaîne, sur `\\` on consomme aussi
    /// le caractère suivant tel quel (gestion correcte de `\\"`, `\\\\`,
    /// `\\n` déjà échappé, `\\uXXXX`). Sur `"` non précédé d'un `\\`,
    /// on sort de la chaîne. Hors chaîne, tout est pass-through (les
    /// newlines structurels du pretty-print entre champs sont préservés).
    ///
    /// À RETIRER en K.2-B lot 2 si le méta-prompt 1-ter suffit
    /// désormais ; à conserver sinon comme filet de sécurité.
    static func escapeUnescapedControlChars(in input: String) -> String {
        var out = String()
        out.reserveCapacity(input.unicodeScalars.count + 32)
        var inString = false
        var iterator = input.unicodeScalars.makeIterator()
        while let c = iterator.next() {
            if !inString {
                if c == "\"" { inString = true }
                out.unicodeScalars.append(c)
            } else {
                switch c {
                case "\\":
                    // Séquence d'échappement : consomme aussi le
                    // caractère suivant tel quel. Couvre proprement
                    // \", \\, \n déjà échappé, \/, \uXXXX (le 'u' passe
                    // ici puis les 4 hex tombent dans default ci-dessous
                    // à l'itération suivante).
                    out.unicodeScalars.append(c)
                    if let next = iterator.next() {
                        out.unicodeScalars.append(next)
                    }
                case "\"":
                    inString = false
                    out.unicodeScalars.append(c)
                case "\n":
                    out.append("\\n")
                case "\r":
                    out.append("\\r")
                case "\t":
                    out.append("\\t")
                default:
                    out.unicodeScalars.append(c)
                }
            }
        }
        return out
    }

    /// Valide qu'un `GeneratedAction` a ses 4 champs non vides (et
    /// l'emoji = exactement 1 grapheme cluster). Retourne la liste des
    /// champs en défaut (vide si tout OK).
    ///
    /// K.2-B : `String.count` en Swift compte les `Character` =
    /// grapheme clusters, donc gère correctement les drapeaux 🇷🇺 (1
    /// grapheme, 2 unicodeScalars) et les emojis ZWJ 👨‍👩‍👧‍👦 (1
    /// grapheme, plusieurs scalars).
    private static func validateFields(_ action: GeneratedAction) -> [String] {
        var missing: [String] = []
        if action.title.trimmingCharacters(in: .whitespaces).isEmpty {
            missing.append("title")
        }
        if action.emoji.count != 1 {
            missing.append("emoji")
        }
        if action.description.trimmingCharacters(in: .whitespaces).isEmpty {
            missing.append("description")
        }
        if action.prompt.trimmingCharacters(in: .whitespaces).isEmpty {
            missing.append("prompt")
        }
        return missing
    }

    // MARK: - SelfTest (K.2-B lot 1-ter — TEMPORAIRE)

    /// Harnais de test à sec du tokenizer `escapeUnescapedControlChars`.
    /// Couvre 7 cas tordus (newline littéral, déjà échappé, guillemet
    /// échappé, backslash double, newline structurel hors string, tab
    /// littéral, cas mixte du bug observé). Affiche ✅/❌ par cas + récap.
    ///
    /// À RETIRER en K.2-B lot 2 (avec le hook ⌘G), une fois la robustesse
    /// du tokenizer confirmée par les tests à sec.
    ///
    /// Pour déclencher : depuis Xcode LLDB `expr ActionGenerator.runSelfTest()`,
    /// OU ajouter temporairement `ActionGenerator.runSelfTest()` dans
    /// `applicationDidFinishLaunching` (loucedeApp.swift).
    static func runSelfTest() {
        print("══════════════════════════════════════════════════════")
        print("[ActionGenerator.runSelfTest] tokenizer escapeUnescapedControlChars")
        print("══════════════════════════════════════════════════════")

        // (name, input, expected). Les `\n` Swift = newline réel (0x0A) ;
        // `\\n` Swift = 2 chars (backslash + n) = forme échappée JSON.
        let cases: [(name: String, input: String, expected: String)] = [
            (
                "1. Newline littéral dans string",
                "{\"k\":\"abc\n  xyz\"}",
                "{\"k\":\"abc\\n  xyz\"}"
            ),
            (
                "2. Déjà bien échappé (passe-through)",
                "{\"k\":\"abc\\n  xyz\"}",
                "{\"k\":\"abc\\n  xyz\"}"
            ),
            (
                "3. Guillemet échappé \\\" dans string",
                "{\"k\":\"il a dit \\\"oui\\\"\"}",
                "{\"k\":\"il a dit \\\"oui\\\"\"}"
            ),
            (
                "4. Backslash double \\\\ dans string",
                "{\"k\":\"path\\\\file\"}",
                "{\"k\":\"path\\\\file\"}"
            ),
            (
                "5. Newline hors string (pretty-print structurel)",
                "{\n  \"k\": \"v\"\n}",
                "{\n  \"k\": \"v\"\n}"
            ),
            (
                "6. Tab littéral dans string",
                "{\"k\":\"a\tb\"}",
                "{\"k\":\"a\\tb\"}"
            ),
            (
                "7. Cas mixte (newlines structurels + littéral intra-string)",
                "{\n  \"k\": \"abc\n  xyz\",\n  \"emoji\": \"🇷🇺\"\n}",
                "{\n  \"k\": \"abc\\n  xyz\",\n  \"emoji\": \"🇷🇺\"\n}"
            ),
        ]

        var passed = 0
        var failed = 0
        for c in cases {
            let result = escapeUnescapedControlChars(in: c.input)
            if result == c.expected {
                print("✅ \(c.name)")
                passed += 1
            } else {
                print("❌ \(c.name)")
                print("    INPUT    : \(c.input.debugDescription)")
                print("    EXPECTED : \(c.expected.debugDescription)")
                print("    GOT      : \(result.debugDescription)")
                failed += 1
            }
        }

        print("──────────────────────────────────────────────────────")
        print("Récap : \(passed)/\(cases.count) OK" + (failed > 0 ? " — \(failed) ÉCHEC(S)" : ""))
        print("══════════════════════════════════════════════════════")
    }
}
