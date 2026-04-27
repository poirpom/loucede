//
//  SuggestionFormView.swift
//  loucede
//
//  Sheet d'envoi de suggestion (Phase 6.16, 2026-04-26).
//  Présentée depuis AboutView. Délègue le réseau à SuggestionService.
//

import SwiftUI

struct SuggestionFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var suggestion: String = ""
    @State private var isSending: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showSuccessToast: Bool = false

    /// Identifiant de l'expéditeur, calculé en lecture seule au moment de
    /// l'affichage (correctif 2026-04-27). Priorité :
    /// (1) heroName si déjà généré, (2) email customer Polar, (3) rien.
    /// Cette valeur est aussi celle envoyée au webhook Zapier dans le
    /// payload — pas besoin pour l'utilisateur de retaper son email.
    private var senderDisplay: String? {
        if let hero = KeychainService.License.heroName, !hero.isEmpty {
            return hero
        }
        if let email = KeychainService.License.customerEmail, !email.isEmpty {
            return email
        }
        return nil
    }

    /// La suggestion doit faire au moins 3 caractères (filtre les envois
    /// accidentels « .. » ou « test ») et au plus 5000 (cap raisonnable
    /// pour éviter de spammer le webhook avec des pavés).
    private var suggestionLooksValid: Bool {
        let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 3 && trimmed.count <= 5000
    }

    private var canSend: Bool {
        suggestionLooksValid && !isSending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Une idée pour loucedé ?")
                    .font(.system(size: 22, weight: .bold))
                Text("Vazy balance")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 20)

            // Mention contextuelle avant les champs
            Text("Une idée d'action pour les modèles ou de fonctionnalité sympa ? Une simple remarque ? C'est par ici")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            // Ligne « Envoyé par » en lecture seule (correctif 2026-04-27).
            // Affichée uniquement si on a une valeur disponible côté
            // licence (heroName ou customerEmail). Sinon, on cache la
            // ligne — pas de saisie manuelle requise.
            if let sender = senderDisplay {
                HStack {
                    Text("Envoyé par :")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(sender)
                        .font(.system(size: 12, weight: .medium))
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.bottom, 16)
            }

            // Champ Suggestion
            VStack(alignment: .leading, spacing: 6) {
                Text("Ta suggestion")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                ZStack(alignment: .topLeading) {
                    if suggestion.isEmpty {
                        Text("Décris ton idée, un bug, ce que tu aimerais voir...")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: $suggestion)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .disabled(isSending)
                }
                .frame(minHeight: 140)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                HStack {
                    Spacer()
                    // Compteur de caractères discret pour rappeler le cap.
                    Text("\(suggestion.count) / 5000")
                        .font(.system(size: 11))
                        .foregroundStyle(suggestion.count > 5000 ? .red : .secondary)
                }
            }
            .padding(.bottom, 20)

            // Boutons
            HStack {
                Button("Annuler") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .disabled(isSending)

                Spacer()

                Button(action: send) {
                    HStack(spacing: 6) {
                        if isSending {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isSending ? "Envoi…" : "Envoyer")
                    }
                    .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(24)
        .frame(width: 480)
        .alert("L'envoi a foiré. Peut-être ça bug 🤷",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            if let msg = errorMessage {
                Text(msg)
            }
        }
        .overlay(alignment: .center) {
            if showSuccessToast {
                ConfirmationToast(message: "Merci pour la suggestion")
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }

    private func send() {
        let cleanSuggestion = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)

        // Phase 6.2 polish (2026-04-27) : payload Zapier avec deux
        // champs séparés (email + heroName) plutôt qu'un seul `sender`.
        // L'admin a besoin de l'email RÉEL pour pouvoir répondre, ET
        // du heroName pour l'identification ludique. Les deux peuvent
        // être vides indépendamment :
        //   - email vide : utilisateur sans licence (cas DEBUG)
        //   - heroName vide : licence active mais user n'a pas encore
        //     cliqué « Obtenir mon nom »
        let realEmail = KeychainService.License.customerEmail ?? ""
        let realHeroName = KeychainService.License.heroName ?? ""

        isSending = true
        errorMessage = nil

        Task {
            do {
                try await SuggestionService.shared.sendSuggestion(
                    email: realEmail,
                    heroName: realHeroName,
                    suggestion: cleanSuggestion
                )
                // Succès : toast 1.2s puis fermeture de la sheet.
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showSuccessToast = true
                }
                isSending = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    dismiss()
                }
            } catch {
                isSending = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    SuggestionFormView()
}
