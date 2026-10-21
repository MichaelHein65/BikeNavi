# GPX importieren und einer Originalspur folgen

Vorabversion 0.5.0-rc.1 vom 21.10.2026, App 0.5.0 (5); reale Datei-Anbieter- und Fahrabnahme ausstehend. Der Import erfolgt vollständig auf dem iPhone. Er benötigt weder Internet noch einen erreichbaren Pi. Eine Hintergrundkarte ist davon unabhängig: Für eine vollständig sichtbare Karte ohne Netzwerk muss zuvor ein unterstütztes Offline-Kartenpaket eingerichtet und geladen sein.

## Bedienung

1. In einer Anwendung unter **Planen → GPX** eine `.gpx`- oder XML-Datei aus **Dateien** wählen. Alternativ in einer anderen App **Teilen → BikeNavi** bzw. **In BikeNavi öffnen** verwenden. Die App registriert GPX als lesbaren Dokumenttyp; die angebotenen Teilen-Ziele hängen auch von der Quell-App ab.
2. Die Vorschau nennt Datei, Abschnitte und Wegpunkte. Bei mehreren Tracks, Routen oder Tracksegmenten den gewünschten **Abschnitt** auswählen. Jeder Trackabschnitt bzw. jede Route bleibt separat; Lücken werden niemals durch eine künstliche Strecke geschlossen.
3. **Start** und **Ziel** sind Punktnummern im ausgewählten Abschnitt, beginnend bei 1. Zahlen direkt eingeben oder schrittweise ändern. Mindestens zwei Punkte wählen. **Richtung umkehren** kehrt den gewählten Bereich einschließlich seiner Punktmetadaten um. Die Karte zeigt die Auswahl, Start und Ziel; gleiche Start-/Zielpositionen einer Rundtour bleiben erhalten.
4. **Als neue Tour importieren** speichert eine neue Fahrradplanung. Die vorherige Planung und eine eventuell laufende/pausierte Fahrt bleiben erhalten. Für weitere Abschnitte dieselbe Datei erneut öffnen. Die Originaldatei wird nicht verändert.
5. **Track folgen** startet die vorhandene Fahrtaufzeichnung mit aktuellem GPS. Fortschritt, Reststrecke und Abweichung beziehen sich auf die Originalspur. **Abseits der GPX-Spur** fordert zur eigenen Orientierung auf; die App ersetzt die Spur nicht durch eine Rückführung. Es gibt keine aus der GPX-Datei erfundenen Abbiegeansagen. ETA bleibt eine modellierte Schätzung, keine aus historischen GPX-Zeitstempeln abgeleitete Zusage.
6. In der Planung **Umkehren** verwenden oder über **Track bearbeiten / Wegpunkte** einen anderen Ausschnitt als neue Tour speichern. Die GPX-Wegpunkte stehen dort auch als Liste und werden auf der Karte als zusätzliche Orte angezeigt. Sie sind keine verpflichtenden Routing-Zwischenziele.
7. Über **GPX** teilen oder im Tourarchiv exportieren. Der Export einer importierten **Planung** enthält den gewählten Abschnitt/Bereich mit seinen Punktnamen, Originalhöhen und Originalzeiten sowie alle GPX-Wegpunkte in ihrer ursprünglichen Reihenfolge. Der Export einer **aufgezeichneten Fahrt** enthält weiterhin die tatsächlich gefahrene Spur und ihre Aufzeichnungssegmente.

Ist bereits eine Fahrt geöffnet, führt **Fahrt fortsetzen** zu ihr. Beende sie vor einer neuen Aufzeichnung. Bei ausstehender GPS-Erfassung lässt sich die Standortsuche abbrechen. Andere Planungsfunktionen berechnen die importierte Originalspur nicht neu; für zusätzliche Routing-Ziele eine neue normale Tour anlegen.

## Unterstütztes Format und Grenzen

- GPX 1.1 und gemeinsames GPX-1.0-Modell: `trk/trkseg/trkpt`, `rte/rtept`, `wpt`; Breite/Länge (WGS84), optionale Höhe (Meter), ISO-8601-Zeit und Punktname.
- UTF-8, Standardnamespace, Präfixnamespace oder Dateien ohne Namespace. Version 1.0/1.1 sowie fehlende Versionsangabe werden für dieses Punktemodell toleriert; keine vollständige XSD-Validierung. Fremde Namespaces und Erweiterungs-Unterbäume werden nicht als GPX-Punkte interpretiert.
- Höchstens 16 MiB Eingabedaten, insgesamt 100.000 Punkte, davon höchstens 1.000 Wegpunkte, und 1.000 Abschnitte. XML-Tiefe höchstens 32, Textfelder höchstens 16 KiB, Punktnamen höchstens 300 Zeichen. Extremwerte über ±100.000 m Höhe werden zurückgewiesen. DTD/Entitätsdeklarationen sind ausgeschlossen; UTF-16 bitte vorher nach UTF-8 konvertieren.
- Fehlerhafte Koordinaten, Höhen, Zeiten und XML führen zu einer verständlichen Ablehnung der gesamten Datei. Ein leeres/einpunktiges Segment lässt sich nicht als Strecke importieren; einen anderen Abschnitt auswählen. Reine Wegpunktdateien lassen sich ansehen, aber ohne Strecke nicht navigieren.
- Keine Glättung, Vereinfachung, Straßenanpassung oder nachträgliche Höhenanreicherung. Unbekannte Höhe/Beläge bleiben unbekannt. Eine gerade Verbindung zwischen zwei weit auseinanderliegenden Punkten **innerhalb** eines Segments ist Teil der Quelldatei, keine geprüfte Straßenroute; Zugänglichkeit vor Ort prüfen.
- Erhalten werden die genannten Kernfelder. Kommentare, Beschreibungen, Links, Hersteller-/OsmAnd-Erweiterungen und sonstige GPX-Metadaten werden nicht übernommen. Dateiformat wird beim Export auf GPX 1.1 normalisiert; Zahlenformatierung kann sich ändern. Originalzeittexte einschließlich Zeitzone und Nachkommastellen bleiben gleich. Nach Umkehr können die Originalzeiten rückwärts laufen, weil sie keine neu gemessene Fahrt sind.
- Ein Import speichert genau den bewusst ausgewählten Abschnitt und Bereich. Nicht ausgewählte Abschnitte verbleiben in der unveränderten Quelldatei. Der Core-Datei-Roundtrip erhält die Punktreihenfolgen und Segmentgrenzen, normalisiert jedoch jeden Trackabschnitt zu einem eigenen Track und ordnet Routen vor Tracks gemäß GPX 1.1.
- GPX-Import startet als Fahrradspur. Es gibt keine neue Auto-, Wasserweg- oder kombinierte Rad-/Wanderplanung und keine automatische Übertragung von Straßenmanövern aus GPX-Erweiterungen.

## Speicherung und Kompatibilität

Die bisherige Tourstruktur und SQLite-Datenbank bleiben erhalten. `CalculatedRoute.gpxTrack` ergänzt optional Punktmetadaten und separate GPX-Wegpunkte; die Route selbst enthält die Originalkoordinaten. Vorhandene Dokumente ohne dieses Feld funktionieren wie bisher. Das Kennzeichen `provider = "GPX · Originalspur"` schützt zusätzlich die Streckenführung. Keine neue Bibliothek erforderlich.

Das aktualisierte Backend meldet `gpxImportAvailable` über `/v1/status`. Bei einem älteren Pi bleiben neue GPX-Touren lokal und werden als ausstehend angezeigt; übrige kompatible Touren werden weiter synchronisiert. Ein Backendupdate ist für GPX-Abgleich erforderlich, für lokalen Import und Streckenverfolgung nicht. Alte Mutationsbelege behalten ihre Hashes, weil das neue optionale Feld bei Abwesenheit vor der Hashberechnung entfernt wird. Ein älterer Client darf gespeicherte GPX-Metadaten nicht still entfernen: Der aktualisierte Server lehnt eine solche Änderung ab, Löschen bleibt möglich. Zur Bearbeitung importierter Touren nur die aktualisierte App verwenden.

Das Backend behält seine 16-MiB-Anfragegrenze. Sehr große Kombinationen aus importierter Spur und langer Fahrtaufzeichnung können diese Grenze erreichen; lokale Daten bleiben bei abgelehntem Abgleich erhalten. Eine allgemeine Aufteilung sehr großer Tourdokumente gehört nicht zu P1.

## Manuell am iPhone prüfen

- Lokale Dateien, iCloud-Datei (zunächst vollständig herunterladen), Teilen aus einer zweiten App, Abbrechen und defekte Datei.
- Im Flugmodus zusätzlich WLAN ausschalten und Pi unerreichbar machen: App kalt starten, gespeicherte GPX-Tour öffnen, Aufzeichnung beginnen, Spur verlassen und zurückkehren, pausieren, neu starten und fortsetzen. Keine Neuberechnung; Karte und Spur getrennt beurteilen.
- Rundtour mit dicht parallelem Hin-/Rückweg, echte GPS-Ungenauigkeit, langer Track, Hintergrund/Sperrbildschirm, VoiceOver und große Schrift.
- Echte Bosch-Werte, Kamera/Fotostation, Blogabgleich und bestehende Modi bei einer Fahrt nachprüfen. Automatisierte Regressionen ersetzen keinen Feldtest.

[Audit](architecture/osmand-gap-analysis.md) · [Roadmap und Prüfergebnisse](roadmap/osmand-inspired-improvements.md) · [Bildschirme](BILDSCHIRME.md)
