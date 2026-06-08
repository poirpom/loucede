//
//  PolishTokens.swift
//  loucede
//
//  Phase Q.1.a — Fondations du polish « popups Things-style ».
//
//  Infrastructure visuelle PARTAGÉE par les 4 surfaces déclenchées par ⌥&
//  (popup principal, mini-popover génération, popover édition, fenêtre de
//  réponse). Q.1.a ne consomme rien : ce fichier est purement additif. La
//  première consommation (et donc la validation visuelle) arrive en Q.1.b.
//
//  Grammaire visuelle : vibrancy macOS (hudWindow), différenciation des zones
//  par tons de fond uniquement (pas de bordures), champs sans contour, coins
//  arrondis prononcés. Cadrage complet : loucede-private/details/polish-popups-things.md
//

import SwiftUI
import AppKit

// MARK: - Tokens sémantiques

/// Valeurs de design partagées du polish des popups (Phase Q.1).
///
/// Namespace de constantes (pas d'instances). Les couleurs dépendantes du
/// mode suivent le pattern projet `@Environment(\.colorScheme)` + ternaire
/// (cf. SettingsView/ActionsView) via des fonctions prenant un `ColorScheme`.
enum PolishTokens {

    // MARK: Matériau

    /// Matériau vibrancy des 4 surfaces.
    static let material: NSVisualEffectView.Material = .hudWindow

    // MARK: Géométrie

    /// Rayon des coins du panneau. 16 = valeur app actuelle (choix délibéré
    /// K.4-lot1 P3, mirrorée côté NSWindow via `hostingView.layer.cornerRadius`).
    static let cornerRadius: CGFloat = 16
    static let paddingHorizontal: CGFloat = 16
    static let paddingVertical: CGFloat = 12

    // MARK: Fonds de zone

    /// Overlay semi-translucide marquant une zone d'accent (bandeau header /
    /// footer) par-dessus la vibrancy. Inversion des tons light/dark.
    static func accentBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(white: 0.0, opacity: 0.40)
            : Color(white: 1.0, opacity: 0.60)
    }

    /// Fond de la zone neutre = vibrancy pure, donc `.clear` (aucun overlay).
    /// À DESSEIN, aucun view modifier `.polishNeutralBackground()` n'est exposé :
    /// une zone neutre ne pose simplement aucun fond et laisse transparaître le
    /// matériau du panneau. Ce token existe pour la sémantique / la doc, en
    /// pendant de `accentBackground(_:)`.
    static let neutralBackground: Color = .clear

    // MARK: Dividers

    /// Couleur des séparateurs style macOS (fins, jamais pleine largeur).
    static func dividerColor(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(white: 1.0, opacity: 0.10)
            : Color(white: 0.0, opacity: 0.08)
    }
    static let dividerHeight: CGFloat = 0.5
    static let dividerPaddingHorizontal: CGFloat = 12

    // MARK: Accent / sélection / curseur

    /// Bleu d'accent loucedé (#3F84F7), identique light/dark. Réservé à la row
    /// sélectionnée et au curseur de saisie. Réutilise `Color(hex:)` global.
    static let selectionBackground = Color(hex: "3F84F7")
    static let cursorColor = Color(hex: "3F84F7")

    // MARK: Ombre

    /// Tokens d'ombre exposés mais NON bundlés dans `polishVibrancy` : la
    /// NSWindow porte déjà une ombre native ; l'application éventuelle par
    /// surface relève de Q.1.b/c/d.
    static let shadowColor = Color.black.opacity(0.25)
    static let shadowRadius: CGFloat = 20
    static let shadowOffsetY: CGFloat = 4
}

// MARK: - Wrapper vibrancy

/// Pont SwiftUI vers `NSVisualEffectView` (blending `.behindWindow` → floute le
/// contenu derrière la fenêtre). Matériau paramétrable, défaut `.hudWindow`.
struct PolishVibrancyView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = PolishTokens.material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

// MARK: - View modifiers

extension View {

    /// Base d'un panneau polish : pose la vibrancy en fond et clippe aux coins
    /// arrondis. Remplace le couple `.background(windowBg).clipShape(...)`.
    /// À appliquer sur la racine de chacune des 4 surfaces.
    func polishVibrancy(
        material: NSVisualEffectView.Material = PolishTokens.material,
        cornerRadius: CGFloat = PolishTokens.cornerRadius
    ) -> some View {
        background(PolishVibrancyView(material: material))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// Marque une zone d'accent (bandeau header/footer) par un overlay
    /// semi-translucide adaptatif light/dark, par-dessus la vibrancy du panneau.
    func polishAccentBackground() -> some View {
        modifier(PolishAccentBackground())
    }
}

/// Implémentation de `.polishAccentBackground()` — lit `colorScheme` en interne
/// pour que les call sites n'aient pas à le propager.
private struct PolishAccentBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background(PolishTokens.accentBackground(colorScheme))
    }
}

// MARK: - Divider

/// Séparateur style macOS (0.5pt, retrait horizontal pour ne pas toucher les
/// bords, couleur adaptative light/dark). À glisser entre groupes (catégories
/// d'actions, groupes du menu déroulant catégorie).
struct PolishDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(PolishTokens.dividerColor(colorScheme))
            .frame(height: PolishTokens.dividerHeight)
            .padding(.horizontal, PolishTokens.dividerPaddingHorizontal)
    }
}
