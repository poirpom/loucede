//
//  IconPickerView.swift
//  loucede
//
//  Phase 6.4 (2026-04-23) : bascule SF Symbols → emojis.
//  Phase 6.10 (2026-04-25) : suppression du popover custom au profit
//  de l'emoji picker système ancré directement sous l'emoji cliqué.
//
//  Le fichier conserve son nom pour éviter un remaniement du projet
//  Xcode, mais son contenu est désormais :
//  - `ActionIconView` : composant d'affichage (emoji avec boîte fixe
//    + fallback placeholder gris pour SF legacy ou icon vide)
//  - `EmojiPickerButton` : bouton-emoji cliquable qui ouvre directement
//    le sélecteur emoji système (NSApp.orderFrontCharacterPalette)
//    ancré sous lui via un TextField caché auto-focalisé.
//

import SwiftUI
import AppKit

// MARK: - Action Icon View (affichage)

/// Style du placeholder rendu quand `icon` n'est pas un emoji valide
/// (mini-session 2026-05-08). Distingue deux contextes d'affichage :
/// - `.grayCircle` (défaut) : lecture seule. Petit cercle gris discret
///   pour les surfaces non-éditables (sidebar Actions, cards Modèles,
///   popup principale). Communique « pas d'emoji, sans plus ».
/// - `.plusButton` : édition. Cercle stroké avec un « + » centré, pour
///   les surfaces où l'utilisateur peut cliquer pour ouvrir le picker
///   emoji (panneau détail Actions via `EmojiPickerButton`). Communique
///   « clique ici pour choisir un emoji ».
enum IconPlaceholderStyle {
    case grayCircle
    case plusButton
}

/// Affiche l'icône d'une action — soit un emoji (cas normal après
/// Phase 6.4), soit un placeholder si la chaîne stockée n'est pas un
/// emoji valide (icônes SF Symbols legacy d'actions custom créées
/// avant la migration, ou `icon` vide, ou la valeur `"star"` posée par
/// défaut par `addNewAction` — héritée de TextAd, jamais remappée
/// puisque hors du seed historique de Phase 6.4).
///
/// Le style du placeholder est paramétrable via `placeholderStyle` :
/// rond gris discret (défaut, lecture seule) ou bouton « + » avec
/// cercle stroké (édition).
///
/// Boîte de taille fixe pour éviter que la liste popup "danse"
/// selon la forme de chaque emoji (drapeau court et large vs
/// smiley haut, etc.).
struct ActionIconView: View {
    let icon: String
    /// Taille de la boîte conteneur (même largeur que hauteur).
    var boxSize: CGFloat = 24
    /// Taille de la police emoji. Fixée pour homogénéiser le rendu
    /// visuel entre emojis de "poids" différents.
    var fontSize: CGFloat = 16
    /// Style du placeholder quand `icon` n'est pas un emoji valide.
    /// Mini-session 2026-05-08 : ajout pour distinguer lecture seule
    /// vs édition. Défaut `.grayCircle` rétrocompat avec tous les
    /// call-sites existants.
    var placeholderStyle: IconPlaceholderStyle = .grayCircle

    var body: some View {
        Group {
            if icon.isEmojiOnly {
                Text(icon)
                    .font(.system(size: fontSize))
            } else {
                placeholder
            }
        }
        .frame(width: boxSize, height: boxSize)
    }

    @ViewBuilder
    private var placeholder: some View {
        switch placeholderStyle {
        case .grayCircle:
            // Rond gris discret — surfaces lecture seule.
            Circle()
                .fill(Color.gray.opacity(0.25))
                .frame(width: fontSize * 0.7, height: fontSize * 0.7)
        case .plusButton:
            // Cercle stroké + « + » centré — surface éditable. La
            // taille suit fontSize pour rester proportionnelle à la
            // boîte (24pt fontSize → 24pt cercle → 13pt plus).
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1.5)
                    .frame(width: fontSize, height: fontSize)
                Image(systemName: "plus")
                    .font(.system(size: fontSize * 0.55, weight: .medium))
                    .foregroundColor(Color.gray.opacity(0.6))
            }
        }
    }
}

// MARK: - Emoji Picker Button (édition)

/// Bouton-emoji qui ouvre directement le sélecteur emoji système macOS
/// (`NSApp.orderFrontCharacterPalette`) ancré juste sous lui, sans
/// popover custom intermédiaire.
///
/// Mécanique : un `TextField` invisible (opacity 0.001) est posé sur le
/// même rectangle que l'emoji affiché. Au clic, on focus ce TextField
/// puis on demande au système d'ouvrir la palette. macOS ancre la
/// palette à proximité du focus de saisie texte courant — donc juste
/// sous notre emoji. L'emoji choisi est ensuite inséré dans le
/// TextField, intercepté par `onChange`, normalisé à un seul grapheme
/// cluster, et propagé au modèle via le `@Binding`.
///
/// Phase 6.10 (2026-04-25) : remplace l'ancien `EmojiPickerView` qui
/// affichait un popover custom (titre + grosse preview + texte d'aide
/// + bouton « Rouvrir le sélecteur d'emoji »). Le picker système couvre
/// déjà tous ces besoins (recherche, catégories, récents) — l'UI
/// intermédiaire n'apportait rien.
struct EmojiPickerButton: View {
    @Binding var icon: String
    var boxSize: CGFloat = 36
    var fontSize: CGFloat = 24
    /// Style du placeholder propagé à l'`ActionIconView` interne quand
    /// `icon` n'est pas un emoji. Mini-session 2026-05-08 : par défaut
    /// `.plusButton` parce que ce composant est par construction destiné
    /// aux surfaces éditables (le clic ouvre le picker). Si un call-site
    /// veut un placeholder discret malgré l'éditabilité, il peut passer
    /// `.grayCircle` explicitement.
    var placeholderStyle: IconPlaceholderStyle = .plusButton

    /// Champ-tampon invisible : reçoit l'emoji inséré par la palette
    /// système. Vidé après chaque traitement pour ne pas accumuler les
    /// graphème entre deux ouvertures successives.
    @State private var hiddenInput: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Affichage visible — identique au reste de l'app, avec
            // propagation du style de placeholder choisi par le call-site.
            ActionIconView(
                icon: icon,
                boxSize: boxSize,
                fontSize: fontSize,
                placeholderStyle: placeholderStyle
            )

            // TextField caché posé sur la même boîte que l'emoji.
            // - opacity 0.001 : invisible mais reste focusable (opacity 0
            //   désactive le focus dans certaines versions de SwiftUI).
            // - allowsHitTesting(false) : laisse le tap atteindre le ZStack
            //   pour qu'on puisse intercepter le click et focus
            //   programmatiquement, plutôt que de focuser via le TextField
            //   directement (sinon, premier clic = focus, deuxième clic =
            //   ouvre la palette — UX confuse).
            TextField("", text: $hiddenInput)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .opacity(0.001)
                .frame(width: boxSize, height: boxSize)
                .allowsHitTesting(false)
                .onChange(of: hiddenInput) { _, newValue in
                    handleInputChange(newValue)
                }
        }
        .contentShape(Rectangle())
        // Mini-session 2026-05-08 : curseur main au survol — signale
        // visuellement la cliquabilité du composant que l'utilisateur ait
        // déjà choisi un emoji ou non. Cohérent avec le fait que le clic
        // ouvre le picker quel que soit l'état actuel.
        .pointerCursor()
        .onTapGesture {
            isFocused = true
            // Léger délai (~50 ms) pour laisser SwiftUI propager le focus
            // au TextField avant d'ouvrir la palette. Sans ce délai, macOS
            // ancre parfois la palette à l'ancien focus (champ « name »
            // au-dessus, par ex.) au lieu du nôtre.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSApp.orderFrontCharacterPalette(nil)
            }
        }
    }

    /// Filtre passif : on accepte tout grapheme cluster qui passe
    /// `isEmojiOnly` (donc emojis, drapeaux, ZWJ, modificateurs de
    /// teinte). Les caractères non-emoji (saisie clavier accidentelle
    /// pendant que le TextField est focus) sont silencieusement
    /// ignorés. Le champ est toujours vidé en sortie pour repartir à
    /// zéro à la prochaine ouverture.
    private func handleInputChange(_ newValue: String) {
        guard !newValue.isEmpty else { return }
        if let last = newValue.last {
            let candidate = String(last)
            if candidate.isEmojiOnly {
                icon = candidate
            }
        }
        // Reset systématique pour éviter que des résidus s'accumulent
        // (frappe parasite avant que le picker ne soit ouvert, etc.).
        if !hiddenInput.isEmpty {
            DispatchQueue.main.async {
                hiddenInput = ""
            }
        }
    }
}

// MARK: - Preview

#Preview("EmojiPickerButton") {
    StatefulPreviewWrapper("🍳") { binding in
        EmojiPickerButton(icon: binding)
    }
    .padding()
}

#Preview("ActionIcon – emoji") {
    HStack {
        ActionIconView(icon: "🇫🇷")
        ActionIconView(icon: "🍳", boxSize: 36, fontSize: 24)
        ActionIconView(icon: "💬")
    }
    .padding()
}

#Preview("ActionIcon – fallback gray") {
    HStack {
        ActionIconView(icon: "text.cursor") // SF legacy → placeholder rond gris
        ActionIconView(icon: "")             // vide → placeholder rond gris
        ActionIconView(icon: "star")         // legacy TextAd → placeholder rond gris
    }
    .padding()
}

#Preview("ActionIcon – fallback plus") {
    HStack {
        ActionIconView(icon: "", boxSize: 36, fontSize: 24, placeholderStyle: .plusButton)
        ActionIconView(icon: "star", boxSize: 36, fontSize: 24, placeholderStyle: .plusButton)
        ActionIconView(icon: "🔥", boxSize: 36, fontSize: 24, placeholderStyle: .plusButton)
    }
    .padding()
}

/// Wrapper pour faire fonctionner les `#Preview` qui ont besoin d'un
/// `@Binding` mutable (pas exposé directement par le DSL Preview).
private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(wrappedValue: initial)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}
