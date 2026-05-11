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
À la fin de chaque session, exécuter `!fin` pour mettre à jour `docs/plan.md` (maintenu exclusivement par CC, format tableau — cf. section « Conventions plan.md »).

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

## Workflow worktree CC ↔ repo principal

CC opère dans un worktree git isolé (`.claude/worktrees/...`). Xcode build depuis le repo principal (`~/Developer/loucede`). Pour propager les modifs CC :

1. CC fait ses commits dans le worktree.
2. CC génère un `git format-patch` par commit en fin de session.
3. L'utilisateur applique chaque patch dans le repo principal via `git am`.
4. Pas de push depuis le worktree, pas d'édition manuelle dans le repo principal pendant qu'une session CC est en cours.

---

## Conventions plan.md

Format : tableau **Statut / Tâche / Commentaire / Date** par section (H3).

Statuts d'exécution :

| Symbole | Statut | Sémantique |
|---|---|---|
| ✅ | Fait | Tâche terminée, livrée |
| 🟦 | En cours | Entamée mais non finie |
| 🟨 | À faire | Identifiée, prévue, en attente |
| ⚠️ | Bloqué | En attente externe / dépendance non résolue |
| ❌ | Annulé | Abandonnée définitivement |
| ⏭️ | Reporté en backlog | Déplacée vers `backlog_v2.md` |

Maintenu **exclusivement par CC** via la commande `!fin`. Faab n'édite plus manuellement le fichier.

Récap final « **État du projet — Tâches restantes (snapshot YYYY-MM-DD HH:MM)** » en bas du fichier : tableau filtré (🟨 / 🟦 / ⚠️ / ⏭️ uniquement, pas de ✅), mis à jour à chaque `!fin`.

⚠️ **Ne pas confondre** avec `backlog_v2.md` (maturité d'idée 🌱 / 🌿 / 🌳). Les 2 fichiers cohabitent avec des sémantiques distinctes.

Source de vérité : `~/Developer/loucede-private/plan.md` (alias `docs/plan.md` dans le workspace public).

---

## État V1 — ce qui reste à faire

Voir le tableau « **État du projet — Tâches restantes** » en bas de `docs/plan.md` pour la liste à jour (🟨 / 🟦 / ⚠️ / ⏭️ uniquement).

Source de vérité unique : `plan.md`. Cette section CLAUDE.md ne duplique plus l'information pour éviter la divergence.

### Phases terminées — ne pas retoucher sans raison explicite

Voir `docs/plan.md` pour l'historique complet des phases et sessions terminées (Phases 0 → 7, Sessions 3 → 5, Pre-V1 P1-P4, Doc native incrément B, polish typo, etc.).

Règle : ne pas modifier le code des phases passées sans raison explicite (régression, refactor justifié, bug critique).

---

## Hors scope V1 — ne pas implémenter

Tout item du `backlog_v2.md` est hors scope V1, notamment :
- i18n / String Catalog / sélecteur de langue
- Filtrage contextuel par app (per-app context)
- Trigger Finder sur sélection de fichier
- Analyse multimodale (images)
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
| `~/.claude/projects/…/memory/user_profile.md` | Profil et préférences utilisateur |
| Git log | Historique immuable des actions effectuées |

> `docs/plan.md` et `docs/backlog_v2.md` sont versionnés dans le repo git — source de vérité indépendante du chemin local du projet.

---

## Raccourcis de session

Quand l'utilisateur envoie exactement l'un de ces mots-clés seuls, exécute l'action correspondante sans demander de confirmation :

**!plan** → Lis `docs/plan.md` et affiche-en le contenu intégralement. Format tableau préservé (pas de conversion). Aucune introduction.

**!fin** → Clôture de session. Met à jour `docs/plan.md` (source réelle `~/Developer/loucede-private/plan.md`) au format tableau :

1. Identifier les tâches accomplies dans la session (nouvelles ✅, transitions 🟨 → 🟦 → ✅, nouvelles tâches émergées).
2. Mettre à jour les sections détaillées concernées avec statut + date + commentaire concis (hash commit, observation runtime clé, décision principale).
3. Préserver les manifests historiques (Commit / Description) en tableau secondaire quand pertinent.
4. Mettre à jour le récap final « **État du projet — Tâches restantes (snapshot YYYY-MM-DD HH:MM)** » :
   - mise à jour de la date du snapshot
   - ajout des nouvelles 🟨 / 🟦 / ⚠️ / ⏭️
   - retrait des tâches devenues ✅ depuis le dernier `!fin`
5. Commit local dans le repo `loucede-private` (pas de push, pas de remote) avec message `docs(plan): session [nom] — [N] tasks updated`.

Ne commence aucune nouvelle tâche.

**!backlog** → Lis `docs/backlog_v2.md` et affiche-en le contenu intégralement en Markdown rendu. Aucune introduction.

**!add [texte]** → Note le texte dans `docs/backlog_v2.md` sans implémenter. Confirme l'ajout.

**!fix [description]** → Correctif uniquement, hors plan d'actions. Identifie le fichier, propose avant de modifier, attends validation, commite après.

**!statut** → Résume en 5 lignes où on en est : dernière tâche faite, tâche en cours, prochaine étape. Aucune introduction.

**!commit** → Commite tout ce qui est en attente avec un message de commit bien formaté résumant les changements. Ne commite pas `CLAUDE.md`.

**!bugs** → Affiche la section "Bugs connus" de `CLAUDE.md`. Aucune introduction.

**!proxy** → Lis et affiche le contenu de `proxy/README.md` (table des endpoints, env vars, déploiement, sécurité). Aucune introduction.

**!phase [X]** → Lis `docs/plan.md` et affiche uniquement le contenu de la Phase X demandée. Format tableau préservé. Aucune introduction, aucun commentaire.

**!commands** → Liste toutes les commandes !slash disponibles (relit la présente section « Raccourcis de session ») avec leur description courte. Format : tableau Markdown avec colonnes [Nom | Description]. Aucune introduction.
