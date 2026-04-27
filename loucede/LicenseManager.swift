//
//  LicenseManager.swift
//  loucede
//
//  Phase 6.2 (2026-04-27) : refactor du stub Phase 6.16 en source de
//  vérité du système de licence Polar.sh.
//
//  Architecture en 3 couches :
//    1. `LicenseService` (réseau) — appels au proxy Scaleway
//    2. `KeychainService.License` (stockage) — clé / activation_id /
//       trial counter / cache offline
//    3. `LicenseManager` (état + logique métier, ce fichier)
//
//  La gate effective sur les fonctionnalités payantes (`hasLicense`,
//  `canRunAction`) lit depuis `status` + `trialUsageCount`. En build
//  Debug, `hasLicense` retourne toujours `true` pour ne pas bloquer
//  les tests pendant le dev.
//

import Foundation
import Combine
import AppKit

@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    /// État côté loucedé. Combine les status Polar (granted / revoked /
    /// disabled) avec les états locaux (validating / offline avec cache).
    enum Status: Equatable {
        /// Pas de clé activée (premier lancement ou après deactivate).
        case unlicensed
        /// Call API en cours (activate, validate ou deactivate).
        case validating
        /// Licence active : status Polar = `granted`, expiration OK.
        case active
        /// Status Polar = `revoked` (admin a coupé l'accès).
        case revoked
        /// Status Polar = `disabled` (paiement annulé, chargeback).
        case disabled
        /// `expiresAt` Polar dépassée. Rare pour des achats one-shot
        /// mais possible avec des subscriptions.
        case expired
        /// Pas de réseau, mais on a un cache récent (< 7j) + dernier
        /// status connu = granted. `hasLicense` reste `true`.
        case offline
    }

    @Published private(set) var status: Status = .unlicensed
    @Published private(set) var trialUsageCount: Int = 0
    @Published private(set) var customerEmail: String?
    @Published private(set) var activationsLimit: Int?
    @Published private(set) var expiresAt: Date?
    @Published var lastError: LicenseError?

    /// Sobriquet super-héros généré une fois sur demande de
    /// l'utilisateur (bouton « Obtenir mon nom » dans Réglages →
    /// Licence). Stocké en Keychain (`KeychainService.License.heroName`)
    /// et conservé tant que la licence est active. Wipe lors du
    /// deactivate.
    @Published private(set) var heroName: String?

    /// `true` pendant l'appel LLM de génération du heroName. Permet
    /// d'afficher un spinner sur le bouton et d'éviter les double-clics.
    @Published private(set) var isGeneratingHeroName: Bool = false

    /// Limite du trial gratuit. Au-delà, `hasTrialRemaining = false`
    /// et l'utilisateur sans licence voit un modal d'achat.
    static let trialLimit: Int = 12

    /// Grace period offline : si la dernière validation réussie date
    /// de moins de 7 jours et que le status connu était `granted`, on
    /// considère la licence active même sans réseau (status = .offline).
    static let offlineGracePeriod: TimeInterval = 7 * 24 * 3600

    /// Source de vérité pour les fonctionnalités license-gated. En
    /// Debug, retourne toujours `true` pour ne pas bloquer les tests
    /// pendant le dev (override compile-time, ne shippe pas en prod).
    var hasLicense: Bool {
        #if DEBUG
        return true
        #else
        switch status {
        case .active, .offline:
            return true
        default:
            return false
        }
        #endif
    }

    /// `true` si l'utilisateur n'a pas encore atteint la limite des
    /// 12 essais gratuits.
    var hasTrialRemaining: Bool {
        trialUsageCount < Self.trialLimit
    }

    /// Source de vérité pour `runAction` : peut-il lancer une action LLM ?
    /// `true` si licence active OU trial encore disponible.
    var canRunAction: Bool {
        hasLicense || hasTrialRemaining
    }

    private init() {
        loadFromKeychain()
    }

    // MARK: - Public API

    /// Charge le state depuis Keychain. Appelé par `init`, re-appelable
    /// manuellement pour resync (peu utile en pratique).
    ///
    /// Met le status sur la base du `lastKnownStatus` cached pour que
    /// `hasLicense` retourne la bonne valeur dès le démarrage, même si
    /// le `validate()` async n'a pas encore répondu.
    func loadFromKeychain() {
        trialUsageCount = KeychainService.License.trialUsageCount
        customerEmail = KeychainService.License.customerEmail
        heroName = KeychainService.License.heroName

        // Si on a une clé en Keychain, on commence dans le state du
        // dernier status connu. Le `validate()` au démarrage confirmera
        // ou ajustera. Sans cette pré-restauration, l'app démarrerait
        // toujours en `.unlicensed` puis flickerait vers `.active`
        // quand le validate répondrait.
        if KeychainService.License.key != nil {
            switch KeychainService.License.lastKnownStatus {
            case "granted":  status = .active
            case "revoked":  status = .revoked
            case "disabled": status = .disabled
            default:         status = .active  // optimiste : licence présente, status inconnu = on suppose OK
            }
        } else {
            status = .unlicensed
        }
    }

    /// Active une nouvelle clé sur cet appareil.
    /// - Stocke `key` + `activation_id` en Keychain en cas de succès.
    /// - Met à jour le status + métadonnées (email, limit_activations,
    ///   expires_at).
    /// - Throws `LicenseError` si l'API rejette (clé invalide, limite
    ///   atteinte, réseau down…).
    func activate(key: String) async throws {
        status = .validating
        lastError = nil

        let label = Host.current().localizedName ?? "Mac"

        do {
            let result = try await LicenseService.shared.activate(key: key, label: label)

            // Stockage Keychain
            KeychainService.License.key = key
            KeychainService.License.activationId = result.id
            KeychainService.License.lastKnownStatus = result.licenseKey.status.rawValue
            KeychainService.License.lastValidatedAt = Date()
            KeychainService.License.customerEmail = result.licenseKey.customer?.email

            // Update state
            updateStateFrom(licenseKey: result.licenseKey)
        } catch let error as LicenseError {
            status = .unlicensed
            lastError = error
            throw error
        } catch {
            let wrapped = LicenseError.unknown(error.localizedDescription)
            status = .unlicensed
            lastError = wrapped
            throw wrapped
        }
    }

    /// Re-valide la clé existante côté Polar. Non-throws — met à jour
    /// `status` et éventuellement `lastError`. Utilisé au démarrage
    /// (validation passive, `silent: true`) et sur trigger manuel.
    ///
    /// `silent` : si `true`, ne passe PAS par le status `.validating`
    /// pendant le call — utile au démarrage pour éviter le flicker
    /// `.active (depuis cache loadFromKeychain) → .validating → .active`.
    /// Le pré-status restauré depuis Keychain reste affiché tant que
    /// la vraie réponse Polar n'est pas tombée.
    ///
    /// Logique offline : si l'erreur est réseau et qu'on a un cache
    /// récent (< 7j) avec dernier status `granted`, on bascule en
    /// `.offline` (qui counts as `hasLicense` via `hasLicense`).
    func validate(silent: Bool = false) async {
        guard let key = KeychainService.License.key,
              let activationId = KeychainService.License.activationId else {
            status = .unlicensed
            return
        }

        if !silent {
            status = .validating
        }
        lastError = nil

        do {
            let result = try await LicenseService.shared.validate(key: key, activationId: activationId)

            // Update Keychain
            KeychainService.License.lastKnownStatus = result.status.rawValue
            KeychainService.License.lastValidatedAt = Date()
            KeychainService.License.customerEmail = result.customer?.email

            // Update state
            updateStateFromValidated(result)
        } catch let error as LicenseError {
            handleValidateError(error)
        } catch {
            status = .unlicensed
            lastError = .unknown(error.localizedDescription)
        }
    }

    /// Désactive l'appareil côté Polar et wipe le Keychain (sauf le
    /// trial counter, qui a été consommé).
    /// Throws si l'API fail — dans ce cas on garde le state actuel
    /// pour que l'utilisateur puisse retenter (sinon il aurait perdu
    /// sa licence localement sans la libérer chez Polar).
    func deactivate() async throws {
        guard let key = KeychainService.License.key,
              let activationId = KeychainService.License.activationId else {
            // Déjà désactivé — no-op, on assure juste que le state est cohérent.
            resetLocalState()
            return
        }

        do {
            try await LicenseService.shared.deactivate(key: key, activationId: activationId)
            KeychainService.License.wipe()  // garde trial counter
            resetLocalState()
        } catch let error as LicenseError {
            lastError = error
            throw error
        }
    }

    /// Incrémente le compteur du trial gratuit. À appeler **après**
    /// une action LLM réussie (pas avant — pour ne pas brûler des
    /// essais sur des erreurs réseau ou clé API absente).
    func incrementTrialUsage() {
        let next = trialUsageCount + 1
        trialUsageCount = next
        KeychainService.License.trialUsageCount = next
    }

    // MARK: - Internals

    private func updateStateFrom(licenseKey: PolarLicenseKey) {
        customerEmail = licenseKey.customer?.email
        activationsLimit = licenseKey.limitActivations
        expiresAt = licenseKey.expiresAt

        if let expires = licenseKey.expiresAt, expires < Date() {
            status = .expired
            return
        }

        switch licenseKey.status {
        case .granted:  status = .active
        case .revoked:  status = .revoked
        case .disabled: status = .disabled
        case .unknown:  status = .unlicensed
        }
    }

    private func updateStateFromValidated(_ result: PolarValidatedLicenseKey) {
        customerEmail = result.customer?.email
        activationsLimit = result.limitActivations
        expiresAt = result.expiresAt

        if let expires = result.expiresAt, expires < Date() {
            status = .expired
            return
        }

        switch result.status {
        case .granted:  status = .active
        case .revoked:  status = .revoked
        case .disabled: status = .disabled
        case .unknown:  status = .unlicensed
        }
    }

    /// Routage des erreurs de `validate()` vers le bon status local.
    private func handleValidateError(_ error: LicenseError) {
        // Réseau down : si on a un cache récent + dernier status granted,
        // on bascule en offline (hasLicense reste true). Sinon, on reflète
        // l'erreur au status.
        if error == .networkUnavailable || error == .proxyUnreachable {
            if let lastValidated = KeychainService.License.lastValidatedAt,
               Date().timeIntervalSince(lastValidated) < Self.offlineGracePeriod,
               KeychainService.License.lastKnownStatus == "granted" {
                status = .offline
                lastError = nil  // pas d'erreur visible — l'app fonctionne en mode dégradé
                return
            }
            // Cache trop ancien ou status non-granted → on reflète l'erreur
            status = .unlicensed
            lastError = error
            return
        }

        // Erreurs Polar « la clé n'existe plus » → wipe local pour
        // cohérence (la clé en Keychain ne sert à rien).
        switch error {
        case .keyNotFound, .invalidKey:
            KeychainService.License.wipe()
            resetLocalState()
        case .activationLimitReached:
            // L'activation_id n'est plus reconnue (probablement désactivée
            // depuis un autre device ou limite atteinte). On garde la clé
            // mais on oublie l'activation pour que l'utilisateur puisse
            // re-activate proprement.
            KeychainService.License.activationId = nil
            status = .unlicensed
        default:
            status = .unlicensed
        }
        lastError = error
    }

    /// Reset les `@Published` locaux à leurs valeurs par défaut.
    /// Le trial counter n'est PAS touché (il survit à la désactivation).
    private func resetLocalState() {
        status = .unlicensed
        customerEmail = nil
        activationsLimit = nil
        expiresAt = nil
        heroName = nil
        lastError = nil
    }

    // MARK: - Hero name (sobriquet généré par le LLM)

    /// Erreur typée pour la génération du heroName.
    enum HeroNameError: LocalizedError {
        case noApiKey
        case invalidResponse
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .noApiKey:
                return "Configure d'abord ta clé API dans Général."
            case .invalidResponse:
                return "Réponse du modèle inexploitable."
            case .networkError(let error):
                return "Erreur réseau : \(error.localizedDescription)"
            }
        }
    }

    /// Génère un nom de super-héros via le provider IA configuré, le
    /// stocke en Keychain et le publie dans `heroName`. Pas de retry,
    /// pas de fallback : si le call fail, l'utilisateur peut juste
    /// re-cliquer le bouton.
    ///
    /// Pattern d'appel HTTP one-shot inspiré de `PromptImprover` —
    /// même structure (différencie Anthropic des deux autres pour les
    /// headers + le shape du body / response).
    ///
    /// Note backlog V2 : propager le nom en metadata du customer Polar
    /// (PATCH /v1/customers/{id}) pour extraction newsletter future.
    /// Nécessite un nouveau endpoint dans le proxy Scaleway, pas
    /// implémenté en V1.
    func generateHeroName() async throws {
        let store = ActionsStore.shared
        guard !store.apiKey.isEmpty else {
            throw HeroNameError.noApiKey
        }

        isGeneratingHeroName = true
        defer { isGeneratingHeroName = false }

        // Tentative #1 avec prompt strict. Si le LLM renvoie un nom
        // collé en un seul mot (« Shadowstrike »), on retry une fois
        // avec un prompt encore plus explicite. Évite le mauvais cas
        // « un mot collé » sans bloquer indéfiniment l'utilisateur.
        var name = try await callLLMForHeroName(store: store, retryAttempt: false)
        if !name.contains(" ") {
            name = try await callLLMForHeroName(store: store, retryAttempt: true)
        }

        heroName = name
        KeychainService.License.heroName = name
    }

    /// Appel HTTP one-shot vers le provider IA pour générer un nom de
    /// hero. `retryAttempt` enrichit le prompt avec des exemples
    /// concrets si le premier essai a échoué (mot collé renvoyé).
    private func callLLMForHeroName(store: ActionsStore, retryAttempt: Bool) async throws -> String {
        let provider = store.selectedProvider
        let model = store.selectedModel
        let apiKey = store.apiKey

        // Prompt enrichi avec exemples pour le retry — les LLMs
        // respectent mieux les contraintes when on leur montre.
        let prompt: String
        if retryAttempt {
            prompt = """
            Generate a two-word English superhero name. The two words MUST be \
            separated by a single space. Examples of valid format: "Shadow Falcon", \
            "Iron Phoenix", "Storm Rider". Examples of INVALID format: "Shadowfalcon", \
            "Ironphoenix" (no space). Reply only with the name, no punctuation, \
            no explanation.
            """
        } else {
            prompt = """
            Generate a two-word English superhero name. The two words must be \
            separated by a space (like "Shadow Falcon", not "Shadowfalcon"). \
            Reply only with the name, no punctuation, no explanation.
            """
        }

        let url = URL(string: provider.baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if provider == .anthropic {
            request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any]
        if provider == .anthropic {
            body = [
                "model": model.id,
                "max_tokens": 50,
                "messages": [["role": "user", "content": prompt]]
            ]
        } else {
            body = [
                "model": model.id,
                "messages": [["role": "user", "content": prompt]]
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw HeroNameError.networkError(error)
        }

        // Parsing selon provider — Anthropic vs OpenAI/Mistral ont des
        // shapes différents, comme PromptImprover.
        var rawText: String?
        if provider == .anthropic {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? [[String: Any]],
               let first = content.first,
               let text = first["text"] as? String {
                rawText = text
            }
        } else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                rawText = content
            }
        }

        guard let raw = rawText else {
            throw HeroNameError.invalidResponse
        }

        // Sanitize : trim espaces + ponctuation finale (le LLM peut
        // ajouter un point ou des guillemets malgré le prompt).
        let cleaningSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let cleaned = raw.trimmingCharacters(in: cleaningSet)

        guard !cleaned.isEmpty else {
            throw HeroNameError.invalidResponse
        }
        return cleaned
    }
}
