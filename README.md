# Karteikarten-MCP

MCP-Server für das Karteikartensystem der TÜV SÜD Akademie (Prototyp). Mit ihm kann
[Claude Code](https://docs.claude.com/en/docs/claude-code/setup) Module, Karten und Meldungen im
Admin-Panel lesen und pflegen, auch in großen Mengen.

> **Nur für die eigene Anwendung im Karteikartensystem.** Keine Weitergabe, keine Nutzung für andere
> Zwecke – siehe [LICENSE](LICENSE). Ohne persönlichen Zugang zum Panel funktioniert der Server nicht.

## Wer darf was?

| Zugang | Schlüssel | Werkzeuge |
|---|---|---|
| Redaktion (Professoren, Lektorat) | persönlicher API-Schlüssel `edk-…` aus dem Panel | `whoami`, `list_modules`, `save_module`, `get_cards`, `upsert_cards`, `delete_cards`, `get_card_history`, `list_reports`, `update_report` |
| Admin | Admin-Schlüssel | zusätzlich Codes, Statistik, Modul löschen |

Der Server zeigt nur die Werkzeuge an, die dein Zugang benutzen darf. Jede Änderung landet mit deinem
Namen und Grund in der Korrekturhistorie der Karte.

## Einrichten

**Am einfachsten:** Im Panel anmelden → Tab „Kurse & Karten“ → „Mit Claude Code bearbeiten“ →
**„Mit einem Klick einrichten“**. Der kopierte Befehl legt `~/Karteikarten-Redaktion` mit Server,
`CLAUDE.md` und `.mcp.json` an und hinterlegt deinen Schlüssel.

**Per npm** (Voraussetzungen: Claude Code und Node.js ab Version 18, Schlüssel wie unten in Schritt 2 abgelegt):

```bash
claude mcp add --scope user karteikarten -- npx -y karteikarten-mcp
```

**Manuell** (Voraussetzungen: Claude Code und Node.js ab Version 18):

1. Dieses Repo herunterladen (Code → Download ZIP) oder klonen.
2. Im Panel einen API-Schlüssel erzeugen und in `~/.karteikarten/api-key.txt` speichern
   (Windows: `%USERPROFILE%\.karteikarten\api-key.txt`).
3. Server anmelden:
   ```bash
   claude mcp add --scope user karteikarten -- node /Pfad/zu/KarteikartenMCP/server.js
   ```
   oder im Projektordner `.mcp.json.example` nach `.mcp.json` kopieren.
4. `claude` starten, mit `/mcp` prüfen und z. B. fragen: „Welche Module gibt es?“

Die `CLAUDE.md` erklärt Claude den Kartenaufbau (IDs behalten, Vorschau vor dem Speichern, Grund
angeben, Tag `korrigiert`). Lege sie in den Ordner, in dem du Claude startest.

## Konfiguration

| Variable | Bedeutung |
|---|---|
| `KARTEIKARTEN_ADMIN_TOKEN_FILE` | Pfad zu einer Datei mit dem Schlüssel |
| `KARTEIKARTEN_ADMIN_URL` | Panel-Adresse, Standard `https://karteikarten-admin.pages.dev` |

Den Schlüssel nie in Chats, Dateien im Repo oder Screenshots weitergeben. Im Panel kannst du ihn
jederzeit widerrufen („Zugriff für Claude widerrufen“).
