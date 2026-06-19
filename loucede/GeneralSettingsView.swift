//
//  GeneralSettingsView.swift
//  loucede
//
//  Réglages généraux : API, préférences, permissions.
//

import SwiftUI

// Phase 6.7b revertée (2026-04-29) : loucedé suit le mode système macOS.
// L'enum AppTheme, l'AppStorage "appTheme" et le picker associé restent
// absents — pas d'option utilisateur, adaptation automatique via
// @Environment(\.colorScheme). La clé UserDefaults "appTheme" reste
// orpheline chez les users existants (inoffensive).

struct GeneralSettingsView: View {
    @StateObject private var store = ActionsStore.shared
    @State private var apiKeyInput: String = ""
    @State private var selectedProvider: AIProvider = .openai
    @State private var selectedModelId: String = ""
    /// U.5.c (batch C) : adoption du helper canonique `ShortcutRecorder`
    /// (l'ex-copie privée + sa `keyCodeMap` morte ont été supprimées). Le
    /// hotkey Carbon est suspendu pendant la capture et rétabli sur tous les
    /// chemins de sortie (commit, Esc, disparition de la vue).
    @StateObject private var recorder = ShortcutRecorder()
    /// Phase 6.5a : toggle « Lancer au démarrage ». Synchronisé avec
    /// `SMAppService.mainApp.status` au .onAppear ; un .onChange relaye
    /// la modification au système. En cas d'échec (rare : profil MDM,
    /// status `.requiresApproval`), on revert visuellement.
    @State private var launchAtLoginEnabled: Bool = false
    @Environment(\.colorScheme) var colorScheme

    /// Liste filtrée par la vérif live si disponible, sinon liste hard-codée
    /// complète. Si l'intersection retombe à 0 (ex. tous nos IDs hard-codés
    /// obsolètes côté serveur), on retourne tout de même la liste hard-codée
    /// complète pour ne pas afficher un Picker vide.
    private var availableModels: [AIModel] {
        let all = AIModel.models(for: selectedProvider)
        guard let verified = store.verifiedModelIds[selectedProvider] else {
            return all
        }
        let filtered = all.filter { verified.contains($0.id) }
        return filtered.isEmpty ? all : filtered
    }

    /// Renvoie le modelId persisté pour ce provider s'il est toujours
    /// dans la liste `availableModels`, sinon bascule sur le défaut et
    /// persiste immédiatement le nouveau choix pour nettoyer l'UserDefaults.
    /// Évite le cas où le Picker a un selection qui ne match aucun tag
    /// (ex. claude-3-5-sonnet-20241022 retiré de la liste) → Picker vide.
    private func resolvedModelId(for provider: AIProvider) -> String {
        let stored = store.modelId(for: provider)
        let validIds = availableModels.map(\.id)
        if validIds.contains(stored) {
            return stored
        }
        let fallback = validIds.first ?? provider.defaultModelId
        store.saveModel(fallback, for: provider)
        return fallback
    }

    // App accent blue color
    private var appBlue: Color {
        Color(red: 0.0, green: 0.584, blue: 1.0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Section Configuration API
                VStack(alignment: .leading, spacing: 16) {
                    Text("Configuration API")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)

                    // Phase 6.11b (2026-04-25) : la carte des specs est imbriquée
                    // dans un VStack avec les Pickers pour qu'elle hérite
                    // automatiquement de la largeur cumulée Provider + Modèle
                    // (suggestion utilisateur : aligner pile sur le bord droit
                    // du Picker modèle, plutôt qu'une largeur cap arbitraire).
                    HStack(alignment: .top) {
                        HStack(spacing: 10) {
                            Image(selectedProvider.iconName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                            Text("Fournisseur IA")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 160, alignment: .leading)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Picker("", selection: $selectedProvider) {
                                    ForEach(AIProvider.allCases, id: \.self) { provider in
                                        Text(provider.rawValue).tag(provider)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .onChange(of: selectedProvider) { _, newValue in
                                    store.saveProvider(newValue)
                                    // Vérif live des modèles pour le nouveau provider
                                    // (la liste filtrée est appliquée quand la réponse arrive).
                                    Task { await store.verifyAvailableModels(for: newValue) }
                                    // Load saved model for this provider (auto-fallback si l'ID persisté n'est plus valide)
                                    selectedModelId = resolvedModelId(for: newValue)
                                    // Load API key for the new provider
                                    apiKeyInput = store.apiKey(for: newValue)
                                }
                                .onAppear {
                                    selectedProvider = store.selectedProvider
                                    selectedModelId = resolvedModelId(for: store.selectedProvider)
                                    apiKeyInput = store.apiKey(for: store.selectedProvider)
                                    // Première vérif du provider courant à l'ouverture des Réglages.
                                    Task { await store.verifyAvailableModels(for: store.selectedProvider) }
                                }

                                Picker("", selection: $selectedModelId) {
                                    ForEach(availableModels) { model in
                                        Text(model.name).tag(model.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .onChange(of: selectedModelId) { _, newValue in
                                    store.saveModel(newValue)
                                }
                                .onChange(of: store.verifiedModelIds[selectedProvider]) { _, _ in
                                    // Si la vérif vient de retirer le modèle actuellement choisi,
                                    // re-résoudre vers un modèle toujours disponible.
                                    selectedModelId = resolvedModelId(for: selectedProvider)
                                }

                                // Spinner discret pendant la vérif live des modèles
                                if store.verifyingProviders.contains(selectedProvider) {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(width: 16, height: 16)
                                }
                            }

                            // La card s'étire à `maxWidth: .infinity` pour
                            // matcher la largeur du VStack parent — qui est
                            // lui-même piloté par la largeur intrinsèque du
                            // HStack des Pickers ci-dessus. Donc card largeur
                            // = Picker provider + Picker modèle (+ spinner si
                            // visible). Pile sur le bord droit du Picker
                            // modèle.
                            if let model = availableModels.first(where: { $0.id == selectedModelId }) {
                                ModelSpecsCard(model: model)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        // L.5 — carte « Coût estimé » dans l'espace droit
                        // jusqu'ici vide (ancien Spacer). maxHeight + alignment
                        // .bottom = aimantée en bas du HStack (donc alignée sur
                        // le bas de ModelSpecsCard) ; la carte grossit vers le
                        // HAUT à mesure que des lignes modèle s'ajoutent.
                        CostEstimateCard(provider: selectedProvider)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }

                    HStack {
                        HStack(spacing: 10) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.orange)
                            Text("Clé API")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 160, alignment: .leading)

                        SecureField(selectedProvider.apiKeyPlaceholder, text: $apiKeyInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .onChange(of: apiKeyInput) { _, newValue in
                                // L7-FN-002 : trim avant persistance Keychain. Un
                                // coller avec espace/newline en fin était stocké
                                // verbatim puis envoyé dans le header Authorization
                                // → 401 silencieux. On ne touche pas `apiKeyInput`
                                // (affichage live intact), seule la valeur persistée
                                // est nettoyée.
                                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                store.saveApiKey(trimmed, for: selectedProvider)
                            }
                    }

                    // Phase 6.11a (2026-04-25) : URL cliquable. Le domaine est
                    // affiché tel quel (sans `https://`, plus lisible) ; le
                    // `Link` y ajoute le scheme pour ouvrir le navigateur.
                    HStack(spacing: 0) {
                        Text("Obtiens ta clé API sur ")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        if let url = URL(string: "https://\(selectedProvider.websiteURL)") {
                            // `Link` gère déjà le curseur pointing hand au hover
                            // sur macOS — pas besoin de `.pointerCursor()`.
                            Link(selectedProvider.websiteURL, destination: url)
                                .font(.system(size: 12, weight: .semibold))
                        } else {
                            // Fallback défensif (URL malformée — ne devrait
                            // jamais arriver vu le contenu hard-codé). On
                            // rend non-cliquable plutôt que de crasher.
                            Text(selectedProvider.websiteURL)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 160)
                }

                Divider()

                // Section Préférences
                VStack(alignment: .leading, spacing: 16) {
                    Text("Préférences")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)

                    VStack(spacing: 0) {
                        if recorder.isRecording {
                            ShortcutTooltip(recordedKeys: recorder.liveKeys, conflictName: nil)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.8, anchor: .bottom).combined(with: .opacity),
                                    removal: .scale(scale: 0.8, anchor: .bottom).combined(with: .opacity)
                                ))
                                .padding(.bottom, 8)
                        }

                        HStack {
                            HStack(spacing: 10) {
                                Image(systemName: "keyboard.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.pink)
                                Text("Raccourci global")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: {
                                // Suspend le hotkey Carbon pendant la capture ;
                                // rétabli sur commit OU annulation Esc. La
                                // disparition de la vue (`.onDisappear`) couvre
                                // le cas « fenêtre fermée pendant l'écoute ».
                                globalAppDelegate?.suspendHotkeys()
                                recorder.start(
                                    onCommit: { globalAppDelegate?.resumeHotkeys() },
                                    onCancel: { globalAppDelegate?.resumeHotkeys() }
                                )
                            }) {
                                HStack(spacing: 6) {
                                    ForEach(store.mainShortcutModifiers, id: \.self) { mod in
                                        Settings3DKey(text: mod)
                                    }
                                    Settings3DKey(text: store.mainShortcut)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.gray.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: recorder.isRecording)

                    // Phase 6.5a (2026-04-25) : toggle « Lancer au démarrage ».
                    // S'appuie sur SMAppService (macOS 13+) — pas de helper
                    // tool ni de plist supplémentaire requis.
                    HStack {
                        HStack(spacing: 10) {
                            Image(systemName: "power.circle.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Lancer au démarrage")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Text("Ouvre loucedé automatiquement à la connexion")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                        }
                        Spacer()
                        Toggle("", isOn: $launchAtLoginEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .onAppear {
                        // Source de vérité = SMAppService.mainApp.status. On le
                        // relit à l'ouverture des Réglages plutôt que d'utiliser
                        // un cache persisté côté app : l'utilisateur peut avoir
                        // désactivé le login item depuis Réglages Système entre-
                        // temps, et on veut refléter l'état réel.
                        launchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
                    }
                    .onChange(of: launchAtLoginEnabled) { _, newValue in
                        let success = LaunchAtLoginManager.shared.setEnabled(newValue)
                        if !success {
                            // Échec (cas rare : MDM, .requiresApproval) — on
                            // resync le toggle sur l'état réel pour ne pas
                            // mentir à l'utilisateur.
                            DispatchQueue.main.async {
                                launchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
                            }
                        }
                    }
                }

                Divider()

                // Permissions Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Autorisations")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)

                    HStack {
                        HStack(spacing: 10) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Accessibilité")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Text("Requis pour les raccourcis clavier globaux")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                        }

                        Spacer()

                        Button(action: {
                            openAccessibilitySettings()
                        }) {
                            Text("Ouvrir les réglages")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(appBlue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(appBlue.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                // M.2.7 — Section Tutoriel (entry point release : rejouer le tuto)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tutoriel")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)

                    HStack {
                        HStack(spacing: 10) {
                            Image(systemName: "graduationcap.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.purple)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Réviser les bases")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Text("Refais le tuto interactif à tout moment")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                        }

                        Spacer()

                        Button(action: {
                            TutorialWindowController.present()
                        }) {
                            Text("Refaire le tuto")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.purple)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.purple.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                #if DEBUG
                Divider()

                // Section Développeur (DEBUG uniquement)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Développeur")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)

                    HStack {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.red)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Réinitialiser l'onboarding")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Text("Réaffiche l'onboarding au prochain lancement")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                        }

                        Spacer()

                        Button(action: {
                            OnboardingManager.shared.resetOnboarding()
                            NSApp.terminate(nil)
                        }) {
                            Text("Réinitialiser et quitter")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.red)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.red.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                #endif

                Spacer()
            }
            .padding(30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onDisappear {
            // L7-FN-001 : si la vue disparaît (fermeture fenêtre / switch
            // d'onglet) pendant une capture, on arrête le monitor ET on
            // rétablit le hotkey Carbon suspendu — sinon ⌥& resterait mort.
            let wasRecording = recorder.isRecording
            recorder.stop()
            if wasRecording { globalAppDelegate?.resumeHotkeys() }
        }
    }
}

// MARK: - Model Specs Card

/// Carte d'information du modèle sélectionné (nom + description + 3 barres
/// Vitesse/Intelligence/Coût). Phase 6.11b : ex-`ModelSpecsTooltip` qui
/// s'affichait en popover au survol du Picker. Désormais inline sous les
/// Pickers, en permanence visible — pas de shadow, fond discret aligné
/// sur les autres conteneurs des Réglages.
struct ModelSpecsCard: View {
    let model: AIModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Nom du modèle. Le logo provider a été retiré (inbox 16/06) :
            // redondant avec le selector Fournisseur au-dessus et avec la
            // marque déjà présente dans le nom (« Mistral Medium »).
            Text(model.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary)

            // Description courte
            Text(model.specs.description)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 3 barres de specs
            VStack(alignment: .leading, spacing: 6) {
                SpecsBar(label: "Vitesse", value: model.specs.speed)
                SpecsBar(label: "Intelligence", value: model.specs.intelligence)
                SpecsBar(label: "Coût tokens", value: model.specs.tokenUsage, inverted: true)
            }
        }
        .padding(14)
        // Pas de cap de largeur ici : la largeur est pilotée par le call site
        // (Phase 6.11b : matche la largeur cumulée des Pickers Provider + Modèle).
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(colorScheme == .dark ? 0.10 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}

struct SpecsBar: View {
    let label: String
    let value: Int // 1-5
    var inverted: Bool = false // For token usage: higher value = lower consumption, so invert display

    private var appBlue: Color {
        Color(red: 0.0, green: 0.584, blue: 1.0)
    }

    // For inverted bars (like token usage), we flip the display
    // tokenUsage 5 (cheap) shows 1 bar, tokenUsage 1 (expensive) shows 5 bars
    private var displayValue: Int {
        inverted ? (6 - value) : value
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 75, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < displayValue ? appBlue : Color.gray.opacity(0.3))
                        .frame(width: 18, height: 6)
                }
            }
        }
    }
}

// MARK: - Carte « Coût estimé » (Phase L.5)

/// Affiche le coût IA estimé cumulé pour le fournisseur sélectionné, à
/// partir des tokens enregistrés par `UsageTracker` (L.3) et de la grille
/// `modelPricing` (L.4). Réactive via `@ObservedObject` sur le tracker.
///
/// Bascule mono ↔ multi selon le nombre de modèles du fournisseur ayant un
/// usage > 0 : 0 ou 1 → layout centré (total seul) ; ≥ 2 → total à gauche +
/// détail par modèle à droite (trié par coût décroissant).
struct CostEstimateCard: View {
    let provider: AIProvider
    @ObservedObject private var usage = UsageTracker.shared
    @Environment(\.colorScheme) var colorScheme

    private var appBlue: Color {
        Color(red: 0.0, green: 0.584, blue: 1.0)
    }

    private struct ModelCost: Identifiable {
        let id: String
        let name: String
        let cost: Double?   // nil = modelId absent de la grille (--,-- €)
    }

    /// Modèles du fournisseur avec usage > 0, triés par coût décroissant.
    private var costs: [ModelCost] {
        AIModel.models(for: provider)
            .compactMap { model -> ModelCost? in
                guard let counts = usage.tokensByModel[model.id],
                      counts.input + counts.output > 0 else { return nil }
                let cost = estimatedCostEUR(modelId: model.id,
                                            inputTokens: counts.input,
                                            outputTokens: counts.output)
                return ModelCost(id: model.id, name: model.name, cost: cost)
            }
            .sorted { ($0.cost ?? -1) > ($1.cost ?? -1) }
    }

    private var total: Double {
        costs.compactMap { $0.cost }.reduce(0, +)
    }

    /// Format FR : virgule, « X,XX € ». `0,00 €` pour un zéro réel,
    /// `< 0,01 €` pour un coût non nul sous le centime, `--,-- €` pour nil.
    private func formatCost(_ value: Double?) -> String {
        guard let value else { return "--,-- €" }
        if value == 0 { return "0,00 €" }
        if value < 0.01 { return "< 0,01 €" }
        let fmt = NumberFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.numberStyle = .currency
        fmt.currencyCode = "EUR"
        return fmt.string(from: NSNumber(value: value)) ?? "--,-- €"
    }

    var body: some View {
        VStack(spacing: 8) {
            // Ligne « Coût total estimé » — toujours présente. Typo + icône
            // fournisseur calquées sur le nom de modèle de ModelSpecsCard
            // (Image 18×18 + spacing 8, 14px bold .primary) pour cohérence
            // visuelle avec le cadre voisin.
            HStack(spacing: 8) {
                Image(provider.iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                Text("Coût total estimé")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
                Text(formatCost(total))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
            }

            // Détail par modèle (tableau 2 colonnes) — affiché seulement à
            // partir de 2 modèles utilisés ; vide en mono/initial (pas de
            // bascule de layout, juste une liste vide).
            if costs.count >= 2 {
                Divider()
                VStack(spacing: 4) {
                    ForEach(costs) { entry in
                        HStack {
                            Text(entry.name)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formatCost(entry.cost))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Divider()

            if let url = URL(string: provider.billingURL) {
                Link("afficher le coût réel →", destination: url)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(appBlue)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(colorScheme == .dark ? 0.10 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    GeneralSettingsView()
        .frame(width: 700, height: 520)
}
