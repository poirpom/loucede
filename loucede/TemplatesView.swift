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

// K.unify.1 (2026-05-20) : `enum PromptCategory` déplacée vers
// `Models.swift` (logique car `Action` l'utilise désormais via le
// champ `category`).

// K.unify.1 (2026-05-20) — SHIM : `promptSuggestions` reste exposé
// comme `let` top-level pour ne pas casser PopoverView K.1 (section
// MODÈLES de la popup) ni la vue Réglages → Modèles pendant la
// transition. Sa valeur est désormais DÉRIVÉE de
// `ActionsStore.defaultActions` (source de vérité unique du modèle
// unifié K.unify). Mapping Action → PromptSuggestion : on ne retient
// que les Actions ayant une `category` non-nil (les 24 seeds en ont
// une, les actions custom créées par l'utilisateur n'en ont
// généralement pas → exclues du shim, ce qui préserve la sémantique
// historique « catalogue Modèles » vs « actions custom »).
//
// ⚠️ À SUPPRIMER en K.unify.3 lors de la refonte popup (section
// MODÈLES sera remplacée par la liste unifiée filtrée par
// catégorie/favoris, lisant directement `ActionsStore.shared.actions`).
//
// Le shim est un closure auto-évalué `{ ... }()` pour que les UUID des
// PromptSuggestion soient stables sur toute la session (lazy init du
// top-level `let` garanti par Swift).
let promptSuggestions: [PromptSuggestion] = {
    ActionsStore.defaultActions.compactMap { action -> PromptSuggestion? in
        guard let category = action.category else { return nil }
        return PromptSuggestion(
            name: action.name,
            description: action.shortDescription ?? "",
            prompt: action.prompt,
            icon: action.icon,
            category: category
        )
    }
}()


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
