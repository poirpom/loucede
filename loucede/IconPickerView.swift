//
//  IconPickerView.swift
//  loucede
//
//  Phase 6.4 (2026-04-23) : bascule SF Symbols → emojis.
//  Le fichier conserve son nom pour éviter un remaniement du
//  projet Xcode, mais son contenu est désormais :
//  - `ActionIconView` : composant d'affichage réutilisable (emoji
//    avec boîte fixe + fallback placeholder gris pour SF legacy)
//  - `EmojiPickerView` : picker flottant qui remplace la grille
//    SF historique. Offre un TextField grand format (capture
//    emoji tapé / collé / sélectionné via ⌃⌘Espace) + bouton
//    d'ouverture du panneau emoji système natif.
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
                // Cercle gris discret — l'utilisateur rouvre l'action
                // pour choisir un emoji via le picker système.
                Circle()
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: fontSize * 0.7, height: fontSize * 0.7)
            }
        }
        .frame(width: boxSize, height: boxSize)
    }
}

// MARK: - Emoji Picker View (édition)

/// Picker flottant affiché depuis `ActionEditorView` quand l'utilisateur
/// clique sur l'icône d'une action. Remplace l'ancienne grille
/// `IconPickerView` (192 SF Symbols).
///
/// UX : un grand TextField centré auto-focalisé — l'utilisateur peut
/// soit taper un emoji, soit appuyer sur ⌃⌘Espace pour ouvrir le
/// panneau emoji système natif (recherche + catégories fournies par
/// macOS). Un bouton « Ouvrir le sélecteur » le propose explicitement
/// pour découverte.
///
/// API identique à l'ancien picker : `selectedIcon: String` (valeur
/// actuelle, pré-remplit le champ) + `onSelect: (String) -> Void`
/// (appelée dès qu'un emoji valide est saisi). Le callback
/// déclenche la fermeture du picker côté appelant.
struct EmojiPickerView: View {
    @Environment(\.colorScheme) var colorScheme
    let selectedIcon: String
    let onSelect: (String) -> Void

    @State private var input: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Choisis un emoji")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            // Grand champ éditable — l'utilisateur tape / colle / sélectionne
            // via le sélecteur système. Le `.onChange` ci-dessous normalise
            // le contenu à un seul emoji et déclenche le callback.
            TextField("", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 48))
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .frame(width: 80, height: 80)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isFocused ? Color.accentColor.opacity(0.6) : Color.gray.opacity(0.2), lineWidth: 1)
                )
                .onChange(of: input) { _, newValue in
                    handleInputChange(newValue)
                }

            VStack(spacing: 2) {
                Text("Tape un emoji, colle-le,")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("ou ⌃⌘Espace pour le sélecteur système")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Button {
                // Focus le champ avant d'ouvrir la palette pour que l'emoji
                // choisi y soit inséré automatiquement par le système.
                isFocused = true
                NSApp.orderFrontCharacterPalette(nil)
            } label: {
                Label("Ouvrir le sélecteur d'emoji", systemImage: "face.smiling")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(width: 280)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        .onAppear {
            // Pré-remplit avec l'emoji courant si c'en est un ; sinon champ vide
            // pour inciter l'utilisateur à choisir (cas SF legacy non migré).
            input = selectedIcon.isEmojiOnly ? selectedIcon : ""
            // Léger délai pour que la focus prise après l'animation d'ouverture.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }

    /// Normalise une saisie quelconque à un unique emoji grapheme cluster.
    /// - Si `newValue` est vide : rien à faire (utilisateur a effacé).
    /// - Si le dernier caractère est un emoji : on le garde seul et on notifie.
    /// - Si le dernier caractère n'est pas un emoji : on restaure l'état.
    private func handleInputChange(_ newValue: String) {
        guard !newValue.isEmpty else { return }

        // On prend le dernier grapheme cluster (gère emojis composés ZWJ, flags…)
        if let lastCluster = newValue.last {
            let candidate = String(lastCluster)
            if candidate.isEmojiOnly {
                if input != candidate {
                    input = candidate
                }
                onSelect(candidate)
                return
            }
        }

        // Saisie non-emoji : rejette et restaure.
        input = selectedIcon.isEmojiOnly ? selectedIcon : ""
    }
}

// MARK: - Preview

#Preview("EmojiPicker") {
    EmojiPickerView(selectedIcon: "🍳") { emoji in
        print("Selected: \(emoji)")
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
