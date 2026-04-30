//
// loucedé — Polar Bridge proxy (Scaleway Functions, Node.js 20)
//
// Reçoit les requêtes signées de l'app (header X-Loucede-App-Key) et les
// relaie vers api.polar.sh en injectant les credentials org côté serveur.
//
// Auth chain :
//   loucedé app ──[X-Loucede-App-Key]──▶ ce proxy ──[Bearer POLAR_TOKEN]──▶ api.polar.sh
//
// Variables d'environnement requises (configurées dans la console Scaleway) :
//   - LOUCEDE_APP_SECRET        secret partagé app↔proxy (header validé en 401 sinon)
//   - POLAR_TOKEN               Polar Organization Access Token (Bearer)
//   - POLAR_ORGANIZATION_ID     UUID de l'org Polar (injecté dans les bodies POST)
//
// Toutes les ops sont routées par le DERNIER segment du path (cohérent avec
// le déploiement initial du 27/04/2026). La table OPS ci-dessous décrit
// chaque op, sa méthode HTTP côté Polar, et la transformation à appliquer.
//
// Voir proxy/README.md pour la doc opérationnelle, le déploiement et les
// scopes Polar requis.
//

const POLAR_API_BASE = 'https://api.polar.sh/v1/license-keys';

/**
 * Op routing table. Chaque op déclare :
 *   - method:       méthode HTTP envoyée à Polar
 *   - polarPath:    fonction(body) ⇒ suffixe de path Polar (peut throw ValidationError)
 *   - injectOrgId:  injecte POLAR_ORGANIZATION_ID dans le body forwardé (POST uniquement)
 *   - forwardBody:  envoie un body JSON à Polar (false pour GET)
 */
const OPS = {
  'activate': {
    method: 'POST',
    polarPath: () => '/activate',
    injectOrgId: true,
    forwardBody: true,
  },
  'validate': {
    method: 'POST',
    polarPath: () => '/validate',
    injectOrgId: true,
    forwardBody: true,
  },
  'deactivate': {
    method: 'POST',
    polarPath: () => '/deactivate',
    injectOrgId: true,
    forwardBody: true,
  },
  'get-license-key': {
    method: 'GET',
    polarPath: (body) => {
      const id = body && body.license_key_id;
      // UUID v4 (case-insensitive) — protège contre une path injection
      // dans l'URL Polar et confirme la shape attendue depuis l'app.
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (!id || !uuidRegex.test(id)) {
        throw new ValidationError('Missing or malformed license_key_id');
      }
      return `/${id}`;
    },
    injectOrgId: false,
    forwardBody: false,
  },
};

class ValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ValidationError';
  }
}

exports.handle = async (event) => {
  // 1. Vérifie le secret partagé loucedé↔proxy
  const headers = event.headers || {};
  const appKey = headers['x-loucede-app-key'] || headers['X-Loucede-App-Key'] || '';
  if (appKey !== process.env.LOUCEDE_APP_SECRET) {
    return jsonResponse(401, { error: 'Invalid app key' });
  }

  // 2. Extrait l'op du dernier segment de path
  const path = event.path || '';
  const op = path.split('/').filter(Boolean).pop();
  const config = OPS[op];
  if (!config) {
    return jsonResponse(400, { error: `Unknown op: ${op}` });
  }

  // 3. Parse le body JSON (peut être vide pour les GET)
  let body = {};
  try {
    body = event.body ? JSON.parse(event.body) : {};
  } catch (_) {
    return jsonResponse(400, { error: 'Invalid JSON body' });
  }

  // 4. Résout le path Polar (peut throw ValidationError pour shape invalide)
  let polarPath;
  try {
    polarPath = config.polarPath(body);
  } catch (e) {
    if (e instanceof ValidationError) {
      return jsonResponse(400, { error: e.message });
    }
    throw e;
  }

  // 5. Construit la requête Polar
  const polarHeaders = {
    'Authorization': `Bearer ${process.env.POLAR_TOKEN}`,
    'Accept': 'application/json',
  };
  let polarBody;
  if (config.forwardBody) {
    if (config.injectOrgId) {
      body.organization_id = process.env.POLAR_ORGANIZATION_ID;
    }
    polarHeaders['Content-Type'] = 'application/json';
    polarBody = JSON.stringify(body);
  }

  // 6. Forward vers Polar
  let polarResponse;
  try {
    polarResponse = await fetch(`${POLAR_API_BASE}${polarPath}`, {
      method: config.method,
      headers: polarHeaders,
      body: polarBody,
    });
  } catch (e) {
    return jsonResponse(502, { error: 'Polar unreachable', detail: String(e) });
  }

  // 7. Passthrough du status + body Polar
  // Pour 204 No Content (cas /deactivate), responseText sera "". Le client
  // Swift route ces cas via postExpectingNoContent qui ne décode jamais
  // le body — donc OK de garder Content-Type: application/json uniformément.
  const responseText = await polarResponse.text();
  return {
    statusCode: polarResponse.status,
    body: responseText,
    headers: { 'Content-Type': 'application/json' },
  };
};

function jsonResponse(statusCode, payload) {
  return {
    statusCode,
    body: JSON.stringify(payload),
    headers: { 'Content-Type': 'application/json' },
  };
}
