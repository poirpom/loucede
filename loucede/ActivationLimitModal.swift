//
//  ActivationLimitModal.swift
//  loucede
//
//  Phase 7 — Session 3 commit 3 (cross-device deactivate, 2026-04-30).
//
//  Sheet présentée quand `LicenseManager.activate(key:)` retourne 403
//  `activationLimitReached`. Permet à l'utilisateur de libérer un slot
//  (désactiver un autre device) puis retry l'activation automatiquement
//  via la même clé.
//
//  Architecture : appelle `LicenseService` directement (pas via
//  `LicenseManager`) pour les calls de pré-load (validate + getLicenseKey
//  + deactivate) car `LicenseManager` est en état `.unlicensed` pendant
//  ce flow (la clé n'est pas encore en Keychain). Le retry final passe
//  par `LicenseManager.activate(key:)` pour bénéficier du flow complet
//  (Keychain persisté, refreshActivations, status update).
//

import SwiftUI

struct ActivationLimitModal: View {
    /// La clé que l'utilisateur veut activer. Utilisée pour les 3 calls
    /// (validate, getLicenseKey, deactivate, retry activate).
    let pendingKey: String

    /// Appelé quand le retry `activate` réussit. Le caller doit fermer
    /// la modale + clear son état (typiquement `keyInput = ""`).
    let onSuccess: () -> Void

    /// Appelé quand l'utilisateur clique sur « Annuler » ou ferme la
    /// modale. Le caller doit fermer la sheet (showLimitReachedModal =
    /// false).
    let onDismiss: () -> Void

    /// Liste des activations en cours pour cette licence, fetchée au
    /// montage. Vide tant que `loadActivations()` n'a pas répondu.
    @State private var activations: [PolarActivationDetail] = []

    /// `true` pendant le pré-load (validate + getLicenseKey).
    @State private var isLoading: Bool = true

    /// `activation_id` actuellement en cours de désactivation, ou `nil`.
    /// Verrouille les autres boutons pendant la désactivation pour
    /// éviter les concurrences.
    @State private var deactivatingId: String?

    /// Erreur affichée inline en cas de problème (réseau, decode,
    /// désactivation échouée, retry échoué non-403).
    @State private var error: String?

    /// Formatter "DD/MM/YYYY" strict (locale POSIX) — dupliqué de
    /// LicenseSettingsView pour l'isolation de la modale. À factoriser
    /// si on l'utilise ailleurs (cf. backlog V1.1).
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "key.slash")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.orange)
                Text("Limite d'appareils atteinte")
                    .font(.system(size: 18, weight: .bold))
                Text("Cette clé est déjà utilisée sur le maximum d'appareils. Désactive un appareil ci-dessous pour libérer un emplacement et activer celui-ci.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Divider()

            // Liste / loading / erreur
            Group {
                if isLoading {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Chargement des appareils…")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                } else if let error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else if activations.isEmpty {
                    Text("Aucun appareil n'est actif sur cette licence.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(activations) { activation in
                                deviceRow(activation)
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
            }

            Spacer()

            // Bouton Annuler
            Button(action: onDismiss) {
                Text("Annuler")
                    .frame(minWidth: 80)
            }
            .buttonStyle(.bordered)
            .disabled(deactivatingId != nil)
        }
        .frame(width: 480, height: 440)
        .padding(20)
        .task {
            await loadActivations()
        }
    }

    /// Une ligne de la liste d'activations — label + date + bouton
    /// « Désactiver ». Pendant qu'une autre désactivation est en cours,
    /// le bouton est désactivé (le set `deactivatingId` ne contient
    /// qu'une valeur, on serialize les actions).
    @ViewBuilder
    private func deviceRow(_ activation: PolarActivationDetail) -> some View {
        let isThisDeactivating = deactivatingId == activation.id
        let anyDeactivating = deactivatingId != nil

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(activation.label)
                    .font(.system(size: 13, weight: .medium))
                Text("Activé le \(Self.dateFormatter.string(from: activation.createdAt))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isThisDeactivating {
                ProgressView().controlSize(.small)
            } else {
                Button(role: .destructive) {
                    Task { await performDeactivateAndRetry(activation) }
                } label: {
                    Text("Désactiver")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .disabled(anyDeactivating)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08)))
    }

    // MARK: - Network actions

    /// Charge la liste des activations en 2 round-trips :
    /// 1. `validate(key:)` — récupère le `license_key.id` (Polar ne
    ///    permet pas un `getLicenseKey` direct par clé string).
    /// 2. `getLicenseKey(id:)` — récupère `activations[]` détaillées.
    ///
    /// 2 calls au lieu d'1 — coût accepté pour ce flow exceptionnel
    /// (validé en Session 3 commit 2 que /validate ne retourne pas le
    /// champ `activations`, contrairement à /get-license-key).
    private func loadActivations() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let validated = try await LicenseService.shared.validate(
                key: pendingKey,
                activationId: nil
            )
            let detailed = try await LicenseService.shared.getLicenseKey(id: validated.id)
            activations = detailed.activations ?? []
        } catch let err as LicenseError {
            error = "Impossible de récupérer la liste des appareils : \(err.localizedDescription)"
        } catch {
            self.error = "Impossible de récupérer la liste des appareils : \(error.localizedDescription)"
        }
    }

    /// Désactive l'activation choisie puis retry l'activation. 3 cas :
    /// - Succès complet → `onSuccess()` (parent ferme la modale).
    /// - Toujours 403 (multiple devices à libérer) → on retire la ligne
    ///   désactivée de la liste, l'utilisateur peut retenter avec une
    ///   autre.
    /// - Autre erreur → affichée inline, la liste reste.
    private func performDeactivateAndRetry(_ activation: PolarActivationDetail) async {
        deactivatingId = activation.id
        defer { deactivatingId = nil }
        error = nil

        // 1. Désactiver le slot choisi côté Polar
        do {
            try await LicenseService.shared.deactivate(
                key: pendingKey,
                activationId: activation.id
            )
        } catch {
            self.error = "Désactivation échouée : \(error.localizedDescription)"
            return
        }

        // 2. Retry l'activation sur cet appareil — passe par
        // LicenseManager pour que le Keychain soit persisté + status
        // mis à jour côté UI parent.
        do {
            try await LicenseManager.shared.activate(key: pendingKey)
            onSuccess()
        } catch LicenseError.activationLimitReached {
            // Toujours over-limit : refresh la liste localement (la
            // ligne désactivée n'est plus dans Polar).
            activations.removeAll { $0.id == activation.id }
        } catch {
            self.error = "Réactivation échouée : \(error.localizedDescription)"
        }
    }
}
