# loucedé — CLAUDE.md

App macOS menu bar en Swift/SwiftUI. Fork de TexTab (GPL v3).
Interface en français. Suit le mode clair/sombre du système. Licence GPL v3.
Bundle ID : `app.loucede.loucede`

---

## Workflow

### Règle absolue
Propose toujours un plan avant de modifier du code.
Une session = une tâche = un commit. Ne pas enchaîner plusieurs tâches dans la même session.

### Correctifs
Session courte et ciblée. Préciser le fichier concerné dès le départ.
Commiter immédiatement après chaque correctif avant de passer à autre chose.

### Plan d'actions
Référencer le numéro de tâche en début de session (ex. "Phase 6.2").
Mettre à jour `docs/plan.md` à la fin de chaque session ou batch de commits.

---

## Architecture — fichiers clés

| Fichier | Rôle |
|---|---|
| `loucedeApp.swift` | Point d'entrée, hotkey Carbon, AppDelegate |
| `PopoverView.swift` | Fenêtre popup principale (liste + résultat) |
| `PopoverState.swift` | ObservableObject partagé, streaming, flush 60 Hz |
| `ActionsStore.swift` | CRUD actions, UserDefaults, export/import JSON+MD |
| `OpenAIService.swift` | Streaming SSE (OpenAI / Anthropic / Mistral) |
| `GeneralSettingsView.swift` | Réglages Général + raccourci configurable |
| `ActionEditorView.swift` | Éditeur d'action (titre, prompt, emoji) |
| `LicenseManager.swift` | Stub licence (hasLicense = true, à étendre Phase 6.2) |
| `SuggestionService.swift` | Envoi suggestions via webhook Zapier → Notion |
| `UpdateChecker.swift` | Vérification GitHub Releases |
| `KeychainService.swift` | Stockage clés API (service : `app.loucede.loucede.apikey`) |

---

## Conventions UI

- **Mode clair/sombre** — suit le système (forçage `darkAqua` retiré en commit 5ab993b)
- **Police** : SF Pro partout — aucune référence à Nunito
- **Couleurs** : popup `#2E2E2E` · zone inférieure `#1B1C1C` · sélection `#3F84F7`
- **Rendu Markdown** dans la fenêtre résultat (swift-markdown-ui) — throttling 60 Hz via `pendingChunkBuffer`
- **Icônes actions** : emojis (pas SF Symbols) depuis Phase 6.4
- **Catégories modèles de prompts** : Traduire / Analyser / Transformer / Structurer / Proposer (ordre figé)

---

## Conventions techniques

- Tout fichier Swift hors SwiftUI utilisant `ObservableObject` / `@Published` / `@ObservedObject` **doit importer `Combine` explicitement** (Foundation ne le ramène pas automatiquement).
- **Une session = une tâche = un commit.** Ne pas enchaîner plusieurs tâches dans la même session sans commit intermédiaire.

---

## État V1 — ce qui reste à faire

### Tâches actives (dans l'ordre)

- [ ] **Correctifs immédiats** (voir section Correctifs ci-dessous) — à traiter en priorité avant Phase 6.2
- [ ] **Phase 6.2** — Système de licence Creem.io (`LicenseManager` ObservableObject + Keychain + UI Réglages → Licence). Stub `LicenseManager.swift` déjà en place. Lire `creem-integration.md` avant de coder.
- [ ] **Phase 6.3** — Onglet « Mises à jour » auto-refresh dans Réglages (via `UpdateChecker`, GitHub Releases)
- [ ] **Phase 7** — Nettoyage & release (entitlements, Info.plist, onboarding, README.md FR, build + notarisation)

### Phases terminées — ne pas retoucher sans raison explicite
Phases 0 → 5, 6.1 (annulée), 6.4 → 6.17 : **toutes terminées**.
Voir `plan.md` pour le détail complet.

---

## Correctifs à appliquer (avant Phase 6.2)

- [ ] **Supprimer le modèle d'action « Extrais les actions concrètes »** — redondant avec « Génère un plan d'actions », résultat moins pertinent aux tests
- [ ] **Remplacer l'emoji du modèle « Génère un plan d'actions »** par ✅. Propager le changement aux actions utilisateurs qui utilisent ce modèle (migration douce)
- [ ] **Onglet « À propos »** — remplacer les étincelles SF Symbol par le logo loucedé (fichier fourni par l'utilisateur au moment du prompt)
- [ ] **Menubar icon** — mettre à jour avec les nouveaux fichiers `menubar.png` / `menubar@2x.png` fournis (padding réduit, logo plus grand). Fichiers fournis par l'utilisateur.
- [ ] **Onglets Réglages** — remplacer les intitulés texte seul par le format `pictogramme + titre` (cohérent macOS). Exemple : `⚙️ Général`, `📝 Actions`, `🤖 Modèles`, `ℹ️ À propos`

---

## Hors scope V1 — ne pas implémenter

Tout item du `backlog.md` est hors scope V1, notamment :
- i18n / String Catalog / sélecteur de langue
- Filtrage contextuel par app (per-app context)
- Trigger Finder sur sélection de fichier
- Analyse multimodale (images)
- URL scheme `loucede://`
- Drag-and-drop réordonnancement actions
- Audit accessibilité complet

---

## Bugs connus

- Warnings « Publishing changes from within view updates » en console pendant streaming — non-bloquant, mitigation Phase 6.14 en place, fix propre prévu en V2
- Bande noire transitoire (~250 ms) lors de la réduction de la fenêtre résultat (touche F) — trade-off accepté (Phase 6.14-fix-2)
- Clés UserDefaults orphelines (`appTheme`, `loucede_shortcut_keys`, `loucede_migration_seed_27_done`) — non-bloquant, cleanup prévu V2

---

## Mémoire projet (sources de vérité)

| Fichier | Contenu |
|---|---|
| `docs/plan.md` | Plan complet 7 phases, décisions, commits |
| `docs/backlog_v2.md` | ~25 items post-V1 structurés par thématique |
| `~/.claude/projects/…/memory/creem-integration.md` | SKILL.md Creem.io (1017 lignes) pour Phase 6.2 |
| `~/.claude/projects/…/memory/user_profile.md` | Profil et préférences utilisateur |
| Git log | Historique immuable des actions effectuées |

> `docs/plan.md` et `docs/backlog_v2.md` sont versionnés dans le repo git — source de vérité indépendante du chemin local du projet.

---

## Raccourcis de session

Quand l'utilisateur envoie exactement l'un de ces mots-clés seuls, exécute l'action correspondante sans demander de confirmation :

**!plan** → Lis `docs/plan.md` et affiche-en le contenu intégralement en Markdown rendu. Convertis ✅ → `- [x]`, ⏭️ → `- [ ]`, ❌ → `- ~~texte barré~~`. Aucune introduction.

**!fin** → Mets à jour `docs/plan.md` avec ce qu'on vient de faire. Affiche les tâches effectuées en `- [x]` et l'état du projet. Ne commence aucune nouvelle tâche.

**!backlog** → Lis `docs/backlog_v2.md` et affiche-en le contenu intégralement en Markdown rendu. Aucune introduction.

**!add [texte]** → Note le texte dans `docs/backlog_v2.md` sans implémenter. Confirme l'ajout.

**!fix [description]** → Correctif uniquement, hors plan d'actions. Identifie le fichier, propose avant de modifier, attends validation, commite après.

**!statut** → Résume en 5 lignes où on en est : dernière tâche faite, tâche en cours, prochaine étape. Aucune introduction.

**!commit** → Commite tout ce qui est en attente avec un message de commit bien formaté résumant les changements. Ne commite pas `CLAUDE.md`.

**!bugs** → Affiche la section "Bugs connus" de `CLAUDE.md`. Aucune introduction.

**!proxy** → Affiche l'URL du proxy Scaleway et rappelle les 3 endpoints disponibles (activate, validate, deactivate). Aucune introduction.

**!phase [X]** → Lis `docs/plan.md` et affiche uniquement le contenu de la Phase X demandée, en Markdown rendu avec cases à cocher (✅ → `- [x]`, ⏭️ → `- [ ]`, ❌ → `- ~~texte barré~~`). Aucune introduction, aucun commentaire.
