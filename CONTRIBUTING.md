# Contribuer à loucedé

Merci de l'intérêt porté à loucedé !

**loucedé** est un fork français de [TexTab](https://github.com/ELPROFUG0/TexTab),
sous licence GPL v3. C'est une app macOS de barre de menu pour piloter des
LLMs (OpenAI, Anthropic, Mistral) via un raccourci clavier configurable.
Entièrement local : pas de télémétrie, pas d'authentification, pas de serveur.

## Bonnes premières contributions

Les issues marquées `good first issue` sont des points d'entrée accessibles
pour découvrir le codebase.

## Comment contribuer

1. **Forke** le dépôt depuis l'interface GitHub.
2. **Clone** ton fork :
   ```bash
   git clone https://github.com/<ton-user>/loucede.git
   cd loucede
   ```
3. **Crée une branche** :
   ```bash
   git checkout -b ma-branche
   ```
4. **Setup** : ouvre `loucede.xcodeproj` dans Xcode (macOS 15.0+).
   Les dépendances SPM sont résolues automatiquement au premier build.
   Aucun `Secrets.swift` requis — les clés API sont saisies par l'utilisateur
   dans les Réglages et stockées dans le Keychain macOS.
5. **Code** : vérifie que le build passe (⌘B) et que l'app se lance (⌘R).
6. **Commit** : messages courts et descriptifs en français, préfixés par la
   phase du plan quand c'est pertinent (ex. `Phase 6.6 : rendu Markdown`).
7. **Pull request** : décris clairement le *quoi* et le *pourquoi* du changement.

## Style de code

- **Swift 5+**, **SwiftUI** pour la UI, **AppKit** quand nécessaire
  (barre de menu, événements globaux, Keychain, panneau emoji système).
- **Commentaires et documentation interne en français** (le projet est
  francophone).
- **Textes UI** : hard-codés en FR pour l'instant. La Phase 5 (i18n) les
  migrera vers un String Catalog (`Localizable.xcstrings`) ; en attendant
  pas de `String(localized:)` requis.
- **Pas de dépendance externe sans bonne raison** — les ajouts SPM doivent
  être compatibles GPL v3 (MIT, BSD, Apache 2.0 OK).

## Questions

Ouvre une issue sur [le dépôt GitHub](https://github.com/poirpom/loucede/issues).
