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
    @StateObject private var usageTracker = UsageTracker.shared

    /// Champ de saisie de clé (binding local — pas dans le manager pour
    /// que l'utilisateur puisse taper sans déclencher un re-render
    /// global).
    @State private var keyInput: String = ""

    /// Focus du champ de saisie de clé. Posé par `consumeFocusRequest()`
    /// quand `manager.focusKeyFieldRequest` est levé après un achat (D.6).
    @FocusState private var keyFieldFocused: Bool

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
    /// Affichée brièvement sous la liste des appareils.
    @State private var heroNameError: String?

    /// Popover explicatif sur le sobriquet (clic sur le `info.circle`).
    /// Doublon du `.help()` (tooltip natif au survol) — certains
    /// utilisateurs cliquent sans attendre le tooltip, le popover
    /// répond visiblement au clic.
    @State private var showHeroNamePopover: Bool = false

    /// Activation que l'utilisateur veut désactiver (autre que le device
    /// courant). Présent → déclenche la modale de confirmation dédiée
    /// dont le wording inclut le label + la date d'activation. `nil` =
    /// pas de modale ouverte. Pour désactiver le device courant, on
    /// continue d'utiliser `showDeactivateConfirm` (même modale qu'avant
    /// commit 3).
    @State private var otherDeviceToDeactivate: PolarActivationDetail?

    /// Set des `activation_id` actuellement en cours de désactivation.
    /// Permet le spinner par ligne dans la liste — l'utilisateur peut
    /// déclencher une autre désactivation en parallèle si besoin sans
    /// bloquer toute l'UI.
    @State private var deactivatingActivationIds: Set<String> = []

    /// Présent quand `performActivate` a reçu une 403
    /// `activationLimitReached`. Déclenche la sheet `ActivationLimitModal`
    /// qui propose de libérer un slot puis retry l'activation.
    @State private var showLimitReachedModal: Bool = false

    /// La clé que l'utilisateur a tentée d'activer juste avant le 403.
    /// Transmise à `ActivationLimitModal` qui s'en sert pour
    /// `validate` + `getLicenseKey` + `deactivate` + retry `activate`.
    @State private var pendingActivationKey: String = ""

    /// `true` si l'utilisateur a une vraie licence Polar (active ou
    /// offline), indépendamment du flag `#if DEBUG`. Utilisé pour
    /// décider d'afficher le compteur trial — en dev, `hasLicense`
    /// est forcé à `true` mais on veut quand même voir le compteur
    /// pour tester l'UI.
    private var hasRealLicense: Bool {
        manager.status == .active || manager.status == .offline
    }

    /// Formatter "DD/MM/YYYY" strict (locale POSIX, pas de
    /// localisation système). Cohérent avec le pattern utilisé par
    /// UsageTracker. Affiché dans la liste des appareils et la modale
    /// de confirmation de désactivation.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

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

                #if DEBUG
                debugLicenseSection
                    .padding(.top, 12)
                #endif

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        // D.6 — focus du champ clé après un achat réussi. `.onAppear`
        // couvre la fenêtre neuve + le switch d'onglet (remount via `.id`),
        // `.onChange` couvre « déjà sur l'onglet Licence ».
        .onAppear { if manager.focusKeyFieldRequest { consumeFocusRequest() } }
        .onChange(of: manager.focusKeyFieldRequest) { _, new in
            if new { consumeFocusRequest() }
        }
        .alert("Désactiver cet appareil ?", isPresented: $showDeactivateConfirm) {
            Button("Annuler", role: .cancel) { }
            Button("Désactiver", role: .destructive) {
                Task { await performDeactivate() }
            }
        } message: {
            Text("L'emplacement sera libéré chez loucedé : tu pourras réactiver cette clé sur un autre appareil.")
        }
        // Modale « désactiver un AUTRE device » (commit 3) — wording
        // dédié avec label + date d'activation. Différente de la modale
        // ci-dessus qui couvre uniquement « (cet appareil) ».
        .alert(
            "Désactiver \"\(otherDeviceToDeactivate?.label ?? "")\" ?",
            isPresented: Binding(
                get: { otherDeviceToDeactivate != nil },
                set: { if !$0 { otherDeviceToDeactivate = nil } }
            )
        ) {
            Button("Annuler", role: .cancel) { otherDeviceToDeactivate = nil }
            Button("Désactiver", role: .destructive) {
                if let device = otherDeviceToDeactivate {
                    Task { await performDeactivateOther(device) }
                }
            }
        } message: {
            if let device = otherDeviceToDeactivate {
                Text("L'appareil \"\(device.label)\" (activé le \(Self.dateFormatter.string(from: device.createdAt))) sera retiré de tes activations. Tu pourras toujours réactiver loucedé dessus plus tard si besoin.")
            }
        }
        // Sheet 403 (commit 3) — limite d'activations atteinte. Affiche
        // la liste des appareils, propose d'en désactiver un, retry
        // l'activation automatiquement après libération du slot.
        .sheet(isPresented: $showLimitReachedModal) {
            ActivationLimitModal(
                pendingKey: pendingActivationKey,
                onSuccess: {
                    keyInput = ""
                    showLimitReachedModal = false
                },
                onDismiss: {
                    showLimitReachedModal = false
                }
            )
        }
        .task {
            // Au montage : rafraîchir la liste des activations pour le
            // compteur X/Y (commit 2). Inclut un fallback de migration
            // si licenseKeyId n'est pas encore en Keychain (utilisateurs
            // pré-Session-3). Silent fail si réseau down — l'UI affiche
            // la limite seule en fallback.
            await manager.refreshActivations()
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
            // Hint post-achat (D.6 polish) : encadré vert englobant le
            // formulaire d'activation, affiché uniquement après un achat
            // réussi (pas dans « activer une autre licence »).
            if manager.postPurchaseHintActive {
                VStack(spacing: 10) {
                    VStack(spacing: 2) {
                        Text("✅ Achat réussi")
                            .font(.system(size: 13, weight: .bold))
                        Text("📧 La licence est dans ta boîte mail")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    activationForm
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
            } else {
                activationForm
            }

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

            if let expires = manager.expiresAt {
                infoRow(label: "Expire le", value: expires.formatted(date: .abbreviated, time: .omitted))
            }

            // Bloc « Mes appareils » (commit 3) — header avec compteur
            // X/Y + liste des activations avec bouton « Désactiver » par
            // ligne. Le bouton sur la ligne marquée « (cet appareil) »
            // déclenche la modale `showDeactivateConfirm` existante
            // (Phase 6.2) ; les autres lignes ouvrent la modale
            // `otherDeviceToDeactivate` au wording dédié.
            // Remplace le bouton bas « Désactiver cet appareil » de
            // Phase 6.2 (devenu redondant avec la ligne du device courant).
            devicesSection

            // Compteur d'utilisations total (visible uniquement si au
            // moins un usage enregistré).
            if usageTracker.count > 0 {
                usageCounter
            }

            // Erreur de génération du heroName (réseau down, etc.)
            if let error = heroNameError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .frame(maxWidth: 320, alignment: .leading)
            }
        }
    }

    // MARK: - Devices section (commit 3 — cross-device deactivate)

    /// Section « Mes appareils » : header avec compteur X/Y + liste
    /// des activations Polar. Visible uniquement quand la licence est
    /// active (cf. callers dans `activeView`).
    @ViewBuilder
    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header : titre + compteur X/Y
            HStack {
                Text("Mes appareils")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let used = manager.activationsUsed, let limit = manager.activationsLimit {
                    Text("\(used) / \(limit)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else if let limit = manager.activationsLimit {
                    // Fallback : refreshActivations a échoué, limite
                    // seule (récupérée par validate au démarrage).
                    Text("Limite : \(limit)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            // Liste : placeholder de chargement si refresh pas encore
            // arrivé, sinon les rows des activations.
            if manager.activations.isEmpty && (manager.activationsLimit ?? 0) > 0 {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Chargement…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(manager.activations) { activation in
                    deviceRow(activation)
                }
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    /// Une ligne de la liste « Mes appareils ». Affiche le label de
    /// l'activation (avec mention `(cet appareil)` si c'est le device
    /// courant), la date d'activation, et un bouton « Désactiver » qui
    /// ouvre la modale de confirmation appropriée. Pendant la
    /// désactivation, un spinner remplace le bouton (par ligne, pas
    /// global).
    @ViewBuilder
    private func deviceRow(_ activation: PolarActivationDetail) -> some View {
        let isCurrent = activation.id == manager.currentActivationId
        let isRowDeactivating = deactivatingActivationIds.contains(activation.id)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(activation.label)
                        .font(.system(size: 13, weight: .medium))
                    if isCurrent {
                        Text("(cet appareil)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Activé le \(Self.dateFormatter.string(from: activation.createdAt))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isRowDeactivating {
                ProgressView().controlSize(.small)
            } else {
                Button(role: .destructive) {
                    if isCurrent {
                        showDeactivateConfirm = true
                    } else {
                        otherDeviceToDeactivate = activation
                    }
                } label: {
                    Text("Désactiver")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
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
                .focused($keyFieldFocused)
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

    #if DEBUG
    // MARK: - Panneau Debug (simulation états licence/trial) — Debug only

    /// Panneau dev pour simuler les états licence/trial sans dépendre de
    /// Polar ni du Keychain. Strictement `#if DEBUG` → absent en Release.
    /// Cf. `DebugLicenseState` + `LicenseManager.debugLicenseOverride`.
    private var debugLicenseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().frame(width: 280)

            Text("🛠 DEBUG — Simulation licence")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("État simulé", selection: $manager.debugLicenseOverride) {
                ForEach(DebugLicenseState.allCases, id: \.self) { state in
                    Text(state.label).tag(state)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            Button("Reset trial counter (→ 0)") {
                manager.debugResetTrialUsage()
            }
            .controlSize(.small)

            // D.3 — test isolé de la fenêtre d'achat Polar (avant que D.4
            // ne câble les vrais boutons « Acheter »).
            Button("🛠 Ouvrir checkout Polar (test isolé)") {
                PurchaseWindowController.present(
                    onSuccess: { print("✅ [D.3] onSuccess — success URL Polar interceptée") },
                    onClose:   { print("✋ [D.3] onClose — fenêtre fermée sans achat") }
                )
            }
            .controlSize(.small)

            // D.6 polish — bascule le hint post-achat pour itérer le design
            // sans refaire un achat VIPDEV.
            Button("Toggle post-purchase hint") {
                manager.postPurchaseHintActive.toggle()
            }
            .controlSize(.small)

            // Lecture live de l'effet courant.
            Text("override: \(manager.debugLicenseOverride.label)  ·  trial: \(manager.trialUsageCount)/\(LicenseManager.trialLimit)  ·  hasLicense: \(manager.hasLicense ? "true" : "false")  ·  canRunAction: \(manager.canRunAction ? "true" : "false")")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    #endif

    // MARK: - Usage counter (licences actives uniquement)

    @ViewBuilder
    private var usageCounter: some View {
        let dateStr = usageTracker.formattedFirstUseDate() ?? ""
        VStack(spacing: 0) {
            Divider()
                .frame(maxWidth: 320)
                .padding(.vertical, 10)

            (
                Text("Depuis le ").foregroundStyle(.secondary)
                + Text(dateStr).foregroundStyle(.primary)
                + Text(", tu as utilisé loucedé ").foregroundStyle(.secondary)
                + Text(usageTracker.count == 1 ? "1 fois." : "\(usageTracker.count) fois.").foregroundStyle(.primary)
            )
            .font(.system(size: 12))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)

            // K.4-lot3 (L1) : moyenne quotidienne sous la phrase du total.
            // Hérite de la condition d'affichage de `usageCounter` (count > 0) ;
            // garde défensive si la moyenne est indisponible (ne devrait pas
            // arriver avec count > 0, firstUseDate étant alors posée).
            if let average = usageTracker.formattedDailyAverage() {
                (
                    Text("Soit une moyenne de ").foregroundStyle(.secondary)
                    + Text("\(average) fois/jour.").foregroundStyle(.primary)
                )
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .padding(.top, 2)
            }
        }
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
        } catch LicenseError.activationLimitReached {
            // 403 (commit 3) : on ouvre la modale dédiée pour permettre
            // à l'utilisateur de libérer un slot. La modale retry
            // l'activate automatiquement après désactivation réussie.
            // Pas d'activationError ici — sinon double signal côté UI
            // (modal + texte d'erreur sous le formulaire).
            pendingActivationKey = trimmed
            showLimitReachedModal = true
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

    /// Désactive un AUTRE device (pas celui-ci) côté Polar, sans wipe
    /// du Keychain — la licence reste active sur cet appareil. Loader
    /// par ligne via `deactivatingActivationIds` (Set) pour ne pas
    /// bloquer toute l'UI si plusieurs désactivations s'enchaînent.
    /// Erreurs silencieuses en V1 (peuplent `manager.lastError`, pas
    /// de toast — note backlog V2 « Toast notifications pour erreurs
    /// UX licence »).
    private func performDeactivateOther(_ device: PolarActivationDetail) async {
        deactivatingActivationIds.insert(device.id)
        defer { deactivatingActivationIds.remove(device.id) }

        do {
            try await manager.deactivate(activationId: device.id)
        } catch {
            // Silent fail : `manager.lastError` est peuplé. La liste
            // se rafraîchit via `refreshActivations()` dans le manager
            // sur succès uniquement, donc en cas d'échec la ligne
            // reste affichée et l'utilisateur peut retenter.
        }
        otherDeviceToDeactivate = nil
    }

    /// Ouvre le checkout Polar dans la fenêtre embarquée (WKWebView).
    /// À l'achat réussi, `presentCheckout` ramène sur Réglages → Licence
    /// avec focus sur le champ de saisie de clé.
    private func openCheckout() {
        PurchaseWindowController.presentCheckout()
    }

    /// D.6 — consomme la demande de focus du champ clé. `async` pour poser
    /// le focus une fois la fenêtre Réglages *key* + reset du flag.
    private func consumeFocusRequest() {
        DispatchQueue.main.async {
            keyFieldFocused = true
            manager.focusKeyFieldRequest = false
        }
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
