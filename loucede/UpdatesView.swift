//
//  UpdatesView.swift
//  loucede
//
//  Phase 6.3 — Onglet Mises à jour dans les Réglages.
//  Phase H.2 — refondu sur Sparkle (façade LoucedeUpdater). Le bouton
//  « Vérifier » déclenche le flux natif Sparkle (dialog progression +
//  erreurs + installation). Les notes affichées sont celles de la version
//  installée (bundle) hors mise à jour, ou celles de l'appcast quand une
//  version plus récente est annoncée.
//

import SwiftUI

struct UpdatesView: View {
    @StateObject private var updater = LoucedeUpdater.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                versionSection
                actionSection
                if let notes = notesToShow, !notes.isEmpty {
                    changelogSection(notes)
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Versions

    private var versionSection: some View {
        HStack(alignment: .top, spacing: 48) {
            versionRow(label: "Version installée", value: updater.currentVersion)
            if let latest = updater.latestVersion {
                versionRow(label: "Dernière version", value: latest, highlight: updater.updateAvailable)
            }
        }
    }

    private func versionRow(label: String, value: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(highlight ? updateOrange : .primary)
                if highlight {
                    Text("NOUVEAU")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(updateOrange))
                }
            }
        }
    }

    // MARK: - Bouton / état

    private var actionSection: some View {
        Group {
            if updater.updateAvailable {
                HStack(spacing: 14) {
                    Button {
                        // Flux natif Sparkle : re-vérifie et propose l'install.
                        updater.checkForUpdates()
                    } label: {
                        Label(
                            "Mettre à jour vers v\(updater.latestVersion ?? "")",
                            systemImage: "arrow.down.circle.fill"
                        )
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()

                    refreshButton
                }
            } else {
                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("À jour")
                            .font(.system(size: 13, weight: .medium))
                    }
                    refreshButton
                }
            }
        }
    }

    private var refreshButton: some View {
        Button {
            // User-initiated : ouvre le dialog Sparkle natif (« loucedé est à
            // jour » / « Mise à jour disponible » / « Impossible de vérifier »).
            updater.checkForUpdates()
        } label: {
            Text("Vérifier à nouveau")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // MARK: - Changelog

    /// Notes à afficher : celles de l'appcast quand une mise à jour est
    /// annoncée, sinon celles de la version installée (bundle).
    private var notesToShow: String? {
        if updater.updateAvailable { return updater.releaseNotes }
        return bundledReleaseNotes
    }

    /// Lit `release-notes/v{version installée}.md` bundlé dans le .app.
    private var bundledReleaseNotes: String? {
        guard let url = Bundle.main.url(
            forResource: "v\(updater.currentVersion)",
            withExtension: "md",
            subdirectory: "release-notes"
        ), let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return content
    }

    private func changelogSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("Notes de version")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            MarkdownView(text: notes)
        }
    }

    // MARK: - Couleur orange partagée

    private var updateOrange: Color {
        Color(red: 0.976, green: 0.620, blue: 0.043) // #F59E0B
    }
}

#Preview {
    UpdatesView()
        .frame(width: 800, height: 480)
}
