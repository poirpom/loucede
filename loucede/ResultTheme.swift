//
//  ResultTheme.swift
//  loucede
//
//  Phase S (C2) — thème MarkdownUI dédié à la fenêtre de réponse IA.
//
//  La fenêtre de réponse est le livrable central (ce que l'utilisateur vient
//  LIRE). Ce thème optimise la lecture longue sur écran : corps 16pt, interligne
//  ~1,5×, échelle de titres resserrée, gras franc, code lisible (bloc qui WRAP),
//  blockquote à barre verticale. Construit à partir de `.basic` (on hérite des
//  défauts sains — tables, listes, h5/h6) en n'écrasant que les styles cadrés.
//
//  Les valeurs STRUCTURANTES (tailles, largeur, paddings, interligne) vivent
//  dans `PolishTokens` ; le RENDU (graisses, marges par niveau, barre, fonds)
//  est ici. Caveat V1 accepté : le code INLINE n'a qu'un fond plat (radius +
//  padding non supportés par l'API text-style MarkdownUI — cf. DocumentationView).
//

import SwiftUI
import MarkdownUI

extension Theme {

    /// Thème de lecture de la fenêtre de réponse. Posé via `.markdownTheme(...)`
    /// sur le `Markdown(state.resultText)` de `PopoverView.resultView`.
    static let loucedeResult = Theme.basic
        // Corps 16pt (vs défaut macOS 13).
        .text {
            FontSize(PolishTokens.resultBodyFontSize)
        }
        // Gras FRANC (le défaut `.basic` est `.semibold`, trop proche du corps).
        .strong {
            FontWeight(.bold)
        }
        // Code inline : monospace + fond plat subtil (caveat radius/padding).
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.92))
            BackgroundColor(PolishTokens.resultInlineCodeBackground)
        }
        // Paragraphe : interligne ~1,5× + rythme vertical de prose. Les listes
        // « tight » (sans ligne vide entre items) ignorent cette marge basse.
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(PolishTokens.resultLineSpacingEm))
                .markdownMargin(bottom: PolishTokens.resultParagraphSpacing)
        }
        // Titres : échelle 24/20/18/16, marges DIFFÉRENCIÉES (plus avant
        // qu'après, plus pour H1/H2 que H3/H4). H1-H3 .semibold, H4 .bold
        // (H4 = taille du corps → c'est la graisse qui le distingue du texte).
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: 28, bottom: 8)
                .markdownTextStyle {
                    FontSize(PolishTokens.resultH1FontSize)
                    FontWeight(.semibold)
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: 24, bottom: 8)
                .markdownTextStyle {
                    FontSize(PolishTokens.resultH2FontSize)
                    FontWeight(.semibold)
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: 20, bottom: 6)
                .markdownTextStyle {
                    FontSize(PolishTokens.resultH3FontSize)
                    FontWeight(.semibold)
                }
        }
        .heading4 { configuration in
            configuration.label
                .markdownMargin(top: 16, bottom: 6)
                .markdownTextStyle {
                    FontSize(PolishTokens.resultH4FontSize)
                    FontWeight(.bold)
                }
        }
        // Bloc de code : WRAP (Text natif, pas de scroll horizontal) + fond +
        // padding + radius. Pattern DocumentationView:443-450.
        .codeBlock { configuration in
            Text(configuration.content)
                .font(.system(size: PolishTokens.resultBodyFontSize * 0.92,
                              design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PolishTokens.resultCodeBlockPadding)
                .background(PolishTokens.resultCodeBlockBackground)
                .clipShape(RoundedRectangle(cornerRadius: PolishTokens.resultCodeBlockCornerRadius))
                .markdownMargin(bottom: PolishTokens.resultParagraphSpacing)
        }
        // Blockquote : barre verticale gauche + retrait, SANS italique (l'override
        // du blockStyle remplace le `.basic` qui appliquait `FontStyle(.italic)`).
        .blockquote { configuration in
            HStack(alignment: .top, spacing: PolishTokens.resultBlockquoteIndent) {
                RoundedRectangle(cornerRadius: PolishTokens.resultBlockquoteBarWidth / 2)
                    .fill(PolishTokens.resultBlockquoteBarColor)
                    .frame(width: PolishTokens.resultBlockquoteBarWidth)
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 4, bottom: PolishTokens.resultParagraphSpacing)
        }
        // Items de liste : léger espacement (la marge collapse avec la marge
        // basse de paragraphe pour les listes « loose »).
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: PolishTokens.resultListItemSpacing)
        }
}
