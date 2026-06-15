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

    // MARK: Géométrie

    /// Rayon des coins du panneau. 16 = valeur app actuelle (choix délibéré
    /// K.4-lot1 P3, mirrorée côté NSWindow via `hostingView.layer.cornerRadius`).
    static let cornerRadius: CGFloat = 16
    static let paddingHorizontal: CGFloat = 16
    static let paddingVertical: CGFloat = 12

    // MARK: Typo — fenêtre de réponse (Phase S — C2)
    //
    // Valeurs STRUCTURANTES de la fenêtre de réponse (lecture longue). Le
    // RENDU des styles markdown vit dans `Theme.loucedeResult` (ResultTheme.swift),
    // posé via `.markdownTheme(...)`. Caveat assumé : le fond du code inline est
    // plat (radius/padding non supportés par l'API text-style MarkdownUI).

    /// Largeur de la fenêtre de réponse. Source UNIQUE partagée par le frame
    /// NSWindow (`resizePopover` .resultCompact) ET le frame du contenu SwiftUI
    /// (PopoverView) → pas de bande transparente latérale. Distincte de
    /// `popoverDefaultWidth` (400, liste/générateur = surfaces de scan).
    /// 618 = bloc texte ~528pt (≈66 car. × 8pt, longueur de ligne optimale)
    /// + 2×45 padding latéral. Calé runtime C2-fix.
    static let resultWindowWidth: CGFloat = 618
    /// Padding latéral du corps markdown (généreux — mesure de lecture).
    static let resultPaddingHorizontal: CGFloat = 45
    static let resultPaddingVertical: CGFloat = 24

    /// Corps markdown (MarkdownUI `\.text`). 16pt = confort lecture écran.
    static let resultBodyFontSize: CGFloat = 16
    /// Interligne ADDITIF relatif (`relativeLineSpacing(.em(_))`). 0.3 ≈ 1,5×
    /// effectif (leading SF naturel ~1,2× + 0,3). À caler à l'œil.
    static let resultLineSpacingEm: CGFloat = 0.3
    /// Marge basse de paragraphe (rythme vertical de la prose). Les items de
    /// liste « tight » l'ignorent (MarkdownUI) → espacement propre via
    /// `resultListItemSpacing`.
    static let resultParagraphSpacing: CGFloat = 16
    /// Espacement entre items de liste (léger — surface de scan dans la lecture).
    static let resultListItemSpacing: CGFloat = 5

    /// Échelle des titres (H1→H4). H4 = taille du corps, distingué par la
    /// GRAISSE (.bold) vs les H1-H3 (.semibold) — cf. ResultTheme.
    static let resultH1FontSize: CGFloat = 24
    static let resultH2FontSize: CGFloat = 20
    static let resultH3FontSize: CGFloat = 18
    static let resultH4FontSize: CGFloat = 16

    /// Fond plat du code (inline + bloc). Adaptatif light/dark via `.secondary`.
    static let resultInlineCodeBackground: Color = .secondary.opacity(0.12)
    static let resultCodeBlockBackground: Color = .secondary.opacity(0.15)
    static let resultCodeBlockCornerRadius: CGFloat = 8
    static let resultCodeBlockPadding: CGFloat = 12

    /// Blockquote — barre verticale gauche. Bleu loucedé #3F84F7 (identité)
    /// en trait FIN (2pt) pour la retenue. C2-fix : la coquetterie validée à
    /// l'œil ; repli `Color(nsColor: .separatorColor)` si jamais trop présente.
    static let resultBlockquoteBarColor: Color = Color(hex: "3F84F7")
    static let resultBlockquoteBarWidth: CGFloat = 2
    static let resultBlockquoteIndent: CGFloat = 12

    // MARK: Barre d'actions sur l'action (fenêtre de réponse — ResultActionsBar)

    /// Q.2.h.2 v2 (Option C) — zone « actions sur l'action affichée » posée
    /// sous le header de la fenêtre de réponse, en continuité visuelle (même
    /// fond accent, pas de séparateur). Contenu : ⌘S Sauvegarder · ⌘E Éditer
    /// (pattern footer : KeyboardKey + label, boutons .plain). Visible via
    /// `PopoverState.showsResultActionsBar` (V1.x-ready).
    /// Hauteur TOTALE de la barre (contenu ~22 + padding bas 10). Sert aussi
    /// au calcul de la hauteur fenêtre (`resizePopover` .resultCompact).
    static let resultActionsBarHeight: CGFloat = 32
    static let resultActionsBarBottomPadding: CGFloat = 10
    /// Espace entre les items ⌘S / ⌘E.
    static let resultActionsBarItemSpacing: CGFloat = 16
    /// Durée des animations d'apparition (fade + slide-down post-settle) et
    /// de disparition (fade + collapse sync resize, pattern K.2-B lot 2b).
    static let resultActionsBarFadeDuration: Double = 0.25

    // MARK: Timing animation resize (popover)

    /// Durée de l'animation NSWindow `resizePopover` par défaut (transitions
    /// liste↔résultat, phases du générateur). Restée snappy.
    static let popoverResizeDuration: Double = 0.25

    /// Q.3 — hauteur de la zone réservée au spinner de génération d'action
    /// (mini-popover Générateur, phase `.loading`). Gabarit volontairement
    /// modéré (~picto du `ConfirmationToast` non scalé ×3) : présence visuelle
    /// sans dominer le compteur posé juste en dessous. Cf.
    /// `details/Q.3-polish-compteur-generation.md`.
    static let generationSpinnerHeight: CGFloat = 44

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

    // MARK: Bordure intérieure

    /// Fine bordure intérieure semi-transparente sur les 4 côtés du panneau —
    /// adoucit l'edge net (visible surtout en dark). Inversion des tons.
    static func innerBorderColor(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(white: 1.0, opacity: 0.12)
            : Color(white: 0.0, opacity: 0.08)
    }
    static let innerBorderWidth: CGFloat = 0.5

    // MARK: Accent / sélection / curseur

    /// Bleu d'accent loucedé (#3F84F7), identique light/dark. Réservé à la row
    /// sélectionnée et au curseur de saisie. Réutilise `Color(hex:)` global.
    static let selectionBackground = Color(hex: "3F84F7")
    static let cursorColor = Color(hex: "3F84F7")

    // MARK: Champs (fill subtil — fiches structurées)

    /// Fill subtil des champs d'une fiche multi-champs (générateur, édition
    /// action) — structure visuellement la colonne de champs. `Color.primary`
    /// est déjà colorScheme-aware (noir opaque en light, blanc opaque en dark).
    /// NE PAS appliquer sur un champ isolé (popup Rechercher) — cf. fiche
    /// `details/polish-popups-things.md` (cas limite isolé vs multiples).
    static let fieldFillColor: Color = .primary.opacity(0.06)
    static let fieldFillColorDisabled: Color = .primary.opacity(0.04)
    static let fieldFillCornerRadius: CGFloat = 8

    // MARK: Ombre

    /// Tokens d'ombre exposés mais NON bundlés dans `polishVibrancy` : la
    /// NSWindow porte déjà une ombre native ; l'application éventuelle par
    /// surface relève de Q.1.b/c/d.
    static let shadowColor = Color.black.opacity(0.25)
    static let shadowRadius: CGFloat = 20
    static let shadowOffsetY: CGFloat = 4
}

// MARK: - View modifiers

extension View {

    // Nom historique. La vibrancy a été retirée pour lisibilité (dogfooding
    // 09/06). Le modifier conserve le clip et la bordure intérieure. Renommage
    // en backlog tech.
    //
    /// Pose un fond opaque adaptatif (`windowBackgroundColor`, suit light/dark),
    /// clippe aux coins arrondis et ajoute la bordure intérieure subtile.
    /// À appliquer sur la racine de chacune des 4 surfaces.
    func polishVibrancy(
        cornerRadius: CGFloat = PolishTokens.cornerRadius
    ) -> some View {
        background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .polishInnerBorder(cornerRadius: cornerRadius)
    }

    /// Marque une zone d'accent (bandeau header/footer) par un overlay
    /// semi-translucide adaptatif light/dark, par-dessus la vibrancy du panneau.
    func polishAccentBackground() -> some View {
        modifier(PolishAccentBackground())
    }

    /// Fine bordure intérieure semi-transparente sur les 4 côtés (adoucit
    /// l'edge net du panneau). Primitive réutilisable : composée par
    /// `polishVibrancy()` ET applicable directement (cas du body popup, qui
    /// pose son fond via un conditionnel et n'appelle pas le sucre).
    func polishInnerBorder(cornerRadius: CGFloat = PolishTokens.cornerRadius) -> some View {
        modifier(PolishInnerBorder(cornerRadius: cornerRadius))
    }

    /// Fill subtil pour structurer un champ dans une fiche multi-champs
    /// (générateur, édition action). Ne PAS appliquer sur les champs isolés
    /// (popup Rechercher) — voir la fiche `details/polish-popups-things.md`.
    func polishFieldFill(disabled: Bool = false) -> some View {
        modifier(PolishFieldFill(disabled: disabled))
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

/// Implémentation de `.polishFieldFill(disabled:)` — fill subtil arrondi.
/// `Color.primary` étant déjà colorScheme-aware, pas de lecture d'environnement.
private struct PolishFieldFill: ViewModifier {
    var disabled: Bool

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: PolishTokens.fieldFillCornerRadius)
                .fill(disabled ? PolishTokens.fieldFillColorDisabled : PolishTokens.fieldFillColor)
        )
    }
}

/// Implémentation de `.polishInnerBorder(cornerRadius:)` — lit `colorScheme`
/// en interne. `strokeBorder` reste à l'intérieur du rect (inset propre,
/// aligné sur le clip parent).
private struct PolishInnerBorder: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(PolishTokens.innerBorderColor(colorScheme),
                              lineWidth: PolishTokens.innerBorderWidth)
        )
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
