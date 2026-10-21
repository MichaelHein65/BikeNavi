# Radplanung, Offline-Regionen und Fahransichten

Vorabversion 0.5.0-rc.1, App 0.5.0 (5), 21. Oktober 2026. Reale Fahrtests stehen aus. GPX-Originalspuren bleiben wie in [GPX.md](GPX.md) beschrieben unverändert. Die folgenden Routenvarianten und die automatische Rückführung gelten für normale Fahrradplanungen.

**Bereitstellungsprüfung vom 21. Oktober:** Der neue Regionsdownload auf dem aktualisierten Pi scheiterte in zwei Versuchen an nicht erreichbaren öffentlichen OSM-Datenquellen (HTTP 503). Daher ist der erste Download derzeit nur bei wieder erreichbarem Anbieter möglich. Gespeicherte Daten und die übrige Navigation bleiben davon getrennt. [Live-Prüfstand](UMSETZUNG.md#pi-bereitstellung-und-live-abnahme).

## Routenwunsch und Wegequalität

In den Planungseinstellungen unter **Routenvariante** wählen: bisherige Planung, Schnell, Komfortabel oder Verkehrsarm. Danach wird die Route neu berechnet. Die drei neuen Varianten nutzen den lokalen Fahrradgraph; fehlt er, lädt der Pi die benötigten OSM-Bereiche. Bei einer passenden gespeicherten Region ist auch die Neuplanung vollständig auf dem iPhone möglich. Andere Anwendungen behalten ihren bisherigen Router.

Alle Varianten beachten dieselben Zugangssperren, Einbahnrichtungen, Abbiegebeschränkungen und den gewählten Belagswunsch. Die Gewichtung ist eine Näherung, keine Zusicherung tatsächlicher Fahrzeit oder Verkehrsmenge. Eine neue Variante kann deshalb auch dieselbe Strecke ergeben.

Kosten pro Kante = Länge × (1 + Belagsaufschlag + Rennradaufschlag + Höhenwunsch + Variantenaufschlag). Die bisherigen Zuschläge bleiben: bevorzugt befestigt +8 bei nicht bekannt befestigtem Belag; Rennrad +3; sanfte Steigungen positive OSM-Steigung/5. Zusätzlich:

| Variante | Zusätzlicher Faktor |
| --- | --- |
| Schnell | 0; kürzere legale Wege als Zeitnäherung |
| Komfortabel | Asphalt/Beton 0, sonst bekannter Belag 0,6, unbekannt 1; kein eigenständiger Radweg +0,2; bekannte positive Steigung/5, fehlende Steigung +0,2 |
| Verkehrsarm | Eigenständiger Radweg 0; Wohn-/Spiel-/Service-/Feldweg 0,3; unbekannt/sonstige Klasse 1; Tertiärstraße 2; Primär-/Sekundärstraße 4 |

In **Deine Strecke → Wegequalität → Abschnitte und Datenquelle** stehen Straßenklasse, eigenständiger Radweg, Belag, bekannte Steigung und Quelle pro Abschnitt. Radstreifen auf Straßen werden noch nicht separat bewertet. Fehlende Angaben bleiben unbekannt. Die Anzeige behauptet keine gemessene Verkehrsbelastung. GPX und ältere/online berechnete Routen ohne diese Merkmale werden nicht durch Schätzungen angereichert.

## Regionen herunterladen und offline verwenden

1. In den Streckendetails **Offline-Regionen verwalten** oder unter **Orte → Offline-Orte und Regionen** öffnen.
2. Name und Ausdehnung wählen. Mittelpunkt ist der Routenstart beziehungsweise der angezeigte aktuelle Standort. 3×3 oder 5×5 Bereiche von je 0,05° bilden eine Region; die reale Breite hängt vom Breitengrad ab. Eine Route kann mehrere Regionen benötigen; derzeit wird für eine einzelne Berechnung eine vollständig passende Region verwendet.
3. Mit Pi-Verbindung **Region laden / fortsetzen**. Jeder Bereich wird geprüft. Ein Abbruch lässt die fertigen Bereiche für die Fortsetzung bestehen; Verlassen der Verwaltungsansicht pausiert den Download. Bereits aktive Pakete bleiben erhalten.
4. Erst nach vollständiger Prüfung wird die Region aktiviert. **Wegenetzkarte verwenden** schaltet auf die lokale Darstellung. Im Kartenmenü kann wieder eine andere Darstellung gewählt werden.
Unvollständige Arbeitsstände lassen sich über **Unvollständige Downloads verwerfen** entfernen; fertige Regionen bleiben erhalten.

5. **Aktualisieren** baut eine neue Paketversion. Bei Fehlern bleibt die alte aktiv. **Löschen** entfernt die gewählte Region und deren Offline-Orte; vorhandene Touraufzeichnungen werden nicht gelöscht.

Die lokale **Wegenetzkarte** zeigt die im Fahrradgraph enthaltenen Wege, die Route und die Navigationsposition. Sie enthält keine vollständige topografische Grundkarte: Gebäude, Geländeflächen, Straßenschrift und Höhenlinien fehlen. Sie benötigt keine Online-Kacheln, Glyphen oder Sprites. Eine ausführliche Offline-Grundkarte bleibt ein separater Download über den eigenen Kartenstil in den Streckendetails; öffentliche Karten werden nicht pauschal heruntergeladen. Eine ausgewählte Online-Karte wird bei Netzausfall nicht als bereit ausgegeben.

Innerhalb einer passenden Region können normale Radtouren neu geplant und über den bisherigen 3-km-Bereich hinaus zurückgeführt werden. Verbindliche Zwischenziele und Belagsgrenzen bleiben erhalten. Außerhalb des gespeicherten Gebiets gibt es keine Zusage einer Neuberechnung; die gespeicherte Route bleibt sichtbar. GPX bleibt absichtlich ohne automatische Rückführung. Rad&Wandern/Wandern, Auto und Seewege erhalten dadurch keinen neuen Offline-Router.

Paketlimits: maximal 25 Bereiche, insgesamt 250 MiB für Regionsdateien einschließlich Arbeitsständen/Karte, mindestens 50 MiB freie Reserve, maximal 32 MiB je Graphdatei, 50.000 Knoten/100.000 Kanten im regionalen Graph (vor Zusammenführung höchstens 100.000 Knoten/200.000 Kanten inklusive Kachelüberlappungen). Dichte Stadtgebiete können das Limit schon bei kleiner Auswahl erreichen. Das Budget der bisherigen Routenkacheln ist separat 250 MiB. Öffentliche Overpass-Server können langsam oder nicht erreichbar sein. Download im Vordergrund; kein versprochener Hintergrunddownload nach Beendigung der App. Fortschritt wird an vollständigen geprüften Bereichen fortgesetzt, nicht innerhalb einer einzelnen HTTP-Antwort.

## Drei Fahransichten

In der Fahrt über **Navigation / E-Bike-Technik / Touristik** die Ansicht wählen. Die letzte Wahl bleibt auf dem iPhone gespeichert. Karte, Abbiegehinweis und Aufzeichnung bleiben dieselben. Navigation zeigt die üblichen Fahrwerte; E-Bike-Technik ergänzt Verbindung, Messqualität und den Status der Energieprognose; Touristik hebt Tourtitel, Offline-Orte und Blog-Ort hervor. Das untere Feld lässt sich bei großen Schriften scrollen. Pause, Höhenprofil, Sprache und Beenden bleiben erreichbar; Sprachsteuerung und VoiceOver verwenden beschriftete Bedienelemente.

## Energie: ehrliche Freigabe statt Schätzung ohne Daten

Die Anzeige unter **E-Bike-Technik → Akku am Ziel** wertet lokal abgeschlossene Fahrten aus. Voraussetzungen: ein Bike pro Fahrt, mindestens vier Akku-Stützstellen über zehn Minuten, mindestens fünf Prozentpunkte Abnahme und fünf Kilometer, mindestens 80 % Streckenabdeckung, verlässliche GPS-Punkte und gemessene Höhen, kein erfasstes Laden/auffälliger SOC-Anstieg, kein langer GPS-/Akku-Ausfall, mindestens 90 % belegter gleicher Unterstützungsmodus. Es werden keine elektrischen Wh aus der Motorleistung erfunden.

Mindestens acht geeignete Fahrten desselben Bikes/Modus innerhalb 180 Tagen: zeitlich ältere Fahrten zum Kalibrieren, die neuesten mindestens drei nur zur Prüfung. Die Bandbreite ist die beobachtete Verbrauchsspanne pro Kilometer mit Zuschlag (20 % und 0,1 Prozentpunkte/km). Sie ist **kein statistisches Konfidenzintervall**. Die zurückgehaltenen Fahrten müssen mindestens 80 % Intervallabdeckung und eine begrenzte mittlere Abweichung erreichen. Bei zu wenigen Daten, veraltetem Bosch-Wert, fehlendem Resthöhenprofil oder Gelände außerhalb der Kalibrierung erscheint **Keine belastbare Prognose**. Auch eine freigegebene Anzeige ist eine grobe Prozentbandbreite, keine Reichweitengarantie; Reserve einplanen. Null Prozent bedeutet, dass der Akku schon vor dem Ziel leer sein könnte.

Der reale Daten-Audit vom 21.10. ergab nur **eine geeignete Fahrt, keine freigegebene Kalibrierung**. Daher derzeit keine numerische Prognose. Details und Erhebungsplan: [Energie-Audit](architecture/energy-data-audit.md). Navigation funktioniert unabhängig davon weiter.

## Offline-Orte

Eine gespeicherte Region öffnen und **Offline-Orte** wählen. Kategorien: Trinkwasser, Rastplätze und Sehenswertes. Suche und Sortierung laufen ohne Netz. Quelle, OSM-Kennung, ältestes Abrufdatum und gegebenenfalls Öffnungszeiten sind sichtbar. Es gibt keine behauptete aktuelle Öffnung oder Trinkwasserprüfung. Die Entfernung ist Luftlinie. Leere Ergebnisse bedeuten fehlende Katalogtreffer, nicht nachgewiesene Abwesenheit vor Ort.

**Ort merken** speichert einen lokalen Favoriten; **Zur Planung hinzufügen** setzt ein Zwischenziel vor das bisherige Ziel beziehungsweise das erste Ziel. Eine laufende Fahrt wird dadurch nicht heimlich verändert. GPX-Originalspuren und Wasserwege werden nicht mit Land-POIs umgeplant. Blog, Kamera und vorhandene Online-Ortesuche bleiben erreichbar. Ein Paketupdate ersetzt den Katalog gemeinsam mit dem Graph; ein gemerkter Ort bleibt als eigener Favorit erhalten.
