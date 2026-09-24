# Änderungen

Alle veröffentlichten Fassungen erhalten einen Git-Tag und einen GitHub-Release. Versionsnummern folgen `MAJOR.MINOR.PATCH`; vor 1.0 kennzeichnet eine neue Minor-Version einen größeren Entwicklungsschritt. Die iOS-Buildnummer steigt unabhängig davon. Details zum Ablauf: [Versionierung](docs/VERSIONIERUNG.md).

## Unveröffentlicht

### Routing über freigegebene Schranken

- Fehler an der Brücke Tisno/Murter behoben: Die OSM-Schranken an beiden Enden waren trotz `access=yes` gesperrt worden. Bewegliche Schranken mit ausdrücklicher Fahrrad-, Fahrzeug- oder allgemeiner Zugangsfreigabe werden nun nach der bestehenden Zugangshierarchie berücksichtigt. Verbote, verschlossene Schranken und nicht unterstützte bedingte Beschränkungen bleiben wirksam; keine geografische Ausnahme und keine Lockerung der Belagsgrenzen.
- Kacheln erhalten die zusätzliche Compilerrevision 2. Neuer Server-Cacheschlüssel verhindert die Wiederverwendung alter Ausschlüsse. Die App erneuert alte Gebietsdaten bei der nächsten Vorbereitung/Planung mit API-Client; gespeicherte Offline-Pakete bleiben lesbar. Für die Korrektur im Betrieb müssen Pi und App aktualisiert werden.
- Reproduzierbare öffentliche OSM-Beispieldaten der Brücke, beider Zufahrten und Schranken hinzugefügt (ODbL, Abruf 24.09.2026). Regression prüft beide Richtungen und alle drei Belagsprofile sowie Zugangshierarchie, Cachemigration und Altbestände.
- Prüfung am 24.09.2026: 90 Swift-Tests und 45 Backend-Tests erfolgreich; zwei bestehende Deprecation-Warnungen der Backend-Testabhängigkeiten. iOS-Debug-Simulator-Build erfolgreich. Keine sichtbare UI-Änderung; Architektur und Bedienungsdokumentation aktualisiert.
- Installation und Betrieb: Am 24.09.2026 signierter iPhone-Debug-Build erfolgreich, auf Michaels iPhone 15 Pro installiert und gestartet; Pi aktualisiert. Live-Prüfung von HTTPS, Zugangsschutz, Beispielrouting, Kreuzungsdaten und Speicherung/Synchronisation erfolgreich; technischen Testeintrag wieder entfernt. Ausgelieferte Tisno-Kachel mit Compilerrevision 2, beiden freigegebenen Schranken und asphaltierter Verbindung in beiden Richtungen direkt am Pi geprüft. Kein neuer Release.
- Rückmeldung am 24.09.2026: Michael bestätigt nach Installation und Pi-Update, dass die Routenplanung an der Tisno-Brücke funktioniert.
- Grenzen: Keine dokumentierte Testfahrt über die Brücke, keine Auswertung des aktuellen Brückenzustands oder von Öffnungszeiten; Wartezeiten bleiben möglich.

## 0.2.0 — 23. September 2026

Entwicklungsfassung, iOS-Build 2. Erster zusammenhängend dokumentierter und getaggter Release. Enthält sämtliche bis zu diesem Release noch unversionierten Erweiterungen seit Commit `eda039f`.

### Navigation und Kartenansicht

- Standort während der laufenden Tour bei 80 % der Kartenhöhe; 500 m Vorausschau bis zum oberen Kartenrand in Blickrichtung.
- Maximal mögliche Perspektive: 60° angefordert; MapLibre begrenzt die Neigung zusätzlich für den nach unten versetzten Kartenmittelpunkt.
- Gemeinsame Steuerung von Position, Richtung, Perspektive und Maßstab; Neuberechnung bei Größenänderungen.
- Freies Verschieben, Zoomen, Drehen und Neigen; automatische Rückkehr zehn Sekunden nach dem letzten manuellen Kartenwechsel, auch ohne neuen GPS-Punkt.
- GPS-Fahrtrichtung ab 1 m/s bei höchstens fünf Sekunden alten Messungen. Bei geringerer Geschwindigkeit oder fehlendem aktuellem Kurs übernimmt ein gültiger Kompasswert. iPhone-Drehungen aktualisieren die Ansicht unabhängig von der Track-Aufzeichnung.
- Kompass wird nur während einer laufenden Aufzeichnung verwendet. Wahre Nordrichtung wird bevorzugt, magnetische Nordrichtung dient als Ersatz. Ungültige, ungenaue oder alte Messungen werden verworfen.
- Routenmagnet bis 25 m bei passender Genauigkeit und Richtung; originale GPS-Aufzeichnung bleibt unverändert.

### Planung und lokale Rückführung

- Routenplanung auf dem iPhone aus gespeicherten OSM-Wegedaten; kein Routingaufruf an den Pi für neue Planungen.
- Versionierte Gebietsdaten, atomare Cache-Manifeste, wiederverwendbare Graphen, Einbahnrichtungen und Abbiegebeschränkungen.
- Lokale Rückführung nach drei genauen Messungen über mindestens fünf Sekunden ab etwa 35 m Abweichung; Prüfung von Position, Aktualität und laufender Fahrt vor Übernahme.
- Wiedereinstieg berücksichtigt Anschluss und verbleibende Tour, noch offene Zwischenziele sowie ein gemeinsames Belagsbudget. Originaltour und temporärer Anschluss werden getrennt gespeichert.
- „Nur bekannte befestigte Wege“ erlaubt insgesamt höchstens 100 m unbefestigte oder unbekannte Abschnitte über die gesamte Tour. Die ältere Server-Routenberechnung verwendet dieselbe Toleranz.
- Belagsindizes bleiben beim Ergänzen von Zugängen und mehreren Etappen gültig. Betroffene gespeicherte lokale Routen werden anhand des Wegenetzes repariert.
- Zielwahl startet die Planung automatisch; ein fehlender Standort wird nachgereicht. Standortanforderungen funktionieren auch im Stillstand nach Zurücksetzen der Planung.
- Warte-, Lade- und Fehlermeldungen bleiben bei eingeklapptem Datenbereich sichtbar. Die Tastatur kann über „Fertig“ geschlossen werden.
- Orte aus Suche und Favoriten werden direkt zur Tour hinzugefügt. Auswahl, Umbenennen und bestätigtes Löschen von Favoriten sind getrennte Aktionen.

### Bike-Daten und Tourenarchiv

- Gemeinsamer Bluetooth-Dienst für Fahrtansicht und Verbindungsdiagnose, Auswahl und Wiederverbindung eines Bosch-Bikes sowie begrenzte Diagnoseprotokolle.
- Decoder für LDI-, Protobuf- und Smartphone-Statusdaten; Anzeige von Akku, Fahrmodus sowie Fahrer- und Motorleistung. Nicht empfangene Werte bleiben als nicht verfügbar erkennbar.
- Letzter Akkumesswert bleibt mit Empfangszeit und Bike-Zuordnung über Neustarts erhalten; gespeicherte Werte werden nicht als neuer Empfang ausgegeben.
- Modusdarstellung: OFF, ECO, TOUR+, AUTO und TURBO mit zugeordneten Farben; unbekannte Codes bleiben erkennbar.
- Kompakte Fahrtansicht mit gut erreichbaren Tasten für Pause, Höhenprofil, Ton und Fahrtende. Abschlussdialog bietet Speichern, Verwerfen und Weiterfahren.
- Neue Bike-Messungen werden während der Aufzeichnung separat in SQLite gespeichert: Fahrt-/Planungs-ID, Zeit, Segment und gegebenenfalls frischer GPS-Bezug. Pausen erzeugen keine Messungen.
- Idempotenter Upload in Paketen bis 500 Messungen, Wiederholungen nach Offline-Phasen und alle 60 Sekunden im laufenden App-Betrieb; Bestätigungen löschen keine lokalen Messungen.
- Tourenarchiv mit Datum und Uhrzeit, farbigen Fahrmodusabschnitten, aufgezeichnetem Höhenprofil sowie getrennten Leistungskurven für Fahrer und Motor. Diagramme unterstützen Verschieben und Vergrößern; Lücken und Pausen bleiben sichtbar.

### Backend und Betrieb

- Authentifizierte Endpunkte für Bike-Messungen und versionierte Offline-Wegedaten; neue Tabellen für Messungen und Gebietscache.
- Messungs-IDs verhindern Duplikate; widersprüchliche Wiederholungen werden abgewiesen. Gelöschte Fahrten verlieren ihre Bike-Messungen; Dokumenthistorie folgt weiterhin dem vorhandenen Synchronisationskonzept.
- Overpass-Ausweichdienst bei Ausfall der öffentlichen Standardquelle; unvollständige Antworten werden nicht als vollständiger Cache gespeichert. Vorhandene Daten bleiben bei fehlgeschlagenem Refresh erhalten.
- Längeres Download-Zeitbudget auf dem iPhone; zusätzliche IPv6-Ausleitung für den BikeNavi-Container über eine eigene Bridge und idempotente Betriebsregeln.
- Legacy-Routing bleibt für ältere Clients verfügbar. Server-Paket, API-Versionsauskünfte, App und Live-Aktivität tragen Version 0.2.0.

### Dokumentation und Prüfung

- README mit bestehendem App-Logo, Hauptansichten und vollständiger [Bildschirmgalerie](docs/BILDSCHIRME.md).
- Explizite Debug-Testposition für reproduzierbare Fahrtansichten; aus Release-Builds ausgeschlossen.
- Reproduzierbare Simulator-Bilder mit öffentlicher Heidelberg-Route und ausdrücklich synthetischer Beispielaufzeichnung; keine persönlichen Touren oder Zugangsdaten.
- Dauerhafte Projektregeln in `AGENTS.md` verpflichten weitere Änderungen zu Änderungsprotokoll, passenden Tests und aktueller Bildschirmdokumentation.
- Aktualisierte Architektur, Umsetzungsübersicht sowie Anleitungen für lokale Rückführung, Bosch-Anbindung und iPhone-Installation.
- UI-Test für Favoriten berücksichtigt sowohl den Abbrechen-Knopf als auch die Popover-Darstellung unter iOS 26.
- Erweiterte Swift-, Backend- und UI-Tests für Routing, Beläge, Standort, Favoriten, Bike-Daten, Speicherung, Auswertung und Kompasssteuerung. Ergebnisse dieses Releases stehen in [Versionierung](docs/VERSIONIERUNG.md).

### Bekannte Grenzen

- Vollständige Offline-Karten mit eigenem Kartenserver sind noch nicht eingerichtet. Ein lokales Wegenetz ersetzt kein Offline-Kartenbild.
- Erste Gebietsdaten-Downloads benötigen eine Verbindung und verfügbare Datenquellen. Die lokale Suche ist auf geladene Gebiete begrenzt; ein vollständiges Höhenmodell fehlt.
- Bike-Messungen werden zum Pi hochgeladen; der Rückimport auf ein neues iPhone fehlt noch. Favoriten werden noch nicht zentral synchronisiert.
- Langzeitbetrieb mit GPS, Kompass, Bluetooth und gesperrtem Bildschirm muss weiter auf echten Touren geprüft werden. Ein erfolgreicher Build oder Simulatorlauf ersetzt diesen Praxistest nicht.

## Vor 0.2.0

Die bisherige Entwicklung trug intern Version 0.1.0, Build 1, ohne Release-Tag. Enthalten waren die Grundlagen für Planung, Speicherung, Pi-Abgleich, Favoriten, Belagsfarben und Sperrbildschirm-Navigation. Die vollständige Einzelhistorie bleibt in Git erhalten.
