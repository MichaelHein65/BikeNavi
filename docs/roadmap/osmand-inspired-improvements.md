# OsmAnd-inspirierte Verbesserungen für BikeNavi

21.10.2026. Grundlage: [Quellcode-Audit](../architecture/osmand-gap-analysis.md). Kleine, unabhängig prüfbare Änderungen; keine Ablösung von Bosch, Blog, Fotostationen oder MapLibre. Aufwand = grobe Entwicklungstage einschließlich Tests, ohne Feldtest-Wartezeit.

| Priorität | Ergebnis und Abhängigkeit | Risiko / Aufwand | Abnahme |
| --- | --- | --- | --- |
| P1 | GPX-Import, Originalspur, Umkehr/Ausschnitt; bestehender Tracker und additiver Datenvertrag | mittel, 7–12 T | Parser-/Roundtrip-/Speicher-/API-/Navigations-/UI-Tests; kein Routing bei Abweichung; iPhone-Dateien/Flugmodus separat |
| P2 | Belag, Straßenklasse, Radweg, Steigung, Quelle/unbekannt pro Abschnitt; Alternativen schnell/komfortabel/verkehrsarm mit dokumentierten Gewichten | mittel, 5–8 T | Öffentliche Referenzstrecken plus fehlende Tags/gesperrte Wege; Verkehr nur mit belegter Quelle, sonst keine Verkehrsbehauptung |
| P3 | Regionales Offline-Karten- **und** Routingpaket, getrennte Statusanzeigen | hoch, 20–40 T | ADR vor Code; frische Installation, Flugmodus ohne Pi, Ausfahrt aus Korridor, Downloadabbruch/Update/Rollback/Speichergrenze |
| P4 | Drei einfache Fahransichten Navigation, E-Bike-Technik, Touristik; bestehende Messwerte | mittel, 4–7 T | Ablesbarkeit, Dynamic Type, VoiceOver, wenige Interaktionen; keine Widget-Matrix ohne Nutzernachweis |
| P5 | Kalibrierte Restenergie-Bandbreite; abhängig von Messqualitätsaudit und echten Trainings-/Holdout-Fahrten | hoch, 10–20 T + Fahrten | Fehlerverteilung/Intervallabdeckung auf zurückgehaltenen Touren; keine Prognose ohne ausreichende Grundlage, Navigation weiter möglich |
| P6 | Offline-POIs mit Herkunft/Stand, Filtern und Wegpunktintegration; auf P3-Paketvertrag aufbauen | mittel, 5–8 T | Ohne Server suchen, Aktualität/Löschung, Import-/Foto-/Blog-Regressionsprüfung |

Die vorgegebene Reihenfolge bleibt sinnvoll. P3 hat größeren strukturellen Umfang als P2; eine Voruntersuchung darf vorgezogen werden, seine Implementierung erfolgt erst nach ADR. P5 darf parallel als reine Messqualitätsauswertung vorbereitet werden, ohne ungeprüfte Prognose einzubauen.

## P3: Vorbereitung der späteren Architekturentscheidung (noch kein Beschluss)

Vergleichen: (A) bestehender Swift-Graph mit regionaler OSM-Extraktion auf dem Pi und versionierten Downloads; (B) eingebettete Routingbibliothek mit regionalem Graph; (C) Serverrouting mit gespeicherten Routen als begrenzter Rückfall. C erfüllt vollständiges regionales Offline-Rerouting nicht. A nutzt vorhandene Zugangs-/Abbiegebeschränkungen, benötigt aber Leistungsmessung für große Regionen. B benötigt einen iOS-/ARM-Prototyp und genaue Bibliotheks-/Datenlizenzprüfung vor Auswahl. Keine neue Dependency in P1.

Der ADR muss konkrete Versionen, Lizenz-/Attributionspflichten (Code und OSM-Daten getrennt), Wartung, Appgröße, Downloadgröße, RAM, Akku, Start-/Reroutinglatenz und Mindest-iOS vergleichen. Paketmanifest: Region/Bounds, Graph-/Kartenschema, Quelldatum, Checksummen, Bytes, kompatible Appversion; atomarer Wechsel erst nach Verifikation, fortsetzbare Downloads, Speicherprüfung, explizite Löschung. Kartenstil/Glyphen/Sprites und Graph getrennt prüfen. Aktuelle Anbieterbedingungen und Kosten erst bei Auswahl anhand Primärquellen prüfen; bislang keine Dienstbuchung/Architekturfestlegung.

## P1: Akzeptanzkriterien und minimaler Entwurf vor Code

1. Lokale GPX-1.1-Datei sowie gemeinsames 1.0-Punktemodell lesen: trk/trkseg, rte/rtept, wpt; Standard-, Präfix- und fehlender Namensraum. Fremde Namespaces dürfen keine Koordinaten einschleusen.
2. XML-Fehler, ungültige Pflichtkoordinaten/Höhen/Zeitwerte, leere Spuren, Ressourcenüberschreitung verständlich melden; keine stille Teilimport-Reparatur. Größen-, Punkte-, Text- und Tiefenlimits, keine DTD/externen Entitäten.
3. Mehrere Strecken/Segmente explizit auswählen. Ein zusammenhängender Abschnitt pro Planung; keine Luftlinienbrücke über Segmentgrenzen. Start/Ziel als Punktbereich und Richtung wählen; Rundtour mit identischem Start/Ziel erhalten. Ein wpt-only-Dokument bleibt les-/exportierbar, aber ist ohne Strecke nicht navigierbar.
4. Ausgewählte Geometrie, Höhen, Zeitstempel und Punktnamen erhalten; wpt-Reihenfolge und -Metadaten separat von Routingzielen speichern. Umkehr kehrt Punktmetadaten mit um. Zeitwerte sind Originalmesszeiten, keine neue Fahrtzeit.
5. Neues optionales `CalculatedRoute.gpxTrack` mit Metadaten, kein Ersatz von Tour-/Aufzeichnungsmodell. Fehlendes Feld bleibt Bestandsverhalten. Provider-Kennzeichen schützt auch bei fehlenden Metadaten vor automatischem Routing.
6. Parser/Export im Core, Vorschau/Dateiauswahl in eigener SwiftUI-Ansicht, Dateiempfang über `onOpenURL` und GPX-UTType. Lesen außerhalb MainActor mit Dateizugriff nur während Lesen. Speichern erst nach Auswahl; alte Planung und aktive Fahrt bleiben erhalten.
7. Importspur überspringt Wegnetzvorbereitung, automatische Höhenanreicherung, Rückführung und automatische Planneuberechnung. Bestehender Tracker zeigt Fortschritt/Abweichung; keine erfundenen Abbiegungen oder Wegeklassifikation. Normale Planungen bleiben unverändert.
8. Backend optional erweitern; Fähigkeitsmeldung verhindert Upload an alten Pi ohne den übrigen Abgleich zu blockieren. Alte Mutationsbelege und JSON-Dokumente bleiben kompatibel; Metadaten dürfen nicht still verloren gehen.
9. Reproduzierbare Unit-/Integrationsprüfungen einschließlich großer Tracks, Datei-/SQLite-/Server-Roundtrip, Umkehr, Rundtour und Offline-Abweichung. Simulatorbuild plus gezielte UI-Prüfung mit ausschließlich synthetischen öffentlichen Beispieldaten.
10. Bedienung/Formatgrenzen, Architektur, Changelog unter Unveröffentlicht und Galerie aktualisieren. Version bleibt 0.4.0 (4); kein Release oder Deployment aus diesem Auftrag abgeleitet.

## P5: Datengüte und Validierung

Zuerst pro Gerät Empfangstakt, Paketlücken, Moduswechsel, Ladeereignisse und Einheiten aus freiwillig bereitgestellten Fahrten prüfen. Nutzbare Kapazität nur übernehmen, wenn bekannt; Akkuprozent allein ist kein Wh-Zähler. Wind, Temperatur, Fahrerleistung, Belag und Fahrstil als Unsicherheiten behandeln. Training und Holdout nach ganzen Touren trennen, keine benachbarten Messpunkte derselben Tour auf beide Gruppen verteilen. Baseline gegen konstanten Verbrauch vergleichen und Bias/MAE/Intervallabdeckung dokumentieren. Fehlende Bosch-Daten führen zu „keine belastbare Prognose“, nicht zum Navigationsabbruch.

## Umsetzung und Validierung

P1 ist lokal implementiert. `Core/GPXImport.swift`/`GPX.swift` liefern Import und Export; `GPXImportView.swift` und der Dateiempfang integrieren den Ablauf. `AppState`/`RouteTracker` schützen die Originalspur, `CalculatedRoute.gpxTrack` und der optionale Serververtrag erhalten Metadaten. Keine zusätzliche Dependency und keine Datenbankmigration; alte Mutationsbelege bleiben gültig. [Dateien, Architekturentscheidungen, Befehle und Ergebnisse](../UMSETZUNG.md#gpx-import-und-originalspur-21-oktober-2026).

| P1-Funktion nach Umsetzung | Status |
| --- | --- |
| GPX 1.1/1.0-Kernfelder, Namensräume, beschädigte/große Dateien | Implementiert, Core-Tests erfolgreich |
| Originalspur, Punktbereich, Umkehr, Rundtour, wpt-Erhalt | Implementiert, Roundtrip-/Speicher-/Navigationsprüfungen erfolgreich |
| Importvorschau, System-Dateidialog, Teilen-Export | Implementiert; Vorschau/Picker im Simulator geprüft, fremde Datei-Anbieter auf iPhone offen |
| Offline-Verfolgung und Wiederaufnahme ohne Neuberechnung | Mit gesperrtem Netzwerk automatisiert geprüft; Feldtest offen |
| Neuer/alter Backendvertrag und alte Tourdaten | API-/native Kompatibilitätsprüfungen erfolgreich; kein Pi-Deployment |
| Regionale Offline-Karten/Rerouting, Energieprognose | Weiterhin nicht durch P1 bereitgestellt; P3/P5 |

212 Swift-Kerntests, 435 Backendtests, 43 native iOS-Tests und zwei gezielte UI-Abläufe erfolgreich. Die drei GPX-Integrationstests nach der letzten Schutzkorrektur nochmals erfolgreich. Simulator-Testbuild und unsignierter Release-Gerätebuild erfolgreich. Changelog, Bedienung, Architektur und Galerie nachgeführt. Version 0.4.0 (4), kein Release oder Deployment.

**Historischer P1-Abnahmeschritt, durch den anschließenden Auftrag zur autonomen Umsetzung erweitert:** ausschließlich die dokumentierte iPhone-Abnahme für Datei-Anbieter und echte Offline-GPS-Verfolgung durchführen; diese überprüft die verbleibenden Grenzen, bevor P2 beginnt.


## Autonomer Folgeauftrag P2–P6 (21. Oktober 2026)

Der Nutzer hat nach P1 die eigenständige Umsetzung aller Stufen, Tests, Dokumentation, Bereitstellung auf Pi/iPhone und Git/GitHub beauftragt. Die ursprüngliche Warteposition vor P2 ist damit aufgehoben. Keine kostenpflichtigen Dienste oder neue Routing-Dependency. Version bleibt 0.4.0 (4), Unveröffentlicht.

| Stufe | Umgesetzter Stand | Bewusste Grenze / offene reale Abnahme |
| --- | --- | --- |
| P2 | Drei gewichtet berechnete Routenwünsche, abschnittsweise OSM-Merkmale, öffentliches Tisno-Referenznetz und synthetische Alternativen | Keine gemessene Verkehrsmenge, Radstreifen unbewertet; unbekannte Daten werden angezeigt |
| P3 | ADR 001, begrenzte Regionen mit Integrität/Version/Update/Fortsetzung/Löschung, unabhängige lokale Wegenetzkarte, regionale Planung/Rückführung | Kleine Regionen statt Länderpakete; ausführliche Topografie separat; echte Flugmodusfahrt, iPhone-RAM/Akku offen |
| P4 | Drei persistente Fahransichten, vorhandene Messwerte, beschriftete Bedienelemente und scrollbarer unterer Bereich | Simulator-Bedienung ist keine Fahrt-/Handschuh-/Sonnenlichtabnahme |
| P5 | Echter Datenaudit, Qualifikationslogik und Holdout-gesteuerte empirische Bandbreite | Nur eine geeignete Fahrt: numerische Prognose **nicht freigegeben**, weitere echte Fahrten notwendig |
| P6 | Paketgebundene Offline-Orte, Suche/Kategorien/Herkunft/Alter, Favoriten und Planungszwischenziele | Keine aktuelle Öffnungs-/Wasserqualitätsgarantie; laufende Fahrt wird nicht still umgeplant |

Bedienung: [RAD_OFFLINE.md](../RAD_OFFLINE.md). Architekturentscheidung: [ADR 001](../architecture/ADR-001-regionale-offline-navigation.md). Reale P5-Evidenz: [Energie-Audit](../architecture/energy-data-audit.md). Abschließende Befehle, Ergebnisse, Bereitstellung und Git-Stand werden in [UMSETZUNG.md](../UMSETZUNG.md) festgehalten.

### Versionsentscheidung des Nutzers

Anschließend ausdrücklich eine neue GitHub-Version für den noch nicht im Fahrbetrieb getesteten Stand beauftragt: **v0.5.0-rc.1 als Prerelease**, App/Live-Aktivität **0.5.0 (5)**. Die vorherige Aussage zur unveränderten 0.4.0 beschreibt nur die Implementierungsphase. Stabile 0.4.0 bleibt bestehen; keine Behauptung einer Feldabnahme.
