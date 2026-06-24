# Contribuer à loucedé

Merci de l'intérêt porté à loucedé !

**loucedé** est un fork français de [TexTab](https://github.com/ELPROFUG0/TexTab),
sous licence GPL v3. C'est une app macOS de barre de menu pour piloter des
LLMs (OpenAI, Anthropic, Mistral) via un raccourci clavier configurable.
App locale : un proxy minimal sert uniquement la validation de licence.

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
6. **Commit** : messages au format conventional commits (préfixes `feat`,
   `fix`, `docs`, `chore`, `refactor`, `style`, `perf`, `test`). Exemples :
   `feat(popup): add response window live-grow`, `fix(license): handle revoked
   keys properly`, `docs(readme): update default shortcut`.
7. **Pull request** : décris clairement le *quoi* et le *pourquoi* du changement.

## Style de code

- **Swift 5+**, **SwiftUI** pour la UI, **AppKit** quand nécessaire
  (barre de menu, événements globaux, Keychain, panneau emoji système).
- **Commentaires et documentation interne en français** (le projet est
  francophone).
- **Textes UI** : hard-codés en français pour l'instant. La migration vers un
  String Catalog (`Localizable.xcstrings`) viendra dans une version ultérieure ;
  en attendant, pas besoin de wrapper en `String(localized:)`.
- **Pas de dépendance externe sans bonne raison** — les ajouts SPM doivent
  être compatibles GPL v3 (MIT, BSD, Apache 2.0 OK).

## Questions

Ouvre une issue sur [le dépôt GitHub](https://github.com/poirpom/loucede/issues).
