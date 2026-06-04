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

#if DEBUG
/// États licence simulables en build Debug, pilotés depuis le panneau
/// Debug de Réglages → Licence. Remplace l'ancien override binaire
/// (`hasLicense` forcé `true`) par un override paramétrable, pour rendre
/// les écrans trial testables sans dépendre de Polar ni du Keychain.
/// Mécanisme permanent (pas éphémère) : sert à tous les tests trial
/// présents et futurs. Absorbe l'item backlog `dev-license.md`.
enum DebugLicenseState: String, CaseIterable {
    /// `hasLicense = true` — défaut, préserve le confort dev (pas
    /// d'incrément de trial en dev).
    case licensed
    /// `hasLicense = false`, compteur trial réel (incréments observables ;
    /// combiner avec « Reset trial counter » pour repartir de 0).
    case trialActive
    /// `hasLicense = false` + trial forcé épuisé (non destructif : ne
    /// touche pas au compteur Keychain) → affiche `TrialExpiredOverlay`.
    case trialExpired

    var label: String {
        switch self {
        case .licensed:     return "Licencié"
        case .trialActive:  return "Trial actif"
        case .trialExpired: return "Trial épuisé"
        }
    }
}
#endif

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

    /// Nombre d'activations actuellement consommées (X dans le compteur
    /// X/Y de Réglages → Licence). Populé par `refreshActivations()`.
    /// `nil` tant que le fetch n'a pas réussi — l'UI affiche alors la
    /// limite seule en fallback.
    @Published private(set) var activationsUsed: Int?

    /// Liste détaillée des activations en cours pour la licence active.
    /// Populée par `refreshActivations()`. Vide tant que pas fetché ou
    /// en cas d'erreur réseau. Sera consommée par l'UI cross-device
    /// deactivate au commit 3.
    @Published private(set) var activations: [PolarActivationDetail] = []

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

    // MARK: UI coordination
    /// Demande de focus du champ de saisie de clé dans `LicenseSettingsView`,
    /// posée après un achat réussi (cf. `PurchaseWindowController.presentCheckout`).
    /// La vue la consomme puis la remet à `false`.
    @Published var focusKeyFieldRequest: Bool = false

    #if DEBUG
    /// Clé UserDefaults de persistance de l'override licence Debug
    /// (survit aux relances de l'app).
    private static let debugOverrideKey = "loucede.debug.licenseOverride"

    /// État licence simulé en Debug (cf. `DebugLicenseState`). Persisté en
    /// UserDefaults via `didSet`. Lu par `hasLicense`/`hasTrialRemaining`.
    /// Défaut `.licensed` → comportement Debug historique préservé.
    @Published var debugLicenseOverride: DebugLicenseState = .licensed {
        didSet {
            UserDefaults.standard.set(debugLicenseOverride.rawValue, forKey: Self.debugOverrideKey)
        }
    }
    #endif

    /// Limite du trial gratuit. Au-delà, `hasTrialRemaining = false`
    /// et l'utilisateur sans licence voit un modal d'achat.
    static let trialLimit: Int = 12

    /// Grace period offline : si la dernière validation réussie date
    /// de moins de 7 jours et que le status connu était `granted`, on
    /// considère la licence active même sans réseau (status = .offline).
    static let offlineGracePeriod: TimeInterval = 7 * 24 * 3600

    /// Source de vérité pour les fonctionnalités license-gated.
    ///
    /// En build Debug, retourne toujours `true` pour ne pas bloquer le
    /// dev (override compile-time, ne shippe pas en prod). Cet override
    /// est le **pivot unique** du mode debug : tout le reste cascade
    /// automatiquement depuis `hasLicense` — pas besoin d'un `#if DEBUG`
    /// supplémentaire ailleurs dans le code.
    ///
    /// ## Surfaces couvertes par cascade
    ///
    /// Les sites suivants deviennent automatiquement « gate ouverte » en
    /// Debug parce qu'ils lisent `hasLicense` (directement ou via une
    /// computed qui en dépend) :
    ///
    /// - `AboutView.swift:99` — bouton « Envoyer une suggestion »
    ///   (direct : `.disabled(!hasLicense)`).
    /// - `PopoverState.swift:167` — gate `runAction` via `canRunAction`
    ///   (cascade `||` : `canRunAction = hasLicense || hasTrialRemaining`).
    /// - `PopoverState.swift:195` — snapshot `consumesTrial` au lancement
    ///   du stream (cascade `!` : `consumesTrial = !hasLicense` → pas
    ///   d'incrément trial en Debug).
    ///
    /// ## Bypass intentionnels (n'utilisent PAS l'override)
    ///
    /// Certains sites dans `LicenseSettingsView` lisent directement
    /// `status` ou `trialUsageCount` pour **ne PAS** être masqués par
    /// l'override — afin que les écrans trial restent testables en Debug :
    ///
    /// - `LicenseSettingsView.swift:96` — computed local `hasRealLicense`
    ///   (basé sur `status == .active || .offline`) pour décider
    ///   d'afficher le compteur trial. Sans ce bypass, l'override
    ///   masquerait toujours le compteur en Debug.
    /// - `LicenseSettingsView.swift:425, :429` — `trialUsageCount` et
    ///   `hasTrialRemaining` lus directement pour tester l'UI du trial.
    ///
    /// ## Limites
    ///
    /// L'override est **binaire** : `hasLicense=true` uniquement. Pour
    /// tester les autres états (`.unlicensed`, `.expired`, `.revoked`,
    /// `.disabled`, `.offline`, `.validating`), il faut aujourd'hui
    /// toucher à Polar ou au Keychain manuellement. Item backlog V2 —
    /// « Menu debug pour simuler états licence multiples » — pour un
    /// override paramétrable au runtime.
    var hasLicense: Bool {
        #if DEBUG
        switch debugLicenseOverride {
        case .licensed:                   return true
        case .trialActive, .trialExpired: return false
        }
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
        #if DEBUG
        // Override « trial épuisé » non destructif : force l'épuisement
        // sans écrire dans le Keychain (réversible en re-sélectionnant un
        // autre état). Les autres cas retombent sur le compteur réel.
        if debugLicenseOverride == .trialExpired { return false }
        #endif
        return trialUsageCount < Self.trialLimit
    }

    /// Source de vérité pour `runAction` : peut-il lancer une action LLM ?
    /// `true` si licence active OU trial encore disponible.
    var canRunAction: Bool {
        hasLicense || hasTrialRemaining
    }

    /// L'`activation_id` du device courant (depuis le Keychain). `nil`
    /// pour les utilisateurs non licenciés ou pré-Session-3 sans cet
    /// id en cache. Permet à l'UI (Réglages → Licence, section « Mes
    /// appareils ») de marquer la ligne correspondante comme
    /// `(cet appareil)` et d'aiguiller le bouton « Désactiver » vers
    /// la modale de confirmation appropriée.
    var currentActivationId: String? {
        KeychainService.License.activationId
    }

    private init() {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: Self.debugOverrideKey),
           let state = DebugLicenseState(rawValue: raw) {
            debugLicenseOverride = state
        }
        #endif
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
            KeychainService.License.licenseKeyId = result.licenseKeyId
            KeychainService.License.lastKnownStatus = result.licenseKey.status.rawValue
            KeychainService.License.lastValidatedAt = Date()
            KeychainService.License.customerEmail = result.licenseKey.customer?.email

            // Update state
            updateStateFrom(licenseKey: result.licenseKey)

            // Rafraîchit la liste des activations en background : elle
            // vient de gagner cette nouvelle entrée, l'UI veut le X/Y à
            // jour dès que possible. Non-await pour ne pas bloquer le
            // retour de activate() sur ce 2e round-trip Polar.
            Task { await refreshActivations() }
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
            KeychainService.License.licenseKeyId = result.id

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

    /// Désactive une activation **arbitraire** (typiquement un autre
    /// appareil que celui-ci) chez Polar. Ne touche PAS au Keychain
    /// local — la licence reste active sur cet appareil, seul le slot
    /// distant est libéré.
    ///
    /// Utilisé par :
    /// - `LicenseSettingsView` : section « Mes appareils » → bouton
    ///   « Désactiver » sur une ligne autre que le device courant
    ///   (ex. ancien Mac vendu/perdu, déconnexion à distance).
    /// - `ActivationLimitModal` : libération d'un slot avant retry du
    ///   `/activate` qui a renvoyé 403 `activationLimitReached`.
    ///
    /// Pour désactiver **cet appareil**, utiliser `deactivate()` (sans
    /// arg) qui wipe également le Keychain et reset l'état local.
    ///
    /// Throws sur erreur API. Sur succès, déclenche
    /// `refreshActivations()` pour mettre à jour le compteur X/Y et
    /// la liste affichée dans les Réglages.
    func deactivate(activationId: String) async throws {
        guard let key = KeychainService.License.key else {
            // Pas de clé locale = on ne peut pas appeler /deactivate.
            // Cas anormal : l'UI ne devrait pas exposer cette option
            // si la licence n'est pas active. Throw pour signaler
            // l'incohérence (visible dans `lastError` côté caller).
            let error = LicenseError.invalidKey
            lastError = error
            throw error
        }
        do {
            try await LicenseService.shared.deactivate(key: key, activationId: activationId)
            await refreshActivations()
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

    #if DEBUG
    /// Debug : remet le compteur de trial réel à 0 (mémoire + Keychain).
    /// Permet de rejouer les transitions « depuis 0 » en `.trialActive`.
    /// Orthogonal à `debugLicenseOverride` (qui simule l'état brut).
    func debugResetTrialUsage() {
        trialUsageCount = 0
        KeychainService.License.trialUsageCount = 0
    }
    #endif

    /// Récupère la liste détaillée des activations chez Polar et met à
    /// jour `activationsUsed` (compteur X) et `activations[]`. Silent
    /// fail en cas d'erreur réseau ou Polar — la limite Y reste
    /// affichée seule en fallback dans l'UI, et la licence reste
    /// fonctionnelle.
    ///
    /// Migration utilisateurs pré-Session-3 : leur `licenseKeyId` n'a
    /// pas été persisté lors de leur activation initiale (ce code
    /// n'existait pas). Si on a une `key` mais pas de `licenseKeyId`,
    /// on déclenche un `validate()` pour le capturer avant de fetcher.
    /// Coûte un round-trip Polar de plus au premier launch post-update,
    /// gratuit ensuite (`licenseKeyId` persisté en Keychain).
    ///
    /// Le fallback de migration ne se déclenche pas à tort : `wipe()`
    /// (KeychainService.swift) supprime systématiquement `key` ET
    /// `licenseKeyId` ensemble. Donc `(licenseKeyId == nil && key != nil)`
    /// ne peut se produire que sur migration pré-Session-3 ou rollback
    /// partiel inattendu.
    ///
    /// `validate(silent:)` est non-throwing : ses erreurs sont
    /// matérialisées via `status` / `lastError` en interne, donc pas
    /// besoin de `try?` autour de l'appel ici.
    ///
    /// À appeler depuis `LicenseSettingsView.task` (au montage) et
    /// après chaque mutation de la liste d'activations (activate
    /// succeeded — déjà branché ; futur cross-device deactivate du
    /// commit 3).
    func refreshActivations() async {
        if KeychainService.License.licenseKeyId == nil
            && KeychainService.License.key != nil {
            await validate(silent: true)
        }

        guard let id = KeychainService.License.licenseKeyId else { return }

        do {
            let result = try await LicenseService.shared.getLicenseKey(id: id)
            if let acts = result.activations {
                activations = acts
                activationsUsed = acts.count
            }
        } catch {
            // Silent fail. Status / hasLicense restent inchangés — la
            // licence est toujours valide, on n'a juste pas la liste à
            // afficher. UI affichera la limite seule en fallback.
        }
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
        activationsUsed = nil
        activations = []
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
