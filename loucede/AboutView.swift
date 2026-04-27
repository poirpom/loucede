//
//  AboutView.swift
//  loucede
//

import SwiftUI
import AppKit

struct AboutView: View {
    @StateObject private var updateChecker = UpdateChecker.shared
    /// Phase 6.2 (2026-04-27) : observation explicite du LicenseManager
    /// pour que le bouton « Envoyer une suggestion » se mette à jour
    /// automatiquement quand `hasLicense` change (activation,
    /// désactivation, basculement online ↔ offline). Avant on lisait
    /// `LicenseManager.shared.hasLicense` directement, ce qui marchait
    /// au premier rendu mais ne réagissait pas aux changements.
    @StateObject private var licenseManager = LicenseManager.shared
    /// Phase 6.16 (2026-04-26) : sheet d'envoi de suggestion.
    @State private var showSuggestionSheet: Bool = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 20)

            // Correctif 2026-04-27 : remplace l'ancienne icône
            // `Image(systemName: "sparkles")` par l'AppIcon réelle de
            // l'application. `NSApp.applicationIconImage` retourne le
            // composite système (incluant le squircle macOS Big Sur+).
            // Taille 64×64pt = même empreinte visuelle que l'étincelle.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)

            Text("loucedé")
                .font(.system(size: 28, weight: .bold))

            Text("Une IA au bout de tes doigts")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("Version \(appVersion) (build \(buildNumber))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if updateChecker.updateAvailable, let latest = updateChecker.latestVersion {
                    Button {
                        updateChecker.openDownloadPage()
                    } label: {
                        Text("Version \(latest) disponible — télécharger")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.link)
                }
            }

            Divider().frame(width: 300)

            VStack(spacing: 8) {
                Text("Logiciel libre sous licence GPL v3")
                    .font(.system(size: 12))
                Text("Fork de TexTab par ELPROFUG0")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Link("Code source sur GitHub",
                     destination: URL(string: "https://github.com/poirpom/loucede")!)
                    .font(.system(size: 12))
            }

            // Phase 6.16 : bouton d'envoi de suggestion. License-gated
            // (cf. `LicenseManager.hasLicense`) — grisé tant que
            // l'utilisateur n'a pas de licence active. En Debug,
            // `hasLicense` est forcé à `true` par le `#if DEBUG` pour
            // ne pas bloquer le dev. Réactivité assurée par le
            // `@StateObject licenseManager` ci-dessus.
            Button {
                showSuggestionSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 12))
                    Text("Envoyer une suggestion")
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .disabled(!licenseManager.hasLicense)
            .help(licenseManager.hasLicense
                  ? "Partage une idée ou une remarque"
                  : "Disponible après activation de la licence")

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .sheet(isPresented: $showSuggestionSheet) {
            SuggestionFormView()
        }
    }
}

#Preview {
    AboutView()
}
