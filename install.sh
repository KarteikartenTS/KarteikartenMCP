#!/usr/bin/env bash
# Karteikarten-MCP – Komplett-Einrichtung für macOS und Linux – in einer Zeile, ohne Vorkenntnisse.
# © 2026 IB-Thomee GmbH. Alle Rechte vorbehalten – nur für die eigene Anwendung im Karteikartensystem.
#
#   curl -fsSL https://raw.githubusercontent.com/KarteikartenTS/KarteikartenMCP/main/install.sh | bash
#   … | bash -s -- <Einrichtungs-Code aus dem Panel>     (optional, sonst wird gefragt)
#
# Installiert ohne Administratorrechte: Node.js (nur falls nötig, nach ~/.karteikarten/node),
# Claude Code (offizieller Installer), den MCP-Server (npm-Paket karteikarten-mcp) und
# meldet ihn bei Claude Code an. Wiederholbar – ein zweiter Lauf aktualisiert alles.
set -euo pipefail

PANEL="${KARTEIKARTEN_ADMIN_URL:-https://karteikarten-admin.pages.dev}"
KK="$HOME/.karteikarten"
WORK="$HOME/Karteikarten-Redaktion"
NODE_MAJOR=22
CODE_ARG="${1:-}"

say()  { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓ %s\033[0m\n' "$*"; }
fail() { printf '\n\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

printf '\033[1mKarteikarten – Claude für die Kartenpflege einrichten\033[0m\n'
mkdir -p "$KK" "$WORK"

# ---------- 1. Node.js ----------
say "1/4 Node.js"
NODE=""
if command -v node >/dev/null 2>&1 && [ "$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)" -ge 18 ]; then
  NODE="$(command -v node)"; ok "vorhanden: $(node -v)"
elif [ -x "$KK/node/bin/node" ]; then
  NODE="$KK/node/bin/node"; ok "vorhanden: $("$NODE" -v) (Karteikarten-eigen)"
else
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) PLAT=darwin-arm64; EXT=tar.gz ;;
    Darwin-x86_64) PLAT=darwin-x64; EXT=tar.gz ;;
    Linux-x86_64) PLAT=linux-x64; EXT=tar.xz ;;
    Linux-aarch64|Linux-arm64) PLAT=linux-arm64; EXT=tar.xz ;;
    *) fail "System $(uname -s) $(uname -m) wird nicht unterstützt." ;;
  esac
  BASE="https://nodejs.org/dist/latest-v$NODE_MAJOR.x"
  LINE="$(curl -fsSL "$BASE/SHASUMS256.txt" | grep " node-v.*-$PLAT.$EXT\$")" || fail "Node.js-Download nicht gefunden."
  SUM="${LINE%% *}"; FILE="${LINE##* }"
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  echo "  lade $FILE …"
  curl -fsSL "$BASE/$FILE" -o "$TMP/$FILE"
  if command -v shasum >/dev/null 2>&1; then GOT="$(shasum -a 256 "$TMP/$FILE")"; else GOT="$(sha256sum "$TMP/$FILE")"; fi
  [ "${GOT%% *}" = "$SUM" ] || fail "Prüfsumme von Node.js stimmt nicht – Abbruch."
  rm -rf "$KK/node"; mkdir -p "$KK/node"
  tar -xf "$TMP/$FILE" -C "$KK/node" --strip-components 1
  NODE="$KK/node/bin/node"; ok "installiert: $("$NODE" -v) in $KK/node"
fi
export PATH="$(dirname "$NODE"):$PATH"

# ---------- 2. Claude Code ----------
say "2/4 Claude Code"
CLAUDE="$(command -v claude || true)"
[ -z "$CLAUDE" ] && [ -x "$HOME/.local/bin/claude" ] && CLAUDE="$HOME/.local/bin/claude"
if [ -n "$CLAUDE" ]; then ok "vorhanden: $CLAUDE"
else
  curl -fsSL https://claude.ai/install.sh | bash
  CLAUDE="$(command -v claude || echo "$HOME/.local/bin/claude")"
  [ -x "$CLAUDE" ] || fail "Claude Code konnte nicht installiert werden. Anleitung: https://docs.claude.com/en/docs/claude-code/setup"
  ok "installiert: $CLAUDE"
fi

# ---------- 3. MCP-Server ----------
say "3/4 MCP-Server (karteikarten-mcp)"
"$(dirname "$NODE")/npm" install --silent --no-fund --no-audit --prefix "$KK/app" karteikarten-mcp@latest >/dev/null
SERVER="$KK/app/node_modules/karteikarten-mcp/server.js"
[ -f "$SERVER" ] || fail "MCP-Server konnte nicht geladen werden."
ok "Version $("$NODE" -p "require('$KK/app/node_modules/karteikarten-mcp/package.json').version")"
if [ -f "$WORK/CLAUDE.md" ]; then cp "$KK/app/node_modules/karteikarten-mcp/CLAUDE.md" "$WORK/CLAUDE.vorlage.md"
else cp "$KK/app/node_modules/karteikarten-mcp/CLAUDE.md" "$WORK/CLAUDE.md"; fi
ok "Arbeitsordner: $WORK"

# ---------- 4. Persönlicher Schlüssel + Anmeldung bei Claude ----------
say "4/4 Persönlicher Zugang"
KEYFILE="$KK/api-key.txt"
INPUT="$CODE_ARG"
if [ -z "$INPUT" ] && [ -s "$KEYFILE" ]; then
  ok "Schlüssel schon vorhanden ($KEYFILE)"
else
  if [ -z "$INPUT" ]; then
    echo "  Im Panel ($PANEL) anmelden → „Karteneditor“ → „Claude als Helfer“ →"
    echo "  „Mit einem Klick einrichten“ und den kopierten Befehl hier einfügen:"
    read -r -p "  > " INPUT < /dev/tty || true
  fi
  CODE="$(printf '%s' "$INPUT" | grep -oE '[0-9a-f]{32}' | head -1 || true)"
  KEY="$(printf '%s' "$INPUT" | grep -oE 'edk-[0-9a-f]+' | head -1 || true)"
  if [ -z "$KEY" ] && [ -n "$CODE" ]; then
    KEY="$(curl -fsSL "$PANEL/api/mcp/setup/$CODE?format=key" || true)"
  fi
  printf '%s' "$KEY" | grep -qE '^edk-[0-9a-f]+$' || fail "Kein gültiger Code – Link schon benutzt oder abgelaufen? Im Panel neu erzeugen und das Skript erneut starten."
  (umask 077; printf '%s' "$KEY" > "$KEYFILE"); chmod 600 "$KEYFILE"
  ok "Schlüssel gespeichert ($KEYFILE)"
fi

"$CLAUDE" mcp remove --scope user karteikarten >/dev/null 2>&1 || true
"$CLAUDE" mcp add --scope user karteikarten -- "$NODE" "$SERVER" >/dev/null
ok "bei Claude Code angemeldet (Name: karteikarten)"

WHO="$(printf '%s\n%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"install","version":"1"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"whoami","arguments":{}}}' | "$NODE" "$SERVER" 2>/dev/null | grep -o '\\"name\\": \\"[^\\]*' | head -1 | sed 's/.*\\"//' || true)"
[ -n "$WHO" ] && ok "Verbindung steht – angemeldet als: $WHO" || echo "  Hinweis: Verbindungstest ohne Antwort – Internet prüfen, Einrichtung bleibt gespeichert."

printf '\n\033[1;32mFertig!\033[0m Neues Terminal-Fenster öffnen und eingeben:\n\n    cd ~/Karteikarten-Redaktion && claude\n\n'
echo "Beim ersten Start meldest du dich bei Claude an. Test: „Welche Module gibt es?“"
