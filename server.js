#!/usr/bin/env node
// © 2026 IB-Thomee GmbH. Alle Rechte vorbehalten – nur für die eigene Anwendung im Karteikartensystem (siehe LICENSE).
// MCP-Server für das Admin-Panel der Karteikarten-App (stdio, ohne Abhängigkeiten).
// Damit kann Claude Code Module, Karten, Codes und Meldungen pflegen – auch in großen Mengen.
//
// Admin: alle Werkzeuge. Redaktion (Professoren, API-Schlüssel edk-… aus dem Panel): nur Kurse, Karten, Meldungen.
// Download für die Redaktion: https://karteikarten-admin.pages.dev/mcp/server.js (Anleitung im Panel, Tab „Karteneditor“).
//
// Schlüssel (erster Treffer gilt):
//   KARTEIKARTEN_ADMIN_TOKEN       direkt als Umgebungsvariable (nicht empfohlen)
//   KARTEIKARTEN_ADMIN_TOKEN_FILE  Pfad zu einer Datei mit dem Schlüssel
//   ~/.karteikarten/api-key.txt    Redaktion: API-Schlüssel aus dem Panel
//   ~/.karteikarten-cloudflare/admin-token.txt   Admin
// KARTEIKARTEN_ADMIN_URL           Standard: https://karteikarten-admin.pages.dev
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { createInterface } from 'node:readline';

const BASE = (process.env.KARTEIKARTEN_ADMIN_URL || 'https://karteikarten-admin.pages.dev').replace(/\/$/, '');
const TOKEN_FILES = [process.env.KARTEIKARTEN_ADMIN_TOKEN_FILE, join(homedir(), '.karteikarten', 'api-key.txt'),
  join(homedir(), '.karteikarten-cloudflare', 'admin-token.txt')].filter(Boolean);

function token() {
  if (process.env.KARTEIKARTEN_ADMIN_TOKEN) return process.env.KARTEIKARTEN_ADMIN_TOKEN.trim();
  const file = TOKEN_FILES.find((f) => existsSync(f));
  if (!file) throw new Error(`Kein Schlüssel gefunden. Im Panel unter „Karteneditor“ einen API-Schlüssel erzeugen und in ${TOKEN_FILES[TOKEN_FILES.length - 2]} speichern.`);
  return readFileSync(file, 'utf8').trim();
}

async function api(method, path, body) {
  const r = await fetch(BASE + path, {
    method,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json', 'User-Agent': 'karteikarten-mcp/1.3' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(data.fehler || `HTTP ${r.status}`);
  return data;
}

const CARD_SCHEMA = {
  type: 'object',
  properties: {
    id: { type: 'string', description: 'Karten-ID. Weglassen = neue Karte. Bestehende ID = Karte ändern (Lernstand bleibt).' },
    chapter: { type: 'string', description: 'Kapitel innerhalb des Moduls, z. B. "Kap. 5 FZV-Tabelle"' },
    front: { type: 'string', description: 'Vorderseite (Frage), HTML erlaubt' },
    back: { type: 'string', description: 'Rückseite (Antwort), HTML erlaubt (Tabellen, <b>, <br>)' },
    tags: { type: 'array', items: { type: 'string' }, description: 'Tags; "Zahlen" nimmt die Karte in den Lernmodus "Zahlen & Daten" auf' },
  },
  required: ['front', 'back'],
};

const TOOLS = [
  {
    name: 'whoami',
    description: 'Mit welchem Zugang arbeitet der Server (Admin oder Redaktion, Name)? Zu Beginn aufrufen.',
    inputSchema: { type: 'object', properties: {} },
    run: () => api('GET', '/api/admin/whoami'),
  },
  {
    name: 'list_modules',
    description: 'Alle Module auf dem Server mit Kartenzahl, Sichtbarkeit (öffentlich oder per Code) und Version.',
    inputSchema: { type: 'object', properties: {} },
    run: () => api('GET', '/api/admin/modules'),
  },
  {
    name: 'save_module',
    description: 'Modul anlegen oder Titel/Sichtbarkeit/Bundesländer ändern. Neue Module sind standardmäßig nur per Freischalt-Code sichtbar.',
    inputSchema: {
      type: 'object',
      properties: {
        id: { type: 'string', description: 'Kennung: Kleinbuchstaben, Ziffern, Bindestrich, z. B. "muendliche-pruefung"' },
        title: { type: 'string', description: 'Anzeigename, z. B. "Mündliche Prüfung"' },
        public: { type: 'boolean', description: 'true = für alle ohne Code sichtbar' },
        laender: { type: 'array', items: { type: 'string', enum: ['BW', 'BY', 'BE', 'BB', 'HB', 'HH', 'HE', 'MV', 'NI', 'NW', 'RP', 'SL', 'SN', 'ST', 'SH', 'TH'] },
          description: 'Bundesländer, für die das Paket gedacht ist (leer = bundesweit). Standorte: Cottenheim = NW + RP, Ulm = BW + BY, Leipzig/Ost = BB, BE, MV, SN, ST, TH' },
      },
      required: ['id', 'title'],
    },
    run: (a) => api('POST', '/api/admin/modules', a),
  },
  {
    name: 'delete_module',
    admin: true,
    description: 'Modul mit allen Karten und Codes endgültig löschen. Nur auf ausdrücklichen Wunsch verwenden.',
    inputSchema: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    run: (a) => api('DELETE', `/api/admin/modules/${encodeURIComponent(a.id)}`),
  },
  {
    name: 'get_cards',
    description: 'Alle Karten eines Moduls (ID, Kapitel, Vorder-/Rückseite, Tags).',
    inputSchema: { type: 'object', properties: { module: { type: 'string' } }, required: ['module'] },
    run: (a) => api('GET', `/api/admin/modules/${encodeURIComponent(a.module)}/cards`),
  },
  {
    name: 'upsert_cards',
    description: 'Karten massenhaft hinzufügen oder ändern (bis 2000 pro Aufruf). Mit id = ändern, ohne id = neu. '
      + 'replace=true ersetzt das ganze Modul (nicht genannte Karten werden gelöscht) – nur bewusst verwenden.',
    inputSchema: {
      type: 'object',
      properties: {
        module: { type: 'string' },
        cards: { type: 'array', items: CARD_SCHEMA },
        replace: { type: 'boolean' },
        reason: { type: 'string', description: 'Grund der Änderung – erscheint in der Korrekturhistorie (z. B. "Meldung #8: Verjährung 6 Monate")' },
        reportId: { type: 'number', description: 'Nummer der Meldung, auf die sich die Korrektur bezieht (optional)' },
      },
      required: ['module', 'cards'],
    },
    run: (a) => api('POST', `/api/admin/modules/${encodeURIComponent(a.module)}/cards`, { cards: a.cards, replace: !!a.replace, reason: a.reason, reportId: a.reportId }),
  },
  {
    name: 'delete_cards',
    description: 'Karten eines Moduls per ID löschen (Lernstand dazu verfällt).',
    inputSchema: { type: 'object', properties: { module: { type: 'string' }, ids: { type: 'array', items: { type: 'string' } }, reason: { type: 'string' } }, required: ['module', 'ids'] },
    run: (a) => api('POST', `/api/admin/modules/${encodeURIComponent(a.module)}/cards/delete`, { ids: a.ids, reason: a.reason }),
  },
  {
    name: 'get_card_history',
    description: 'Korrekturhistorie einer Karte: frühere Fassungen mit Datum, Wer, Grund, Meldungsnummer. Ohne id: letzte Änderungen (optional je Modul).',
    inputSchema: { type: 'object', properties: { id: { type: 'string', description: 'Karten-ID (optional)' }, module: { type: 'string' }, limit: { type: 'number' } } },
    run: (a) => (a.id ? api('GET', `/api/admin/cards/${encodeURIComponent(a.id)}/history`)
      : api('GET', `/api/admin/history?limit=${a.limit || 50}${a.module ? `&module=${encodeURIComponent(a.module)}` : ''}`)),
  },
  {
    name: 'list_codes',
    admin: true,
    description: 'Freischalt-Codes (optional nur für ein Modul) mit Bezeichnung, Ablaufdatum, Status.',
    inputSchema: { type: 'object', properties: { module: { type: 'string' } } },
    run: async (a) => {
      const r = await api('GET', '/api/admin/codes');
      return a.module ? { codes: r.codes.filter((c) => c.module === a.module) } : r;
    },
  },
  {
    name: 'create_code',
    admin: true,
    description: 'Neuen Freischalt-Code für ein Modul erzeugen (zufällig oder eigener Code, optional mit Kontingent), z. B. je Lehrgang. Lernende geben ihn in der App unter "Modul freischalten" ein.',
    inputSchema: {
      type: 'object',
      properties: {
        module: { type: 'string' }, label: { type: 'string' }, expires: { type: 'string', description: 'JJJJ-MM-TT, optional' },
        code: { type: 'string', description: 'eigener Code (optional), z. B. "RAPHI"; sonst zufällig' },
        maxUses: { type: 'number', description: 'max. Anzahl Freischaltungen (optional, sonst unbegrenzt)' },
      },
      required: ['module'],
    },
    run: (a) => api('POST', '/api/admin/codes', a),
  },
  {
    name: 'set_code_active',
    admin: true,
    description: 'Code sperren (active=false) oder entsperren. Gesperrt: Modul verschwindet bei diesen Lernenden beim nächsten Start.',
    inputSchema: { type: 'object', properties: { code: { type: 'string' }, active: { type: 'boolean' } }, required: ['code', 'active'] },
    run: (a) => api('POST', `/api/admin/codes/${encodeURIComponent(a.code)}`, { active: a.active }),
  },
  {
    name: 'list_reports',
    description: 'Fehlermeldungen, Fragen und Wünsche der Lernenden (type fehler/frage/wunsch) inkl. betroffener Karte, Antwort und interner Notiz.',
    inputSchema: { type: 'object', properties: { status: { type: 'string', enum: ['offen', 'in-arbeit', 'erledigt', 'abgelehnt', 'alle'] } } },
    run: (a) => api('GET', `/api/admin/reports?status=${encodeURIComponent(a.status || 'offen')}`),
  },
  {
    name: 'update_report',
    description: 'Status einer Meldung/eines Wunsches setzen, optional Antwort an die einsendende Person (sichtbar in der App) '
      + 'und interne Notiz. Weggelassene Felder bleiben unverändert.',
    inputSchema: {
      type: 'object',
      properties: {
        id: { type: 'number' },
        status: { type: 'string', enum: ['offen', 'in-arbeit', 'erledigt', 'abgelehnt'] },
        reply: { type: 'string', description: 'Antwort an die Lernenden, freundlich und kurz' },
        note: { type: 'string', description: 'interne Notiz, nur im Panel' },
      },
      required: ['id', 'status'],
    },
    run: (a) => api('POST', `/api/admin/reports/${a.id}`, { status: a.status, note: a.note, reply: a.reply }),
  },
  {
    name: 'get_stats',
    description: 'Anonymer Lernfortschritt: Lernende, Pakete (Module) mit gelernten Karten, Aktivität, Fortschritt je Kapitel (nur Gruppen ab der Mindestgruppe).',
    inputSchema: { type: 'object', properties: {} },
    run: () => api('GET', '/api/admin/stats'),
  },
];

/** Rolle des Schlüssels (einmal je Start); bei Fehler nur die Redaktions-Werkzeuge anbieten. */
let roleCache;
function role() {
  roleCache ??= api('GET', '/api/admin/whoami').then((w) => w.role, () => 'editor');
  return roleCache;
}

// ---------- MCP (JSON-RPC 2.0 über stdio, eine Nachricht pro Zeile) ----------
const send = (msg) => process.stdout.write(JSON.stringify({ jsonrpc: '2.0', ...msg }) + '\n');

async function onMessage(msg) {
  const { id, method, params } = msg;
  if (method === 'initialize') {
    return send({ id, result: {
      protocolVersion: params?.protocolVersion || '2025-06-18',
      capabilities: { tools: {} },
      serverInfo: { name: 'karteikarten-admin', version: '1.3.0' },
      instructions: 'Admin-Panel der Karteikarten-App (TÜV SÜD Akademie). Karten bestehen aus Kapitel, Vorderseite, Rückseite, Tags. '
        + 'Beim Ändern immer die bestehende id mitgeben, damit der Lernstand erhalten bleibt. Löschen und replace nur auf ausdrücklichen Wunsch.',
    } });
  }
  if (method === 'tools/list') {
    const admin = (await role()) === 'admin';
    return send({ id, result: { tools: TOOLS.filter((t) => admin || !t.admin).map(({ name, description, inputSchema }) => ({ name, description, inputSchema })) } });
  }
  if (method === 'tools/call') {
    const tool = TOOLS.find((t) => t.name === params?.name);
    if (!tool) return send({ id, error: { code: -32602, message: `Unbekanntes Werkzeug: ${params?.name}` } });
    try {
      const result = await tool.run(params.arguments || {});
      return send({ id, result: { content: [{ type: 'text', text: JSON.stringify(result, null, 1) }] } });
    } catch (e) {
      return send({ id, result: { content: [{ type: 'text', text: `Fehler: ${e.message}` }], isError: true } });
    }
  }
  if (method === 'ping') return send({ id, result: {} });
  if (id !== undefined && !method?.startsWith('notifications/')) send({ id, error: { code: -32601, message: `Methode nicht unterstützt: ${method}` } });
}

createInterface({ input: process.stdin }).on('line', (line) => {
  if (!line.trim()) return;
  let msg;
  try { msg = JSON.parse(line); } catch { return send({ id: null, error: { code: -32700, message: 'Ungültiges JSON' } }); }
  onMessage(msg).catch((e) => send({ id: msg.id ?? null, error: { code: -32603, message: e.message } }));
});
