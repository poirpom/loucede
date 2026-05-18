//
//  TemplatesView.swift
//  loucede
//
//  Templates view with prompt suggestions grid
//

import SwiftUI

// MARK: - Prompt Suggestion Model

struct PromptSuggestion: Identifiable {
    let id = UUID()
    let name: String
    /// Description courte (≤80 signes) affichée sur la carte du modèle dans
    /// le catalogue. Remplace la preview tronquée du prompt qui était peu
    /// lisible. Correctif 2026-04-28.
    let description: String
    let prompt: String
    let icon: String
    let category: PromptCategory
}

/// Phase 6.12 (2026-04-25) : refonte complète des catégories. Anglais
/// generic-coding → catégories français orientées texte. Ordre figé
/// (Traduire, Analyser, Extraire, Transformer, Structurer, Proposer) imposé
/// par l'utilisateur — `CaseIterable` itère dans l'ordre de déclaration, donc
/// l'ordre des `case` ci-dessous est la source de vérité pour la UI.
///
/// Phase B.2.a (2026-05-13) : ajout de `.extract` (« Extraire ») entre
/// `.analyze` et `.transform` pour accueillir les modèles d'extraction
/// (recette, données structurées, entités) du nouveau catalogue 25 actions.
enum PromptCategory: String, CaseIterable {
    case translate = "Traduire"
    case analyze = "Analyser"
    case extract = "Extraire"
    case transform = "Transformer"
    case structure = "Structurer"
    case propose = "Proposer"
    /// Catégorie ajoutée pour les modèles publiés par l'utilisateur via
    /// l'éditeur d'action (toggle « Ajouter aux Modèles »). Correctif 2026-04-28.
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

// Modèles fournis par l'utilisateur — catalogue V1 (Phase B.2.d, 2026-05-18).
// 25 actions / 6 catégories. L'ordre des catégories suit l'enum
// PromptCategory : .translate / .analyze / .extract / .transform /
// .structure / .propose (CaseIterable itère dans l'ordre de déclaration).
// Source de vérité : actions-audit/modeles-de-prompts.csv (BDD Notion).
//
// Les 6 actions adossées au seed (Top 5 V1 + recette de cuisine)
// référencent les constantes statiques `ActionsStore.xxxPrompt` (single
// source of truth, synchronisées avec `defaultActions`). Les 19 autres
// portent leur prompt en littéral inline copié du CSV.
//
// B.2.d : « Raccourcis ce texte » est passé en inline (le prompt CSV
// « élagage 30-50 % » colle mieux au nom/description que concisePrompt
// qui faisait de la reformulation) → `ActionsStore.concisePrompt`
// devient orpheline, suppression prévue B.2.f.
let promptSuggestions: [PromptSuggestion] = [
    // MARK: Traduire (6) — "Traduis en français" en tête (seed default action)
    PromptSuggestion(
        name: "Traduis en français",
        description: "Traduire en français naturel et idiomatique",
        prompt: ActionsStore.translateFrPrompt,
        icon: "🇫🇷",
        category: .translate
    ),
    PromptSuggestion(
        name: "Traduis en anglais",
        description: "Traduire en anglais naturel et idiomatique",
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
        icon: "🇬🇧",
        category: .translate
    ),
    PromptSuggestion(
        name: "Traduis en espagnol",
        description: "Traduire en espagnol neutre international",
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
        icon: "🇪🇸",
        category: .translate
    ),
    PromptSuggestion(
        name: "Traduis en portugais",
        description: "Traduire en portugais naturel et idiomatique",
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
        icon: "🇵🇹",
        category: .translate
    ),
    PromptSuggestion(
        name: "Traduis en allemand",
        description: "Traduire en allemand naturel et idiomatique",
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
        icon: "🇩🇪",
        category: .translate
    ),
    PromptSuggestion(
        name: "Traduis en italien",
        description: "Traduire en italien naturel et idiomatique",
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
        icon: "🇮🇹",
        category: .translate
    ),
    // MARK: Analyser (3) — "Résume ce texte" en tête (seed default action)
    PromptSuggestion(
        name: "Résume ce texte",
        description: "Extraire les idées essentielles en quelques points clés",
        prompt: ActionsStore.summarizePrompt,
        icon: "🤏",
        category: .analyze
    ),
    PromptSuggestion(
        name: "Identifie l'idée principale",
        description: "Identifier la thèse centrale en 1 à 2 phrases",
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

        Sortie attendue :
        - Répondre uniquement avec l'idée principale, en 1 ou 2 phrases.
        - Pas d'introduction, pas de commentaire, pas de liste.
        """,
        icon: "🎯",
        category: .analyze
    ),
    PromptSuggestion(
        name: "Explique simplement",
        description: "Vulgariser le texte pour un lecteur non-spécialiste",
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

        Sortie attendue :
        - Répondre uniquement avec la version vulgarisée du texte.
        - Pas d'introduction, pas de commentaire.
        """,
        icon: "🧩",
        category: .analyze
    ),
    // MARK: Extraire (3) — "Extrais la recette de cuisine" en tête (seed default action)
    PromptSuggestion(
        name: "Extrais la recette de cuisine",
        description: "Extraire et reformater une recette en système métrique",
        prompt: ActionsStore.recipeExtractionPrompt,
        icon: "🍳",
        category: .extract
    ),
    PromptSuggestion(
        name: "Extrais les noms propres",
        description: "Lister les personnes lieux et organisations mentionnés",
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
        icon: "🏷️",
        category: .extract
    ),
    PromptSuggestion(
        name: "Extrais les dates",
        description: "Lister toutes les dates mentionnées avec leur contexte",
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
        icon: "📅",
        category: .extract
    ),
    // MARK: Transformer (7) — "Corrige les fautes", "Améliore le style", "Raccourcis" adossés au seed
    PromptSuggestion(
        name: "Corrige les fautes",
        description: "Corriger orthographe grammaire et typographie",
        prompt: ActionsStore.correctPrompt,
        icon: "✍️",
        category: .transform
    ),
    PromptSuggestion(
        name: "Améliore le style",
        description: "Améliorer la fluidité sans changer le sens",
        prompt: ActionsStore.improveStylePrompt,
        icon: "✨",
        category: .transform
    ),
    PromptSuggestion(
        name: "Reformule",
        description: "Paraphraser en préservant le sens et le registre",
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

        Sortie attendue :
        - Répondre uniquement avec la version reformulée.
        - Pas d'introduction, pas de commentaire.
        """,
        icon: "🔄",
        category: .transform
    ),
    PromptSuggestion(
        name: "Rends plus formel",
        description: "Réécrire dans un registre formel et soigné",
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

        Sortie attendue :
        - Répondre uniquement avec la version réécrite.
        - Pas d'introduction, pas de commentaire.
        """,
        icon: "🕴️",
        category: .transform
    ),
    PromptSuggestion(
        name: "Rends plus convivial",
        description: "Réécrire dans un registre chaleureux et accessible",
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

        Sortie attendue :
        - Répondre uniquement avec la version réécrite.
        - Pas d'introduction, pas de commentaire.
        """,
        icon: "😊",
        category: .transform
    ),
    PromptSuggestion(
        name: "Raccourcis ce texte",
        description: "Réduire la longueur en préservant l'essentiel",
        prompt: """
        Rôle : éditeur synthétique.

        Tâche : raccourcir le texte fourni en préservant les informations essentielles, dans la même langue que le texte original.

        Procédure :
        1. Identifier les informations centrales du texte.
        2. Repérer les passages redondants, illustratifs ou accessoires.
        3. Reformuler de manière condensée en éliminant le superflu.

        Règles :
        - Réduire la longueur du texte d'environ 30 à 50 %.
        - Préserver toutes les idées essentielles et informations clés.
        - Éliminer les redondances, les exemples illustratifs non critiques, les digressions.
        - Préserver le ton et le registre du texte (formel, informel, technique, etc.).
        - Préserver la structure du texte (paragraphes, listes, etc.) en l'adaptant si nécessaire.
        - Ne pas dénaturer le sens, ne pas inventer.

        Sortie attendue :
        - Répondre uniquement avec la version raccourcie du texte.
        - Pas d'introduction, pas de commentaire, pas d'indication de longueur.
        """,
        icon: "✂️",
        category: .transform
    ),
    PromptSuggestion(
        name: "Réponds à cet email",
        description: "Rédiger une réponse adaptée au contenu reçu",
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

        Cas particuliers :
        - Si l'email contient des informations sensibles ou ambiguës, signaler les points à clarifier sans inventer de réponse.
        - Si le ton est conflictuel, adopter une réponse mesurée et professionnelle.

        Sortie attendue :
        - Répondre uniquement avec le texte de l'email de réponse complet (salutation incluse, formule de politesse incluse).
        - Pas d'introduction, pas de commentaire.
        """,
        icon: "📧",
        category: .transform
    ),
    // MARK: Structurer (3) — "Génère une Todo list" en tête (seed default action)
    PromptSuggestion(
        name: "Génère une Todo list",
        description: "Structurer des notes brutes en plan d'actions",
        prompt: ActionsStore.todoListPrompt,
        icon: "✅",
        category: .structure
    ),
    PromptSuggestion(
        name: "Convertis en tableau",
        description: "Transformer les informations en tableau Markdown",
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

        Cas particulier :
        - Si le texte ne se prête pas à un tableau, répondre uniquement : "Ce texte ne peut pas être converti en tableau de manière pertinente."

        Sortie attendue :
        - Répondre uniquement avec le tableau en Markdown.
        - Pas d'introduction, pas de commentaire.
        """,
        icon: "📊",
        category: .structure
    ),
    PromptSuggestion(
        name: "Propose un plan structuré",
        description: "Transformer le texte en plan hiérarchique numéroté",
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

        Sortie attendue :
        - Répondre uniquement avec le plan hiérarchique.
        - Pas d'introduction, pas de commentaire.
        """,
        icon: "🗂️",
        category: .structure
    ),
    // MARK: Proposer (3)
    PromptSuggestion(
        name: "Propose des titres",
        description: "Proposer plusieurs titres accrocheurs aux angles variés",
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

        Sortie attendue :
        - Répondre uniquement avec la liste numérotée des 5 titres.
        - Pas d'introduction, pas de commentaire, pas d'explication des choix.
        """,
        icon: "📰",
        category: .propose
    ),
    PromptSuggestion(
        name: "Propose des questions",
        description: "Proposer des questions pour approfondir ou ouvrir le débat",
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

        Sortie attendue :
        - Répondre uniquement avec la liste numérotée des questions.
        - Pas d'introduction, pas de commentaire.
        """,
        icon: "❓",
        category: .propose
    ),
    PromptSuggestion(
        name: "Propose des angles différents",
        description: "Proposer plusieurs perspectives alternatives sur le sujet",
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

        Sortie attendue :
        - Répondre uniquement avec les 3 angles structurés en Markdown.
        - Pas d'introduction, pas de commentaire.
        """,
        icon: "🔍",
        category: .propose
    ),
]


// MARK: - Templates View (Grid of Cards)

struct TemplatesView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var store = ActionsStore.shared
    @State private var selectedCategory: PromptCategory? = nil
    /// Mini-session catalogue (2026-05-08) : la bascule auto vers l'onglet
    /// Actions après ajout d'un modèle a été retirée. Le callback reste
    /// câblé côté `SettingsView` pour usage futur potentiel (ex. bouton
    /// « Voir dans Actions » sur les cards déjà ajoutées) mais n'est plus
    /// appelé par `addTemplateToActions`. Le state transient `addedTemplateId`
    /// a aussi été retiré : le feedback visuel est désormais porté par la
    /// coche verte permanente (state persistant via `originTemplateName`).
    var onNavigateToActions: (Action) -> Void

    /// Modèles publiés par l'utilisateur (correctif 2026-04-28). Rendus
    /// dynamiquement à partir des actions du store dont `isInTemplates == true`.
    /// Si la `shortDescription` est vide ou absente, on fallback sur les 80
    /// premiers caractères du prompt.
    var userTemplates: [PromptSuggestion] {
        store.actions
            .filter { $0.isInTemplates }
            .map { action in
                let desc: String = {
                    if let s = action.shortDescription, !s.isEmpty {
                        return s
                    }
                    return String(action.prompt.prefix(80))
                }()
                return PromptSuggestion(
                    name: action.name.isEmpty ? "Sans titre" : action.name,
                    description: desc,
                    prompt: action.prompt,
                    icon: action.icon,
                    category: .custom
                )
            }
    }

    /// Catalogue complet : built-ins + modèles utilisateur (en queue).
    var allTemplates: [PromptSuggestion] {
        promptSuggestions + userTemplates
    }

    var filteredTemplates: [PromptSuggestion] {
        if let category = selectedCategory {
            return allTemplates.filter { $0.category == category }
        }
        return allTemplates
    }

    var inputBackgroundColor: Color {
        colorScheme == .light
            ? Color(red: 241/255, green: 241/255, blue: 239/255)
            : Color(NSColor.controlBackgroundColor)
    }

    var textGrayColor: Color {
        colorScheme == .light
            ? Color(white: 0.35)
            : Color(white: 0.65)
    }

    /// Mini-session catalogue (2026-05-08) : un modèle est considéré
    /// « déjà ajouté » si une action existe avec `originTemplateName`
    /// égal au nom du template, OU si une action a simplement le même
    /// nom que le template. Le match `OR` couvre :
    ///   - actions du seed default V1 (Résume, Corrige, Style, Traduis FR,
    ///     Todo) → match par `name`, leur `originTemplateName` est `nil`
    ///   - actions pré-mini-session (créées avant 2026-05-08) → match
    ///     par `name`, idem `originTemplateName == nil`
    ///   - actions post-mini-session non renommées → matchent les deux
    ///   - actions post-mini-session **renommées** par l'utilisateur →
    ///     match par `originTemplateName` (le `name` ne matche plus)
    ///   - userTemplates (catégorie « Mes modèles ») → match par `name`,
    ///     puisqu'un userTemplate dérive d'une action `isInTemplates: true`
    ///     dont le `name` est identique
    /// Edge case accepté V1 : si l'utilisateur crée manuellement une
    /// action nommée comme un built-in sans origine, la coche apparaît
    /// quand même sur le built-in (homonymie pure traitée comme
    /// « déjà présent dans la liste »).
    func isTemplateAdded(_ template: PromptSuggestion) -> Bool {
        store.actions.contains { action in
            action.originTemplateName == template.name || action.name == template.name
        }
    }

    func addTemplateToActions(_ template: PromptSuggestion) {
        // V1 : nombre d'actions illimité.
        // Mini-session catalogue (2026-05-08) : `originTemplateName` permet
        // d'afficher la coche verte « déjà ajoutée » sur la card du template
        // correspondant (`isTemplateAdded(_:)` ci-dessus). Lien stable across
        // launches puisque les noms de templates sont des `let` au scope du
        // fichier.
        let newAction = Action(
            name: template.name,
            icon: template.icon,
            prompt: template.prompt,
            actionType: .ai,
            originTemplateName: template.name
        )
        // Wrappe dans withAnimation pour que la transition « + » → coche
        // verte sur la card soit animée par le ressort déjà câblé sur
        // `TemplateCard` (cf. `.animation(.spring, value: isAdded)`).
        // Plus de bascule auto vers l'onglet Actions ni de flash transitoire :
        // le feedback visuel est porté par la coche verte permanente, et
        // l'utilisateur reste sur Modèles pour ajouter d'autres templates
        // en série sans interruption du flow.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            store.addAction(newAction)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with category filter
            VStack(spacing: 12) {
                HStack {
                    Text("Modèles de prompts")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(textGrayColor)

                    Spacer()

                    Text("Clique pour ajouter aux Actions")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // Category pills
                HStack(spacing: 8) {
                    TemplateCategoryPill(
                        title: "Tous",
                        isSelected: selectedCategory == nil,
                        textColor: textGrayColor,
                        backgroundColor: inputBackgroundColor
                    ) {
                        selectedCategory = nil
                    }

                    ForEach(PromptCategory.allCases, id: \.self) { category in
                        TemplateCategoryPill(
                            title: category.rawValue,
                            isSelected: selectedCategory == category,
                            textColor: textGrayColor,
                            backgroundColor: inputBackgroundColor
                        ) {
                            selectedCategory = category
                        }
                    }

                    Spacer()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Templates grid
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(filteredTemplates) { template in
                        TemplateCard(
                            template: template,
                            isAdded: isTemplateAdded(template),
                            onTap: {
                                addTemplateToActions(template)
                            }
                        )
                    }
                }
                .padding(24)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Template Category Pill

struct TemplateCategoryPill: View {
    let title: String
    let isSelected: Bool
    var textColor: Color
    var backgroundColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(textColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(backgroundColor)
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? textColor.opacity(0.5) : Color.gray.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Template Card

struct TemplateCard: View {
    @Environment(\.colorScheme) var colorScheme
    let template: PromptSuggestion
    let isAdded: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var inputBackgroundColor: Color {
        colorScheme == .light
            ? Color(red: 241/255, green: 241/255, blue: 239/255)
            : Color(NSColor.controlBackgroundColor)
    }

    var textGrayColor: Color {
        colorScheme == .light
            ? Color(white: 0.35)
            : Color(white: 0.65)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Icon and name header
                // Phase 6.12 polish (2026-04-25) : `alignment: .top` pour
                // que l'icône reste alignée avec le début du titre quand
                // celui-ci passe sur 2 lignes (sinon center default = icône
                // qui flotte au milieu d'un VStack devenu plus haut).
                HStack(alignment: .top, spacing: 10) {
                    // Phase 6.12 (2026-04-25) : `template.icon` est désormais
                    // un emoji (ex. 🇪🇸, ⚠️, 🧩) plutôt qu'un nom de SF Symbol.
                    // On garde la boîte 3D colorée (couleur catégorie) en
                    // background pour ancrer visuellement la carte sur sa
                    // catégorie, et on affiche l'emoji par-dessus.
                    //
                    // Mini-session 2026-05-08 : check `isEmojiOnly` ajouté
                    // pour éviter d'afficher la chaîne littérale (« star »
                    // par défaut de `addNewAction`, ou autre SF Symbol
                    // legacy) à l'intérieur de la boîte colorée. Fallback
                    // sur le rond gris discret de `ActionIconView` —
                    // cohérence visuelle avec les built-ins sans emoji et
                    // avec la sidebar Actions.
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(template.category.color.opacity(0.2))
                            .frame(width: 36, height: 36)
                            .offset(y: 2)

                        RoundedRectangle(cornerRadius: 8)
                            .fill(template.category.color.opacity(0.12))
                            .frame(width: 36, height: 36)

                        if template.icon.isEmojiOnly {
                            Text(template.icon)
                                .font(.system(size: 20))
                        } else {
                            Circle()
                                .fill(Color.gray.opacity(0.25))
                                .frame(width: 14, height: 14)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        // Phase 6.12 polish : `lineLimit(2)` pour les titres
                        // longs (ex. « Extrais les actions concrètes »,
                        // « Détecte les incohérences ») qui débordaient et
                        // se faisaient tronquer en `lineLimit(1)`.
                        Text(template.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(textGrayColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(template.category.rawValue)
                            .font(.system(size: 10))
                            .foregroundColor(template.category.color)
                    }

                    Spacer()

                    // Added checkmark or hover indicator
                    if isAdded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else if isHovered {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Color(red: 0.0, green: 0.584, blue: 1.0))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(12)

                // Divider
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 1)

                // Description courte (correctif 2026-04-28) — remplace la
                // preview tronquée du prompt qui était peu lisible. Calibré
                // ≤80 signes côté contenu, mais on garde lineLimit(2) en
                // sécurité pour le wrap sur cards étroites (3 colonnes).
                Text(template.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(12)

                // Phase 6.12 polish : Spacer en bas pour que le contenu
                // reste collé en haut quand le `frame(minHeight:)` ci-
                // dessous étire la card. Sans ça, SwiftUI distribuerait
                // l'espace mort entre les enfants du VStack.
                Spacer(minLength: 0)
            }
            // Phase 6.12 polish : hauteur minimale pour uniformiser les
            // cards dans la grille — sinon une card à titre court (1 ligne)
            // serait plus petite que celle d'à côté à titre long (2 lignes),
            // créant un effet escalier entre colonnes.
            .frame(minHeight: 130, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isAdded ? Color.green.opacity(0.05) : inputBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isAdded ? Color.green.opacity(0.3) :
                        isHovered ? Color(red: 0.0, green: 0.584, blue: 1.0).opacity(0.5) :
                        Color.gray.opacity(0.15),
                        lineWidth: isHovered || isAdded ? 2 : 1
                    )
            )
            .scaleEffect(isHovered && !isAdded ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isAdded)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .disabled(isAdded)
    }
}

// MARK: - Preview

#Preview {
    TemplatesView(onNavigateToActions: { _ in })
        .frame(width: 700, height: 500)
}
