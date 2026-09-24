# Versionierung und Releases

## Version 0.2.0

Datum: 23. September 2026. App und Live-Aktivität: **0.2.0 (2)**. Backend: **0.2.0**. Git-Tag: **v0.2.0**. Entwicklungsfassung vor 1.0, kein App-Store-Release.

- [Änderungsprotokoll](../CHANGELOG.md)
- [GitHub-Releases](https://github.com/MichaelHein65/BikeNavi/releases)
- [Bildschirmgalerie](BILDSCHIRME.md)

`VERSION` ist die Vorgabe für das Xcode-Generierungsskript. `CURRENT_PROJECT_VERSION` im Skript ist die fortlaufende iOS-Buildnummer. Die Einstellungen lesen Version und Buildnummer aus dem tatsächlich gebauten App-Bundle. Der Server führt seine Paketversion in `server/pyproject.toml` und seine API-Version in `server/bikenavi/__init__.py`; beide werden bei einem Release gemeinsam angehoben.

## Entwicklungsstand nach 0.2.0

Am 24. September 2026 wurde die Korrektur für freigegebene Schranken an der Tisno-Brücke als Debug-App auf Michaels iPhone 15 Pro installiert und der Pi aktualisiert. Michael hat die funktionierende Routenplanung anschließend bestätigt. 90 Swift-Tests, 45 Backend-Tests, Simulator- und signierter Gerätebuild sowie die Live-Prüfungen am Pi waren erfolgreich. Details stehen unter „Unveröffentlicht“ im [Änderungsprotokoll](../CHANGELOG.md).

App-/Backend-Version bleiben 0.2.0, iOS-Buildnummer 2. Diese installierte Entwicklungsfassung enthält zusätzliche Änderungen gegenüber dem unveränderten Release-Tag `v0.2.0`. Die Kachel-Compilerrevision 2 ist davon unabhängig. Es wurde kein neuer Git-Tag oder GitHub-Release erstellt.

## Ablauf für weitere Releases

1. Alle vorgesehenen Änderungen prüfen und in `CHANGELOG.md` mit Datum, Verhalten, Grenzen und Tests dokumentieren.
2. `VERSION`, Buildnummer im Generierungsskript sowie beide Server-Versionsangaben aktualisieren. Versionsprüfung im Backend-Test anpassen.
3. `python3 scripts/generate_project.py` ausführen. App und Live-Aktivität erhalten dieselbe Version.
4. Swift- und Backend-Tests, Simulator-/Gerätebuild und für die Änderungen relevante UI-Tests ausführen. Ergebnisse und verbleibende Grenzen festhalten.
5. Bei UI-Änderungen die Galerie aus einem separaten Simulator mit Beispieldaten aktualisieren; alle Bilder vor Veröffentlichung ansehen.
6. Vorgesehene Quelldateien, Tests, Dokumentation und Bilder gezielt in Git aufnehmen. `.env`, Datenbanken, lokale Logs, Buildprodukte und private Aufzeichnungen bleiben ausgeschlossen.
7. Commit auf GitHub übertragen; einen annotierten Tag `vX.Y.Z` auf genau diesen Commit setzen und pushen. Danach einen GitHub-Release mit den zugehörigen Änderungsnotizen erstellen. Bestehende Release-Tags nicht verschieben.
8. Installation auf iPhone und Deployment auf Pi sind eigene Schritte. Ein GitHub-Release aktualisiert laufende Geräte und Server nicht automatisch.

## Prüfung für 0.2.0

- 88 Swift-Kerntests erfolgreich, einschließlich Kompassauswahl, Routing, Belagsreparatur, Bike-Decodern, Speicher und Auswertung.
- 42 Backend-Tests erfolgreich; zwei Deprecation-Warnungen aus Abhängigkeiten, keine Testfehler.
- Simulator-Build mit UI-Testziel erfolgreich.
- Signierter iPhone-Release-Build erfolgreich; App und Live-Aktivität enthalten nachweislich Version 0.2.0, Build 2.
- Versionsangaben in `VERSION`, Xcode-Projekt, Server-Paket und API abgeglichen.
- Python-Skripte und IPv6-Shellskript syntaktisch geprüft; keine lokalen Zugangsschlüssel in den vorgesehenen Git-Dateien gefunden.
- Alle fünf UI-Interaktionstests erfolgreich: vier im Gesamtlauf, der an iOS 26 angepasste Favoriten-Test im gezielten Wiederholungslauf.
- Beide Dokumentations-Tests in gezielten Läufen erfolgreich; 14 echte Simulator-Screenshots exportiert und visuell geprüft.
- Alle lokalen Dokumentationslinks und Bildverweise geprüft.

Der iPhone-Build mit Karten- und Kompasskorrektur wurde vor diesem Release bereits installiert und gestartet. Der Release-Build mit der neuen Versionsnummer wird hier als gebaut dokumentiert; eine Installation dieses Builds oder ein Pi-Deployment ist damit nicht behauptet. Mehrstündige Touren und tatsächliche Leistungswerte vom fahrenden Bike bleiben Praxistests.
