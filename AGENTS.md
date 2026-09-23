# Projektregeln für BikeNavi

- Änderungen an Verhalten, Datenformaten, Betrieb und Oberfläche im `CHANGELOG.md` dokumentieren. Nach einem veröffentlichten Release neue Einträge zunächst unter „Unveröffentlicht“ sammeln; vorhandene Release-Einträge nicht als Protokoll für spätere Änderungen überschreiben.
- Architektur- und Bedienungsdokumentation bei betroffenen Änderungen mitführen. Bei sichtbaren UI-Änderungen auch die betroffenen Bilder in `docs/BILDSCHIRME.md` aktualisieren.
- Versionsnummern, Buildnummer, Git-Tags und GitHub-Releases nach `docs/VERSIONIERUNG.md` pflegen. Ein GitHub-Release ist kein automatisches Geräte- oder Pi-Deployment.
- Änderungen mit den passenden Tests und Builds prüfen; tatsächliche Ergebnisse und verbleibende Grenzen dokumentieren. Simulatorprüfungen nicht als Feldtest ausgeben.
- Vorhandene lokale Änderungen erhalten und vor einem Commit prüfen. Zugangsdaten, `.env`, private Fahrtaufzeichnungen, lokale Datenbanken, Diagnoseprotokolle und Buildprodukte nicht versionieren. Für öffentliche Bilder ausschließlich gekennzeichnete Beispieldaten verwenden.
- Neue Swift-Dateien über `scripts/generate_project.py` in das Xcode-Projekt aufnehmen; dauerhafte Projekteinstellungen ebenfalls im Generator ändern.
