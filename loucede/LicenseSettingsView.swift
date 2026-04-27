//
//  LicenseSettingsView.swift
//  loucede
//
//  Phase 6.2 (2026-04-27) : onglet « Licence » dans Réglages.
//  Présente l'état courant de `LicenseManager.shared.status` et permet
//  à l'utilisateur d'activer / désactiver une clé Polar.
//
//  Layout : VStack centrée, sous-vue dédiée par status. Utilise un seul
//  `@StateObject` partagé sur le singleton `LicenseManager` pour réagir
//  automatiquement aux changements de status (validation au démarrage,
//  activation, désactivation, transitions offline ↔ active).
//

import SwiftUI
import AppKit

struct LicenseSettingsView: View {
    @StateObject private var manager = LicenseManager.shared

    /// Champ de saisie de clé (binding local — pas dans le manager pour
    /// que l'utilisateur puisse taper sans déclencher un re-render
    /// global).
    @State private var keyInput: String = ""

    /// Spinners locaux pour les opérations en cours (évite que le bouton
    /// soit cliquable deux fois).
    @State private var isActivating: Bool = false
    @State private var isDeactivating: Bool = false

    /// Confirmation modale avant deactivate.
    @State private var showDeactivateConfirm: Bool = false

    /// Erreur d'activation (différent de `manager.lastError` qui couvre
    /// les erreurs de validate au démarrage). Affichée juste sous le
    /// formulaire d'activation.
    @State private var activationError: String?

    /// Erreur transitoire lors de la génération du heroName via LLM.
    /// Affichée brièvement sous le bouton « Désactiver cet appareil ».
    @State private var heroNameError: String?

    /// Popover explicatif sur le sobriquet (clic sur le `info.circle`).
    /// Doublon du `.help()` (tooltip natif au survol) — certains
    /// utilisateurs cliquent sans attendre le tooltip, le popover
    /// répond visiblement au clic.
    @State private var showHeroNamePopover: Bool = false

    /// `true` si l'utilisateur a une vraie licence Polar (active ou
    /// offline), indépendamment du flag `#if DEBUG`. Utilisé pour
    /// décider d'afficher le compteur trial — en dev, `hasLicense`
    /// est forcé à `true` mais on veut quand même voir le compteur
    /// pour tester l'UI.
    private var hasRealLicense: Bool {
        manager.status == .active || manager.status == .offline
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 16)

                // Icône + titre selon status
                statusHeader

                // Body principal selon status
                Group {
                    switch manager.status {
                    case .unlicensed:  unlicensedView
                    case .validating:  validatingView
                    case .active:      activeView
                    case .offline:     offlineView
                    case .revoked:     statusErrorView(
                        title: "Cette licence a été révoquée",
                        message: "L'accès à cette licence a été coupé côté Polar. Active une autre clé pour continuer."
                    )
                    case .disabled:    statusErrorView(
                        title: "Cette licence est désactivée",
                        message: "Le paiement associé à cette licence a été annulé ou contesté. Active une autre clé pour continuer."
                    )
                    case .expired:     statusErrorView(
                        title: "Cette licence a expiré",
                        message: expiredMessage
                    )
                    }
                }
                .frame(maxWidth: 420)

                // Trial counter en bas si pas de licence Polar réelle.
                // On vérifie le `status` directement, PAS `hasLicense`,
                // pour ne pas être masqué par l'override `#if DEBUG`
                // (qui ferait toujours `hasLicense == true` et cacherait
                // le compteur même quand l'utilisateur n'a pas activé
                // de licence).
                if !hasRealLicense {
                    trialCounter
                        .padding(.top, 8)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .alert("Désactiver cet appareil ?", isPresented: $showDeactivateConfirm) {
            Button("Annuler", role: .cancel) { }
            Button("Désactiver", role: .destructive) {
                Task { await performDeactivate() }
            }
        } message: {
            Text("L'emplacement sera libéré chez loucedé : tu pourras réactiver cette clé sur un autre appareil.")
        }
    }

    // MARK: - Status header (icône + titre)

    @ViewBuilder
    private var statusHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: headerIconName)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(headerColor)
                .symbolEffect(.bounce, value: manager.status)

            Text(headerTitle)
                .font(.system(size: 20, weight: .bold))
                .multilineTextAlignment(.center)
        }
    }

    private var headerIconName: String {
        switch manager.status {
        case .unlicensed:  return "key"
        case .validating:  return "key.viewfinder"
        case .active:      return "checkmark.shield.fill"
        case .offline:     return "icloud.slash"
        case .revoked:     return "xmark.shield.fill"
        case .disabled:    return "exclamationmark.shield.fill"
        case .expired:     return "clock.badge.exclamationmark.fill"
        }
    }

    private var headerColor: Color {
        switch manager.status {
        case .unlicensed:  return .secondary
        case .validating:  return .secondary
        case .active:      return .green
        case .offline:     return .blue
        case .revoked:     return .red
        case .disabled:    return .orange
        case .expired:     return .orange
        }
    }

    private var headerTitle: String {
        switch manager.status {
        case .unlicensed:  return "Aucune licence active"
        case .validating:  return "Validation…"
        case .active:      return "Licence active"
        case .offline:     return "Mode hors-ligne"
        case .revoked:     return "Licence révoquée"
        case .disabled:    return "Licence désactivée"
        case .expired:     return "Licence expirée"
        }
    }

    // MARK: - Unlicensed (pas de clé)

    @ViewBuilder
    private var unlicensedView: some View {
        VStack(spacing: 14) {
            activationForm

            Text("Pas encore de clé ?")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Button(action: openCheckout) {
                Text("Acheter une licence")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Validating (spinner)

    @ViewBuilder
    private var validatingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Vérification de la licence en cours…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
    }

    // MARK: - Active (status granted, OK)

    @ViewBuilder
    private var activeView: some View {
        VStack(spacing: 12) {
            // Sous-titre Bienvenue (correctif 2026-04-27).
            // Padding bottom pour respirer entre lui et les infos.
            Text("Bienvenue dans la tcheam #loucedé")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)

            // Ligne « Activée pour » : nom hero ou bouton de génération
            heroNameRow

            if let email = manager.customerEmail {
                infoRow(label: "Email", value: email)
            }

            if let limit = manager.activationsLimit {
                infoRow(label: "Limite d'appareils", value: "\(limit)")
            }
            if let expires = manager.expiresAt {
                infoRow(label: "Expire le", value: expires.formatted(date: .abbreviated, time: .omitted))
            }

            Button(role: .destructive) {
                showDeactivateConfirm = true
            } label: {
                HStack(spacing: 6) {
                    if isDeactivating {
                        ProgressView().controlSize(.small)
                    }
                    Text("Désactiver cet appareil")
                }
                .frame(minWidth: 200)
            }
            .buttonStyle(.bordered)
            .disabled(isDeactivating)
            .padding(.top, 8)

            // Erreur de génération du heroName (réseau down, etc.)
            if let error = heroNameError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .frame(maxWidth: 320, alignment: .leading)
            }
        }
    }

    /// Ligne « Activée pour » avec deux modes :
    /// - hero name déjà généré → affiche le nom + ℹ️ explicatif
    /// - pas de nom → bouton « Obtenir mon nom » (disabled si pas de
    ///   clé API configurée)
    @ViewBuilder
    private var heroNameRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Activée pour")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            if let hero = manager.heroName {
                HStack(spacing: 4) {
                    Text(hero)
                        .font(.system(size: 12, weight: .medium))
                        .textSelection(.enabled)
                    Button {
                        showHeroNamePopover.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Sobriquet attribué arbitrairement par le CODIR de loucedé")
                    .popover(isPresented: $showHeroNamePopover, arrowEdge: .bottom) {
                        Text("Sobriquet attribué arbitrairement par le CODIR de loucedé.")
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .frame(maxWidth: 240)
                    }
                }
            } else {
                Button {
                    Task { await performGenerateHeroName() }
                } label: {
                    HStack(spacing: 4) {
                        if manager.isGeneratingHeroName {
                            ProgressView().controlSize(.small)
                        }
                        Text(manager.isGeneratingHeroName ? "Génération…" : "Obtenir mon nom")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(ActionsStore.shared.apiKey.isEmpty || manager.isGeneratingHeroName)
                .help(ActionsStore.shared.apiKey.isEmpty
                      ? "Configure d'abord ta clé API dans Général"
                      : "Génère un sobriquet via le LLM configuré (une seule fois)")
            }
        }
        .frame(maxWidth: 320)
    }

    // MARK: - Offline (cache valide < 7j)

    @ViewBuilder
    private var offlineView: some View {
        VStack(spacing: 12) {
            Text("Pas de connexion réseau, mais ta licence reste active grâce au cache local.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let email = manager.customerEmail {
                infoRow(label: "Activée pour", value: email)
            }
            if let lastValidated = KeychainService.License.lastValidatedAt {
                infoRow(label: "Dernière vérification", value: lastValidated.formatted(date: .abbreviated, time: .shortened))
            }

            Button {
                Task { await manager.validate() }
            } label: {
                Text("Re-vérifier maintenant")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
    }

    // MARK: - Status d'erreur (revoked / disabled / expired)

    @ViewBuilder
    private func statusErrorView(title: String, message: String) -> some View {
        VStack(spacing: 14) {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let email = manager.customerEmail {
                infoRow(label: "Compte", value: email)
                    .padding(.bottom, 4)
            }

            Divider().frame(width: 200)

            Text("Activer une autre licence")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            activationForm

            Button(action: openCheckout) {
                Text("Acheter une licence")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Formulaire d'activation (réutilisé en unlicensed et en error states)

    @ViewBuilder
    private var activationForm: some View {
        VStack(spacing: 8) {
            TextField("Colle ta clé licence ici", text: $keyInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .disabled(isActivating)
                .onSubmit {
                    Task { await performActivate() }
                }

            Button {
                Task { await performActivate() }
            } label: {
                HStack(spacing: 6) {
                    if isActivating {
                        ProgressView().controlSize(.small)
                    }
                    Text(isActivating ? "Activation…" : "Activer cette clé")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isActivating || keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let error = activationError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Trial counter

    @ViewBuilder
    private var trialCounter: some View {
        VStack(spacing: 6) {
            Divider().frame(width: 280)
            HStack(spacing: 4) {
                Text("Utilisations gratuites :")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("\(manager.trialUsageCount) / \(LicenseManager.trialLimit)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(manager.hasTrialRemaining ? Color.secondary : Color.red)
            }
            ProgressView(value: Double(manager.trialUsageCount), total: Double(LicenseManager.trialLimit))
                .frame(width: 200)
                .tint(manager.hasTrialRemaining ? .blue : .red)
        }
        .padding(.top, 12)
    }

    // MARK: - Helper rows

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .textSelection(.enabled)
        }
        .frame(maxWidth: 320)
    }

    // MARK: - Computed messages

    private var expiredMessage: String {
        guard let expires = manager.expiresAt else {
            return "Cette licence a dépassé sa date de validité. Active une autre clé pour continuer."
        }
        return "Cette licence a expiré le \(expires.formatted(date: .abbreviated, time: .omitted)). Active une autre clé pour continuer."
    }

    // MARK: - Actions

    /// Tentative d'activation de la clé saisie. Met à jour
    /// `activationError` en cas d'échec, vide le champ + clear l'erreur
    /// en cas de succès.
    private func performActivate() async {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isActivating = true
        activationError = nil
        defer { isActivating = false }

        do {
            try await manager.activate(key: trimmed)
            // Succès : clear le champ
            keyInput = ""
            activationError = nil
        } catch let error as LicenseError {
            activationError = error.localizedDescription
        } catch {
            activationError = error.localizedDescription
        }
    }

    /// Désactivation de l'appareil courant côté Polar. Conserve le
    /// trial counter (déjà consommé). En cas d'échec API, on garde le
    /// state actuel pour que l'utilisateur puisse retenter — sinon il
    /// aurait perdu sa licence localement sans libérer le slot.
    private func performDeactivate() async {
        isDeactivating = true
        defer { isDeactivating = false }

        do {
            try await manager.deactivate()
        } catch {
            // L'erreur est déjà dans manager.lastError (rendue par
            // l'erreur HTTP). On laisse le state actuel.
        }
    }

    /// Ouvre le checkout Polar dans le navigateur par défaut.
    /// Étape 6 (à venir) remplacera ça par une `LicenseCheckoutView`
    /// embarquée en WKWebView qui intercepte la clé après paiement.
    private func openCheckout() {
        NSWorkspace.shared.open(LicenseConfig.productCheckoutURL)
    }

    /// Lance la génération du heroName via le provider IA configuré.
    /// Stocke en Keychain en cas de succès (LicenseManager s'en charge).
    /// Affiche brièvement l'erreur en cas d'échec (réseau down, clé API
    /// invalide, réponse LLM vide…). Auto-clear l'erreur après 4 s.
    private func performGenerateHeroName() async {
        heroNameError = nil
        do {
            try await manager.generateHeroName()
        } catch {
            heroNameError = error.localizedDescription
            // Auto-clear l'erreur après 4 secondes pour ne pas
            // l'afficher en permanence si l'utilisateur ne réessaie pas.
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if heroNameError == error.localizedDescription {
                heroNameError = nil
            }
        }
    }
}

#Preview {
    LicenseSettingsView()
        .frame(width: 700, height: 540)
}
