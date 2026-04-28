//
//  UpdatesView.swift
//  loucede
//
//  Phase 6.3 — Onglet Mises à jour dans les Réglages.
//

import SwiftUI

struct UpdatesView: View {
    @StateObject private var checker = UpdateChecker.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                versionSection
                actionSection
                if let notes = checker.releaseNotes, !notes.isEmpty {
                    changelogSection(notes)
                } else if checker.errorMessage != nil {
                    errorSection
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Versions

    private var versionSection: some View {
        HStack(alignment: .top, spacing: 48) {
            versionRow(label: "Version installée", value: checker.currentVersion)
            if let latest = checker.latestVersion {
                versionRow(label: "Dernière version", value: latest, highlight: checker.updateAvailable)
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
            if checker.isChecking {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Vérification en cours…")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            } else if checker.updateAvailable {
                HStack(spacing: 14) {
                    Button {
                        checker.openDownloadPage()
                    } label: {
                        Label(
                            "Télécharger la version \(checker.latestVersion ?? "")",
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
            checker.checkForUpdates()
        } label: {
            Text("Vérifier à nouveau")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // MARK: - Changelog

    private func changelogSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("Notes de version")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            MarkdownView(text: notes)
        }
    }

    // MARK: - Erreur

    private var errorSection: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.secondary)
            Text("Impossible de vérifier les mises à jour.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
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
