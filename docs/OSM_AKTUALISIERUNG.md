# Automatische OSM-Aktualisierung auf dem Pi

Der Pi hält den **Kroatien-Auszug** selbst aktuell. Dafür laufen `bikenavi-osm-update.timer` und der zugehörige Systemdienst unabhängig von Mac, Codex und iPhone. Quelle ist [Geofabrik Kroatien](https://download.geofabrik.de/europe/croatia.html), Datenlizenz ODbL. Andere Länder werden dadurch nicht automatisch installiert.

## Zeitplan und Fehlerverhalten

- Täglich **05:15 Uhr plus bis zu 30 Minuten Zufallsverzögerung**, in der auf dem Pi eingestellten Ortszeit. `Persistent=true` holt eine während einer Abschaltung verpasste Ausführung beim nächsten Aktivieren nach.
- Bei Fehlern versucht systemd den Lauf nach **einer Stunde** erneut. Ein Lauf darf höchstens zwei Stunden dauern; anschließend wird auch sein Importcontainer entfernt. Der Job verwendet höchstens einen CPU-Kern. Die bestehende Einschränkung der Pi-Kernel-Speicherlimits bleibt bestehen.
- Eine Prozesssperre verhindert parallele Importe. Der laufende API-Container bindet die Karten weiterhin nur lesend ein. Der separate Importcontainer nutzt für Geofabrik das Hostnetz des Pi, ohne einen Dienstport zu öffnen. Er kann ausschließlich den Kartenordner beschreiben; Anwendungsskripte und Container-Dateisystem bleiben lesend.
- Zunächst wird nur die kleine Prüfsummendatei abgefragt. Bei unveränderter Quelle werden Alter und vorhandener Index geprüft, ohne das PBF erneut zu laden oder zu importieren.
- Neue Auszüge dürfen höchstens **sieben Tage alt** sein. Bleibt die Quelle länger stehen, erscheint ein Fehler im Dienstjournal und in der Statusdatei. Der bisherige gültige Stand bleibt verfügbar; die bestehende harte **30-Tage-Grenze** des Regionsendpunkts wird nicht verlängert. Längere Anbieter- oder Netzausfälle können daher weiterhin einen Eingriff erfordern.

## Sichere Freigabe und Speicher

`scripts/update_offline_extract.py` lädt PBF und Landespolygon per HTTPS in `server/data/osm/.updates/staging/`. Die PBF-Prüfsumme muss vor und nach dem Download übereinstimmen; Dateigrößen und Downloadzeiten sind begrenzt. Der OSM-Quellzeitpunkt darf nicht zurücklaufen. Vor dem Import müssen mindestens 5 GiB beziehungsweise das Zwölffache der PBF-Größe frei sein.

Der vorhandene Importer prüft vollständige Wegreferenzen und SQLite-Integrität. Anschließend werden SHA-256, Quellmetadaten, Abdeckung und ein tatsächlich kompilierbarer Radgraph bei Tisno geprüft. Der Kroatien-Index muss mindestens zehn Millionen Nodes und eine Million Ways enthalten; gegenüber einem vorherigen automatischen Index darf keine dieser Anzahlen um mehr als 20 Prozent fallen. Auffällige Änderungen werden zur Prüfung zurückgehalten.

Erst danach wird der neue Index mit einem eigenen Dateinamen installiert und sein JSON-Manifest atomar freigegeben. Dateien und Verzeichniseinträge werden vor beziehungsweise nach der Freigabe synchronisiert. Ein abgebrochener Import ersetzt keinen aktiven Index; beim nächsten Lauf wird sein separater Arbeitsordner aufgeräumt.

Mindestens die **zwei jüngsten automatischen Generationen** und alle weniger als sieben Tage alten Dateien bleiben erhalten. Bei täglichen Änderungen bedeutet das ungefähr eine Woche Rückfallstände, aktuell etwa 12–16 GiB zuzüglich manueller Bestände und Arbeitsraum. Nur Dateien mit dem vom Updater erzeugten Präfix `croatia-auto-` werden bereinigt. Manuell installierte Quellen, darunter der erste Kroatien-Index, bleiben erhalten. Die Woche Abstand schützt auch laufende Leser vor der Entfernung gerade abgelöster Dateien.

Neue Quellzeitpunkte verdrängen ältere Server-Cachekacheln beim nächsten Abruf. Kann die neue Quelle nicht geprüft werden, bleibt eine noch gültige Cachekachel verfügbar. Bereits auf dem iPhone gespeicherte Regionen ändern sich erst über **Aktualisieren**; dabei bleibt die bisherige Region bis zum vollständigen Download erhalten.

## Betrieb und Diagnose

`scripts/deploy_pi.py` überträgt Importer, Updater und Dienstdateien, baut das passende Backend-Image und installiert beziehungsweise aktiviert den Timer und stößt eine erste Prüfung ohne Warten auf den nächsten Morgen an. Bestehende Kartendaten bleiben erhalten. Es werden weder Zugangsdaten für den Updater noch eine zusätzliche öffentliche Schnittstelle benötigt.

```sh
ssh pi5 'systemctl list-timers bikenavi-osm-update.timer --no-pager'
ssh pi5 'systemctl status bikenavi-osm-update.service --no-pager'
ssh pi5 'sudo -n journalctl -u bikenavi-osm-update.service -n 80 --no-pager'
ssh pi5 'cat /srv/bikenavi/server/data/osm/.updates/status.json'
```

Ein erfolgreich abgeschlossener Einmaldienst ist anschließend **inactive (dead)** mit `Result=success`; das ist normal. Entscheidend sind der aktive Timer, die Statusdatei und der letzte Abschluss im Journal. `result=updated` bedeutet Freigabe, `unchanged` eine geprüfte unveränderte Quelle, `failed` einen Fehler. `checkedAt` bezeichnet den Beginn der Prüfung. Während eines Laufs zeigt die Statusdatei noch den vorherigen Abschluss; den laufenden Zustand zeigt systemd. Ein harter Prozessabbruch kann die vorherige Statusdatei stehen lassen, daher bei Fehlern immer das Journal prüfen. Es wird keine automatische Nachricht versendet.

Sofort einen Lauf anstoßen:

```sh
ssh pi5 'sudo -n systemctl start --no-block bikenavi-osm-update.service'
```

Einen echten Regionsdownload samt Cache und Prüfsummen prüfen:

```sh
.venv/bin/python scripts/check_region_download.py --latitude 43.775 --longitude 15.625 --radius 2 --refresh
```

Zum Anhalten erst den Timer, dann den Dienst stoppen. Ein laufender Import wird dabei abgebrochen; der aktive Index bleibt erhalten:

```sh
ssh pi5 'sudo -n systemctl stop bikenavi-osm-update.timer bikenavi-osm-update.service'
```

Für einen kontrollierten Rückfall nach einem fachlich fehlerhaften Update den in `status.json` genannten Index ermitteln und beim zugehörigen gleichnamigen JSON-Manifest die Endung `.json` in `.json.disabled` umbenennen. Den Index zunächst behalten. Der Leser wählt dann die jüngste verbleibende gültige Quelle; in der App **Aktualisieren** verwenden, um auch bereits erzeugte Cache-/Regionspakete zu ersetzen. Ein Rückfall auf Daten älter als 30 Tage ist ausgeschlossen. Nach Behebung den Timer mit `sudo systemctl start bikenavi-osm-update.timer` wieder aktivieren und einen manuellen Lauf prüfen.

Die konkrete Erstabnahme steht in [UMSETZUNG.md](UMSETZUNG.md#automatische-osm-aktualisierung--21-oktober-2026). Dies ersetzt keine reale Fahr- oder Langzeitabnahme.
