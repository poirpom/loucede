//
//  TemplatesView.swift
//  typo
//
//  Templates view with prompt suggestions grid
//

import SwiftUI

// MARK: - Prompt Suggestion Model

struct PromptSuggestion: Identifiable {
    let id = UUID()
    let name: String
    let prompt: String
    let icon: String
    let category: PromptCategory
}

/// Phase 6.12 (2026-04-25) : refonte complète des catégories. Anglais
/// generic-coding → catégories français orientées texte. Ordre figé
/// (Traduire, Analyser, Transformer, Structurer, Proposer) imposé par
/// l'utilisateur — `CaseIterable` itère dans l'ordre de déclaration, donc
/// l'ordre des `case` ci-dessous est la source de vérité pour la UI.
enum PromptCategory: String, CaseIterable {
    case translate = "Traduire"
    case analyze = "Analyser"
    case transform = "Transformer"
    case structure = "Structurer"
    case propose = "Proposer"

    /// Icône SF Symbol associée — pas affichée dans `TemplateCard` (qui
    /// montre désormais l'emoji du modèle Phase 6.12), mais conservée pour
    /// future use éventuel (ex. pill avec icône, navigation latérale).
    var icon: String {
        switch self {
        case .translate: return "globe"
        case .analyze:   return "chart.bar.xaxis"
        case .transform: return "arrow.triangle.2.circlepath"
        case .structure: return "list.bullet.rectangle"
        case .propose:   return "lightbulb"
        }
    }

    /// Couleur d'accent par catégorie. Palette douce, mappée 1-pour-1 sur
    /// les anciennes couleurs pour ne pas tout chambouler visuellement.
    var color: Color {
        switch self {
        case .translate: return Color(red: 0.45, green: 0.55, blue: 0.70) // Soft slate blue
        case .analyze:   return Color(red: 0.60, green: 0.52, blue: 0.58) // Dusty rose
        case .transform: return Color(red: 0.50, green: 0.60, blue: 0.55) // Sage green
        case .structure: return Color(red: 0.55, green: 0.50, blue: 0.65) // Muted lavender
        case .propose:   return Color(red: 0.65, green: 0.55, blue: 0.50) // Warm taupe
        }
    }
}

// Modèles fournis par l'utilisateur (Phase 6.12, 2026-04-25).
// Remplace les ~25 templates anglo-coding-centriques d'avant.
// Source : `documents-persos/Privé et partagé/modèles de prompts ...csv`.
let promptSuggestions: [PromptSuggestion] = [
    PromptSuggestion(
        name: "Traduis en espagnol",
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
        - Usa el tratamiento de “tú” por defecto, salvo que el texto original requiera un registro formal.
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
        prompt: """
        Papel: tradutor profissional.
        
        Tarefa: traduzir o texto fornecido para português.
        
        Procedimento:
        1. Detecta automaticamente o idioma de origem.
        2. Compreende o sentido global antes de traduzir.
        3. Produz uma tradução fiel, natural e fluida em português.
        
        Regras de tradução:
        - Usar português natural e corrente (evitar tradução literal ou excessivamente livre).
        - Usar sempre o tratamento por “tu” (2ª pessoa informal), de forma consistente.
        - Manter o tom, o registo e o nível de formalidade do texto original (formal, informal, técnico, etc.).
        - Preservar nomes próprios, marcas e acrónimos sem alteração.
        - Adaptar expressões idiomáticas para equivalentes naturais em português.
        - Se não existir equivalente natural, manter o termo original entre aspas com uma breve explicação entre parênteses.
        - Não acrescentar nem omitir informações.
        
        Formatação:
        - Manter rigorosamente a estrutura original:
        títulos, subtítulos, listas, citações, parágrafos e quebras de linha.
        - Respeitar a ordem do texto original.
        
        Saída:
        - Responder apenas com a tradução.
        - Sem introdução, sem comentários, sem explicações.
        """,
        icon: "🇵🇹",
        category: .translate
    ),
    PromptSuggestion(
        name: "Traduis en anglais",
        prompt: """
        Role: professional translator.
        
        Task: translate the provided text into English.
        
        Procedure:
        1. Automatically detect the source language.
        2. Fully understand the overall meaning of the text before translating.
        3. Produce an accurate, natural, and fluent English translation.
        
        Translation rules:
        - Use natural, idiomatic English (avoid literal, word-for-word translation).
        - Preserve the exact meaning, tone, and register of the original text (formal, informal, technical, etc.).
        - Maintain consistency in terminology throughout the text.
        - Keep proper names, brands, acronyms, and standard technical terms unchanged.
        - Adapt idiomatic expressions into natural English equivalents.
        - If no natural equivalent exists, keep the original term in quotation marks with a brief explanation in parentheses.
        - Do not add, remove, or alter information.
        
        Formatting:
        - Strictly preserve the original structure: titles, subtitles, lists, quotes, paragraphs, and line breaks.
        - Maintain the original order of sentences and sections.
        
        Output:
        - Respond only with the translated text.
        - Do not add any introduction, explanation, or comment before or after the translation.
        """,
        icon: "🇬🇧",
        category: .translate
    ),
    PromptSuggestion(
        name: "Détecte les incohérences",
        prompt: """
        Analyse le texte suivant et identifie les incohérences, contradictions, ambiguïtés ou informations manquantes, dans la même langue que le texte original.
        Règles :
        - Présente chaque problème détecté sous forme de liste numérotée en Markdown
        - Pour chaque problème : cite brièvement le passage concerné entre guillemets, puis explique l'incohérence en une phrase
        - Si aucun problème n'est détecté, réponds uniquement : "Aucune incohérence détectée."
        - Réponds uniquement avec la liste, sans introduction ni commentaire
        """,
        icon: "⚠️",
        category: .analyze
    ),
    PromptSuggestion(
        name: "Extrais les arguments",
        prompt: """
        Tu es un expert en analyse argumentative. Analyse le texte suivant et identifie ses composantes argumentatives, dans la même langue que le texte original.
        Règles :
        - Présente les éléments dans cet ordre en Markdown :
          **Thèse principale** : l'idée centrale défendue
          **Arguments majeurs** : liste numérotée des arguments principaux
          **Preuves et exemples** : liste des éléments factuels ou illustratifs utilisés
          **Contre-arguments** : objections mentionnées ou implicites, le cas échéant
        - Si le texte n'est pas argumentatif, réponds uniquement : "Ce texte n'a pas de structure argumentative identifiable."
        - Réponds uniquement avec l'analyse structurée, sans commentaire
        """,
        icon: "⚖️",
        category: .analyze
    ),
    PromptSuggestion(
        name: "Extrais les actions concrètes",
        prompt: """
        Analyse le texte suivant et identifie toutes les actions, recommandations ou étapes pratiques mentionnées, dans la même langue que le texte original.
        Règles :
        - Regroupe les actions par thème ou par priorité logique, même si le texte est désorganisé
        - Présente chaque groupe avec un intitulé en **gras** suivi des actions en liste numérotée
        - Formule chaque action à l'infinitif, de manière courte et actionnable
        - Utilise le format Markdown pour la mise en forme
        - Si aucune action n'est identifiable, réponds uniquement : "Aucune action concrète identifiée."
        - Réponds uniquement avec la liste structurée, sans introduction ni commentaire
        """,
        icon: "✅",
        category: .analyze
    ),
    PromptSuggestion(
        name: "Analyse les biais",
        prompt: """
        Tu es un expert en pensée critique et rhétorique. Analyse le texte suivant et identifie les biais cognitifs, présupposés, positions idéologiques ou angles implicites présents, dans la même langue que le texte original.
        Règles :
        - Présente chaque biais détecté sous forme de liste en Markdown
        - Pour chaque biais : indique son **nom** en gras, cite brièvement le passage concerné entre guillemets, puis explique en une phrase en quoi il constitue un biais
        - Si aucun biais n'est détecté, réponds uniquement : "Aucun biais identifiable dans ce texte."
        - Réponds uniquement avec l'analyse, sans introduction ni commentaire
        """,
        icon: "🙅",
        category: .analyze
    ),
    PromptSuggestion(
        name: "Génère des questions",
        prompt: """
        Lis le texte suivant et génère une liste de questions pertinentes, dans la même langue que le texte original.
        Règles :
        - Propose entre 3 et 10 questions selon la richesse du texte, réparties en trois catégories présentées en Markdown :
          **Compréhension** : questions pour vérifier la bonne lecture du texte
          **Approfondissement** : questions pour aller plus loin sur les idées abordées
          **Réflexion critique** : questions pour challenger les positions ou ouvrir le débat
        - Chaque question doit être précise et ancrée dans le contenu du texte — n'invente pas de questions hors sujet
        - Réponds uniquement avec la liste structurée en Markdown, sans introduction ni commentaire
        """,
        icon: "❓",
        category: .analyze
    ),
    PromptSuggestion(
        name: "Simplifie",
        prompt: """
        Tu es un expert en vulgarisation. Simplifie le texte suivant pour le rendre accessible à un lecteur non spécialiste, dans la même langue que le texte original.
        Règles :
        - Remplace le vocabulaire technique ou complexe par des mots courants
        - Raccourcis les phrases longues
        - Supprime le jargon sans valeur ajoutée
        - Conserve toutes les idées essentielles sans en dénaturer le sens
        - Conserve la structure du texte original (paragraphes, listes, etc.)
        - Réponds uniquement avec la version simplifiée, sans commentaire
        """,
        icon: "🧩",
        category: .transform
    ),
    PromptSuggestion(
        name: "Améliore le style",
        prompt: """
        Tu es un éditeur expérimenté. Améliore la qualité stylistique et la fluidité du texte suivant, dans la même langue que le texte original.
        Règles :
        - Corrige les lourdeurs, répétitions et maladresses de style
        - Améliore les transitions entre les phrases et les paragraphes
        - Varie le vocabulaire sans trahir le sens original
        - Conserve strictement le contenu, le sens et la structure du texte
        - Conserve la mise en forme originale (paragraphes, listes, etc.)
        - Réponds uniquement avec la version améliorée, sans commentaire
        """,
        icon: "✨",
        category: .transform
    ),
    PromptSuggestion(
        name: "Optimise pour le SEO",
        prompt: """
        Tu es un expert en rédaction web et SEO. Réécris le texte suivant pour améliorer sa lisibilité web et son référencement naturel, dans la même langue que le texte original.
        Règles :
        - Structure le contenu avec des titres et sous-titres hiérarchiques si pertinent (H1, H2, H3)
        - Rédige des paragraphes courts et aérés
        - Privilégie les phrases actives et directes
        - Intègre naturellement les mots-clés présents dans le texte original
        - Conserve toutes les informations originales sans en ajouter de nouvelles
        - Utilise le format Markdown pour la mise en forme
        - Réponds uniquement avec la version optimisée, sans commentaire
        """,
        icon: "🔍",
        category: .transform
    ),
    PromptSuggestion(
        name: "Adopte un ton professionnel",
        prompt: """
        Role: Tu es un éditeur professionnel.
        Task: Réécris le texte suivant avec un ton professionnel, dans la même langue que le texte original.
        Règles :
        • Adopte un registre formel, soigné et bienveillant
        • Remplace les tournures familières, relâchées ou ambiguës
        • Conserve strictement le sens et les informations du texte original
        • Conserve la structure du texte (paragraphes, listes, etc.)
        • Réponds uniquement avec la version réécrite, sans commentaire
        """,
        icon: "🕴️",
        category: .transform
    ),
    PromptSuggestion(
        name: "Réorganise la logique",
        prompt: """
        Tu es un éditeur expérimenté. Réorganise le texte suivant pour améliorer sa structure logique et la progression des idées, dans la même langue que le texte original.
        Règles :
        - Regroupe les idées et paragraphes similaires
        - Ordonne les éléments du général au particulier, ou selon une progression naturelle
        - Conserve intégralement toutes les phrases et informations du texte original — ne supprime rien, ne reformule rien
        - Conserve la mise en forme originale (listes, titres, etc.)
        - Réponds uniquement avec le texte réorganisé, sans commentaire
        """,
        icon: "🧠",
        category: .structure
    ),
    PromptSuggestion(
        name: "Convertis en tableau",
        prompt: """
        Analyse le texte suivant et transforme ses informations en tableau structuré en Markdown, dans la même langue que le texte original.
        Règles :
        - Détermine les colonnes les plus pertinentes selon le contenu (ex. Concept / Description / Exemple, ou Critère / Avantages / Inconvénients, etc.)
        - Chaque ligne du tableau correspond à un élément, une idée ou une entrée distincte
        - Conserve toutes les informations importantes du texte original
        - Si le texte ne se prête pas à un tableau, réponds uniquement : "Ce texte ne peut pas être converti en tableau de manière pertinente."
        - Réponds uniquement avec le tableau en Markdown, sans commentaire
        """,
        icon: "📊",
        category: .structure
    ),
    PromptSuggestion(
        name: "Génère un plan d'actions",
        prompt: """
        Tu es un expert en gestion de projet et en organisation. À partir du texte suivant — qui peut être des notes brutes, désorganisées ou incomplètes — génère un plan d'actions structuré et progressif, dans la même langue que le texte original.
        Règles :
        • Organise les actions en phases logiques et séquentielles, chacune avec un titre clair en Markdown (## Phase 1 — Nom, etc.)
        • Sous chaque phase, liste les tâches à effectuer sous forme de cases à cocher Markdown (- [ ] Tâche)
        • Si une phase comporte des risques, prérequis ou points d'attention, ajoute-les sous un intitulé ⚠️ Points d'attention en liste à puces
        • Regroupe les tâches similaires dans la même phase, même si elles apparaissent éparpillées dans le texte
        • Ne supprime aucune information utile du texte original
        • Si une information est ambiguë, formule la tâche correspondante avec un ? en fin de ligne pour signaler qu'une clarification est nécessaire
        • Réponds uniquement avec le plan en Markdown, sans introduction ni commentaire
        """,
        icon: "🗺️",
        category: .structure
    ),
    PromptSuggestion(
        name: "Propose des titres",
        prompt: """
        Analyse le texte suivant et propose 5 titres pertinents et accrocheurs, dans la même langue que le texte original.
        Règles :
        - Chaque titre doit être court, clair et refléter fidèlement le contenu
        - Varie les approches : informatif, intrigant, direct, questions, etc.
        - Présente les titres sous forme de liste numérotée en Markdown
        - Réponds uniquement avec la liste, sans commentaire
        """,
        icon: "📰",
        category: .propose
    ),
    PromptSuggestion(
        name: "Propose un plan structuré",
        prompt: """
        Analyse le texte suivant et transforme-le en plan hiérarchique, dans la même langue que le texte original.
        Règles :
        - Utilise une numérotation claire : I / A / 1 / a
        - Regroupe les idées similaires sous des parties cohérentes
        - Les intitulés doivent être courts et explicites
        - N'inclus pas le contenu du texte, uniquement les intitulés du plan
        - Utilise le format Markdown pour la mise en forme
        - Réponds uniquement avec le plan, sans commentaire
        """,
        icon: "🗂️",
        category: .propose
    ),
]


// MARK: - Templates View (Grid of Cards)

struct TemplatesView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var store = ActionsStore.shared
    @State private var selectedCategory: PromptCategory? = nil
    @State private var addedTemplateId: UUID? = nil
    var onNavigateToActions: (Action) -> Void

    var filteredTemplates: [PromptSuggestion] {
        if let category = selectedCategory {
            return promptSuggestions.filter { $0.category == category }
        }
        return promptSuggestions
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

    func addTemplateToActions(_ template: PromptSuggestion) {
        // V1 : nombre d'actions illimité.
        let newAction = Action(
            name: template.name,
            icon: template.icon,
            prompt: template.prompt,
            actionType: .ai
        )
        store.addAction(newAction)

        // Show confirmation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            addedTemplateId = template.id
        }

        // Navigate to Actions tab after a short delay and select the new action
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                addedTemplateId = nil
            }
            onNavigateToActions(newAction)
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
                            isAdded: addedTemplateId == template.id,
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
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(template.category.color.opacity(0.2))
                            .frame(width: 36, height: 36)
                            .offset(y: 2)

                        RoundedRectangle(cornerRadius: 8)
                            .fill(template.category.color.opacity(0.12))
                            .frame(width: 36, height: 36)

                        Text(template.icon)
                            .font(.system(size: 20))
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

                // Prompt preview
                Text(template.prompt)
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
