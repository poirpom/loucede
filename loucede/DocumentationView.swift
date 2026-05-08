//
//  DocumentationView.swift
//  loucede
//
//  Point 4 pre-V1 — phase de transition (2026-05-08 puis suite).
//
//  Cette vue est temporairement un placeholder « En construction » :
//  la webview Notion publique introduite en première version a été
//  abandonnée suite à des observations runtime (breadcrumbs non-filtrés,
//  panneaux latéraux Notion peu adaptés à un contexte embed, liens
//  « retour à la database » qui cassent la promesse de containment
//  loucedé).
//
//  La cible finale est une intégration NATIVE :
//  Notion API + proxy Scaleway + rendu via swift-markdown-ui (déjà en
//  deps). Sera développée en 4 incréments :
//    A — proxy Scaleway + Notion API
//    B — layout fenêtre + binding API
//    C — polish rendu Markdown
//    D — sidebar avec covers + emojis
//
//  L'infrastructure d'ouverture de fenêtre côté `AppDelegate`
//  (`docWindow`, `openDocumentation()`, `setFrameAutosaveName`,
//  shortcut ⌘D dans le popup) reste intacte — seul le contenu rendu
//  par cette vue est remplacé temporairement.
//

import SwiftUI

struct DocumentationView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Documentation en construction")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.primary)

            Text("On y travaille. Reviens bientôt.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#Preview {
    DocumentationView()
        .frame(width: 900, height: 700)
}
