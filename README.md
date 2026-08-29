# JP Coding

Ein Coding-Agent für macOS mit der vollen Werkzeugkiste von Claude Code — aber über
frei nutzbare Modelle bei NVIDIA NIM statt über die Anthropic-API. Eigene Oberfläche,
eigene Konfiguration, komplett getrennt von einer eventuell vorhandenen Claude-Installation.

![macOS](https://img.shields.io/badge/macOS-12%2B-black) ![License](https://img.shields.io/badge/license-MIT-green)

---

## Was es kann

- **Chat mit echtem Agenten** — liest und schreibt Dateien, führt Befehle aus, arbeitet
  mehrstufig. Es ist Claude Code unter der Haube, nur mit anderem Modell-Anbieter.
- **Modell frei wählbar** — vier vorgetestete Modelle plus alle weiteren, die NVIDIA anbietet.
  Ein Klick auf `TEST` prüft live; fällt ein Modell aus, wechselt die App selbstständig.
- **Skills** — an- und abschaltbar, eigene importierbar.
- **Dateianhänge** — Dateien an eine Nachricht hängen, der Agent liest sie.
- **Pro Chat ein Arbeitsordner** — wird beim Anlegen gewählt.
- **Alles lokal** — Chats, Sessions und Einstellungen liegen im App-Paket.
- **Sandbox** — der Agent läuft in einer macOS-Sandbox ohne Schreibrechte auf
  `~/.claude`, Shell-Profile oder die Schlüsseldatei.

## Voraussetzungen

| | |
|---|---|
| macOS | 12 oder neuer |
| Node.js | für die Claude-Code-CLI ([nodejs.org](https://nodejs.org)) |
| NVIDIA-NIM-Schlüssel | kostenlos unter [build.nvidia.com](https://build.nvidia.com/settings/api-keys) |

Alles Weitere — `uv`, den Proxy und den Autostart — installiert die App selbst.

## Installation

1. `JP Coding.app` nach **Programme** ziehen.
2. Beim ersten Start: **Rechtsklick → Öffnen** (die App ist nicht signiert, ein normaler
   Doppelklick wird von macOS blockiert). Falls die Warnung bestehen bleibt:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/JP Coding.app"
   ```
3. Im Willkommensfenster den NVIDIA-Schlüssel eintragen und **Einrichten und starten**
   klicken. Der Rest läuft automatisch — der Fortschritt steht im Log darunter.

## Bedienung

| Aktion | Wo |
|---|---|
| Neuer Chat | Seitenleiste, Ordner wird abgefragt |
| Modell wechseln | Kopfzeile |
| Modell prüfen / reparieren | `TEST` in der Kopfzeile |
| Datei anhängen | `+` links im Eingabefeld |
| Abbrechen | roter Knopf während der Ausführung |
| Chat exportieren | `EXPORT`, ergibt eine Markdown-Datei |
| Skills, API-Schlüssel | unten in der Seitenleiste |

Berechtigungen stehen auf **Vollzugriff**: Der Agent darf im gewählten Ordner
alles. Das ist Absicht — ein Coding-Agent ohne Shell ist nutzlos. Geschützt wird
nicht durch Nachfragen, sondern durch die Sandbox. Ein `git init` im Projektordner
ist trotzdem eine gute Idee.

## Selbst bauen

```bash
git clone https://github.com/DEIN-NAME/jp-coding.git
cd jp-coding
./build.sh                                    # baut nach /Applications
./build.sh ./dist                             # baut nach ./dist
./build.sh /Applications --with-skills ~/.claude/skills   # mit eigenen Skills
```

Das Skript braucht nur macOS-Bordmittel (`python3`, `sips`, `iconutil`).

### Aufbau

```
src/
  Info.plist            App-Metadaten
  launcher.sh           startet Backend und Fenster
  icon.py               erzeugt das Icon ohne externe Bibliotheken
  bin/models.json       vorgetestete Modelle, Reihenfolge = Fallback-Kette
  server/jp_server.py   Backend (nur Standardbibliothek)
  server/ui/            Oberfläche
```

Der Backend-Server spricht mit dem lokalen Proxy
([free-claude-code](https://github.com/Alishahryar1/free-claude-code)), der die
Anthropic-Schnittstelle auf NVIDIA NIM und andere Anbieter übersetzt. Die
Claude-Code-CLI läuft als Kindprozess in `sandbox-exec`.

## Sicherheit

Der Agent bekommt volle Werkzeugrechte, deshalb ist die Sandbox nicht optional.
Gesperrt sind auf Kernel-Ebene: Schreiben nach `~/.claude`, in Shell-Profile,
in `~/.fcc` und ins App-Paket selbst, sowie Lesen von `~/.fcc/.env`, `~/.ssh` und `~/.aws`.

Die Sandbox schützt Dateien, nicht das Netzwerk: Was im Arbeitsordner liegt, kann an
den Modellanbieter gehen. Und `sandbox-exec` ist von Apple als veraltet markiert —
fällt es weg, bricht der Start mit Fehler ab statt still ungeschützt zu laufen.

## Fehlersuche

| Symptom | Ursache |
|---|---|
| Fenster bleibt leer | Backend-Log: `.../JP Coding.app/Contents/Resources/JPData/server.log` |
| „Proxy offline" | Einstellungen → System → *Proxy neu starten* |
| Modell antwortet nicht | `TEST` — die App sucht dann selbst ein funktionierendes |
| Kein Modell erreichbar | Schlüssel prüfen oder NVIDIA-Kontingent erschöpft |

## Lizenz

MIT — siehe [LICENSE](LICENSE).
