//
//  AZERTYKeyboard.swift
//  loucede
//
//  Phase R : clavier AZERTY stylisé du panneau droit de la card « Raccourci »
//  de l'écran accordéon. Valeur pédagogique : l'utilisateur voit OÙ sont les
//  touches de son raccourci sur le clavier physique. Le highlight suit le
//  raccourci réellement enregistré dans ActionsStore (dynamique).
//
//  E.1 — couleurs SÉMANTIQUES adaptatives uniquement (controlBackgroundColor,
//  separatorColor, primary/secondary). Seule exception assumée : le highlight
//  en bleu de MARQUE loucedé via le colorset Any+Dark `OnboardBrandBlue`
//  (cohérence avec les boutons Valider / rows sélectionnées — PAS l'accent
//  système configurable de l'utilisateur).
//

import SwiftUI

struct AZERTYKeyboard: View {
    /// Modifiers ordonnés du raccourci courant (symboles : ^ ⌥ ⇧ ⌘).
    let modifiers: [String]
    /// Touche principale du raccourci (lettre majuscule ou symbole, ex. « & »).
    let key: String

    // MARK: - Dimensions

    // Dimensions calées pour tenir dans le panneau droit ~480 (proto 920×640).
    private let unit: CGFloat = 26      // largeur d'une touche « 1u »
    private let keyHeight: CGFloat = 28
    private let gap: CGFloat = 4

    /// Identités à mettre en surbrillance = modifiers ∪ { touche }.
    /// Les valeurs correspondent aux `id` des KeyCap (cf. `rows`).
    private var highlighted: Set<String> {
        Set(modifiers).union([key.uppercased()])
    }

    /// Libellé lisible du raccourci pour le tooltip (« ⌥ & »).
    private var shortcutLabel: String {
        (modifiers + [key]).joined(separator: " ")
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: gap) {
                        ForEach(row) { cap in
                            keyCapView(cap)
                        }
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)

            shortcutTooltip
        }
    }

    // MARK: - Tooltip « Ton raccourci : ⌥ & »

    private var shortcutTooltip: some View {
        HStack(spacing: 6) {
            Text("Ton raccourci :")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(shortcutLabel)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
                )
        )
    }

    // MARK: - Touche

    @ViewBuilder
    private func keyCapView(_ cap: KeyCap) -> some View {
        let isOn = highlighted.contains(cap.id)
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isOn ? Color("OnboardBrandBlue") : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isOn ? Color("OnboardBrandBlue") : Color(NSColor.separatorColor).opacity(0.5),
                                lineWidth: 1)
                )
            Text(cap.label)
                .font(.system(size: cap.fontSize, weight: .medium, design: .rounded))
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .frame(width: unit * cap.width + gap * (cap.width - 1), height: keyHeight)
        .scaleEffect(isOn ? 1.06 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isOn)
    }

    // MARK: - Layout AZERTY (Mac FR, simplifié pour la pédagogie)

    /// `id` = identité de matching (symbole modifier, lettre majuscule, ou
    /// symbole de touche). `label` = ce qui est dessiné (peut différer de
    /// l'id, ex. control : label « ⌃ » / id « ^ »).
    private struct KeyCap: Identifiable {
        let id: String
        let label: String
        var width: CGFloat = 1
        var fontSize: CGFloat = 12
        init(_ idLabel: String, width: CGFloat = 1, fontSize: CGFloat = 12) {
            self.id = idLabel
            self.label = idLabel
            self.width = width
            self.fontSize = fontSize
        }
        init(id: String, label: String, width: CGFloat = 1, fontSize: CGFloat = 12) {
            self.id = id
            self.label = label
            self.width = width
            self.fontSize = fontSize
        }
    }

    private var rows: [[KeyCap]] {
        [
            // Rangée chiffres (symboles AZERTY non-shiftés). « & » = touche 1.
            ["&", "é", "\"", "'", "(", "§", "è", "!", "ç", "à", ")"].map { KeyCap($0) },
            // AZERTY
            ["A", "Z", "E", "R", "T", "Y", "U", "I", "O", "P"].map { KeyCap($0) },
            // QSDFGHJKLM
            ["Q", "S", "D", "F", "G", "H", "J", "K", "L", "M"].map { KeyCap($0) },
            // WXCVBN + ponctuation, encadrée par ⇧ (modifier bonus optionnel).
            [KeyCap(id: "\u{21E7}", label: "\u{21E7}", width: 1.8)]
            + ["W", "X", "C", "V", "B", "N", ",", ";", ":"].map { KeyCap($0) }
            + [KeyCap(id: "\u{21E7}R", label: "\u{21E7}", width: 1.8)],
            // Rangée modificateurs (id = symbole stocké par le recorder).
            [
                KeyCap(id: "fn", label: "fn", fontSize: 10),
                KeyCap(id: "^", label: "\u{2303}", fontSize: 12),          // control
                KeyCap(id: "\u{2325}", label: "\u{2325}", fontSize: 12),   // option
                KeyCap(id: "\u{2318}", label: "\u{2318}", width: 1.4),     // command
                KeyCap(id: "space", label: "", width: 4.2),
                KeyCap(id: "\u{2318}R", label: "\u{2318}", width: 1.4),    // command droit (id distinct, non matché)
                KeyCap(id: "\u{2325}R", label: "\u{2325}"),                // option droit (id distinct)
            ],
        ]
    }
}
