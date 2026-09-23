# Umsetzungsstand – Version 0.2.0

Stand: 23. September 2026. Dies ist eine Entwicklungsfassung, keine für lange Touren freigegebene Navigations-App.

## Implementiert

- Xcode-Projekt für iPhone ab iOS 17 mit SwiftUI und MapLibre Native.
- Kartenansicht, Kartenpunkte als Start/Ziel/Zwischenziel, Standort als Startpunkt, Textsuche sowie Sortieren und Entfernen von Wegpunkten.
- Automatische lokale Neuberechnung nach Änderungen an Punkten oder Profil; eine veraltete Antwort überschreibt keine neuere Planung.
- Automatischer Tourname aus Start und Ziel. Bei Kartenpunkten werden Ortsnamen über den Pi ermittelt; die gewählten Koordinaten bleiben unverändert. Eigene Namen bleiben auch nach Neustart und Synchronisierung erhalten. Ein leerer, mit „Fertig“ bestätigter Name schaltet die Automatik wieder ein.
- Fahrradtyp, E-Unterstützung, Wunsch nach sanften Steigungen und drei Belagsoptionen.
- Echte ORS-Routen mit Linie, Abbiegehinweisen, Höhenprofil, Wegbelägen und Warnungen.
- Die Planungsansicht färbt die Route abschnittsweise nach dem Untergrund; eine Legende erläutert die Farben. Fehlende Daten bleiben grau. Ältere gespeicherte Routen können über den eingeblendeten Hinweis neu berechnet werden, um Abschnittsdaten zu erhalten.
- Der Datenbereich lässt sich nach unten auf den Tourtitel einklappen und nach oben wieder vollständig öffnen. Ein Pfeil bietet dieselbe Funktion ohne Wischgeste; die gewählte Darstellung bleibt beim nächsten Start erhalten.
- Ein eigenes App-Icon mit Fahrrad und Navigationspfeil ist im Asset-Katalog eingebunden.
- Lokale Speicherung von Planungen und Fahrtaufzeichnungen in SQLite, Tourenarchiv, erneute Planung aus einer alten Fahrt und GPX-Export.
- Fahrtansicht mit GPS-Aufzeichnung, Pause/Fortsetzen/Beenden, lokalen Abbiegehinweisen, optionaler Sprachausgabe und Abweichungsanzeige. Der Tab „Fahren“ startet eine berechnete Planung direkt. Die Karte folgt der Fahrtrichtung, hält den Standort unten, zeigt 500 m voraus in maximal möglicher Perspektive und stellt diese Ansicht zehn Sekunden nach manuellen Änderungen wieder her und verwendet die Belagsfarben auch bei Fahrten und gespeicherten Touren. Eine Live-Aktivität hält eine fahrtrichtungsorientierte Routengrafik mit Position, Abbiegestelle, echten OSM-Nebenstraßen, Belagsfarben, Entfernung und verbleibender Strecke auf dem Sperrbildschirm aktuell; die Dynamic Island zeigt eine kompakte Fassung. Der Pi lädt die Kreuzungsarme beim Berechnen und speichert sie in der Route für die Offline-Fahrt.
- Ab etwa 35 m Abweichung bestätigen drei genaue Messungen über mindestens fünf Sekunden den Bedarf für eine lokale Rückführung. Noch offene Zwischenziele bleiben erhalten; zwischen Berechnungen liegen mindestens zehn Sekunden.
- Gespeicherte Orte mit frei wählbaren Namen wie „Zuhause“ oder „Arbeit“. Sie stehen bei der Ortssuche zur Auswahl und können dort umbenannt oder gelöscht werden.
- Nach einem App-Neustart kann eine gespeicherte unterbrochene Fahrt aus einem pausierten Zustand fortgesetzt werden. Während der Unterbrechung werden keine GPS-Punkte erfunden.
- FastAPI-Backend mit eigener PostgreSQL-Datenbank auf dem Pi; API-Zugang per Bearer-Token, private HTTPS-Verbindung über Tailscale.
- Optimistischer Versionsabgleich, idempotente Übertragungen, synchronisierte Löschungen und Erhalt einer lokalen Konfliktkopie.
- Manueller Datenbank-Backup- und Wiederherstellungstest auf einem separaten temporären Datenbankbestand.

## Einschränkungen dieser Fassung

- Eigene Protomaps-Kartenpakete auf dem Pi sind noch einzurichten. Die Online-Karte funktioniert; der Offline-Downloadcode ist vorhanden, aber bis zur Einrichtung einer erlaubten eigenen Quelle deaktiviert.
- Gespeicherte Orte liegen derzeit nur auf dem iPhone; ihr zentraler Abgleich mit dem Pi folgt.
- Touristisches Suchen nach Namen funktioniert. Eigene POI-Kategorien, eine Liste entlang der Strecke und der zusätzliche Fahrweg zu einem POI folgen noch.
- Für ältere, serverseitig berechnete Routen gilt: Die öffentliche ORS-API unterstützt keine frei definierbaren Belagsgewichtungen. „Befestigte Wege bevorzugen“ vergleicht die erhaltene Fahrradroute mit einer Rennradroute und bewertet bekannte unbefestigte bzw. unbekannte Abschnitte schlechter. Das ist keine vollständige Suche über alle möglichen Wege.
- „Nur bekannte befestigte Wege“ erlaubt nach Michaels Vorgabe insgesamt maximal 100 m unbefestigte oder unbekannte Abschnitte über die gesamte Route (nicht je Abschnitt oder Zwischenziel). Größere Abweichungen werden verworfen; akzeptierte Abweichungen werden in den Routenhinweisen genannt. Vollständig fehlende Belagsdaten bleiben ein Ablehnungsgrund. Befestigt umfasst auch Pflaster und ist keine Garantie für Asphalt oder den tatsächlichen Zustand vor Ort.
- Für den Legacy-Server gilt: Gravel verwendet zunächst das Tourenradprofil. E-Unterstützung wählt beim Tourenrad das ORS-E-Bike-Profil; Kombinationen für alle Fahrradarten sind noch zu verfeinern.
- Profile sind in jeder Planung gespeichert. Frei benennbare wiederverwendbare Profilvorlagen sind noch nicht implementiert.
- Fahrtaufzeichnungen werden derzeit nach Pausen bzw. Fahrtende als vollständige Dokumente übertragen. Die im Zielkonzept vorgesehenen separaten Upload-Abschnitte und eine auf lange Fahrten optimierte lokale Punktablage folgen später.
- GPX-Import, automatische Rundtourvorschläge, Mehrbenutzer-Freigaben und periodische Backups sind noch offen.
- Der Backend-Datenbankaufbau ist das initiale Schema. Vor weiteren Schemaänderungen sind versionierte Migrationen einzuführen.
- Hintergrund-Ortung ist implementiert. Akkuverbrauch, lange Fahrten, GPS-Ausfälle, gesperrter Bildschirm und Sprachausgabe müssen auf einem echten iPhone draußen überprüft werden.

## Verifikation

- Backend-Tests prüfen Zugriffsschutz, idempotente Übertragungen, konkurrierende Änderungen, Löschungen, Cursor, fehlenden API-Schlüssel, Belagsausschlüsse, Antwortformat und Fehlerbehandlung.
- Swift-Tests prüfen persistente Offline-Speicherung, Änderungen während eines Uploads, Konfliktkopien, Versionsschutz, Routenfortschritt, GPS-Ausreißer, getrennte Aufzeichnungssegmente und echte ORS-Antworten.
- Reale ORS-Abfragen auf öffentlichen Heidelberg-Beispielkoordinaten liefern Routen, Höhendaten, Beläge, Abbiegehinweise und Suchtreffer.
- Der Pi-Endpunkt wird zusätzlich über HTTPS geprüft: Authentifizierung, Routenberechnung, Speichern, Abgleich und Wiederholung einer Übertragung. Technische Testeinträge werden danach aus dem Archiv entfernt.
- Simulator-Build und visuelle Prüfung der Kartenansicht wurden durchgeführt. Feldtests stehen noch aus.
- Nach einem auf dem iPhone sichtbaren Kontrastfehler wurden Kartenfelder, Texte und Akzentfarben auf zusammenpassende helle und dunkle Farben umgestellt. Die Planung mit einer Beispielroute wurde in beiden Systemdarstellungen im Simulator visuell geprüft.
- Ein Simulator-Interaktionstest führt beide Wischbewegungen, den Pfeil zum Umschalten und einen App-Neustart aus. Er prüft den sichtbaren Tourtitel, das Ein-/Ausblenden der Daten und den Erhalt des Namens. Belagsgrenzen, unbekannte Abschnitte, Indexvalidierung und Archivkompatibilität werden zusätzlich getestet.
- Die Entwicklungsfassung wurde auf einem echten iPhone gebaut, installiert und mit dem Pi abgeglichen. Die eigentliche Navigation im Freien ist noch nicht getestet.

## Nächster fachlicher Schritt

Eine bekannte kurze Tour auf einem echten iPhone planen und abfahren. Parallel die gewünschte erste Kartenregion für den Pi festlegen und daraus die vollständigen Offline-Pakete aufbauen. Danach touristische POIs entlang der Route ergänzen und die Wegpräferenzen mit vertrauten Asphalt-, Schotter- und Waldstrecken bewerten.

### Bike-Messungen je Fahrt

Während einer laufenden (nicht pausierten) Fahrt werden neu empfangene BLE-Messungen sofort separat in SQLite gespeichert. Jede Fahrt hat eine eigene UUID und verweist über `sourcePlanID` auf die Planung. Die Messungen enthalten Bike-ID, Empfangszeit in Unix-Sekunden, Aufzeichnungssegment und optional einen höchstens 15 Sekunden alten GPS-Punkt mit eigener Zeit und Genauigkeit. Nicht gelieferte Werte bleiben leer; zwischengespeicherte Anzeige-Werte werden nicht als neue Messung übernommen. Einheiten: Leistung Watt, Trittfrequenz U/min, Bike-Geschwindigkeit km/h, GPS-Geschwindigkeit m/s. Der Fahrmodus bleibt der empfangene Bosch-Code.

Nach Pause/Ende werden zunächst die Fahrt, anschließend Messungen in Paketen von höchstens 500 übertragen. Ohne erreichbaren Pi bleibt alles lokal. Wiederholung erfolgt beim Öffnen, im laufenden App-Betrieb alle 60 Sekunden und manuell unter Touren. iOS kann die App im Hintergrund anhalten; spätestens beim erneuten Öffnen läuft der Abgleich weiter. Eine Bestätigung entfernt keine lokale Messung. Eindeutige Messungs-IDs verhindern doppelte Einträge bei Wiederholungen. Der Pi speichert Messungen in einer eigenen PostgreSQL-Tabelle, außerhalb der Dokument-Versionshistorie. Abruf: authentifiziert über `GET /v1/rides/{id}/bike-samples?after=<cursor>` mit monotonem Cursor; Darstellung später nach Messzeit sortieren.

In den Fahrtdetails stehen Messungsanzahl und noch ausstehende Übertragungen. Fahrmodusfarben, aufgezeichnete Höhen und getrennte Fahrer-/Motorleistungskurven sind in den Fahrtdetails umgesetzt; Diagramme lassen sich verschieben und vergrößern. Derzeit erfolgt der Abgleich der Messungen zum Pi; ein Rückimport auf ein neu eingerichtetes iPhone ist noch nicht Bestandteil dieser Funktion.

### Fahrtende, Fahrmodus und Neuberechnung

Der Abschlussdialog bietet Speichern, Nicht speichern und Weiterfahren. Verwerfen entfernt lokal die Messungen und Fahrtinhalte und legt eine Löschvormerkung für den Pi an. Der Pi entfernt zu einer gelöschten Fahrt auch deren Bike-Messungen. Eine bereits gestartete Upload-Bestätigung darf die Löschvormerkung nicht zurücknehmen. Die vorhandene Dokument-Synchronisationshistorie bleibt Teil des bisherigen Serverkonzepts; dies ist keine zugesicherte sichere Datenlöschung aller alten Versionen.

Die persönliche Moduszuordnung lautet 0 OFF (schwarz), 1 ECO (grün), 2 TOUR+ (blau), 3 AUTO (magenta), 4 TURBO (rot). Abgelaufene oder fehlende Messwerte bleiben leer; unbekannte Codes werden weiterhin als STUFE plus Code dargestellt. OFF erhält für die Lesbarkeit im Dunkelmodus einen hellen Hintergrund.

Online-Neuberechnungen werden bei Pause/Ende abgebrochen; überholte Antworten nach Fahrt-/Routenwechsel, nach mehr als 15 Sekunden, nach über 50 m Ortsänderung oder bei Rückkehr auf die Route werden nicht übernommen. Dieser Zwischenstand wurde am 22.09.2026 durch die lokale Rückführung ersetzt; siehe [LOKALE_NEUBERECHNUNG.md](LOKALE_NEUBERECHNUNG.md).


### Lokale Rückführung, 22.09.2026

Versionierte Wegenetz-Downloads über den Pi, dauerhafter Cache mit atomaren Manifesten, lokale abbiegebewusste Suche und getrennte Speicherung von Originaltour und Anschluss sind integriert. Während der Rückführung wird kein Routingserver kontaktiert. Unterbrechungen, Bewegungen während der Berechnung, Pflichtzwischenziele und das gemeinsame Belagsbudget sind berücksichtigt. Nach dem Test startet wieder die normale App; technische Gerätetests sind ausschließlich per Debug-Umgebungsvariable erreichbar. Details, Grenzen und gemessene iPhone-Laufzeiten stehen in LOKALE_NEUBERECHNUNG.md.


## Loop 22.09.2026: Planung auf dem iPhone

- Zielauswahl aktiviert die automatische Planung unabhängig von Karte, Suche oder Favorit; ein fehlender GPS-Start wird später ergänzt.
- Der bisherige Aufruf des Pi-Routingdienstes ist durch lokale A*-Suche auf gespeicherten OSM-Wegedaten ersetzt. Der Pi liefert Daten und archiviert Touren. Graphen werden für weitere Planänderungen im Speicher wiederverwendet.
- Wiedereinstieg minimiert Anschluss plus verbleibende Route mit Belagspräferenzen, unter Einhaltung offener Zwischenziele. Bei Ablauf des zweisekündigen Budgets bleibt ein bereits gefundener gültiger Anschluss nutzbar.
- Navigation und Kartenpunkt werden bei kleinen Abweichungen bis 25 m auf die Route projiziert. GPS-Aufzeichnungen bleiben unverändert.
- Grenzen: erster Gebietsdaten-Download benötigt Verbindung; lokale Suche ist auf den geladenen Korridor beschränkt, kein vollständiges Höhenmodell. Einzelheiten in LOKALE_NEUBERECHNUNG.md.

### Korrektur der Belagsfarben

Beim Ergänzen eines Start-Zugangs und beim Verbinden mehrerer lokal berechneter Etappen wurde die Geometrie vor dem Lesen der Belagsabschnitte verlängert. Die dadurch eingefügten unbekannten Restabschnitte machten die Indizes ungültig; die Karte zeigte die ganze Tour grau. Die Abschnitte werden jetzt vor der Geometrieänderung übernommen. Betroffene gespeicherte lokale Planungen und fortsetzbare Fahrten erhalten ihre Belagszuordnung beim Laden des Wegenetzes zurück, ohne Änderung der Routenlinie. Echte unbekannte Beläge bleiben grau. Regressionstests decken Zugänge, mehrere Etappen, Speicherung und Reparatur ab.

### Zielwahl nach „−“: Standort im Stillstand

Die Standortmessung für die Planung verwendet jetzt keinen Bewegungsfilter. Bei einer ausdrücklichen Standortanforderung ohne frische Messung wird der Standortdienst außerhalb laufender Fahrten neu gestartet. So muss man sich nicht erst fünf Meter bewegen, nachdem die letzte Messung älter als die erlaubten 15 Sekunden geworden ist. Während einer Fahrt bleibt der 5-m-Filter bestehen. Standortfehler erhalten einen sichtbaren Hinweis; Warte- und Ladezustände bleiben auch bei eingeklappten Tourdetails sichtbar.

Der neue Simulator-Bedienungstest setzt einen festen Standort, wartet 18 Sekunden, betätigt „Planung zurücksetzen“, wählt einen Kartenpunkt als Ziel und prüft die Übernahme von „Mein Standort“ und den tatsächlichen Aufruf der Routenberechnung. Der Test hat absichtlich keinen Karten-Cache/Server: Die erwartete Meldung über fehlende Wegedaten weist den Berechnungsaufruf nach, nicht eine fertig berechnete Strecke. Die Standortsimulation erfolgt im Test über XCUIDevice; eine vor dem Xcode-Test gesetzte simctl-Position wurde im Testlauf nicht geliefert.

### Kartensteuerung und Release, 23.09.2026

Die laufende Tour verankert den Standort bei 80 % der Kartenhöhe. Der Maßstab wird anhand der tatsächlichen Projektion auf 500 m bis zum oberen Rand kalibriert. Die Kamera fordert 60° Neigung an; MapLibre begrenzt den Winkel zusätzlich entsprechend dem versetzten Mittelpunkt. Verschieben, Zoom, Drehung, Neigung und Kompass-Taste unterbrechen die Automatik für zehn Sekunden.

Die Fahrtrichtung stammt bei Bewegung ab 1 m/s aus einem höchstens fünf Sekunden alten GPS-Kurs. Im Stand oder bei langsamem Tempo dreht die Anzeige mit dem Kompass des iPhones. Heading-Updates lösen unabhängig von aufgezeichneten GPS-Punkten eine Aktualisierung aus. In einer pausierten Tour bleibt die Karte frei bedienbar; „Fortsetzen“ aktiviert die Nachführung wieder.

Alle bis dahin offenen Änderungen sind in [CHANGELOG.md](../CHANGELOG.md) zusammengeführt; die Release-Prüfungen stehen in [VERSIONIERUNG.md](VERSIONIERUNG.md).
