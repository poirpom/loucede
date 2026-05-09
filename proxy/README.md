# proxy/ — Polar Bridge + Notion Docs (Scaleway Functions)

Code source du proxy `polar-bridge` déployé sur **Scaleway Functions**
(runtime Node.js 20, région `fr-par`). Ce proxy expose deux familles
d'endpoints à l'app loucedé :

1. **Polar Bridge** — relais authentifié vers `api.polar.sh` pour la
   gestion des licences. Le proxy garde le `POLAR_TOKEN` côté serveur
   et injecte le `POLAR_ORGANIZATION_ID` dans les bodies POST.
2. **Notion Docs** — relais authentifié vers `api.notion.com` pour la
   documentation utilisateur de l'app. Le proxy garde le `NOTION_TOKEN`
   côté serveur et applique un filtre `Type=Utilisateur AND État=Terminé`
   pour ne pas exposer les drafts.

Toutes les requêtes de l'app sont authentifiées via le même secret
partagé (`X-Loucede-App-Key`).

> **Pas de CI** : le déploiement se fait **à la main** depuis la console
> Scaleway. Le déploiement initial était un copier-coller dans l'éditeur
> inline. Depuis l'ajout de Notion (deps externes : `@notionhq/client`,
> `notion-to-md`), le déploiement passe par **upload d'un ZIP** contenant
> `handler.js` + `package.json` + `package-lock.json` + `node_modules/`.
> Voir section "Déploiement (manuel)" ci-dessous.
> Ce dossier est la source de vérité versionnée — la console Scaleway en
> est juste la copie déployée.

## Architecture
                                ┌─[Bearer POLAR_TOKEN]──▶ api.polar.sh
                                │
loucedé.app ──[X-Loucede-App-Key]──▶ proxy
│
└─[Bearer NOTION_TOKEN]─▶ api.notion.com

L'app n'a JAMAIS les tokens Polar et Notion. Elle envoie un secret
partagé (`X-Loucede-App-Key`) que le proxy vérifie avant tout forward.
Le proxy ajoute ensuite le bon Bearer token selon la cible (Polar ou
Notion) et injecte les paramètres serveur-side (`POLAR_ORGANIZATION_ID`
pour Polar, filtre `Type=Utilisateur AND État=Terminé` pour Notion).

Le routeur principal (`exports.handle` dans `handler.js`) délègue vers
`handlePolarOp` ou `handleNotionOp` selon le dernier segment du path.
Le code Polar reste isolé du code Notion (pas de partage de variables ou
d'état) pour éviter les régressions croisées.

## Endpoints exposés

Routage par dernier segment de path. L'app POST tous les endpoints (le
proxy traduit en GET côté Polar/Notion quand nécessaire).

### Polar Bridge

| Endpoint app                  | Méthode app | Polar (méthode + path)                         | Description                                                |
|-------------------------------|-------------|------------------------------------------------|------------------------------------------------------------|
| `POST /activate`              | POST        | `POST /v1/license-keys/activate`               | Active une clé sur cet appareil                            |
| `POST /validate`              | POST        | `POST /v1/license-keys/validate`               | Valide une clé existante (status, limites, expiration)     |
| `POST /deactivate`            | POST        | `POST /v1/license-keys/deactivate`             | Libère un slot d'activation                                |
| `POST /get-license-key`       | POST        | `GET /v1/license-keys/{license_key_id}`        | Récupère une licence + sa liste d'activations (compteur X/Y) |

Body attendu pour `/get-license-key` : `{"license_key_id": "<UUID>"}`.
Le proxy valide que l'`id` est un UUID avant de le concaténer dans
l'URL Polar (protection path injection).

### Notion Docs

| Endpoint app           | Méthode app | Notion (méthode + path)                                         | Description                                                  |
|------------------------|-------------|-----------------------------------------------------------------|--------------------------------------------------------------|
| `POST /notion-list`    | POST        | `POST /v1/databases/{NOTION_DATABASE_ID}/query`                 | Liste les tutos publiés (filtre + tri serveur-side)          |
| `POST /notion-page`    | POST        | `GET /v1/pages/{id}` + `GET /v1/blocks/{id}/children` (récursif) | Récupère le contenu d'un tuto converti en Markdown           |

**`POST /notion-list`** :
- Body : `{}` (pas de paramètres)
- Filtre serveur : `Type = Utilisateur AND État = Terminé` (l'app ne
  peut pas demander tous les tutos, seulement les publiés)
- Tri : `N° ASC` (l'ordre éditorial est encodé dans les numéros côté
  Notion ; 01-Bienvenue → 32-FAQ)
- Réponse : `{ pages: [{ id, title, summary, icon, cover, category,
  level, priority, number }] }`
- L'`id` retourné est utilisable pour `POST /notion-page` (UUID v4)

**`POST /notion-page`** :
- Body : `{"page_id": "<UUID>"}`
- Validation UUID v4 case-insensitive (idem Polar `get-license-key`)
- Conversion Notion blocks → Markdown via `notion-to-md`
- Réponse : `{ id, title, markdown }`
- Le Markdown est consommable côté Swift via `swift-markdown-ui`

## Variables d'environnement

À configurer dans la console Scaleway → Functions → polar-bridge →
Variables d'environnement (mode **Secret** pour toutes) :

| Variable                  | Famille | Contenu                                                                                  |
|---------------------------|---------|------------------------------------------------------------------------------------------|
| `LOUCEDE_APP_SECRET`      | Commune | Secret partagé loucedé↔proxy. Doit matcher `LicenseConfig.appSecret` côté app Swift.     |
| `POLAR_TOKEN`             | Polar   | Polar Organization Access Token (scopes : `license_keys:read` + `license_keys:write`).   |
| `POLAR_ORGANIZATION_ID`   | Polar   | UUID de l'organisation Polar. Injecté dans les bodies POST.                              |
| `NOTION_TOKEN`            | Notion  | Internal Integration Token (commence par `ntn_`). Capability : Read content uniquement.  |
| `NOTION_DATABASE_ID`      | Notion  | UUID de la BDD doc Notion (sans tirets, format Notion : `3582f817bcad80f79444d1f071c65efe`). |

### ⚠️ Scope `license_keys:read` requis

Les Organization Access Tokens Polar ne sont **pas éditables après
création**. Si le token actuellement déployé fonctionne pour
`activate` / `validate` / `deactivate` (qui requièrent
`license_keys:write`) mais que `/get-license-key` retourne **403
Forbidden**, c'est que le scope `license_keys:read` n'avait pas été
coché à la création.

Procédure de remplacement :

1. Polar Dashboard → Settings → Access Tokens → **Create New Token**
2. Cocher `license_keys:read` ET `license_keys:write` (et tout autre
   scope que tu utilises déjà ; au minimum les deux).
3. Copier la nouvelle valeur.
4. Console Scaleway → variable `POLAR_TOKEN` → remplacer.
5. Redéployer la fonction.
6. Re-tester avec le curl `/get-license-key` ci-dessous.

## Déploiement (manuel)

Depuis l'ajout des dépendances Notion (`@notionhq/client`, `notion-to-md`),
le déploiement passe par upload d'un ZIP au lieu du copier-coller inline.

### Procédure

1. Préparer le ZIP localement :
```bash
   cd ~/Developer/loucede/proxy
   zip -r proxy.zip handler.js package.json package-lock.json node_modules/
```

2. Console Scaleway → Functions → namespace → fonction `polar-bridge`.
3. Onglet **Code** → "Upload a zip" → sélectionner `proxy.zip`.
4. **Save & Deploy**.
5. Lancer les smoke tests ci-dessous (régression Polar + nouveaux endpoints Notion).

> Note : le ZIP doit contenir `node_modules/` (pas re-installé côté Scaleway).
> Le `.gitignore` exclut `node_modules/` du repo Git mais pas du ZIP de
> déploiement, qui est généré ad hoc et ignoré aussi (`*.zip`).

## Smoke test — curl

Remplacer `<APP_SECRET>`, `<KEY>`, `<ACTIVATION_ID>`, `<LICENSE_KEY_ID>`
par des valeurs réelles.

### Régression — `/validate` (doit toujours fonctionner)

```bash
curl -s -X POST \
  "https://loucedelicenseproxyejpzefpl-polar-bridge.functions.fnc.fr-par.scw.cloud/validate" \
  -H "X-Loucede-App-Key: <APP_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"key":"<KEY>","activation_id":"<ACTIVATION_ID>"}' \
  | jq
```

Attendu : status 200, JSON avec `id`, `status: "granted"`, `activation`,
`customer`, etc.

### `/get-license-key`

```bash
curl -s -X POST \
  "https://loucedelicenseproxyejpzefpl-polar-bridge.functions.fnc.fr-par.scw.cloud/get-license-key" \
  -H "X-Loucede-App-Key: <APP_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"license_key_id":"<LICENSE_KEY_ID>"}' \
  | jq
```

Attendu : status 200, JSON `LicenseKeyWithActivations` avec un champ
`activations` qui est un tableau d'objets `{id, license_key_id, label,
created_at, modified_at, meta}`. Si le compte n'a qu'une seule
activation, le tableau aura 1 élément.

Status d'erreur possibles :
- **400** — `license_key_id` manquant ou pas un UUID. Body : `{"error":"Missing or malformed license_key_id"}`
- **401** — `X-Loucede-App-Key` manquant ou mauvais. Vérifier que la valeur côté app matche la variable d'env Scaleway.
- **403** — Token Polar n'a pas le scope `license_keys:read`. Voir section ci-dessus.
- **404** — Le `license_key_id` n'existe pas chez Polar (ou n'appartient pas à cette org).
- **502** — Le proxy n'a pas pu joindre Polar. Body : `{"error":"Polar unreachable", "detail":"..."}`.

### Nouveau — `/notion-list`

```bash
curl -s -X POST \
  "https://loucedelicenseproxyejpzefpl-polar-bridge.functions.fnc.fr-par.scw.cloud/notion-list" \
  -H "X-Loucede-App-Key: <APP_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{}' \
  | jq
```

Attendu : status 200, JSON `{ pages: [...] }`. Aujourd'hui (mai 2026), 
seules 2 pages sortent : Bienvenue (`01`) et Installer (`02`). Au fur 
et à mesure que les tutos sont rédigés et passés en `État: Terminé` 
côté Notion, ils s'ajoutent à la liste sans modification du proxy.

Status d'erreur possibles :
- **401** — `X-Loucede-App-Key` manquant ou mauvais.
- **502** — Le proxy n'a pas pu joindre Notion. Body : `{"error":"Notion unreachable", "detail":"..."}`.
- **400/403/404** — Erreur Notion API (proxy passthrough du status code Notion). 
  Body : `{"error":"Notion API error", "code":"...", "message":"..."}`.

### Nouveau — `/notion-page`

```bash
curl -s -X POST \
  "https://loucedelicenseproxyejpzefpl-polar-bridge.functions.fnc.fr-par.scw.cloud/notion-page" \
  -H "X-Loucede-App-Key: <APP_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"page_id":"3582f817-bcad-8092-8039-dad1f7d09ab2"}' \
  | jq
```

Attendu : status 200, JSON `{ id, title: "Bienvenue dans loucedé",
markdown: "..." }`. Le `markdown` contient le contenu de la page
converti depuis les blocks Notion via `notion-to-md`.

Status d'erreur possibles :
- **400** — `page_id` manquant ou pas un UUID. Body : `{"error":"Missing or malformed page_id"}`.
- **401** — `X-Loucede-App-Key` manquant ou mauvais.
- **404** — La page n'existe pas (ou n'est pas partagée avec l'intégration `loucedé doc proxy`).
- **502** — Le proxy n'a pas pu joindre Notion.

## Sécurité

- Le `LOUCEDE_APP_SECRET` est shipped dans le binaire macOS (décompilable).
  Risque borné : pas de fuite des `POLAR_TOKEN` ou `NOTION_TOKEN`, juste
  possibilité de spammer le proxy si compromis. En cas de fuite : régénérer
  la valeur (`openssl rand -hex 32`), update Scaleway env var **et** push
  une nouvelle release de l'app avec la nouvelle valeur dans
  `LicenseConfig.appSecret`.
- En cas de fuite du `POLAR_TOKEN` : Polar Dashboard → Access Tokens →
  **Revoke**, créer un nouveau token avec les bons scopes
  (`license_keys:read` + `license_keys:write`), mettre à jour la variable
  `POLAR_TOKEN` dans la console Scaleway, redéployer. L'app n'a pas
  besoin d'être touchée — le token n'y figure jamais.
- Le `POLAR_TOKEN` ne quitte jamais le serveur Scaleway (mode Secret env var).
- L'`organization_id` est injecté serveur-side : un attaquant qui forgerait
  un body malveillant ne peut pas cibler une autre org Polar.
- Le `NOTION_TOKEN` ne quitte jamais le serveur Scaleway (mode Secret env var).
  En cas de fuite : Notion → Settings → Integrations → `loucedé doc proxy`
  → **Regenerate secret**, mettre à jour la variable `NOTION_TOKEN` dans
  la console Scaleway, redéployer. L'app n'a pas besoin d'être touchée —
  le token n'y figure jamais.
- L'intégration Notion `loucedé doc proxy` a la capability **Read content
  uniquement**. Aucune écriture, aucun accès aux comments ou aux
  utilisateurs. Si le token fuite, un attaquant ne peut que lire la doc
  publique (déjà accessible via `loucede.notion.site`).

## Lien avec l'app

| Côté Swift                                    | Endpoint proxy        |
|-----------------------------------------------|-----------------------|
| `LicenseService.activate(key:label:)`         | `POST /activate`      |
| `LicenseService.validate(key:activationId:)`  | `POST /validate`      |
| `LicenseService.deactivate(key:activationId:)`| `POST /deactivate`    |
| `LicenseService.getLicenseKey(id:)`           | `POST /get-license-key` |
| `DocumentationService.fetchList()` (à venir)  | `POST /notion-list`   |
| `DocumentationService.fetchPage(id:)` (à venir) | `POST /notion-page` |

Configuration côté app dans `loucede/LicenseConfig.swift` (URL du proxy
+ `appSecret`). La même URL est partagée pour tous les endpoints (Polar
et Notion) — seul le path final change selon l'op.