# JP Coding

Eine native macOS-App mit der vollen Werkzeugkiste von Claude Code — aber über frei
nutzbare Modelle bei NVIDIA NIM statt über die Anthropic-API. Kein Browser-Fenster,
kein Electron: SwiftUI, ein 2-MB-Binary.

![macOS](https://img.shields.io/badge/macOS-14%2B-black) ![Swift](https://img.shields.io/badge/Swift-6-orange) ![License](https://img.shields.io/badge/license-MIT-green)

---

## Was es kann

**Agent** — liest und schreibt Dateien, führt Befehle aus, arbeitet mehrstufig. Es ist
Claude Code unter der Haube, nur mit anderem Modell-Anbieter. Werkzeugaufrufe erscheinen
als Chips im Verlauf.

**Modellwahl, die nicht lügt** — die App testet Modelle selbst gegen den Proxy und zeigt
pro Eintrag den echten Zustand: grüner Haken mit Antwortzeit, rotes Kreuz mit Begründung,
oder ehrliches Fragezeichen. Beim Wechsel wird sofort geprüft; antwortet das Modell nicht,
sucht die App automatisch ein funktionierendes. Ein Fehlschlag wird einmal wiederholt,
bevor ein Modell als defekt gilt — NVIDIAs Gratis-Modelle schwanken von Lauf zu Lauf.

### Mitgelieferter Grundstock

Sieben Modelle, jedes **im echten Agenten** geprüft — also durch die Claude-Code-CLI mit
vollem System-Prompt und allen Werkzeugdefinitionen, nicht nur mit einer kleinen
API-Anfrage. Genau das ist der Unterschied: Modelle bestehen den kleinen Test und
scheitern trotzdem am Agenten.

| Modell | Antwort im Agenten |
|---|---|
| gpt-oss-120b | 4,3 s |
| nemotron-3-nano-30b | 2,8 s |
| gpt-oss-20b | 3,1 s |
| nemotron-3-super-120b | 5,1 s |
| nemotron-3-nano-omni-reasoning | 7,5 s |
| nemotron-3.5-lightning-30b | 8,3 s |
| llama-3.2-11b-vision | 29,5 s |

Alle laufen mit abgeschaltetem Reasoning (`[fast]`) — das ist für Agentenbetrieb
durchweg die bessere Variante.

Von 63 Chat-Modellen, die NVIDIA listet, sind je nach Tageszeit nur 8 bis 13 erreichbar;
der Rest gibt `HTTP 404 – Function not found` oder `410 Gone`. Nicht agententauglich sind
DeepSeek-v4, Mistral-Large, Qwen3, Llama-Nemotron, Kimi (`Invalid request sent to
provider`), MiniMax-M3 (Anbieter-Limit) und nemotron-3-ultra.

**Mehr Modelle bekommst du über weitere Anbieter**: Groq, Cerebras, Google Gemini und
OpenRouter haben großzügige Gratis-Kontingente, Z.AI liefert GLM. Schlüssel in den
Einstellungen eintragen — die Modelle erscheinen dann von allein in der Liste.

**Slash-Befehle im Eingabefeld** — `/` öffnet die Liste, Pfeiltasten navigieren, Tab
vervollständigt. Fünfzehn App-Befehle (`/new`, `/model`, `/code`, `/preview`, `/skills` …)
plus alle Befehle, die die Claude-Code-CLI meldet — inklusive deiner Skills.

**Code-Editor** — Dateibaum des Projektordners, Editor mit Monospace und Undo, Sichern,
Bildvorschau. Ordner wie `node_modules` und `.git` werden ausgeblendet.

**Live-Vorschau** — WebKit-Ansicht auf eine Datei im Projekt oder eine Adresse wie
`http://localhost:3000`. Findet `index.html` von allein und lädt bei Dateiänderung
automatisch neu.

**Skills** — an- und abschaltbar, eigene importierbar, Suche.

**Dateianhänge**, **Chat-Export als Markdown**, **Stop-Knopf**, **Eingabeverlauf** mit
Pfeil-hoch, **pro Chat ein Arbeitsordner**.

**Sandbox** — der Agent läuft in `sandbox-exec` ohne Schreibrechte auf `~/.claude`,
Shell-Profile, `~/.fcc` und das App-Paket selbst.

## Voraussetzungen

| | |
|---|---|
| macOS | 14 oder neuer (Apple Silicon) |
| Node.js | für die Claude-Code-CLI ([nodejs.org](https://nodejs.org)) |
| NVIDIA-NIM-Schlüssel | kostenlos unter [build.nvidia.com](https://build.nvidia.com/settings/api-keys) |

Alles Weitere — `uv`, den Proxy und den Autostart — installiert die App selbst.

## Installation

1. `JP Coding.app` nach **Programme** ziehen.
2. Beim ersten Start **Rechtsklick → Öffnen** (die App ist nicht notarisiert). Falls die
   Warnung bleibt:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/JP Coding.app"
   ```
3. Im Willkommensfenster den NVIDIA-Schlüssel eintragen und **Einrichten und starten**.
   Der Fortschritt steht im Log darunter.

Beim ersten Start prüft die App den mitgelieferten Modell-Grundstock im Hintergrund, damit
die Liste sofort echte Zustände zeigt.

## Bedienung

| Aktion | Wo |
|---|---|
| Neuer Chat | Seitenleiste oder `/new` — Ordner wird abgefragt |
| Modell wechseln | Kopfzeile oder `/model` |
| Modelle durchtesten | im Modell-Fenster: *Grundstock testen* / *ALLE testen* |
| Editor | `CODE` oder `/code` |
| Live-Vorschau | `VORSCHAU` oder `/preview` |
| Datei anhängen | Büroklammer oder `/attach` |
| Abbrechen | roter Knopf oder `/stop` |
| Alle Befehle | `/help` |

Berechtigungen stehen auf **Vollzugriff**: Der Agent darf im gewählten Ordner alles.
Das ist Absicht — ein Coding-Agent ohne Shell ist nutzlos. Geschützt wird nicht durch
Nachfragen, sondern durch die Sandbox. Ein `git init` im Projektordner ist trotzdem
eine gute Idee.

## Selbst bauen

```bash
git clone https://github.com/jakobxtb/jp-coding.git
cd jp-coding
./build.sh                                                # nach /Applications
./build.sh ./dist                                         # nach ./dist
./build.sh /Applications --with-skills ~/.claude/skills    # mit eigenen Skills
```

Braucht nur die Xcode Command Line Tools (`swiftc`, `sips`, `iconutil`) — kein Xcode-Projekt.

### Aufbau

```
src/mac/
  App.swift          Einstiegspunkt, AppDelegate
  Model.swift        Datentypen, Store, Pfade, Protokoll
  Backend.swift      Proxy, .env, Setup-Installation, Skills
  ModelProbe.swift   Modelltests mit gespeichertem Ergebnis
  Runner.swift       Claude-Code-Prozess in der Sandbox, stream-json
  ContentView.swift  Hauptfenster
  Composer.swift     Eingabefeld mit CLI-Tastatur, Slash-Befehle
  Workspace.swift    Dateibaum, Editor, Live-Vorschau
  ModelSheet.swift   Modellauswahl mit Zustandsanzeige
  Sheets.swift       Einstellungen, Skills, Setup, Hilfe
  Markdown.swift     Markdown zu SwiftUI
  Theme.swift        Farben, Glasflächen, Hintergrund
```

Die App spricht mit dem lokalen Proxy
([free-claude-code](https://github.com/Alishahryar1/free-claude-code)), der die
Anthropic-Schnittstelle auf NVIDIA NIM und andere Anbieter übersetzt. Die Claude-Code-CLI
läuft als Kindprozess in `sandbox-exec`, ihre `stream-json`-Ausgabe wird zeilenweise
geparst.

## Sicherheit

Gesperrt auf Kernel-Ebene: Schreiben nach `~/.claude`, in Shell-Profile, in `~/.fcc` und
ins App-Paket, sowie Lesen von `~/.fcc/.env`, `~/.ssh` und `~/.aws`. Nachgewiesen mit
`--dangerously-skip-permissions`: Der Agent prallt mit `operation not permitted` ab.

Die Sandbox schützt Dateien, nicht das Netzwerk: Was im Arbeitsordner liegt, kann an den
Modellanbieter gehen. `sandbox-exec` ist von Apple als veraltet markiert — fällt es weg,
bricht der Start mit Fehler ab statt still ungeschützt zu laufen.

## Fehlersuche

| Symptom | Ursache |
|---|---|
| Modell antwortet nicht | Im Modell-Fenster *TEST* — NVIDIAs Gratis-Modelle fallen häufig aus |
| „Proxy offline" | Einstellungen → System → *Proxy neu starten* |
| Kein Modell erreichbar | Schlüssel prüfen oder NVIDIA-Kontingent erschöpft |
| Sonstiges | Protokoll: `~/Library/Application Support/JP Coding/debug.log` |

Chats und Einstellungen liegen im App-Paket unter `Contents/Resources/JPData`. Ein Neubau
löscht sie.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
