# ADR 001: Regionale Navigation auf dem iPhone

Status: beschlossen am 21.10.2026 vor P3-Implementierung, aufgrund des Auftrags zur autonomen Umsetzung. Additive, rücknehmbare Erweiterung; keine neue Dienstbuchung.

## Entscheidung und Alternativen

Bestehende Swift-Engine und OSM-Kachelcompiler beibehalten. Regionale Pakete enthalten eine rechteckige Auswahl vollständiger Graphkacheln, einen lokalen POI-Katalog und eine aus dem Graph erzeugte einfache Wegenetzkarte. Diese Karte benötigt weder Internet noch Pi, Glyphen oder Sprites. Sie zeigt fahrbare Wege, keine vollständige topografische Grundkarte; die vorhandene ausführliche MapLibre-Karte ist ein **separater** optionaler Download des eigenen Kartenanbieters. Die App nennt diese beiden Kartenarten ausdrücklich. Kein Massendownload öffentlicher Rasterkarten.

| Option | Nutzen | Konsequenz |
| --- | --- | --- |
| Bestehender Swift-Graph, Compiler v1/Zugangsrevision 3 | Gleiche erprobte Zugangssperren, keine neue Runtime, iOS 17/ARM64 vorhanden | Region begrenzen, Speicher und Suchdauer prüfen; keine Kontinentabdeckung |
| GraphHopper einbetten | Größere Routinginfrastruktur | Java/JVM bzw. separater iOS-Port; laut aktuellem Hauptrepository Offline-Routing nicht mehr offiziell unterstützt. Zweite Zugangslogik, neue Build-/Lizenzprüfung; für diesen Ausbau verworfen |
| ORS/Pi mit Routencache | Bereits integriert, gute Onlineplanung | Keine freie regionale Neuberechnung im Flugmodus; bleibt Onlineoption |

Swift-Core ist Projektcode; MapLibre Native bleibt exakt 6.31.0 (vorhandene BSD-Lizenz und Attribution beibehalten). OSM-Daten: ODbL, sichtbares © OpenStreetMap contributors und Lizenzlink; Datenpakete unter ODbL bereitstellen. Keine neuen Abonnements. Öffentliche Overpass-Instanzen bleiben ein begrenzter, störungsanfälliger Vorbereitungsdienst; serieller Abruf, kleine Regionen, keine permanente Massenextraktion. Große Regionen benötigen später eigenen Extraktcompiler, keine bloße Anhebung der Limits.

## Paketvertrag und Betrieb

Schema 1, stabile Regions-ID, Anzeigename, Liste der 0,05°-Kacheln, Paketversion, Erstellungsdatum und je Datei SHA-256/Bytezahl/Quelldatum. Höchstens 25 Kacheln; regionale Grenzen 50.000 Knoten/100.000 Kanten, vor Zusammenführung 100.000/200.000 einschließlich Überlappungen; bestehende Suchlimits bleiben. Regionen sind geographische Rechtecke unabhängig vom Routenkorridor. Jede Kachel wird vor Speicherung verifiziert, anschließend gemeinsamer Graph validiert. Erst dann atomarer Manifestwechsel. Vorversion bleibt bis erfolgreichem Abschluss aktiv. Fortsetzung erfolgt an verifizierten Kachelgrenzen; Versionswechsel legt einen neuen Arbeitsstand an. Abbruch darf die aktive Region nicht beschädigen. Explizite Löschung entfernt nur das gewählte Paket. Speicherbudget und freier Plattenplatz werden vor weiteren Dateien geprüft.

Die lokale Wegenetzkarte wird aus genau dem validierten Graph erzeugt und mit dem aktiven Paket gespeichert. Neuplanung und Rückführung können den gesamten geladenen regionalen Graph nutzen; außerhalb der Region weiterhin ehrliche Fehlermeldung. Andere Anwendungen, GPX-Originalspur, Aufzeichnung, Blog und Bosch bleiben getrennt.

## Abnahme und Grenzen

Automatisiert: frischer Speicher, vollständiges Paket, offline neu planen, Rückführung über 3 km, Wiederaufnahme, beschädigter Hash, fehlende Datei, Fehlupdate mit unveränderter Vorversion, Löschung und Budget. Öffentliches Referenznetz plus synthetisches größeres Netz mit Laufzeitmessung. Simulator: lokale Karte bei gesperrtem Netz, Regionsverwaltung, Ansichtwechsel. Unsigned/signed ARM64-Build. RAM/Akku und echte Flugmodus-GPS-Fahrt am iPhone können weder aus Mac-Laufzeiten noch Simulatorbildern bestätigt werden; diese bleiben explizite Geräteabnahme.

## Primärquellen (21.10.2026 geprüft)

- [OpenStreetMap: Copyright und ODbL](https://www.openstreetmap.org/copyright)
- [GraphHopper: offizielles Repository und Offline-Unterstützung](https://github.com/graphhopper/graphhopper)
- [MapLibre Native iOS: OfflineStorage](https://maplibre.org/maplibre-native/ios/latest/documentation/maplibre/mlnofflinestorage/)
