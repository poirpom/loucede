//
// loucedé — Proxy Scaleway Functions (Node.js 20)
//
// Ce proxy expose deux familles d'endpoints à l'app loucedé :
//
//   1. Polar Bridge — relais authentifié vers api.polar.sh pour la
//      gestion des licences (activate / validate / deactivate /
//      get-license-key).
//   2. Notion Docs — relais authentifié vers api.notion.com pour la
//      documentation utilisateur de l'app (notion-list / notion-page).
//
// Auth chain commune (ne change pas selon la cible) :
//   loucedé app ──[X-Loucede-App-Key]──▶ ce proxy ──[Bearer TOKEN]──▶ api.{polar|notion}
//
// Variables d'environnement requises (configurées dans la console Scaleway) :
//   Polar Bridge :
//     - LOUCEDE_APP_SECRET        secret partagé app↔proxy (header validé en 401 sinon)
//     - POLAR_TOKEN               Polar Organization Access Token (Bearer)
//     - POLAR_ORGANIZATION_ID     UUID de l'org Polar (injecté dans les bodies POST)
//   Notion Docs :
//     - NOTION_TOKEN              Internal Integration Token (commence par 'ntn_')
//     - NOTION_DATABASE_ID        UUID de la BDD doc (sans tirets, format Notion)
//
// Toutes les ops sont routées par le DERNIER segment du path. Le routeur
// principal (exports.handle) délègue vers handlePolarOp ou handleNotionOp
// selon le segment reconnu. Les ops Polar sont décrites dans la table OPS.
// Les ops Notion sont des fonctions dédiées (handleNotionList, handleNotionPage).
//
// Voir proxy/README.md pour la doc opérationnelle, le déploiement et les
// scopes/capabilities requis côté Polar et Notion.
//

const { Client: NotionClient } = require('@notionhq/client');
const { NotionToMarkdown } = require('notion-to-md');

const POLAR_API_BASE = 'https://api.polar.sh/v1/license-keys';

// === POLAR OPS — table de routage ===
//
// Chaque op déclare :
//   - method:       méthode HTTP envoyée à Polar
//   - polarPath:    fonction(body) ⇒ suffixe de path Polar (peut throw ValidationError)
//   - injectOrgId:  injecte POLAR_ORGANIZATION_ID dans le body forwardé (POST uniquement)
//   - forwardBody:  envoie un body JSON à Polar (false pour GET)
//
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

// === NOTION OPS — table de routage ===
//
// Mapping op → handler dédié. Contrairement aux Polar OPS (configuration
// déclarative + flux unique), les ops Notion ont des shapes très
// différentes (query database vs retrieve page+blocks), donc fonctions
// séparées pour clarté.
//
const NOTION_OPS = {
  'notion-list': handleNotionList,
  'notion-page': handleNotionPage,
};

class ValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ValidationError';
  }
}

// === ROUTEUR PRINCIPAL ===
//
// 1. Vérifie le secret partagé (auth chain commune Polar + Notion)
// 2. Extrait l'op du dernier segment de path
// 3. Branche vers handleNotionOp (si op Notion) OU handlePolarOp (si op Polar)
// 4. Renvoie 400 Unknown op si l'op n'est ni Polar ni Notion
//
exports.handle = async (event) => {
  // 1. Vérifie le secret partagé loucedé↔proxy (auth chain commune)
  const headers = event.headers || {};
  const appKey = headers['x-loucede-app-key'] || headers['X-Loucede-App-Key'] || '';
  if (appKey !== process.env.LOUCEDE_APP_SECRET) {
    return jsonResponse(401, { error: 'Invalid app key' });
  }

  // 2. Extrait l'op du dernier segment de path
  const path = event.path || '';
  const op = path.split('/').filter(Boolean).pop();

  // 3. Branche vers la famille d'ops correspondante
  if (NOTION_OPS[op]) {
    return await handleNotionOp(op, event);
  }
  if (OPS[op]) {
    return await handlePolarOp(op, event);
  }

  // 4. Op inconnue
  return jsonResponse(400, { error: `Unknown op: ${op}` });
};

// === HANDLER POLAR ===
//
// Logique inchangée par rapport à la version pré-Notion (commit 27/04/2026) :
// résout le path Polar, construit la requête, forward, passthrough du status
// et du body. Juste isolée dans une fonction dédiée pour permettre le
// branchement amont entre familles d'ops (Polar vs Notion).
//
async function handlePolarOp(op, event) {
  const config = OPS[op];

  // 1. Parse le body JSON (peut être vide pour les GET)
  let body = {};
  try {
    body = event.body ? JSON.parse(event.body) : {};
  } catch (_) {
    return jsonResponse(400, { error: 'Invalid JSON body' });
  }

  // 2. Résout le path Polar (peut throw ValidationError pour shape invalide)
  let polarPath;
  try {
    polarPath = config.polarPath(body);
  } catch (e) {
    if (e instanceof ValidationError) {
      return jsonResponse(400, { error: e.message });
    }
    throw e;
  }

  // 3. Construit la requête Polar
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

  // 4. Forward vers Polar
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

  // 5. Passthrough du status + body Polar
  // Pour 204 No Content (cas /deactivate), responseText sera "". Le client
  // Swift route ces cas via postExpectingNoContent qui ne décode jamais
  // le body — donc OK de garder Content-Type: application/json uniformément.
  const responseText = await polarResponse.text();
  return {
    statusCode: polarResponse.status,
    body: responseText,
    headers: { 'Content-Type': 'application/json' },
  };
}

// === HANDLERS NOTION ===
//
// Branche d'entrée unique pour les ops Notion. Parse le body, délègue au
// handler dédié (handleNotionList ou handleNotionPage). Contrairement à
// Polar (table OPS + flux unique), Notion a des shapes très différentes
// par op, donc on duplique pas la logique : chaque handler gère son cas.
//
async function handleNotionOp(op, event) {
  // 1. Parse le body JSON (peut être vide pour notion-list, requis pour notion-page)
  let body = {};
  try {
    body = event.body ? JSON.parse(event.body) : {};
  } catch (_) {
    return jsonResponse(400, { error: 'Invalid JSON body' });
  }

  // 2. Délègue au handler de l'op
  const handler = NOTION_OPS[op];
  try {
    return await handler(body);
  } catch (e) {
    if (e instanceof ValidationError) {
      return jsonResponse(400, { error: e.message });
    }
    // Erreurs Notion : le SDK lance des APIResponseError avec status code
    if (e.status) {
      return jsonResponse(e.status, {
        error: 'Notion API error',
        code: e.code || 'unknown',
        message: e.message || 'No detail',
      });
    }
    return jsonResponse(502, { error: 'Notion unreachable', detail: String(e) });
  }
}

// notion-list — Récupère la liste des tutos publiés
//
// Filtre côté serveur : Type=Utilisateur AND État=Terminé. Tri par N° ASC
// (l'ordre éditorial est encodé dans les numéros côté Notion).
//
// Body attendu : {} (pas de paramètres)
//
// Réponse : { pages: [{ id, title, summary, icon, cover, category, level,
//                       priority, number }] }
//
async function handleNotionList(_body) {
  const notion = new NotionClient({ auth: process.env.NOTION_TOKEN });

  const response = await notion.databases.query({
    database_id: process.env.NOTION_DATABASE_ID,
    filter: {
      and: [
        { property: 'Type', select: { equals: 'Utilisateur' } },
        { property: 'État', status: { equals: 'Terminé' } },
      ],
    },
    sorts: [
      { property: 'N°', direction: 'ascending' },
    ],
  });

  // Mapping JSON simplifié : ne renvoie que ce dont l'app a besoin pour
  // afficher la sidebar. Évite de leaker la structure interne Notion.
  const pages = response.results.map((page) => ({
    id: page.id,
    title: extractTitle(page),
    summary: extractRichText(page.properties['Résumé']),
    icon: extractEmoji(page.icon),
    cover: extractCover(page.cover),
    category: extractSelect(page.properties['Catégorie']),
    level: extractSelect(page.properties['Niveau']),
    priority: extractSelect(page.properties['Priorité']),
    number: extractRichText(page.properties['N°']),
  }));

  return jsonResponse(200, { pages });
}

// notion-page — Récupère le contenu d'une page convertie en Markdown
//
// Body attendu : { page_id: "<UUID>" }
// Validation UUID v4 case-insensitive (idem Polar get-license-key).
//
// Réponse : { id, title, markdown }
//
async function handleNotionPage(body) {
  const pageId = body && body.page_id;
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!pageId || !uuidRegex.test(pageId)) {
    throw new ValidationError('Missing or malformed page_id');
  }

  const notion = new NotionClient({ auth: process.env.NOTION_TOKEN });
  const n2m = new NotionToMarkdown({ notionClient: notion });

  // 1. Récupère les métadonnées de la page (pour le titre)
  const page = await notion.pages.retrieve({ page_id: pageId });

  // 2. Récupère les blocks et convertit en Markdown
  const mdBlocks = await n2m.pageToMarkdown(pageId);
  const mdString = n2m.toMarkdownString(mdBlocks);

  return jsonResponse(200, {
    id: page.id,
    title: extractTitle(page),
    markdown: mdString.parent || '',
  });
}

// === HELPERS NOTION ===
//
// Extracteurs de propriétés Notion vers types simples (string | null).
// Les propriétés Notion ont des shapes typées complexes (rich_text est
// un array d'objets, select est un objet { name, color, id }, etc.).
// Ces helpers normalisent vers du JSON consommable côté Swift.
//

function extractTitle(page) {
  const title = page.properties && page.properties['Titre'];
  if (!title || title.type !== 'title' || !Array.isArray(title.title)) return '';
  return title.title.map((t) => t.plain_text || '').join('');
}

function extractRichText(property) {
  if (!property || property.type !== 'rich_text' || !Array.isArray(property.rich_text)) return null;
  if (property.rich_text.length === 0) return null;
  return property.rich_text.map((t) => t.plain_text || '').join('');
}

function extractSelect(property) {
  if (!property || property.type !== 'select' || !property.select) return null;
  return property.select.name || null;
}

function extractEmoji(icon) {
  if (!icon || icon.type !== 'emoji') return null;
  return icon.emoji || null;
}

function extractCover(cover) {
  if (!cover) return null;
  if (cover.type === 'external') return cover.external && cover.external.url || null;
  if (cover.type === 'file') return cover.file && cover.file.url || null;
  return null;
}

// === HELPER GÉNÉRIQUE ===

function jsonResponse(statusCode, payload) {
  return {
    statusCode,
    body: JSON.stringify(payload),
    headers: { 'Content-Type': 'application/json' },
  };
}