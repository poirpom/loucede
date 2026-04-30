# Backlog V2 — loucedé

Idées de fonctionnalités, polish et corrections à creuser **après la
release V1** (= phases 6.2 + 6.3 + 7 terminées + mise en vente publique).
Pas de code à écrire pour ces items tant que la V1 n'est pas shippée et
stabilisée.

## Conventions

- **Origine** : d'où vient l'item — Phase X reverted/différée, TODO dans
  le code, scope V1 explicitement exclu, observation d'usage, etc.
- **Statut** : 🌱 *À creuser* | 🌿 *Cadré* | 🌳 *Prêt à coder*
- Détail technique inclus uniquement quand l'item est déjà cadré.

## Sommaire

1. [Architecture / dette technique](#architecture--dette-technique)
2. [UX Réglages](#ux-réglages)
3. [UX Popup](#ux-popup)
4. [UX Onboarding](#ux-onboarding)
5. [Modèles IA](#modèles-ia)
6. [Fonctionnalités hors scope V1](#fonctionnalités-hors-scope-v1)
7. [Contenu (prompts, modèles)](#contenu-prompts-modèles)
8. [Modèle économique](#modèle-économique)
9. [Internationalisation](#internationalisation)

---

## Architecture / dette technique

### `LicenseManager` → `ObservableObject` + `@Published`

**Origine** : Phase 6.16 (stub créé en attendant Phase 6.2)
**Statut** : 🌿 Cadré

Aujourd'hui `LicenseManager` est un stub avec `hasLicense: Bool`
toujours `true`. Quand Phase 6.2 sera implémentée, la classe doit
conformer à `ObservableObject` avec `@Published var hasLicense: Bool`
pour que les vues react automatiquement aux changements (achat,
expiration, désactivation).

Le code consommateur (`AboutView` button disabled state, futurs autres
license-gated) devra alors observer via `@StateObject` ou
`@ObservedObject` au lieu d'accéder via `LicenseManager.shared.hasLicense`
en propriété figée.

### `UsageTracker` → `ObservableObject` injecté plutôt que singleton

**Origine** : Phase 7 (singleton choisi pour V1 par simplicité)
**Statut** : 🌱 À creuser

`UsageTracker.shared` est un singleton `@MainActor` — cohérent avec
`LicenseManager.shared` mais contraire à l'architecture SwiftUI
recommandée (injection d'environment). Migrer vers `ObservableObject`
injecté via `.environmentObject(UsageTracker())` au niveau `AppDelegate`
ou `ContentView` pour l'aligner avec `LicenseManager` quand ce dernier
sera lui-même refactorisé (voir item ci-dessus).

### Cleanup `appTheme` / `savedColorScheme`

**Origine** : résidu de Phase 6.7b (passage en dark-only)
**Statut** : 🌱 À creuser

Code mort résiduel : le picker Apparence a été retiré mais des bouts
de code observateurs ou clés `UserDefaults` orphelins peuvent
subsister. Audit + suppression. Pas urgent (n'impacte pas l'usage),
juste de l'hygiène.

### `MenuBarMenuView.swift` ligne 23

**Origine** : commentaire dans le code
**Statut** : 🌱 À creuser

Commentaire « À nettoyer plus tard si on veut retirer la prop côté
sous-vues ». Refactor mineur de propagation de prop devenue inutile.

### Cleanup clés `UserDefaults` orphelines

**Origine** : Phases 2.7, 6.7b, 3.4 — clés laissées dans les `defaults`
des utilisateurs migrés
**Statut** : 🌱 À creuser

Clés à nettoyer pour les installs existants :
- `loucede_migration_seed_27_done` (Phase 2.7 retirée)
- `appTheme` (Phase 6.7b dark-only)
- `loucede_shortcut_keys` (Phase 3.4)
- `loucede_license_key` (legacy TexTab, supprimé en Phase 7 — 2026-04-29)
- `loucede_is_license_valid` (legacy TexTab, supprimé en Phase 7 — 2026-04-29)

Aucune ne casse quoi que ce soit aujourd'hui — c'est juste de
l'hygiène. Une migration one-shot de cleanup pourrait `removeObject`
ces clés au prochain démarrage post-update, en posant un nouveau flag
`loucede_migration_cleanup_done`.

### Warnings « Publishing changes from within view updates »

**Origine** : observation console pendant streaming + transitions de
fenêtre
**Statut** : 🌿 Cadré

Visibles en boucle dans la console pendant le streaming + transitions
F (agrandir/réduire). Pas un crash (mitigation Phase 6.14-fix +
6.14-fix-2 en place), mais polluent les logs.

À nettoyer en déférant les mutations critiques de `@Published` via
`DispatchQueue.main.async` ou `Task.yield()`. En particulier :
- `state.resultText += chunk` dans `flushPendingChunks`
- `state.isProcessing = false` à la fin du streamTask

### Remplacer Zapier par un appel direct Notion via le proxy Scaleway

**Origine** : Phase 6.16 — `SuggestionService` POST sur webhook Zapier.
Suggestion utilisateur 2026-04-27 : éliminer la dépendance externe.
**Statut** : 🌿 Cadré

Aujourd'hui `SuggestionService.sendSuggestion()` POST sur
`https://hooks.zapier.com/hooks/catch/...` qui forward vers une base
Notion via un Zap configuré côté admin.

**Inconvénients du setup actuel :**
- Dépendance externe Zapier (3e service à maintenir, en plus de Polar
  et Scaleway).
- Tier gratuit Zapier limité (100 tasks/mois) — risque de blocage
  silencieux si l'app est utilisée à grande échelle.
- Configuration côté Zapier opaque (pas dans le repo, peut casser
  sans préavis).
- URL webhook publique → spam potentiel mitigeable mais pas idéal.

**Proposition : tout centraliser au proxy Scaleway.** Nouvel endpoint
`POST /suggest` qui :
1. Reçoit le payload loucedé (email, suggestion, version, build,
   platform, locale, submittedAt) — header `X-Loucede-App-Key` déjà
   géré par le proxy.
2. Appelle l'API Notion directement
   (`POST https://api.notion.com/v1/pages` avec
   `parent.database_id`) pour créer une page dans la database
   « Suggestions loucedé ».

**Travail technique :**
- **Côté Notion :** créer une integration interne, partager la
  database des suggestions avec, copier le token (`secret_xxx`).
- **Côté Scaleway :** ajouter env vars `NOTION_TOKEN` +
  `NOTION_DATABASE_ID` (en mode Secret). Étendre `handler.js` pour
  router `POST /suggest` vers `api.notion.com/v1/pages` avec
  `Authorization: Bearer NOTION_TOKEN` + `Notion-Version: 2022-06-28`.
  Mapper chaque champ du payload sur les properties de la database
  (Title, Email, Version, Platform, etc.).
- **Côté Swift :** modifier `SuggestionService.sendSuggestion()` pour
  POST sur `<proxy>/suggest` au lieu du webhook Zapier — l'auth est
  déjà géré (même header `X-Loucede-App-Key`).
- **Cleanup :** retirer la constante `webhookURL` Zapier de
  `SuggestionService.swift`. Désactiver le Zap côté Zapier (ou le
  garder en backup quelques semaines avant suppression).

**Bénéfices :**
- Zéro dépendance externe au-delà de Polar (Scaleway gère déjà tout).
- Free tier Scaleway largement suffisant (1M invocations/mois).
- Tout centralisé : un seul endroit où regarder pour l'auth et le
  routing du proxy (`handler.js` versionné).
- Plus robuste : pas de risque d'oublier de mettre à jour le Zap si
  on ajoute un champ au payload.

**À grouper avec le redéploiement Scaleway** prévu pour :
- Phase 6.2 Étape 6 (checkout WKWebView, peut nécessiter une route
  proxy si on doit relayer Polar checkout webhook)
- Compteur activations X/Y (`GET /license-keys/{id}`)

Un seul redéploiement pour les 3 ajouts → réduit le risque de
régression et la friction.

---

## UX Réglages

### Drag-and-drop pour réordonner les actions

**Origine** : Phase 6.11c — **reverted** (commit `d03a9c2`)
**Statut** : 🌿 Cadré

La tentative initiale (`List` SwiftUI natif + `.onMove`) n'a pas
fonctionné en pratique : les gestes drag étaient absorbés par le
`ScrollView` parent, l'`.onMove` ne se déclenchait jamais. Reverted.

À reprendre en **approche B** : `.onDrag` / `.onDrop` manuels avec
`NSItemProvider` sur le `VStack` actuel. Plus de code à écrire mais
préserve le visuel exact et permet un contrôle fin des zones
droppables (filled vs empty slots, blocage du drag depuis un slot
vide, etc.).

L'archi Phase 6.8d-bis garantit que le réordonnancement actualise
automatiquement les raccourcis ⌘+touche (position détermine raccourci
via `ActionsStore.shortcut(forPosition:)`).

### Filtrage contextuel des actions par application (per-app context)

**Origine** : suggestion utilisateur 2026-04-26
**Statut** : 🌿 Cadré

Lorsque loucedé est déclenché (raccourci global ⌃⌥W), détecter
l'application active via `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`,
puis filtrer la liste des actions affichées dans le popup pour ne
montrer que celles pertinentes pour cette application.

Cas d'usage typiques :
- Sélection d'un bout de code dans Xcode → seulement les actions
  « Coding » pertinentes apparaissent (Explique le code, Optimise,
  Ajoute des commentaires)
- Sélection dans Mail → actions « Email reply », « Tonalité formelle »,
  « Résume ce mail » prioritaires
- Sélection dans un blog culinaire (Safari) → action « Extrais la
  recette »

**Approche retenue : tags optionnels par action**

- Chaque action peut se voir attribuer une **liste optionnelle**
  d'applications cibles (bundle identifiers)
- Si une action n'a **aucun** tag app → elle s'affiche **toujours**
  (comportement par défaut actuel, rétrocompat préservée)
- Si une action a **un ou plusieurs** tags app → elle ne s'affiche
  que si l'app active correspond
- L'utilisateur peut gérer ces tags depuis le panneau
  **Réglages → Actions** (ajout d'une UI dédiée dans l'éditeur
  d'action)

**Points techniques à anticiper**

- Détection via `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`
- Non bloquant, aucun impact sur les performances (lookup local instant)
- Aucune permission supplémentaire requise (Accessibility API déjà
  en place pour la capture de texte sélectionné)
- Prévoir la migration des actions existantes : aucun tag par défaut
  → comportement inchangé pour les utilisateurs qui upgradent
- Stockage : nouveau champ `targetBundleIDs: [String]?` sur `Action`,
  `Codable` rétrocompatible (`decodeIfPresent`), pas de migration JSON
- UX éditeur : possibilité d'ajouter une app via picker (`NSOpenPanel`
  filtré sur `.application`) qui résout le bundle ID automatiquement,
  OU saisie manuelle pour les power-users
- Édition : présenter les tags comme des chips/pills avec suppression
  rapide (X au survol)
- Affichage popup : le filtre est invisible — l'utilisateur voit
  juste la liste pertinente ; éventuellement un toggle « Afficher
  tout » ou un raccourci (par ex. ⌘⇧A) pour bypass le filtre
  ponctuellement

### Statut opérationnel du provider dans Réglages → Général

**Origine** : suggestion utilisateur 2026-04-29
**Statut** : 🌿 Cadré

Afficher un indicateur visuel (cercle vert/orange/rouge) du statut
opérationnel du provider sélectionné, sur la ligne « Fournisseur IA »
de l'onglet Général. Récupération async au chargement de l'onglet.

**Sources (format Atlassian Statuspage identique pour les trois) :**
- Anthropic : `https://status.anthropic.com/api/v2/status.json`
- OpenAI : `https://status.openai.com/api/v2/status.json`
- Mistral : `https://mistralai.statuspage.io/api/v2/status.json`

**Format de réponse commun :**
```json
{ "status": { "indicator": "none" | "minor" | "major" | "critical" } }
```

**Mapping indicateur → couleur :**
- `"none"` → ● vert (opérationnel)
- `"minor"` → ● orange (dégradé)
- `"major"` / `"critical"` → ● rouge (incident)

**Implémentation pressentie :**
- `ProviderStatusChecker` (class ou struct async) : méthode
  `fetchStatus(for: AIProvider) async -> ProviderStatus` avec enum
  `ProviderStatus { case operational, degraded, incident, unknown }`.
  URL switchée selon le provider, décodage `Codable` minimaliste sur
  `indicator`.
- Déclenchement dans `GeneralSettingsView.onAppear` pour le provider
  actuellement sélectionné + `.onChange(of: selectedProvider)` pour
  mise à jour à la volée.
- UI : petit `Circle` coloré (6-8 pt) à droite du logo provider,
  avant le Picker. État `unknown` = gris (pas encore chargé ou réseau
  indisponible). Pas d'état persisté — rafraîchi à chaque ouverture
  de l'onglet.
- Optionnel : tooltip `.help("Anthropic : opérationnel")` au survol
  du cercle pour les daltoniens.

**Avantages :** une seule implémentation pour les trois providers
(même format JSON Atlassian), pas d'auth requise, endpoints publics
et stables.

### Audit accessibilité visuelle complet

**Origine** : ex-Phase 7.1 — peut être avant ou après release selon
priorité
**Statut** : 🌱 À creuser

Passe finale sur **toute** l'UI (popup, liste, résultat, réglages,
onboarding) :
- Contrastes : ratios AA/AAA dans les deux modes (clair + sombre) —
  vérifier `#2E2E2E`, `#1B1C1C`, `#3F84F7`, textes secondaires et leurs
  équivalents clair
- Tailles de texte : lisibilité minimum, cohérence footers / labels /
  boutons
- Focus visible clavier partout (navigation ↑↓, Tab dans réglages)
- Test avec « Augmenter le contraste » macOS activé
- Test avec Dynamic Type / taille police système augmentée

### ~~Pictogrammes colorés du menu Général à uniformiser~~ ❌ ANNULÉ (2026-04-29)

Tâche annulée — doublon avec Phase 7.0a déjà marquée annulée dans plan.md.

### Layout « label ferré à droite / control ferré à gauche » dans Réglages

**Origine** : observation usage 2026-04-27 — densité UI actuelle à
évaluer post-V1
**Statut** : 🌱 À creuser

Explorer le style macOS natif où chaque ligne d'un panneau de réglages
est composée de deux colonnes alignées sur une colonne médiane :
- **À gauche** : le label de la propriété, ferré à droite (aligné à
  droite contre la colonne médiane)
- **À droite** : le control (Picker, TextField, Toggle, …), ferré à
  gauche

Exemples macOS de référence : Keynote / Pages / Numbers (panneaux
Format, Document), Mail (Préférences → Comptes, Règles), Réglages
Système macOS (presque tous les panneaux), Notes, etc.

Effet visuel attendu : densification + lisibilité (l'œil scanne plus
vite une colonne de labels alignés à droite + une colonne de controls
alignés à gauche que des lignes mises en page librement).

Périmètre potentiel :
- `GeneralSettingsView` (Configuration API, Préférences, Autorisations)
- `LicenseSettingsView` (lignes infoRow déjà alignées label/value)
- `ActionEditorView` (header + raccourci + zone prompt)

Travail technique :
- Refactor potentiel via `LabeledContent` SwiftUI natif
  (`LabeledContent("Fournisseur IA") { Picker(...) }`) qui produit
  exactement ce layout, ou via un wrapper custom + `alignmentGuide`
  pour contrôle fin de la colonne médiane.
- Peut s'envisager comme un design system maison
  (`SettingsRow(label:) { ... }`) appliqué progressivement à toutes
  les vues.

À évaluer post-V1 selon le ressenti utilisateur sur la densité de
l'UI actuelle. Pas urgent : si l'UI actuelle est jugée bien, on
n'investit pas le temps de refactorer.

---

## UX Popup

### Bande noire transitoire à la réduction de la fenêtre résultat

**Origine** : Phase 6.14-fix-2 — trade-off accepté pour fermer le
crash AppKit
**Statut** : 🌿 Cadré

En mode F→F (réduction), pendant les 250ms d'animation NSWindow, le
`ScrollView` est déjà à `maxHeight=300` mais la window est encore
plus grande → fine bande noire (`#1B1C1C`) visible en bas pendant la
transition.

Améliorable via :
- Synchronisation propre des animations via `CATransaction`
- Ou animation SwiftUI déférée (lancer le `withAnimation` *après* la
  fin de l'animation NSWindow, pas en parallèle)
- Ou interpoler manuellement le `maxHeight` via une closure
  `NSAnimationContext.completion`

Cosmétique, pas bloquant — le crash était la priorité, c'est résolu.

---

## UX Onboarding

### Écran raccourci — clavier animé avec glow sur les touches

**Origine** : asset `keyboard.imageset` conservé intentionnellement (photo clavier Mac standard)
**Statut** : 🌿 Cadré

Utiliser `keyboard.imageset` comme fond de l'écran raccourci dans l'onboarding.
Animer un glow (halo lumineux) sur les touches correspondant au raccourci par défaut
⌃⌥W. L'animation bascule dynamiquement si l'utilisateur a changé son raccourci
(lire `ActionsStore.mainShortcutModifiers` + `mainShortcut` pour positionner le glow
sur les bonnes touches).

Techniquement : overlay SwiftUI avec `Canvas` ou `ZStack` de cercles floutés positionnés
en coordonnées fixes selon la touche (mapping position physique → coordonnée image).

### Écran post-raccourci animé

**Origine** : ex-Phase 7.0e
**Statut** : 🌱 À creuser

3 vagues animées successives du raccourci choisi en gras, sous-titre
plus petit : « (Si tu ne devais retenir qu'une seule chose
aujourd'hui) ». À insérer après l'écran de capture du raccourci
(`ShortcutStep`) et avant `LaunchAtLoginStep` ou `ActivationStep`.

Polish narratif, renforce la mémorisation du raccourci par
l'utilisateur.

### Liens providers — design plus engageant sous le champ clé API

**Origine** : Phase 7.3 — V1 = liste texte serrée (logo + label + flèche,
hover flat), fonctionnelle mais minimaliste
**Statut** : 🌱 À creuser

Affiner le design de la section "Pas encore de clé ?" dans `APIKeyStep`.
La V1 est lisible et non-intrusive, mais pourrait être plus engageante :
cards avec couleur brand légère par provider, illustration ou micro-animation
au survol, ou encore un layout accordéon (section repliée par défaut,
expand au clic).

À évaluer en fonction du feedback utilisateur sur l'onboarding post-V1.

### Visibilité du raccourci clavier sur l'écran Raccourci — bandeau de droite

**Origine** : Phase 7.3 — V1 = `[⌘] ou [⌥] + [W]` + mention bonus `[^]`/`[⇧]`, fonctionnel et pédagogique
**Statut** : 🌱 À creuser

Affiner le bandeau droit de `ShortcutStep` pour le rendre plus engageant visuellement.
La V1 est correcte (hiérarchie claire, cycling animation sur ⌘/⌥, ligne bonus en fond),
mais la zone droite peut être plus impactante : plus grande illustration clavier,
micro-animation sur les touches du raccourci actif, ou mise en scène narrative
(« voilà ce que tu viens de configurer »).

À évaluer avec les retours utilisateurs sur l'onboarding post-V1.

### Padding écran « Comment ça marche » — espacements globaux

**Origine** : Phase 7.3 — V1 = padding-top contenu à 32pt, correct mais densité à affiner
**Statut** : 🌱 À creuser

L'écran `FeaturesStep` a été ajusté à 32pt entre le titre et les 4 lignes de features.
L'ensemble peut encore respirer davantage : espacement inter-lignes, marge bottom
avant les boutons, ou refonte en layout centré pleine hauteur.

À réévaluer post-V1 si des retours signalent une impression d'étroitesse.

---

## Modèles IA

### ~~Ajouter Claude Haiku 4.5+ aux modèles disponibles~~ ✅ TERMINÉ (2026-04-29, commit 092bfd3)

`claude-haiku-4-5-20251001` ajouté à `AIModel.allModels` avec specs speed 5 / intelligence 3 / tokenUsage 5 (convention inversée SpecsBar).

### Audit régulier des IDs de modèles

**Origine** : note `project_loucede.md` (bugs à investiguer)
**Statut** : 🌱 À creuser

Vérifier périodiquement la validité de `gpt-4o`, `gpt-4o-mini`,
`gpt-4-turbo`, `o1-mini` chez OpenAI et `mistral-*-latest` chez
Mistral. Les alias `-latest` se mettent normalement à jour seuls,
mais à confirmer.

Le système de vérif live (Phase 4.3) couvre une partie du problème
(retire de la liste les IDs qui ne sont plus servis), mais n'avertit
pas que de **nouveaux** modèles existent. Une revue manuelle tous les
3-6 mois reste nécessaire.

---

## Fonctionnalités hors scope V1

### URL scheme `loucede://` pour automation

**Origine** : `project_loucede.md` — mentionné mais non implémenté
**Statut** : 🌿 Cadré

Permettre l'invocation depuis Raccourcis.app, Alfred, Raycast (par
exemple `loucede://action?id=traduire-fr&text=…`).

Ouvre l'app à des workflows automatisés sans passer par le raccourci
clavier global. Utile pour les power-users qui veulent intégrer
loucedé à leur stack productive.

À caler en Phase 7 release ou post-V1 selon priorité.

### Analyse multimodale (images)

**Origine** : V1 scope explicitement exclu (`project_loucede.md`)
**Statut** : 🌱 À creuser

Permettrait par exemple de capturer une image et lui appliquer une
action « Décris cette image », « Extrais le texte » (OCR via LLM),
« Identifie ce produit ».

Demande :
- Extension du modèle `Action` (champ acceptant les inputs image)
- Capture d'image système (presse-papier image existant + screenshot
  via Cmd+Shift+4 ?)
- Provider qui supporte multimodal (GPT-4o, Claude Sonnet 4, Gemini)

### Trigger sur sélection de fichier dans Finder

**Origine** : V1 scope exclu (`project_loucede.md`)
**Statut** : 🌱 À creuser

Permettrait de sélectionner un `.txt` / `.md` / `.json` dans Finder,
déclencher loucedé, et obtenir une action sur le contenu du fichier
plutôt que sur le texte sélectionné.

Demande :
- Observation des sélections Finder via Accessibility API ou
  AppleScript bridge
- Lecture du contenu du fichier sélectionné
- Limite de taille (les actions LLM restent borné par le contexte
  modèle)

### Prompts spécifiques par type de fichier

**Origine** : V1 scope exclu — lié au point précédent
**Statut** : 🌱 À creuser

Par exemple « Améliore le code » uniquement quand un `.swift` est
sélectionné, « Convertis CSV en Markdown » sur un `.csv`, etc.

Cohérent avec le filtrage contextuel par bundle ID, mais sur la
dimension *type de contenu* plutôt que *app source*.

---

## Contenu (prompts, modèles)

### Catalogue de prompts étendu

**Origine** : todo « Catalogue de prompts (futur) » mentionné en
session
**Statut** : 🌱 À creuser

Création de nouveaux modèles de prompts au-delà des 17 actuels
(Phase 6.12). Nouvelles catégories possibles : juridique, médical,
marketing, éducation, jeu vidéo, etc.

Le travail éditorial est en cours côté utilisateur. À intégrer au seed
quand les nouveaux prompts seront finalisés et testés.

### Migration push de nouveaux prompts du seed

**Origine** : observation du mécanisme actuel
**Statut** : 🌱 À creuser

Aujourd'hui les nouveaux prompts du seed (Phase 6.9c) sont migrés en
mode « doux » : remplacés seulement si non-modifiés par l'utilisateur.

Pour pousser des mises à jour aux installs existants même quand le
prompt a été édité, prévoir un mécanisme de notification : « Une
nouvelle version améliorée du prompt X est disponible (changelog : ...).
Tu veux la voir / la garder ? ».

UI possible : badge sur l'action concernée + diff visuel à
l'ouverture.

### Onglet Modèles i18n 3 langues

**Origine** : `plan.md` — questions d'architecture à trancher
**Statut** : 🌱 À creuser (dépendance i18n)

Descriptions et noms des modèles localisés (`AIModel.allModels`
actuellement hard-codés en FR dans `OpenAIService.swift`). À
structurer en clés `String(localized:)` quand le String Catalog
sera en place.

Dépend de la mise en place du String Catalog (cf.
[Internationalisation](#internationalisation)).

---

## Modèle économique

### 8a — Promus V1 (voir plan.md — Session 3 Phase 7)

> Ces 3 items ont été promus du backlog V2 vers le plan V1 le 2026-04-29.
> Ils seront traités en Session 3 Phase 7 avant la release 1.0.

### Mode debug / licence developer

**Origine** : besoin admin (toi) — accès permanent aux features
license-gated sans avoir à acheter ta propre licence
**Statut** : 🌿 Cadré

Pour conserver l'accès aux fonctionnalités license-gated (envoi de
suggestion, futures features) sur tous les environnements de dev sans
acheter une licence.

Approches pressenties :
- **A. Flag `#if DEBUG`** : `LicenseManager.hasLicense` retourne `true`
  systématiquement en builds Debug. Simple, pas de leak en Release.
- **B. Clé spéciale dans `UserDefaults`** : par exemple
  `loucede_dev_license = true`. À activer manuellement via Terminal
  (`defaults write app.loucede.loucede loucede_dev_license -bool YES`).
  Plus discret qu'un flag compile-time.
- **C. Combinaison** : flag DEBUG + override clé manuelle pour les
  builds Release de test interne.

Vote : **A pour V1**, peut évoluer vers C si besoin de tester en
Release sans perturber le flow utilisateur.

### Mécanisme de réactivation après changement de Mac

**Origine** : usage prévu — utilisateur change de Mac, comment
récupérer sa licence ?
**Statut** : 🌿 Cadré

Creem.io supporte le device activation tracking, mais l'UX côté
utilisateur doit être pensée :

- Bouton « Désactiver sur cet appareil » dans Réglages → Licence (V1)
- Email automatique avec un lien magique de réactivation sur le
  nouveau Mac (« Clique ici pour activer loucedé sur ce nouveau Mac »)
- Limite raisonnable : 3-5 activations cumulées avant friction
  (contact support)

À designer une fois Phase 6.2 implémentée.

### Compteur exact d'activations utilisées (« X / Y appareils »)

**Origine** : Phase 6.2 polish — feedback utilisateur 2026-04-27
**Statut** : 🌿 Cadré

Aujourd'hui l'écran Réglages → Licence affiche « Limite d'appareils : 3 »
(la limite max). On voudrait afficher « 1 / 3 » (utilisations actuelles
vs limite) pour que l'utilisateur sache combien d'emplacements lui
restent.

**Pourquoi pas en V1 :** la réponse de `POST /license-keys/activate` et
`POST /license-keys/validate` de Polar **ne contient pas** le compteur
d'activations actuelles, juste `limit_activations` (la limite max).
Pour avoir le ratio précis, il faut un appel séparé
`GET /v1/license-keys/{id}` qui retourne `LicenseKeyWithActivations`
(avec liste détaillée).

**Travail technique :**
- Nouvelle route `GET /license-keys/{id}` dans le proxy Scaleway
  qui forward avec auth Bearer (organization_id côté serveur).
  Ajouter dans le `handler.js` Node.js.
- Re-déploiement Scaleway (token déjà OK, pas de nouveau scope
  requis — `license_keys:read` couvre).
- Nouvelle méthode `LicenseService.getLicenseKey(id: String)` côté Swift.
- Nouveau `@Published private(set) var activationsUsed: Int?` dans
  `LicenseManager`.
- Auto-fetch après `activate()` et `validate()` réussis (le
  `licenseKey.id` est dispo dans la réponse).
- UI : remplacer `infoRow("Limite d'appareils", "3")` par
  `infoRow("Appareils activés", "1 / 3")`.

**À grouper avec :** le checkout WKWebView (Étape 6 Phase 6.2) qui
touchera aussi le proxy → un seul redéploiement Scaleway pour les
deux ajouts.

### 8b — V1.1 (backlog post-release)

> Ces 2 items restent en backlog. Ils seront reprochés après la release 1.0
> quand la base utilisateurs sera suffisante pour en valider l'utilité.

### Liste « Membres de la tcheam » dans Réglages → Licence

**Origine** : suggestion utilisateur 2026-04-27 — suite logique du
heroName (sobriquet généré au moment de l'activation, ressenti
communautaire)
**Statut** : 🌱 À creuser

Sous le bouton « Désactiver cet appareil » dans l'écran licence
active, ajouter un bouton « Membres de la tcheam » qui ouvre un
popover (ou sheet) listant tous les heroNames de tous les
utilisateurs licenciés actifs de loucedé.

UX cible :
- Popover scrollable avec liste de heroNames (ex. « Shadow Falcon »,
  « Iron Phoenix », …)
- Tri alphabétique ou par date d'activation
- Compteur en haut : « 47 membres »

**À définir : source de données.** 3 options possibles :

- **A. Polar customer metadata** — Suppose que la propagation
  `heroName → customer.metadata` soit déjà implémentée (cf. entrée
  backlog plus haut). Lecture via `GET /v1/customers?metadata.heroName=*`
  ou itération + filtre. Contrainte : Polar n'a pas forcément un
  endpoint « lister tous les customers » ouvert au public côté client
  — à creuser.
- **B. Endpoint custom sur le proxy Scaleway** — Le proxy maintient
  une liste agrégée (ex. en KV store ou dans une simple base SQLite)
  alimentée par chaque activation. Affichage simple et rapide.
- **C. Source externe (Notion, Airtable, Google Sheet)** — Côté admin
  on importe les heroNames dans une base lisible publiquement
  (read-only) que loucedé interroge. Découplé du flow Polar.

**Pré-requis :** la propagation `heroName → customer.metadata Polar`
(autre entrée du backlog) doit être en place avant de pouvoir
implémenter A. Pour B ou C, on peut commencer indépendamment.

**Pourquoi pas en V1 :** complexité serveur + question privacy à
trancher (les utilisateurs OK pour qu'on affiche leur sobriquet
publiquement ? probablement oui car non-PII, mais à confirmer dans
les CGU). À reprendre quand la base utilisateur sera assez grande
pour rendre la liste intéressante.

### Propager le heroName en metadata Polar customer

**Origine** : Phase 6.2 polish — heroName généré localement, mais
non synchronisé côté Polar pour exploitation newsletter
**Statut** : 🌿 Cadré

Le « sobriquet super-héros » généré via `LicenseManager.generateHeroName()`
est stocké en Keychain local (Phase 6.2). Pour pouvoir l'exploiter
côté serveur (newsletter personnalisée, support, segmentation), il
faut le propager en metadata du customer Polar via :

```
PATCH https://api.polar.sh/v1/customers/{customer_id}
Body: { "metadata": { "heroName": "Shadow Falcon" } }
```

**Travail technique :**
- Nouveau endpoint dans le proxy Scaleway : `POST /customer-metadata`
  qui forward vers `PATCH /v1/customers/{id}` avec auth Bearer
  (organization_id côté serveur). Ajouter dans le `handler.js` Node.js.
- Re-déploiement Scaleway (variable `POLAR_TOKEN` déjà en place,
  scope `customers:write` à vérifier).
- Nouvelle méthode `LicenseService.updateCustomerMetadata(customerId:metadata:)`
  côté Swift.
- Auto-trigger après `generateHeroName()` réussi : appeler le proxy
  avec `customer.id` (déjà dispo dans la réponse Polar `/activate`
  et `/validate`).
- Gérer l'échec gracieusement : si la propagation fail, le heroName
  reste local — on n'échoue pas la génération entière.

**Pourquoi pas en V1 :** ajoute un endpoint serveur + un re-déploiement
Scaleway pour un nice-to-have. La newsletter / segmentation n'est pas
en place côté admin pour l'instant. À implémenter quand le besoin
serveur sera concret.

---

## Internationalisation

### String Catalog `.xcstrings`

**Origine** : ex-Phase 5.1 — reportée explicitement post-V1
**Statut** : 🌿 Cadré

Migrer toutes les chaînes hard-codées vers un catalogue unique. Langue
source FR, locales additionnelles à activer.

**Conditionnel à un signal utilisateur non-FR** (demande explicite ou
adoption internationale détectée). Sans ce signal, on reste mono-FR
indéfiniment.

Travail technique :
- Activer un catalog unique
- Remplacer partout `"texte"` par `String(localized: "Clé")`
- Langue source : français, locale `fr` ajoutée, autres vides au
  départ

### Sélecteur de langue dans Réglages

**Origine** : ex-Phase 5.2 — dépend du Catalog ci-dessus
**Statut** : 🌱 À creuser (dépendance)

Picker `Locale` dans l'onglet Général + `.environment(\.locale, …)`
sur la racine SwiftUI. Approche moderne, pas de redémarrage de l'app
nécessaire pour la bascule.

Dépend du Catalog (5.1) qui doit fournir au moins 2 langues pour
qu'un sélecteur ait du sens.
