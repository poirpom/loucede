//
//  BundleImageProvider.swift
//  loucede
//
//  Phase F.2 (2026-06-12) : rendu des images `bundle://` de la doc
//  locale. Les `.md` migrés par `scripts/migrate-notion-docs.py`
//  référencent leurs images via `![alt](bundle://images/<fichier>)` —
//  un scheme custom que l'`AsyncImage` du provider MarkdownUI par
//  défaut ne sait pas résoudre.
//
//  Choix d'implémentation : `ImageProvider` MarkdownUI (protocole
//  public depuis 2.0, appliqué via `.markdownImageProvider()` sur le
//  `Markdown` de DocumentationView) plutôt qu'un `URLProtocol` custom
//  — pas d'enregistrement global URLSession, scopé au seul rendu doc.
//
//  Les images des tutos sont toutes des blocs autonomes (pas d'image
//  inline dans du texte) → le provider bloc suffit, pas de
//  `markdownInlineImageProvider`.
//

import SwiftUI
import MarkdownUI

/// Résout les URLs `bundle://images/<fichier>` vers les fichiers de
/// `Contents/Resources/Documentation/images/` et les rend en `Image`
/// SwiftUI. Toute URL non résolue (scheme inattendu, fichier absent)
/// rend `Color.clear` — dégradation silencieuse, cohérente avec le
/// reste de la doc (pas de placeholder cassé).
struct BundleImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        Group {
            if let nsImage = Self.resolveImage(url: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    // Plafond à la taille native : une capture étroite
                    // ne doit pas être agrandie pour remplir la colonne
                    // (flou) — elle peut seulement rétrécir si la zone
                    // de lecture est plus étroite qu'elle.
                    .frame(maxWidth: nsImage.size.width)
            } else {
                Color.clear
                    .frame(height: 0)
            }
        }
    }

    /// `bundle://images/<fichier>` → `NSImage`, ou `nil` si l'URL n'est
    /// pas au format attendu ou si le fichier manque au bundle.
    /// Parsing : scheme `bundle`, host `images` (le « dossier » dans la
    /// notation `bundle://images/...`), lastPathComponent = nom de
    /// fichier — résolu dans `Documentation/images/`.
    private static func resolveImage(url: URL?) -> NSImage? {
        guard let url,
              url.scheme == "bundle",
              url.host == "images",
              !url.lastPathComponent.isEmpty,
              let resourceRoot = Bundle.main.resourceURL else {
            return nil
        }
        let fileURL = resourceRoot
            .appendingPathComponent("Documentation/images", isDirectory: true)
            .appendingPathComponent(url.lastPathComponent)
        return NSImage(contentsOf: fileURL)
    }
}
