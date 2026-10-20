# Karteikarten-MCP – Komplett-Einrichtung für Windows („Ich habe keine Ahnung“).
# © 2026 IB-Thomee GmbH. Alle Rechte vorbehalten – nur für die eigene Anwendung im Karteikartensystem.
#
#   irm https://raw.githubusercontent.com/KarteikartenTS/KarteikartenMCP/main/install.ps1 | iex
#   & ([scriptblock]::Create((irm <url>))) <Einrichtungs-Code>     (optional, sonst wird gefragt)
#
# Installiert ohne Administratorrechte: Node.js (nur falls nötig, nach ~\.karteikarten\node),
# Claude Code (offizieller Installer, braucht Git für Windows), den MCP-Server (npm-Paket karteikarten-mcp)
# und meldet ihn bei Claude Code an. Wiederholbar – ein zweiter Lauf aktualisiert alles.
param([string]$Code = '')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Panel = if ($env:KARTEIKARTEN_ADMIN_URL) { $env:KARTEIKARTEN_ADMIN_URL } else { 'https://karteikarten-admin.pages.dev' }
$KK = Join-Path $HOME '.karteikarten'
$Work = Join-Path $HOME 'Karteikarten-Redaktion'
function Say($t) { Write-Host "`n> $t" -ForegroundColor Cyan }
function Ok($t) { Write-Host "  OK  $t" -ForegroundColor Green }
function Fail($t) { Write-Host "`nFEHLER: $t" -ForegroundColor Red; throw $t }

Write-Host 'Karteikarten - Claude fuer die Kartenpflege einrichten' -ForegroundColor White
New-Item -ItemType Directory -Force $KK, $Work | Out-Null

# ---------- 1. Node.js ----------
Say '1/4 Node.js'
$Node = $null
$sys = Get-Command node -ErrorAction SilentlyContinue
if ($sys -and [int](& node -p "process.versions.node.split('.')[0]") -ge 18) { $Node = $sys.Source; Ok "vorhanden: $(& node -v)" }
elseif (Test-Path (Join-Path $KK 'node\node.exe')) { $Node = Join-Path $KK 'node\node.exe'; Ok "vorhanden: $(& $Node -v) (Karteikarten-eigen)" }
else {
  $plat = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
  $base = 'https://nodejs.org/dist/latest-v22.x'
  $line = ((Invoke-WebRequest "$base/SHASUMS256.txt" -UseBasicParsing).Content -split "`n") | Where-Object { $_ -match " node-v.*-$plat\.zip$" } | Select-Object -First 1
  if (-not $line) { Fail 'Node.js-Download nicht gefunden.' }
  $sum, $file = $line.Trim() -split '\s+'
  $tmp = Join-Path $env:TEMP "kk-$([guid]::NewGuid())"; New-Item -ItemType Directory $tmp | Out-Null
  Write-Host "  lade $file ..."
  Invoke-WebRequest "$base/$file" -OutFile (Join-Path $tmp $file) -UseBasicParsing
  if ((Get-FileHash (Join-Path $tmp $file) -Algorithm SHA256).Hash.ToLower() -ne $sum) { Fail 'Pruefsumme von Node.js stimmt nicht - Abbruch.' }
  Expand-Archive (Join-Path $tmp $file) -DestinationPath $tmp -Force
  if (Test-Path (Join-Path $KK 'node')) { Remove-Item -Recurse -Force (Join-Path $KK 'node') }
  Move-Item (Join-Path $tmp ($file -replace '\.zip$', '')) (Join-Path $KK 'node')
  Remove-Item -Recurse -Force $tmp
  $Node = Join-Path $KK 'node\node.exe'; Ok "installiert: $(& $Node -v) in $KK\node"
}
$NodeDir = Split-Path $Node
$env:Path = "$NodeDir;$env:Path"

# ---------- 2. Claude Code ----------
Say '2/4 Claude Code'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Write-Host '  Claude Code braucht Git fuer Windows - Installation ueber winget ...'
  try { winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements | Out-Null } catch { }
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') + ";$NodeDir"
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'Git fehlt. Bitte von https://git-scm.com/download/win installieren und das Skript erneut starten.' }
}
$Claude = (Get-Command claude -ErrorAction SilentlyContinue).Source
if (-not $Claude -and (Test-Path "$HOME\.local\bin\claude.exe")) { $Claude = "$HOME\.local\bin\claude.exe" }
if ($Claude) { Ok "vorhanden: $Claude" }
else {
  Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
  $Claude = (Get-Command claude -ErrorAction SilentlyContinue).Source
  if (-not $Claude) { $Claude = "$HOME\.local\bin\claude.exe" }
  if (-not (Test-Path $Claude)) { Fail 'Claude Code konnte nicht installiert werden. Anleitung: https://docs.claude.com/en/docs/claude-code/setup' }
  Ok "installiert: $Claude"
}

# ---------- 3. MCP-Server ----------
Say '3/4 MCP-Server (karteikarten-mcp)'
& (Join-Path $NodeDir 'npm.cmd') install --silent --no-fund --no-audit --prefix (Join-Path $KK 'app') karteikarten-mcp@latest | Out-Null
$Pkg = Join-Path $KK 'app\node_modules\karteikarten-mcp'
$Server = Join-Path $Pkg 'server.js'
if (-not (Test-Path $Server)) { Fail 'MCP-Server konnte nicht geladen werden.' }
Ok "Version $((Get-Content (Join-Path $Pkg 'package.json') -Raw | ConvertFrom-Json).version)"
$md = if (Test-Path (Join-Path $Work 'CLAUDE.md')) { 'CLAUDE.vorlage.md' } else { 'CLAUDE.md' }
Copy-Item (Join-Path $Pkg 'CLAUDE.md') (Join-Path $Work $md) -Force
Ok "Arbeitsordner: $Work"

# ---------- 4. Persönlicher Schlüssel + Anmeldung bei Claude ----------
Say '4/4 Persoenlicher Zugang'
$KeyFile = Join-Path $KK 'api-key.txt'
$In = $Code
if (-not $In -and (Test-Path $KeyFile) -and (Get-Item $KeyFile).Length -gt 0) { Ok "Schluessel schon vorhanden ($KeyFile)" }
else {
  if (-not $In) {
    Write-Host "  Im Panel ($Panel) anmelden -> 'Kurse & Karten' -> 'Claude als Helfer' ->"
    Write-Host "  'Mit einem Klick einrichten' und den kopierten Befehl hier einfuegen:"
    $In = Read-Host '  >'
  }
  $Key = ([regex]::Match($In, 'edk-[0-9a-f]+')).Value
  $Hex = ([regex]::Match($In, '[0-9a-f]{32}')).Value
  if (-not $Key -and $Hex) { try { $Key = (Invoke-WebRequest "$Panel/api/mcp/setup/$Hex`?format=key" -UseBasicParsing).Content.Trim() } catch { } }
  if ($Key -notmatch '^edk-[0-9a-f]+$') { Fail 'Kein gueltiger Code - Link schon benutzt oder abgelaufen? Im Panel neu erzeugen und das Skript erneut starten.' }
  Set-Content -NoNewline -Path $KeyFile -Value $Key
  Ok "Schluessel gespeichert ($KeyFile)"
}

& $Claude mcp remove --scope user karteikarten 2>$null | Out-Null
& $Claude mcp add --scope user karteikarten -- $Node $Server | Out-Null
Ok 'bei Claude Code angemeldet (Name: karteikarten)'

$req = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"install","version":"1"}}}' + "`n" +
       '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"whoami","arguments":{}}}'
try {
  $out = $req | & $Node $Server 2>$null | Select-Object -Last 1 | ConvertFrom-Json
  $who = ($out.result.content[0].text | ConvertFrom-Json).name
  Ok "Verbindung steht - angemeldet als: $who"
} catch { Write-Host '  Hinweis: Verbindungstest ohne Antwort - Internet pruefen, Einrichtung bleibt gespeichert.' }

Write-Host "`nFertig! Neues PowerShell-Fenster oeffnen und eingeben:`n`n    cd ~\Karteikarten-Redaktion; claude`n" -ForegroundColor Green
Write-Host "Beim ersten Start meldest du dich bei Claude an. Test: 'Welche Module gibt es?'"
