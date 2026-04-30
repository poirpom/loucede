---
name: Plan de fork loucedé
description: Plan de référence des 7 phases du fork TexTab → loucedé, à utiliser pour tous les récaps et arbitrages
type: project
originSessionId: 782f9a83-a3ee-4daa-bf06-2d4377a84636
---
**Contexte :** Fork TexTab (~32 fichiers Swift, ~5-6k lignes) → loucedé. Plan validé en Phase 0 de la conversation. Les récaps s'alignent sur cette structure de phases.

## Phase 0 — Préparation
- Renommer projet Xcode `typo` → `loucede`, target, scheme, bundle ID (`moises.typo` → `app.loucede.loucede`)
- Nouveau repo GitHub GPL v3, retirer remote origin TexTab
- Supprimer : `AuthManager.swift`, `LoginRequiredView.swift`, `PaywallView.swift`, `supabase/`, `Secrets.swift`
- Retirer dépendance SPM Lottie + `LottieView.swift`, `AnimatedCatLogo.swift`
- Retirer plugins : `PluginsView.swift`, `PluginProcessor.swift`, `IconPickerView.swift`, enum `PluginType`
- Décision : garder `UpdateChecker.swift` (pointera vers GitHub Releases futures)
- Nettoyer `Info.plist` : retirer `textab://`, `NSAllowsArbitraryLoads`, polices Nunito

## Phase 1 — Fondations & performance — ✅ TERMINÉE (2026-04-23)
### 1.1 Popup préchargée (exigence critique) — ✅ FAIT
- Créer `popoverWindow` **une fois** dans `applicationDidFinishLaunching`
- `PopoverState: ObservableObject` partagé avec `reset()` avant chaque show
- Flux showPopover : capture texte → `reset()` → repositionner → `makeKeyAndOrderFront + NSApp.activate`
- Objectif : coût d'ouverture quasi-zéro

### 1.2 Positionnement près du texte sélectionné — ❌ ANNULÉ (2026-04-22)
- Décision utilisateur : garder la fenêtre centrée sur l'écran du curseur. Ainsi elle apparaît toujours au même endroit, prédictible.
- L'implémentation Accessibility API (`AXUIElementCopyAttributeValue`) n'est donc pas nécessaire.

### 1.3 Polish UX post-tests — ✅ FAIT
- ✅ Navigation ↑↓ + ↵ dans liste prompts
- ✅ `⮐` coller / `⌘⮐` copier depuis résultat
- ✅ Badges raccourcis à côté des boutons
- ✅ Toasts "Copié ✓" / "Collé ✓"
- ❌ 1.3d Esc depuis résultat → retour liste : **ANNULÉE** (2026-04-23) — comportement actuel (Esc ferme le popup) jugé satisfaisant par l'utilisateur, cohérent avec l'indication de pied de fenêtre « esc Fermer »

## Phase 2 — Système de prompts refondu — ✅ TERMINÉE (commits b12d68d, 288afd8, 7cfca2d, 168f974, d280173)
### 2.1 Modèle enrichi — ✅ FAIT
- Décision utilisateur : **pas d'emoji**, les pictos SF Symbols actuels (champ `icon` configurable) suffisent.
- Le seul ajout retenu par rapport au modèle `Action` existant est `slotIndex: Int?` (position 0-9 pour keycodes 18-29).
- Renommage `Action` → `Prompt` : à garder (cohérence FR + isolé du fork TexTab), mais c'est cosmétique.
```swift
// Cible (ajout uniquement du champ slotIndex)
struct Prompt: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String        // ex. "Traduis en français"
    var icon: String        // SF Symbol, déjà présent et configurable
    var prompt: String      // le prompt système complet (nom de champ actuel)
    var slotIndex: Int?     // 0-9 (touches &é"'(§è!çà) ou nil pour "libre"
}
```

### 2.2 Store local unique — ✅ FAIT
- Décision utilisateur : `ActionsStore` conservé (pas de renommage), UserDefaults clé `loucede_actions`
- CRUD + seed 5 prompts FR par défaut + migration silencieuse du seed legacy

### 2.3 Sélection par keycode physique (AZERTY/QWERTY compat) — ✅ FAIT
- `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` pendant que popup est key window
- Mapping keyCodes physiques 18-29 → slots 0-9

### 2.4 Export/Import JSON — ✅ FAIT
- `NSSavePanel`/`NSOpenPanel` → sérialisation `[Action]`
- Envelope schéma `loucede-actions-v1`, stratégie `replace`/`append`

## Phase 3 — Raccourci global configurable — ✅ TERMINÉE (2026-04-23, commit 8cfb006)
### 3.1 ShortcutRecorderView — ✅ FAIT
- `GeneralSettingsView.startRecordingMainShortcut` : `NSEvent.addLocalMonitorForEvents([.keyDown, .flagsChanged])` capture combo en direct
- Stocke `(mainShortcutModifiers: [String], mainShortcut: String, mainShortcutKeyCode: UInt16)` — conversion Unicode → Carbon via computed `mainCarbonModifiers`
- Affichage Unicode : ⌃⌥W

### 3.2 Persistence — ✅ FAIT
- 3 clés UserDefaults : `loucede_main_shortcut`, `loucede_main_shortcut_modifiers`, `loucede_main_shortcut_keycode`
- Défaut retenu : **⌃⌥W** (keycode 6, compat AZERTY/QWERTY)
- `ActionsStore.saveMainShortcut()` persiste les 3

### 3.3 Réenregistrement dynamique — ✅ FAIT
- Publisher Combine `ActionsStore.$mainShortcut` avec debounce 500 ms dans `loucedeApp` → `UnregisterEventHotKey` + `RegisterEventHotKey`
- Un seul `hotKeyRef` principal (signature Carbon `0x4C434544` "LCED")

### 3.4 Connexion onboarding ShortcutStep → ActionsStore — ✅ FAIT (2026-04-23, commit 8cfb006)
- Bug corrigé : `ShortcutStep.swift` écrivait dans la clé orpheline `loucede_shortcut_keys` jamais lue ailleurs
- Branché sur `ActionsStore.shared` (source unique) : lecture via computed, écriture des 3 champs (modifiers, lettre, keyCode) + `saveMainShortcut()`
- Le publisher Combine ré-enregistre le hotkey automatiquement après capture onboarding

## Phase 4 — Intégration providers LLM — ✅ TERMINÉE (2026-04-23, commit f425514)
### 4.1 Simplification OpenAIService.swift — ✅ FAIT
- ✅ OpenAI + Anthropic + Mistral uniquement (OpenRouter/Perplexity/Groq déjà retirés à l'origine)
- ✅ **4.1a Clés API UserDefaults → Keychain** (commit 1b87f37, `KeychainService.swift`, migration silencieuse, service `app.loucede.loucede.apikey`)
- ✅ Architecture SSE streaming conservée (deux implémentations claires : `streamOpenAICompatibleChat`, `streamAnthropicChat`)

### 4.2 Réglages "IA & API" — ✅ FAIT
- Picker provider → champ sécurisé clé → Picker modèle dépendant : tout en place (`GeneralSettingsView`)

### 4.3 Vérif live des modèles — ✅ FAIT (commit 2ac80d3, étendu à Anthropic par f425514)
- `AIService.listAvailableModelIds(provider:apiKey:)` via `GET /v1/models` (OpenAI + Mistral + **Anthropic** depuis f425514)
- `ActionsStore.verifyAvailableModels(for:)` async, déclenchée à l'ouverture Réglages et au changement de provider
- Auto-heal du modèle persisté s'il n'est plus servi
- Fallback vers liste hard-codée si pas de clé, échec réseau ou intersection vide
- Headers conditionnés par provider : `Authorization: Bearer` (OpenAI/Mistral) vs `x-api-key` + `anthropic-version: 2023-06-01` (Anthropic)

### 4.4 Fonction « Améliorer » (PromptImprover) — ✅ FAIT (commit f425514)
- Bouton ✨ dans l'éditeur d'action (`ActionsView.swift`), appel LLM pour développer une idée basique en prompt détaillé
- Méta-prompt système + wrapper user message traduits EN→FR, exemples adaptés (formel, drôle + un EN pour vérifier la règle « conserve la langue de l'utilisateur »)
- Module isolé (`PromptImprover` classe, ~100 lignes), désactivé si clé API vide
- Support des 3 providers avec branchement `if provider == .anthropic` pour endpoint/headers/shape de réponse

## Phase 5 — Interface française & i18n — ✅ TERMINÉE en opt.A (2026-04-24, commit c98e7f8)

**Décision V1 : Option A — FR hardcodé.** loucedé reste mono-langue FR. Option B (String Catalog) et Option C (picker de langue EN/FR) reportées au backlog post-V1 tant qu'aucun signal utilisateur non-FR n'émerge.

### 5.0 Traductions FR hardcodées — ✅ TERMINÉE
- ✅ 5.0a Boutons onboarding (commit d280173)
- ✅ 5.0b Menu Actions : "New Action" / "Delete" / "Saved" (commit d280173)
- ✅ 5.0c Dernière salve 13 chaînes (commit c98e7f8) — QuickPromptView (Prompt rapide / Écris ton prompt… / fermer / exécuter), TemplatesView (Modèles de prompts / Clique pour ajouter aux Actions / Tous), PermissionsStep (Accès accordé ! / En attente d'accès), ActionsView (Déjà utilisé / Utilisé par / Enregistrement… / Appuie sur ⌘ ou ⌥ + touche), ShortcutStep (ex.)

### 5.1 String Catalog (.xcstrings) — 📦 BACKLOG POST-V1
- Activer un catalog unique
- Partout `String(localized: "Clé")` au lieu de littéraux
- Langue source : français, locale `fr` ajoutée, autres vides
- **Conditionnel à un signal utilisateur non-FR** (demande explicite ou adoption internationale)

### 5.2 Sélecteur de langue — 📦 BACKLOG POST-V1
- Réglages → Picker Locale
- `.environment(\.locale, …)` sur racine SwiftUI (approche moderne, pas redémarrage)
- Dépend de 5.1 (nécessite un catalog avec au moins 2 langues)

## Phase 6 — Ajouts
### 6.1 Bouton "Envoyer par mail" — ❌ ANNULÉE (2026-04-24)
- Abandonnée suite à révision du scope Phase 6. La popup loucedé reste focalisée sur copier/coller/retour ; l'envoi par mail sort du cœur d'usage « IA au bout de tes doigts ».

### 6.2 Système de licence (V1 inactif, V2 ready)
- Module isolé : `enum LicenseStatus { case personal, trial(remaining: Int), licensed(key: String), expired }`
- `LicenseManager: ObservableObject`, V1 toujours `.personal`
- Vue Réglages "🔑 Licence" : "Version personnelle — utilisations illimitées"
- V2 : `#if COMMERCIAL` → `.trial(12)` + UI achat
- Stockage : clé licence Keychain, compteur UserDefaults

### 6.3 Onglet "Mises à jour" auto-refresh
- Onglet Réglages affichant le log / historique des mises à jour (via `UpdateChecker`)
- Auto-rafraîchissement à l'ouverture de l'onglet (pas de bouton manuel requis)
- Décision à prendre : format (changelog brut depuis GitHub Releases ? locale ?)
- **Indicateur popup** : quand une mise à jour est disponible, afficher une ligne `🆕 Mise à jour disponible` dans la popup principale, **au-dessus du bouton Réglages** (sous la liste d'actions, avant le settings row). Ligne cliquable qui ouvre les Réglages directement sur l'onglet **Mises à jour** (deeplink interne via `SettingsView` selectedTab). Visible uniquement si `UpdateChecker` détecte une release plus récente que la version courante. Disparait après update ou si l'utilisateur ferme manuellement (à arbitrer)

## Phase 7 — Nettoyage & release
- Vérifier entitlements (retirer OAuth callback, inter-process). Garder ce qui est nécessaire à Accessibility API
- Mettre à jour `Info.plist` : `CFBundleName`, catégorie, version, explication permission Accessibility
- Garder `NSApp.setActivationPolicy(.accessory)`
- Refaire onboarding minimal : bienvenue → permission Accessibilité → raccourci → clé API → terminé
- Icônes + assets : branding loucedé
- README.md FR, GPL v3 conservée, CONTRIBUTING.md adapté
- **Note architecture** : `TemplatesView.swift` est **conservé** — c'est l'onglet `case 2:` du TabView des Réglages (cf. `SettingsView.swift:67`), pas un fichier orphelin. Toute mention "orphelin" dans un résumé de session antérieur est **incorrecte** et à ignorer

### 7.2 Onboarding clé API — champ unique avec auto-détection du fournisseur
- **Champ unique de saisie**, quel que soit le fournisseur. L'utilisateur n'a **pas** à choisir son fournisseur manuellement — loucedé le détecte automatiquement au collage/saisie selon le préfixe :
  - `sk-ant-…` → Anthropic
  - `sk-…` → OpenAI
  - autre pattern → Mistral (à confirmer / fallback)
- Une fois détecté, configure automatiquement `provider` côté `ActionsStore` + stocke la clé dans Keychain (service `app.loucede.loucede.apikey`)
- Feedback visuel : badge/label « Détecté : OpenAI » sous le champ après collage
- Cas d'erreur : préfixe inconnu → message « Format de clé non reconnu » + lien vers les fournisseurs supportés

### 7.3 Onboarding clé API — liens vers les fournisseurs sur le même écran
- Sur le **même écran** que la saisie de clé API, inclure les liens permettant d'aller créer une clé chez chaque fournisseur supporté
- **Réutiliser tels quels** les liens déjà présents dans Réglages → Général (cf. `GeneralSettingsView`, Phase 6.11a — `Link` SwiftUI cliquables avec scheme `https://`)
- Liens : `console.mistral.ai/api-keys`, `platform.openai.com/api-keys`, `console.anthropic.com/settings/keys` (à vérifier au moment de l'implémentation)
- Disposition à arbitrer pendant l'implémentation (ligne sous le champ ? bloc dépliable ? trois boutons-pills ?)

### 7.1 Audit accessibilité visuelle (avant release)
- Passe finale sur **toute** l'UI (popup, liste, résultat, réglages, onboarding)
- Contrastes : vérifier ratios AA/AAA dans les deux modes (clair + sombre), couleurs sombre actuelles `#2E2E2E`, `#1B1C1C`, `#3E65B5` + leurs équivalents clair + textes
- Tailles de texte : lisibilité minimum, cohérence entre footers / labels / boutons
- Focus visible clavier partout (navigation ↑↓, Tab dans réglages)
- Test avec "Augmenter le contraste" macOS activé
- Test avec Dynamic Type / taille police système augmentée si pertinent

### Phase 7 — État restant (~85 %)

| Session | Bloc | Contenu | Statut |
|---------|------|---------|--------|
| Session 3 | **8a — Modèle économique V1** | Mode debug `#if DEBUG` · Mécanisme réactivation Mac · Compteur activations X/Y (proxy Scaleway) | 🔴 BLOQUANT |
| Session 4 | **7.1 — Audit accessibilité** | Contrastes AA/AAA clair + sombre · Focus clavier · Dynamic Type | 🟠 RECOMMANDÉ |
| Session 5 | **Release 1.0** | Bump 0.9.0 → 1.0 · Notarisation · DMG · GitHub Release | 🔴 BLOQUANT |

## Ajouts hors plan initial (confirmés par project_loucede.md)
- **Mistral** comme 3e provider (plan mentionnait OpenAI + Anthropic)
- **URL scheme `loucede://`** pour automation (Raccourcis, Alfred, Raycast) — à caler dans Phase 7 release ou section dédiée
- **Multi-modèles Anthropic à maintenir** (Claude 3.5 retirés, défaut `claude-sonnet-4-20250514`) + vérif même pattern pour OpenAI/Mistral

---

## Backlog étendu — 2026-04-22 (session soirée, tests réels)

### Phase 1 follow-up — UI polish popup

| # | Tâche | Détail |
|---|---|---|
| 1.4a | ✅ Toasts plus grands (+200 %) | Toast, texte, picto : augmenter toutes les dimensions / font-sizes. `ConfirmationToast` dans PopoverView.swift |
| 1.4b | ✅ Touche `F` agrandit la fenêtre résultat | Largeur 500 px (ajustée, 400→500) + hauteur 70 % visibleFrame (15 % marge haut/bas). Animation 0.25 s easeInOut synchronisée NSWindow (NSAnimationContext) + SwiftUI (withAnimation). Indicateur footer `F Agrandir` / `F Réduire` entre Coller et Retour. Reset auto au retour liste / réouverture popup |
| 1.4c | ❌ ANNULÉE — taille des boutons Copier / Coller / Retour | Décision utilisateur : taille actuelle jugée bonne après test visuel |
| 1.4d | ✅ Pictos SF retirés + KeyboardKey avant libellé sur Copier / Coller / Retour | Cohérence d'ordre avec le footer nav de la liste ; pattern unifié `KeyboardKey → Text` |
| 1.4e | ✅ Augmenter légèrement la taille du texte des indications de navigation | Bas de la liste d'actions (↑↓ Naviguer, ↵ Valider, esc Fermer) |
| 1.4f | ✅ Cohérence indications pied liste vs pied résultat | Acquise via 1.4d (KeyboardKey → Text unifié) + 1.4e (13pt des deux côtés) + boutons .plain |
| 1.4g | ✅ Champ de recherche dans la liste d'actions | Bandeau toujours visible avec placeholder « Rechercher » + curseur clignotant (cadence 0.53 s). Frappe libre alimente la recherche (filter case-insensitive sur nom). Backspace / Esc via monitor NSEvent (SwiftUI `.onKeyPress(.delete/.escape)` peu fiable). Slots passés en `⌘+chiffre` (Option B) pour libérer les chiffres nus au profit de la recherche. Badges popup + Picker Settings en `⌘1`…`⌘0`. Slots déjà pris grisés/désactivés dans le menu Settings |
| 1.4h | ✅ Couleur de fond de la popup : `#2E2E2E` | Fenêtre popup principale — palette sombre unifiée |
| 1.4i | ✅ Couleur de fond zone basse (liste + résultat) : `#1B1C1C` | Distinguer la zone d'actions/résultat du chrome supérieur |
| 1.4j | ✅ Couleur barre de sélection dans la liste d'actions (popup) : `#3F84F7` | Remplacer `Color.accentColor.opacity(0.25)` sur la ligne sélectionnée dans `PopoverView.actionRow` |

### Phase 1.5 — Polish fenêtre Réglages (nouveau bucket)

| # | Tâche | Détail |
|---|---|---|
| 1.5a | ✅ Ouvrir Réglages sur l'onglet "Général" par défaut | Actuellement ouvre sur "Prompts". Modifier la sélection initiale du `TabView` |
| 1.5b | ✅ Renommer l'onglet "Prompts" → "Actions" | Cohérence avec le reste du vocabulaire (`ActionsStore`, "Actions"…) |
| 1.5d | ✅ Texte des items de la liste d'actions en **gras** | Renforcer la lisibilité / hiérarchie visuelle (liste côté Réglages, `ActionListRow`) |

### Phase 2 tweak — seed de prompts par défaut

| # | Tâche | Détail |
|---|---|---|
| 2.5 | Mettre à jour la prompt "Traduis en emoji" | Nouveau texte : « Traduis le texte suivant en une séquence d'emojis. Veille à respecter la structure des phrases et du texte, en incluant la ponctuation. Réponds uniquement avec les emojis, sans texte, sans explication. » |
| 2.6a | ✅ Ajouté au seed "Commente ce post LinkedIn" (commit b42e29b) | Slot 5, icon `bubble.left`. Prompt sarcasme poli. Migration one-shot renomme « Réponds à ce post LinkedIn » → « Commente ce post LinkedIn » pour les configs existantes |
| 2.6b | ✅ Ajouté au seed "Extrais la recette" (commit b42e29b) | Slot 6, icon `fork.knife`. Prompt recette FR + système métrique + structuration Markdown. Migration one-shot ajoute l'action sur premier slot libre si absente. Flag `loucede_migration_seed_26_done` |
| 2.7 | ❌ RETIRÉE en Phase 6.7 (2026-04-24) | Ajoutée au seed le 2026-04-23 (slot 7, 💡, pédagogue chaleureux) puis **retirée du seed** en Phase 6.7 suite au feedback utilisateur (action jugée redondante avec les prompts perso que chacun se construira). Code supprimé : entrée `defaultActions`, `migrateSeed27IfNeeded()`, constante `explainPrompt`. La clé UserDefaults `loucede_migration_seed_27_done` reste orpheline (un commentaire la documente dans Models.swift) — aucune migration destructive sur les users qui avaient déjà l'action à jour, ils la gardent dans leur liste locale |

### Phase 6 anticipée — UX pictogrammes d'actions — ✅ TERMINÉE (2026-04-23, commit 4f810bd)

| # | Tâche | Détail |
|---|---|---|
| 6.4 | ✅ SF Symbols → emojis | Mapping seed : 🇫🇷, 🇬🇧, 😀, ✍️, 🤏, 💬, 🍳. Extension `String.isEmojiOnly` (heuristique Unicode). `ActionIconView` composant d'affichage réutilisable (boîte fixe, fallback `Circle` gris pour SF legacy). `EmojiPickerView` remplace la grille 192 SF : TextField auto-focalisé + bouton `NSApp.orderFrontCharacterPalette`. Migration one-shot `migrateIconsToEmojiIfNeeded()` via table `sfToEmojiMapping`. Flag `loucede_migration_icons_emoji_done` |
| 6.4-alt | ❌ NON RETENUE | Alternative "catégories SF Symbols" abandonnée au profit de l'option B emojis (décision 2026-04-23) |

### Phase 6 anticipée — Rendu Markdown dans la fenêtre de résultat

| # | Tâche | Détail |
|---|---|---|
| 6.6 | ✅ Rendu Markdown via MarkdownUI (2026-04-23) | Remplacement `Text(state.resultText)` → `Markdown(state.resultText)` dans `PopoverView.swift:428`. Dépendance SPM `gonzalezreal/swift-markdown-ui` (MIT, compat GPL v3). Supporte titres (`#`/`##`), gras, italique, code inline, blocs de code, listes à puces/numérotées, citations, liens. Taille texte alignée sur le reste de la popup via `.markdownTextStyle(\.text) { FontSize(13) }`. Bouton « Copier » continue de coller le Markdown brut (préservation de la mise en forme pour Notion/Obsidian/VSCode). Motivé par les actions 2.6b « Extrais la recette » et 2.7 « Expliquer » qui produisent du Markdown structuré |

### Phase 6.7 — Correctifs UI/UX (2026-04-24) — ✅ TERMINÉE

Bundle de 5 correctifs suite à feedback utilisateur après premiers usages réels. Objectif : finir de nettoyer ce qui restait bancal avant d'attaquer les Phases 5 / 6.5 / 7.

| # | Tâche | Détail |
|---|---|---|
| 6.7a | ✅ Seed cleanup : retirer 3 actions des défauts | Supprimé du seed `defaultActions` (Models.swift) : « Traduis en anglais » (ancien slot 1), « Commente ce post LinkedIn » (ancien slot 5), « Expliquer » (ancien slot 7). Renumérotation des slots restants : 0=Traduis FR, 1=Traduis emoji, 2=Corrige fautes, 3=Résume, 4=Extrais recette. Suppression du code devenu mort : `migrateSeed27IfNeeded()` et `explainPrompt`. Pas de migration destructive sur les installs existants — les users qui avaient déjà ces actions les gardent |
| 6.7b | ✅ loucedé dark-only (commit 6dcf323) | **3 tentatives infructueuses** d'adaptation clair/sombre (d2561d5, 463d513, bc28728) : `@Environment(\.colorScheme)` puis `.preferredColorScheme()` puis `NSApp.appearance` + KVO — aucune ne propage correctement dans l'empilement NSPanel borderless + nonactivatingPanel hébergeant NSHostingView. **Décision utilisateur** : « loucedé sera sombre — point ». Bascule définitive : `NSApp.appearance = NSAppearance(named: .darkAqua)` dès `applicationDidFinishLaunching`, picker Apparence retiré des Réglages, enum `AppTheme` + `@AppStorage("appTheme")` + observateurs KVO supprimés. Couleurs `#2E2E2E` / `#1B1C1C` / `#3F84F7` à nouveau hardcodées, `Color.primary` conservé (rend blanc en dark-only). 215 lignes supprimées, 30 ajoutées sur 4 fichiers (loucedeApp.swift, GeneralSettingsView.swift, PopoverView.swift, MenuBarMenuView.swift) |
| 6.7c | ✅ Message erreur clé API absente | Remplacement dans `OpenAIService.swift` (3 occurrences, un par provider OpenAI/Anthropic/Mistral) : `[Mode démo] Clé API non configurée. Ouvrez les Réglages pour ajouter votre clé.` → `Aucune clé API renseignée. Rendez-vous dans les réglages (dans la barre de menus) pour arranger ça :)` |
| 6.7d | ✅ Bouton « Réglages » dans la liste popup | Ligne fixe sous la liste d'actions (après Divider), toujours visible — pas scrollée avec la liste. Icône engrenage `gearshape` + label « Réglages » + badge `⌘,`. Navigable ↑↓+↵ (index = `filteredActions.count`, dernier cran de navigation). Raccourci `⌘,` standard macOS géré dans le NSEvent monitor via `charactersIgnoringModifiers` (indépendant layout AZERTY/QWERTY). Cohérence visuelle : même padding / radius / fond bleu sélectionné que `actionRow` |
| 6.7e | ✅ Hauteur popup pour 10 actions + Réglages | `popoverDefaultHeight` porté de 500 à 540 px (AppDelegate), remplacement des `height: 500` en dur par référence à la constante (`positionPopoverCentered` ×2 + `createPopoverWindow`). ScrollView de la liste reste cappée à 360 px (10 rows), le settings row (~35 px) se loge sous la ScrollView. L'utilisateur voit ses 10 actions + Réglages d'un coup sans scroll même avec aperçu texte actif |

### Phase 6.8 — Polish Actions & Emoji picker (2026-04-25) — ✅ TERMINÉE

Bundle de 7 sous-phases identifiées en usage réel post-6.7. Trois sous-groupes : éditeur d'actions (3 + fix) + raccourcis position-based (1) + emoji picker (2) + crash streaming (1).

| # | Tâche | Détail |
|---|---|---|
| 6.8a | ✅ Élargir Réglages (commit 8da3976) | Largeur Réglages 700→800 px, sidebar Actions 220→280 px |
| 6.8b | ✅ Raccourci clavier dans liste actions Réglages (commit 8da3976) | `ActionListRow` affiche le badge ⌘+touche à droite du nom |
| 6.8c | ✅ Sauvegarde auto éditeur action (commit 43efbc7) | Bouton « Enregistrer » retiré. `.onChange` sur name/icon/prompt → `scheduleSave()` debouncé 300 ms. Hint « Sauvegarde auto » en footer |
| 6.8c-fix | ✅ Crash sauvegarde auto (commit a9f605c) | Le `Timer.scheduledTimer` initial firait pendant view update + `selectedAction = updatedAction` provoquait boucles re-render → crash. Fix : `DispatchQueue.main.asyncAfter` + `DispatchWorkItem` (cancellation propre, capture snapshot d'`action` au planning) |
| 6.8d | ❌ ANNULÉE — raccourci ⌘+caractère libre | Décision utilisateur : « trop de changements qui alourdissent et compliquent le projet ». Remplacée par 6.8d-bis |
| 6.8d-bis | ✅ Raccourcis position-based (commit 70b9706) | Cap dur à 15 actions. `ActionsStore.positionShortcuts` (10 chiffres + AZERT). Le raccourci d'une action = sa position dans `actions[]`. Sidebar Réglages = 15 slots fixes (occupés/vides). Éditeur : badge ⌘X readonly. Plus de SlotPicker manuel. Champ `slotIndex` conservé Codable mais non consulté |
| 6.8e | ✅ Modifier emoji existant (commit a1dad37) | Champ vide à l'ouverture du picker + emoji actuel en placeholder grisé. Évitait les concaténations « 🇫🇷🇬🇧 » sur édition |
| 6.8f | ✅ Clic rond gris → emoji picker natif ancré (commit ceefe04) | Auto-ouverture de `NSApp.orderFrontCharacterPalette` via `DispatchQueue.main.asyncAfter` 0.1s sur `.onAppear`. Bouton « Rouvrir le sélecteur d'emoji » comme repli (sera retiré en Phase 6.10) |
| 6.8g | ✅ Throttling streaming 60 Hz (commit e383784) | Crash AppKit pendant action LLM avec markdown structuré. Fix : `pendingChunkBuffer` + `flushTask` à 60 Hz au lieu de muter `resultText` à chaque chunk. Re-renders Markdown coalescés sur 1 frame |

### Phase 6.9 — Polish popup & seed prompts (2026-04-25) — ✅ TERMINÉE

| # | Tâche | Détail |
|---|---|---|
| 6.9a | ❌ ANNULÉE | Reliquat — accès aux Réglages déjà visible suffisamment depuis 6.7d |
| 6.9b | ✅ Hauteur popup dynamique (commit 51597bd) | Helper `calculatedPopoverHeight()` côté AppDelegate combine `actions.count` (cap 10 visibles) + `hasSelection`. Avec 5 actions sans selection : 296 pt vs 540 pt avant. Refactor `resizePopover(expanded:Bool)` → `resizePopover(to:PopoverMode)` avec `.list / .resultCompact / .resultExpanded`. Resize auto au passage liste↔résultat |
| 6.9c | ✅ Nouveaux prompts seed + migration douce (commit 37a1ff5) | Réécriture des 4 prompts historiques sur templates structurés (Rôle / Tâche / Procédure / Règles / Sortie). Seed final : Traduis FR 🇫🇷 / Résume 🤏 / Corrige fautes ✍️ / Extrais recette de cuisine 🍳 / Sois concis ✂️. « Traduis en emoji » sort du seed (préservé chez utilisateurs existants). Migration douce via `migrateSeed69cIfNeeded` : remplace les prompts non-modifiés (match BIT-EXACT), ajoute « Sois concis » si absente |

### Phase 6.10 — Simplification emoji picker (2026-04-25) — ✅ TERMINÉE (commit 305767a)

Suppression du popover custom au profit du picker emoji système macOS ancré directement sous l'emoji cliqué.

- `EmojiPickerView` (200 lignes) supprimé : titre + grosse preview + texte d'aide + bouton « Rouvrir »
- Nouveau `EmojiPickerButton` : ZStack avec `ActionIconView` + TextField invisible (`opacity 0.001`, `allowsHitTesting(false)`). Au tap, focus le TextField puis `NSApp.orderFrontCharacterPalette` — macOS ancre la palette sur le focus = sous l'emoji
- Filter passif : `isEmojiOnly` accepte les emojis (clavier, paste, picker), reste rejeté
- ActionEditorView : `@State showIconPicker` + bloc flottant supprimés
- Net : -59 lignes, UX nettement plus directe

### Phase 6.11 — Polish Réglages (2026-04-25) — ✅ a/b TERMINÉES, c REVERTED

| # | Tâche | Détail |
|---|---|---|
| 6.11a | ✅ Liens API cliquables (commit 5f42d32) | URL `console.mistral.ai/api-keys` etc. en `Link` SwiftUI cliquable. Scheme `https://` ajouté à la construction, affichage sans scheme. Curseur main natif au hover |
| 6.11b | ✅ Specs modèle inline (commits 146844e + 99b50cb) | Ancien popover au survol du Picker remplacé par `ModelSpecsCard` permanente. Carte intégrée dans VStack imbriqué sous les Pickers → hérite naturellement de la largeur cumulée Provider+Modèle. Pas de PreferenceKey, layout SwiftUI natif |
| 6.11c | ❌ Reverted (commit d03a9c2) | Drag-and-drop avec `List`+`.onMove` ne fonctionnait pas en pratique (gestes absorbés par ScrollView parent). Documenté en backlog V2 pour reprise en approche `.onDrag`/`.onDrop` manuels sur VStack |

### Phase 6.12 — Refonte des modèles de prompts (2026-04-25) — ✅ TERMINÉE (commits 46da469 + dac1627)

Remplacement complet des 25 modèles anglais coding-centriques par 17 modèles FR fournis par l'utilisateur (CSV éditorial).

- Catégories : Writing/Coding/Productivity/Creative/Analysis (EN) → **Traduire / Analyser / Transformer / Structurer / Proposer** (FR), ordre figé par déclaration `CaseIterable`
- `PromptSuggestion.icon` : SF Symbol → emoji (cohérent avec Phase 6.4 sur `Action.icon`)
- `TemplateCard` : `Image(systemName:)` → `Text(emoji)` taille 20 pt sur fond coloré 3D
- 17 modèles répartis : 3 Traduire (ES/PT/EN), 5 Analyser, 4 Transformer, 3 Structurer, 2 Proposer
- Polish suite (commit dac1627) : titres tronqués → `lineLimit(2)` + `.frame(minHeight: 130, alignment: .top)` pour uniformiser hauteur cards dans la grille (évite l'effet escalier entre colonnes)

### Phase 6.13 — Export Markdown en complément du JSON (2026-04-25) — ✅ TERMINÉE (commit 4503577)

Bouton « Exporter » devient menu déroulant avec 2 choix :
- **Sauvegarde JSON** (existant) — format ré-importable, schema `loucede-actions-v1`
- **Lecture Markdown** (nouveau) — non ré-importable, joliment formaté pour archivage / partage / lecture dans renderer Markdown

Format Markdown : titre H1 + métadonnées italique + section H2 par action + raccourci en gras + prompt en blockquote (`> `). Le blockquote préserve le rendu du Markdown contenu dans les prompts (titres, listes, gras) au lieu d'un bloc code monospace.

`ActionsStore.exportActionsMarkdown() -> Data?` produit le contenu, `exportActionsAsMarkdown()` côté UI gère le `NSSavePanel`.

### Phase 6.14 — Crash AppKit pendant streaming (2026-04-26) — ✅ FIXÉ via 6.14-fix + 6.14-fix-2

Crash `NSInternalInconsistencyException` : « The window has been marked as needing another Update Constraints in […] ». Reproduction : appui sur F (agrandir/réduire) pendant qu'une action LLM streame du markdown structuré.

| # | Tâche | Détail |
|---|---|---|
| 6.14 | ❌ Reverted | Mitigation initiale : `Text(state.resultText)` brut pendant le streaming, `Markdown(...)` à la fin (`isProcessing == false`). Insuffisante : le crash venait des transitions de fenêtre, pas du re-parse Markdown |
| 6.14-fix | ✅ Suspendre flush pendant transitions (commit f239210) | `PopoverState.suspendFlush()` / `resumeFlush()` autour des animations NSWindow (touche F, retour liste, lancement action). Le buffer `pendingChunkBuffer` continue à accumuler les chunks LLM, application différée à la fin de l'animation (300 ms). Aucun token perdu |
| 6.14-fix-2 | ✅ Retirer withAnimation sur resultExpanded (commit 761a330) | Race condition résiduelle : SwiftUI animait `frame(maxHeight: 300↔2000)` du ScrollView (~15 re-renders interpolés sur 250 ms) en parallèle de l'animation NSWindow. AppKit voyait deux passes de constraints chevauchantes → exception. Fix : set instantané de `resultExpanded`, seule la NSWindow s'anime côté AppKit. Trade-off : fine bande noire transitoire (`#1B1C1C`) en bas pendant la réduction (250 ms), accepté |

### Phase 6.15 — UX raccourcis vue résultat (2026-04-26) — ✅ TERMINÉE (commit 57e4964)

Trois changements liés sur la vue résultat du popup.

1. **Esc ferme partout** — Avant : Esc en vue résultat délégué à SwiftUI `.onKeyPress(.escape)` peu fiable, comportement imprévisible (parfois retour liste, parfois fermeture, parfois rien). Après : centralisé dans le NSEvent monitor (capture fiable des touches physiques). Convention macOS standard (Spotlight, Raycast, Alfred). Pour relancer une action sur le même texte : ⌃⌥W puis ⌘N (~1 seconde).
2. **Inversion ⌘⏎ ↔ ⏎** — `⏎` devient Copier (action par défaut, non-destructive, popup reste ouvert). `⌘⏎` devient Coller (action engagée, destructive, popup ferme). Logique sécurité : *the easier the action, the less destructive it should be*. Adaptée aux modèles 6.12 majoritairement consultatifs (Analyser, Proposer).
3. **Réarrangement boutons + renommage** — `[esc Fermer] [F Agrandir]` à gauche, `[⌘⏎ Coller] [⏎ Copier]` à droite. Convention macOS (action par défaut à droite, comme Save dialog). « Retour » → « Fermer » (cohérent avec nouveau comportement de Esc).

### Phase 6.16 — Bouton suggestion dans À propos (2026-04-26) — ✅ TERMINÉE (commit d44bc84)

Ajout d'un bouton license-gated qui ouvre une sheet de saisie pour envoyer une suggestion à un webhook Zapier (qui forward vers Notion admin).

- `LicenseManager.swift` (nouveau, **stub pour Phase 6.2**) : `hasLicense: Bool` retourne `true` actuellement, sera étendu en Phase 6.2 (`@Published` + Keychain Creem.io). License-gate effective branchée sur `LicenseManager.shared.hasLicense`
- `SuggestionService.swift` (nouveau) : POST JSON au webhook avec payload (email + suggestion + version + build + plateforme + locale + timestamp ISO). Erreur typée (`networkUnavailable / serverError(code) / encodingFailed / unknown`)
- `SuggestionFormView.swift` (nouveau) : sheet 480 pt avec validation client (email regex, suggestion 3-5000 chars), feedback (loading / toast « Merci pour la suggestion » / alert « L'envoi a foiré. Peut-être ça bug 🤷 »), `⌘↵` pour envoyer
- Bouton dans AboutView sous infos GitHub, disabled selon `hasLicense`. Tooltip explicite

Sécurité : URL webhook publique (repo GPL v3) → spam potentiel atténué par la license-gate effective en 6.2 + régénération URL côté Zapier si abus.

### Phase 6.17 — Icônes loucedé + cleanup TexTab (2026-04-27) — ✅ TERMINÉE (commit 816f980)

**Branding visuel :**
- `loucede.icns` (106 Ko) à la racine du repo, généré via `iconutil` depuis `loucede.iconset` (10 tailles : 16/32/128/256/512 en @1x + @2x). Source `documents-persos/logo-et-Icône/icone-loucede/logo-1024.png`. Utilisable pour DMG, preview Finder, doc
- `AppIcon.appiconset` : `logo textab.png` (1.4 Mo) supprimé, remplacé par 10 PNG individuels redimensionnés. `Contents.json` complet avec filenames explicites pour chaque scale/size. Xcode régénère son `AppIcon.icns` automatiquement à partir de ces PNG
- `MenuBarIcon.imageset` : SVG `MenuBarIcon.svg` supprimé, remplacé par `menubar.png` (18×18) + `menubar@2x.png` (36×36). `template-rendering-intent: template` conservé (teinte automatique macOS selon dark/light + état actif du menu)

**Cleanup résidus TexTab/typo :**
- 13 en-têtes Swift `//  typo` → `//  loucede` (les fichiers étaient hérités de TexTab dont le nom interne Xcode était `typo`)
- `loucedeApp.swift:2` : `//  typoApp.swift` → `//  loucedeApp.swift`
- `ChatView.swift:5` : « AI Chat interface for TexTab » → « AI Chat interface for loucede »
- Mention « Fork de TexTab par ELPROFUG0 » conservée volontairement dans `AboutView.swift:57` et `README.md:60` — obligation GPL v3 (mention de l'auteur original)

### Correctifs UI 2026-04-27 — ✅ TERMINÉS (commits 27579c8, 16c5250, 8dfb72f, 48c952a)

Lot de 4 correctifs visuels post-6.17 sur les Réglages, à la suite des premiers tests utilisateur après la finition du branding.

| # | Correctif | Détail |
|---|---|---|
| A | ✅ Retrait « Extrais les actions concrètes » du seed Modèles (commit 27579c8) | Redondant avec « Génère un plan d'actions » (catégorie Structurer). `promptSuggestions` passe de 17 à 16 entrées. Pas de migration : seul le seed des Modèles est touché, pas `defaultActions` |
| B | ✅ Emoji ✅ pour « Génère un plan d'actions » + migration douce (commit 16c5250) | `TemplatesView` icon "🗺️" → "✅". Migration `migratePlanActionsEmojiIfNeeded` matche `name + icon == 🗺️` pour ne pas écraser une personnalisation utilisateur. Flag `loucede_migration_plan_actions_emoji_done` |
| C | ✅ AppIcon réelle dans AboutView (commit 8dfb72f) | Remplacement de `Image(systemName: "sparkles")` par `Image(nsImage: NSApp.applicationIconImage)` 64×64pt. `import AppKit` ajouté. `.interpolation(.high)` pour downscale propre depuis l'icône source 1024×1024 |
| D | ✅ Onglets Réglages format pictogramme (commit 48c952a) | Refactor `TabTextButton` → `TabIconButton` (SF Symbol au-dessus + label en dessous, fond pillé corner radius 8 quand sélectionné). SF Symbols : `gearshape` / `square.and.pencil` / `wand.and.stars` / `info.circle`. Style macOS natif Settings |

### Phase 6.2 — Système de licence Polar.sh — ✅ TERMINÉE Étapes 1-5 + 7-9 (commit af9f6a1)

Système de licence end-to-end avec Polar.sh comme MoR (à la place de Creem initialement prévu). Architecture en 3 couches : proxy Scaleway Functions (Node.js 20, fr-par) qui garde POLAR_TOKEN + ORG_ID côté serveur, couche réseau Swift typée, et état + Keychain côté `LicenseManager` ObservableObject.

**Étapes implémentées :**

| # | Étape | Détail |
|---|---|---|
| 1 | ✅ `LicenseConfig.swift` | Constantes : proxyBaseURL Scaleway, appSecret partagé `X-Loucede-App-Key`, productCheckoutURL Polar. `assertConfigured()` filet de sécurité dev (check longueur secret + détection placeholder text) |
| 2 | ✅ `LicenseService.swift` | 3 méthodes async vers le proxy : `activate(key:label:)`, `validate(key:activationId:)`, `deactivate(key:activationId:)`. Erreur typée `LicenseError`. Modèles Codable typés (`PolarActivation`, `PolarValidatedLicenseKey`, `PolarLicenseStatus` enum forward-compat). Custom date decoder ISO8601 avec/sans fractions. URLSession isolation MainActor + formatters file-level pour Sendable closure |
| 3 | ✅ `KeychainService.License` namespace | Service Keychain dédié (`app.loucede.loucede.license`) séparé des clés API. Accessors type-safe : `key`, `activationId`, `trialUsageCount` (Int), `lastValidatedAt` (Date sérialisée timeIntervalSince1970), `lastKnownStatus`, `customerEmail`, `heroName`. `wipe(includingTrialCounter:)` pour deactivate (conserve trial counter par défaut) |
| 4 | ✅ `LicenseManager` refactor stub → ObservableObject | 7 status enum : `unlicensed/validating/active/revoked/disabled/expired/offline`. `@Published` pour status, trialUsageCount, customerEmail, activationsLimit, expiresAt, heroName, isGeneratingHeroName, lastError. `hasLicense` avec `#if DEBUG` qui retourne toujours `true` en dev. `canRunAction = hasLicense \|\| hasTrialRemaining`. Méthodes async `activate`, `validate`, `deactivate` + `incrementTrialUsage` + `generateHeroName` (LLM avec retry si pas d'espace). Logique offline 7 jours dans `validate()` |
| 5 | ✅ `LicenseSettingsView.swift` | Sous-vue dédiée par status. Active : sous-titre « Bienvenue dans la tcheam #loucedé » + heroName en 2 temps (bouton « Obtenir mon nom » → nom + ℹ️ avec popover) + email + limite d'appareils + bouton désactiver (avec alert confirmation). Offline : message rassurant + dernière vérif + bouton re-vérifier. Revoked/disabled/expired : message explicatif + formulaire pour activer une autre clé. Compteur trial (X / 12) toujours visible si pas de licence Polar réelle (utilise `status` direct, contourne `#if DEBUG`) |
| 6 | 📦 LicenseCheckoutView (WKWebView embarqué) — **EN ATTENTE** | À grouper avec le redéploiement Scaleway suivant (cf. backlog V2 — compteur activations X/Y, Notion direct, Membres tcheam). Pour l'instant : bouton « Acheter une licence » utilise `NSWorkspace.shared.open(LicenseConfig.productCheckoutURL)` qui ouvre le checkout dans Safari |
| 7 | ✅ 5e onglet « Licence » dans SettingsView | Inséré entre Modèles (index 2) et À propos (index 4 désormais). SF Symbol `key.fill`. Renumérotation des index |
| 8 | ✅ Validate au démarrage + cache offline | `Task { await LicenseManager.shared.validate(silent: true) }` dans `setupApp()` (loucedeApp.swift). `silent: true` évite le flicker `.active (cache) → .validating → .active` au démarrage. Cache offline 7 jours géré dans `validate()` : si réseau down + cache récent + lastKnownStatus granted → status `.offline` (counts as `hasLicense`) |
| 9 | ✅ Branchement runAction + modal trial épuisé | `PopoverState.runAction` : guard `LicenseManager.canRunAction` en début. Si false → `showTrialExpiredModal = true`, action non lancée. Snapshot `consumesTrial = !hasLicense` au lancement (pas affecté par activation en cours de stream). Incrément trial APRÈS stream réussi uniquement (pas brûler d'essai sur erreur réseau). Modal : overlay sur le popup (pas une sheet macOS séparée), wording « 😱 12 - 12 = 0 / Pour continuer à utiliser loucedé en douce, c'est 8€ 💸 » + boutons « Plus tard » / « Acheter ». Esc = Plus tard, Return = Acheter |

### Phase 6.18 — Logo loucedé dans la popup principale (2026-04-28) — ✅ TERMINÉE (commits b3d3f84, f3674f1, 935314c)

Trois itérations sur le placement du logo loucedé dans la popup principale (mainView), cliquable pour ouvrir les Réglages depuis n'importe quel contexte.

| # | Itération | Détail |
|---|---|---|
| 6.18 | ❌ Initial — placement zone basse (commit b3d3f84) | Logo en haut de la zone basse `#1B1C1C`, juste avant la search bar. Visuellement isolé, pas rattaché à un contexte. `popoverChromeHeight: 108 → 152` |
| 6.18-fix | ❌ Re-placement dans le preview (commit f3674f1) | Logo déplacé dans la zone preview (haute `#2E2E2E`), à droite du preview du texte capturé, sur la même ligne (`HStack(alignment: .top)`). Visible UNIQUEMENT si selection. `popoverChromeHeight: 152 → 108`, popoverPreviewHeight inchangé (le logo aligné top tient dans la hauteur du preview de 3 lignes max) |
| 6.18-fix-2 | ✅ Final — toujours visible (commit 935314c) | Top bar TOUJOURS visible (avec preview à gauche si selection, juste Spacer + logo à droite sinon). Le `Divider` après la top bar est toujours visible. `popoverChromeHeight: 108 → 161` (+53 = 28pt logo + 12+12 paddings + 1 divider). `popoverPreviewHeight: 67 (absolu) → 12 (delta)` — sémantique change : c'est désormais le surplus de hauteur ajouté quand selection présente, pas la hauteur absolue du preview |

**Specs visuelles finales :**
- Taille logo : 28×28 pt
- Border radius : 7pt en `.continuous` (squircle macOS Big Sur+)
- Ferrage horizontal : 12pt du bord droit (aligné sur les badges ⌘+touche des actionRows)
- `pointerCursor()` au survol + `.help("Ouvrir les Réglages")` pour le tooltip natif
- `Image(nsImage: NSApp.applicationIconImage)` — composite système avec masque squircle déjà appliqué

### Questions d'architecture à trancher (utilisateur)

- **Onglet Modèles** des réglages : liste actuellement hard-codée dans `OpenAIService.swift` (`AIModel.allModels`). Possibilité (V2) de la passer en i18n 3 langues via String Catalog. À décider : structure des catégories, nombre à afficher.
- ~~**Fonction Enhance**~~ : tranché 2026-04-23 — conservée et traduite en FR (commit f425514)
