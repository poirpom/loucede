# proxy/ — Polar Bridge (Scaleway Functions)

Code source du proxy `polar-bridge` déployé sur **Scaleway Functions**
(runtime Node.js 20, région `fr-par`). Ce proxy se trouve entre l'app
loucedé et l'API Polar.sh : il garde le `POLAR_TOKEN` côté serveur et
authentifie les requêtes de l'app via un secret partagé.

> **Pas de CI** : le déploiement se fait **à la main** depuis la console
> Scaleway. Quand `handler.js` change, copier-coller le contenu dans la
> console et redéployer manuellement. Ce dossier est la source de vérité
> versionnée — la console Scaleway en est juste la copie déployée.

## Architecture

```
loucedé.app ──[X-Loucede-App-Key]──▶ proxy ──[Bearer POLAR_TOKEN]──▶ api.polar.sh
```

L'app n'a JAMAIS le token Polar. Elle envoie un secret partagé
(`X-Loucede-App-Key`) que le proxy vérifie avant tout forward. Le
`POLAR_ORGANIZATION_ID` est injecté côté serveur dans les bodies POST,
pour les ops Polar qui le requièrent.

## Endpoints exposés

Routage par dernier segment de path. L'app POST tous les endpoints (le
proxy traduit en GET côté Polar quand nécessaire).

| Endpoint app                  | Méthode app | Polar (méthode + path)                         | Description                                                |
|-------------------------------|-------------|------------------------------------------------|------------------------------------------------------------|
| `POST /activate`              | POST        | `POST /v1/license-keys/activate`               | Active une clé sur cet appareil                            |
| `POST /validate`              | POST        | `POST /v1/license-keys/validate`               | Valide une clé existante (status, limites, expiration)     |
| `POST /deactivate`            | POST        | `POST /v1/license-keys/deactivate`             | Libère un slot d'activation                                |
| `POST /get-license-key`       | POST        | `GET /v1/license-keys/{license_key_id}`        | Récupère une licence + sa liste d'activations (compteur X/Y) |

Body attendu pour `/get-license-key` : `{"license_key_id": "<UUID>"}`.
Le proxy valide que l'`id` est un UUID avant de le concaténer dans
l'URL Polar (protection path injection).

## Variables d'environnement

À configurer dans la console Scaleway → Functions → polar-bridge →
Variables d'environnement (mode **Secret** pour les 3) :

| Variable                  | Contenu                                                                                  |
|---------------------------|------------------------------------------------------------------------------------------|
| `LOUCEDE_APP_SECRET`      | Secret partagé loucedé↔proxy. Doit matcher `LicenseConfig.appSecret` côté app Swift.     |
| `POLAR_TOKEN`             | Polar Organization Access Token (scopes : `license_keys:read` + `license_keys:write`).   |
| `POLAR_ORGANIZATION_ID`   | UUID de l'organisation Polar. Injecté dans les bodies POST.                              |

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

1. Console Scaleway → Functions → namespace → fonction `polar-bridge`.
2. Onglet **Code** → coller le contenu de `handler.js` à la place du
   handler existant.
3. **Save & Deploy**.
4. Lancer les deux curl de smoke test ci-dessous pour valider la
   non-régression et le nouvel endpoint.

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

### Nouveau — `/get-license-key`

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

## Sécurité

- Le `LOUCEDE_APP_SECRET` est shipped dans le binaire macOS (décompilable).
  Risque borné : pas de fuite du `POLAR_TOKEN`, juste possibilité de
  spammer le proxy si compromis. En cas de fuite : régénérer la valeur
  (`openssl rand -hex 32`), update Scaleway env var **et** push une nouvelle
  release de l'app avec la nouvelle valeur dans `LicenseConfig.appSecret`.
- En cas de fuite du `POLAR_TOKEN` : Polar Dashboard → Access Tokens →
  **Revoke**, créer un nouveau token avec les bons scopes
  (`license_keys:read` + `license_keys:write`), mettre à jour la variable
  `POLAR_TOKEN` dans la console Scaleway, redéployer. L'app n'a pas
  besoin d'être touchée — le token n'y figure jamais.
- Le `POLAR_TOKEN` ne quitte jamais le serveur Scaleway (mode Secret env var).
- L'`organization_id` est injecté serveur-side : un attaquant qui forgerait
  un body malveillant ne peut pas cibler une autre org Polar.

## Lien avec l'app

| Côté Swift                                    | Endpoint proxy        |
|-----------------------------------------------|-----------------------|
| `LicenseService.activate(key:label:)`         | `POST /activate`      |
| `LicenseService.validate(key:activationId:)`  | `POST /validate`      |
| `LicenseService.deactivate(key:activationId:)`| `POST /deactivate`    |
| `LicenseService.getLicenseKey(id:)`           | `POST /get-license-key` |

Configuration côté app dans `loucede/LicenseConfig.swift` (URL du proxy
+ `appSecret`).
