//
//  AboutView.swift
//  loucede
//

import SwiftUI

struct AboutView: View {
    @StateObject private var updateChecker = UpdateChecker.shared

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

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    AboutView()
}
