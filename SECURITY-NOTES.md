# Notes de sécurité

## Secrets hérités du fork upstream (TexTab)

loucedé est un fork de `ELPROFUG0/TexTab`. L'historique git hérité du
dossier `typo/` contient deux secrets introduits par le mainteneur
upstream (Moises) :

- **Clé API OpenRouter** — commit `4d19ece` (« Add AI-powered prompt
  improvement and fix settings editor »).
- **JWT Supabase (anon key)** — commit `da70422` (« Add subscription
  system with Supabase auth and Stripe payments »).

### Pourquoi ils ne sont pas réécrits

- Ces secrets sont **déjà publics** depuis le dépôt source
  `ELPROFUG0/TexTab` (public, étoilé et forké). Le push de loucedé ne les
  introduit pas : il les reproduit dans un nouveau lieu où ils sont déjà
  accessibles.
- Ils **ne nous appartiennent pas** (compte OpenRouter / projet Supabase
  de Moises) → nous ne pouvons pas les rotater.
- Réécrire l'historique casserait l'intégrité du fork et la traçabilité de
  la généalogie GPL v3.

Décision : documenter, ne pas réécrire l'historique.

## Secret applicatif loucedé

L'app loucedé authentifie ses appels au proxy Scaleway via un header
`X-Loucede-App-Key`. Ce secret partagé :

- **Protège** l'endpoint du proxy contre les requêtes hors-loucedé
  (anti-spam, anti-mapping d'infrastructure).
- **Ne protège PAS** les secrets serveur (`POLAR_TOKEN`, `NOTION_TOKEN`)
  qui restent côté Scaleway et ne sont jamais transmis à l'app.
- Est **shippé dans le binaire** de l'app (donc décompilable par un
  attaquant motivé). Risque borné assumé en V1 — un attaquant qui le
  récupère peut spammer le proxy, sans obtenir les tokens serveur ni les
  données utilisateur.

Côté code, ce secret est injecté au build via `Secrets.xcconfig`
(gitignoré, cf. `Secrets.xcconfig.example`), exposé dans `Info.plist` sous
la clé `LoucedeAppSecret`, et lu au runtime via `LicenseConfig.appSecret`.
Aucune valeur en clair dans le code source.
