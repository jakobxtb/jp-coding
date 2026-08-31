# JP Coding

Eine native macOS-App mit der vollen Werkzeugkiste von Claude Code — aber über den
Modell-Anbieter deiner Wahl statt über die Anthropic-API. Kein Browser-Fenster,
kein Electron: SwiftUI, ein 2-MB-Binary.

![macOS](https://img.shields.io/badge/macOS-14%2B-black) ![Swift](https://img.shields.io/badge/Swift-6-orange) ![License](https://img.shields.io/badge/license-MIT-green)

---

## Was es kann

**Agent** — liest und schreibt Dateien, führt Befehle aus, arbeitet mehrstufig. Es ist
Claude Code unter der Haube, nur mit anderem Modell-Anbieter. Werkzeugaufrufe erscheinen
als Chips im Verlauf.

**Dreizehn Anbieter, eine Oberfläche** — NVIDIA NIM, Groq, Cerebras, OpenRouter, Google
Gemini, Z.AI (GLM), Moonshot, DeepSeek, Mistral, Codestral, Fireworks, OpenCode und Wafer.
In der Modellauswahl schaltest du oben zwischen ihnen um; die Liste zeigt dann nur die
Modelle dieses Anbieters. Ein Punkt je Anbieter sagt, woran du bist: grün mit Anzahl heißt
Modelle verfügbar, grau mit `–` heißt kein Schlüssel hinterlegt.

Trägst du in den Einstellungen einen Schlüssel ein, startet der Proxy neu und die Modelle
erscheinen von allein — es gibt keine gepflegte Liste, die veralten könnte. **Groq und
Cerebras haben großzügige Gratis-Kontingente und deutlich zuverlässigeres Tool-Calling
als NVIDIAs Gratis-Modelle.**

**Modellwahl, die nicht lügt** — die App testet jedes Modell über die echte Claude-Code-CLI
und verlangt einen **echten Werkzeugaufruf**: Das Modell muss eine Datei anlegen. Wer nur
Text zurückgibt, ist als Agent nutzlos und wird rot markiert. Beim Wechsel wird sofort
geprüft; fällt das Modell aus, sucht die App automatisch ein funktionierendes. Ein
Fehlschlag wird einmal wiederholt — Gratis-Modelle schwanken von Lauf zu Lauf.

**Kosten und Eignung pro Modell** — jede Zeile zeigt eine Eignungsnote von 1 bis 10 fürs
Programmieren und die geschätzten Kosten pro Nachricht, berechnet aus den echten
OpenRouter-Preisen. Standardmäßig ist nach Eignung sortiert. Das macht den Unterschied
sichtbar: `claude-opus-4.5` liegt bei ~$0,24 pro Nachricht, `gemini-2.5-flash` bei
~$0,026, `gpt-oss-20b` bei ~$0,001.

**Verbrauch im Blick** — unter jeder Antwort stehen Eingabe- und Ausgabe-Token und die
tatsächlichen Kosten. In der Seitenleiste laufen der OpenRouter-Verbrauch, das
Restguthaben und die Summe des aktuellen Chats mit.

**Arbeitsanzeige** — während der Agent läuft, siehst du die verstrichene Zeit, ob er
gerade nachdenkt, schreibt oder ein Werkzeug benutzt, und wie viel Text schon da ist.

**Konnektoren (MCP)** — Einstellungen → Info → *Konnektoren-Datei anlegen* erzeugt eine
`mcp.json` im App-Paket, in der gleichen Form wie in Claude Code. Sie wird per
`--mcp-config` durchgereicht und ist von deiner echten Claude-Konfiguration getrennt.

Der Schalter **Reasoning** entscheidet, ob das Modell mit oder ohne Denkphase läuft. Aus ist
für Agentenbetrieb fast immer besser: gpt-oss-20b antwortet damit in 2,4 s statt 62 s.

**Slash-Befehle im Eingabefeld** — `/` öffnet die Liste, Pfeiltasten navigieren, Tab
vervollständigt. Fünfzehn App-Befehle (`/new`, `/model`, `/code`, `/preview`, `/skills` …)
plus alle Befehle, die die Claude-Code-CLI meldet — inklusive deiner Skills.

**Code-Editor** — Dateibaum, Tabs für offene Dateien, Syntaxfarben für Swift, JS/TS,
Python, HTML, CSS und Shell, Tab-Einrückung, Sichern, Bildvorschau. Ordner wie
`node_modules` und `.git` bleiben ausgeblendet. Zeilennummern hat er noch nicht.

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
| Ein Anbieter-Schlüssel | z. B. [OpenRouter](https://openrouter.ai/keys) (alle großen Modelle, Guthaben), [Groq](https://console.groq.com/keys) oder [NVIDIA NIM](https://build.nvidia.com/settings/api-keys) (beide gratis) |

Alles Weitere — `uv`, den Proxy und den Autostart — installiert die App selbst.

## Installation

1. `JP Coding.app` nach **Programme** ziehen.
2. Beim ersten Start **Rechtsklick → Öffnen** (die App ist nicht notarisiert). Falls die
   Warnung bleibt:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/JP Coding.app"
   ```
3. Im Willkommensfenster einen Anbieter-Schlüssel eintragen und **Einrichten und starten**.
   Der Fortschritt steht im Log darunter. Weitere Anbieter jederzeit unter
   Einstellungen → API-Schlüssel nachtragen.

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
| Kein Modell erreichbar | Schlüssel prüfen oder Kontingent erschöpft |
| OpenRouter: alle Modelle geben 404 | Im OpenRouter-Konto unter [Preferences](https://openrouter.ai/settings/preferences) die *Allowed Providers* prüfen — ist dort ein einzelner Anbieter eingetragen, lehnt OpenRouter alle anderen Modelle ab |
| Sonstiges | Protokoll: `~/Library/Application Support/JP Coding/debug.log` |

Chats und Einstellungen liegen im App-Paket unter `Contents/Resources/JPData`. Ein Neubau
löscht sie.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
