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

/// Affiche l'icône d'une action — soit un emoji (cas normal après
/// Phase 6.4), soit un placeholder gris si la chaîne stockée n'est
/// pas un emoji valide (icônes SF Symbols legacy d'actions custom
/// créées avant la migration, ou `icon` vide).
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

    var body: some View {
        Group {
            if icon.isEmojiOnly {
                Text(icon)
                    .font(.system(size: fontSize))
            } else {
                // Fallback : SF Symbol legacy non migré, ou icon vide.
                // Cercle gris discret — l'utilisateur clique dessus pour
                // ouvrir le picker système et choisir un emoji.
                Circle()
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: fontSize * 0.7, height: fontSize * 0.7)
            }
        }
        .frame(width: boxSize, height: boxSize)
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

    /// Champ-tampon invisible : reçoit l'emoji inséré par la palette
    /// système. Vidé après chaque traitement pour ne pas accumuler les
    /// graphème entre deux ouvertures successives.
    @State private var hiddenInput: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Affichage visible — identique au reste de l'app.
            ActionIconView(icon: icon, boxSize: boxSize, fontSize: fontSize)

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

#Preview("ActionIcon – fallback") {
    HStack {
        ActionIconView(icon: "text.cursor") // SF legacy → placeholder
        ActionIconView(icon: "")             // vide → placeholder
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
