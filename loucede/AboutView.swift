//
//  AboutView.swift
//  loucede
//

import SwiftUI
import AppKit

struct AboutView: View {
    @StateObject private var updater = LoucedeUpdater.shared

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

            // F.4 C4 (retour runtime) : tagline + version + lien code
            // source resserrés (spacing 8 vs 24 du VStack racine).
            VStack(spacing: 8) {
                Text("Une IA au bout de tes doigts")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                VStack(spacing: 4) {
                    Text("Version \(appVersion) (build \(buildNumber))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    if updater.updateAvailable, let latest = updater.latestVersion {
                        Button {
                            // Flux natif Sparkle (dialog install).
                            updater.checkForUpdates()
                        } label: {
                            Text("Mettre à jour vers v\(latest)")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.link)
                    }
                }

                // F.4 C4 : lien remonté ici depuis le bloc GPL (ex-libellé
                // « Code source sur GitHub », supprimé là-bas — pas de
                // doublon).
                Link("Code source",
                     destination: URL(string: "https://github.com/poirpom/loucede")!)
                    .font(.system(size: 12))
            }

            // Bouton d'envoi de suggestion (2026-05-29). Ouvre un
            // `mailto:` pré-rempli vers salut@loucede.app via le client
            // mail par défaut. Plus de formulaire ni de webhook (cf.
            // décision n°4) : infra minimale, transparence pour
            // l'utilisateur, pas de license-gating.
            // F.4 C4 : remonté à la place de l'ex-Divider (retour runtime).
            Button {
                openSuggestionMail()
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
            .help("Partage une idée ou une remarque par email")

            VStack(spacing: 8) {
                Text("Logiciel libre sous licence GPL v3")
                    .font(.system(size: 12))
                // Lien inline sur le mot « TexTab » (markdown natif de
                // Text) vers le repo d'origine du fork — URL identique
                // au README. Le reste de la phrase reste secondary.
                Text("Fork de [TexTab](https://github.com/ELPROFUG0/TexTab) par ELPROFUG0")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// Ouvre le client mail par défaut sur un brouillon pré-rempli vers
    /// salut@loucede.app. `URLComponents` gère l'encodage (sauts de ligne
    /// en %0A, UTF-8 pour les accents du sujet).
    private func openSuggestionMail() {
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = "salut@loucede.app"
        comps.queryItems = [
            URLQueryItem(name: "subject", value: "À propos de loucedé"),
            URLQueryItem(name: "body", value: "Salut Fabrice,\n\nJ'utilise loucedé et je voulais te dire :")
        ]
        if let url = comps.url {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    AboutView()
}
