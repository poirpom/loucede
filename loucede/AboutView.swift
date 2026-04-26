//
//  AboutView.swift
//  loucede
//

import SwiftUI

struct AboutView: View {
    @StateObject private var updateChecker = UpdateChecker.shared
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

            Image(systemName: "sparkles")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.accentColor)

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
            // l'utilisateur n'a pas de licence active. La gate effective
            // sera connectée en Phase 6.2 ; le stub actuel retourne
            // toujours `true` pour permettre les tests pendant le dev.
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
            .disabled(!LicenseManager.shared.hasLicense)
            .help(LicenseManager.shared.hasLicense
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
