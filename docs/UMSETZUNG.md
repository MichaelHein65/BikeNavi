# Umsetzungsstand – erste Ausbaustufe

Stand: 19. September 2026. Dies ist eine Entwicklungsfassung, keine für lange Touren freigegebene Navigations-App.

## Implementiert

- Xcode-Projekt für iPhone ab iOS 17 mit SwiftUI und MapLibre Native.
- Kartenansicht, Kartenpunkte als Start/Ziel/Zwischenziel, Standort als Startpunkt, Textsuche sowie Sortieren und Entfernen von Wegpunkten.
- Automatische Online-Neuberechnung nach Änderungen an Punkten oder Profil; eine veraltete Antwort überschreibt keine neuere Planung.
- Automatischer Tourname aus Start und Ziel. Bei Kartenpunkten werden Ortsnamen über den Pi ermittelt; die gewählten Koordinaten bleiben unverändert. Eigene Namen bleiben auch nach Neustart und Synchronisierung erhalten. Ein leerer, mit „Fertig“ bestätigter Name schaltet die Automatik wieder ein.
- Fahrradtyp, E-Unterstützung, Wunsch nach sanften Steigungen und drei Belagsoptionen.
- Echte ORS-Routen mit Linie, Abbiegehinweisen, Höhenprofil, Wegbelägen und Warnungen.
- Die Planungsansicht färbt die Route abschnittsweise nach dem Untergrund; eine Legende erläutert die Farben. Fehlende Daten bleiben grau. Ältere gespeicherte Routen können über den eingeblendeten Hinweis neu berechnet werden, um Abschnittsdaten zu erhalten.
- Der Datenbereich lässt sich nach unten auf den Tourtitel einklappen und nach oben wieder vollständig öffnen. Ein Pfeil bietet dieselbe Funktion ohne Wischgeste; die gewählte Darstellung bleibt beim nächsten Start erhalten.
- Ein eigenes App-Icon mit Fahrrad und Navigationspfeil ist im Asset-Katalog eingebunden.
- Lokale Speicherung von Planungen und Fahrtaufzeichnungen in SQLite, Tourenarchiv, erneute Planung aus einer alten Fahrt und GPX-Export.
- Fahrtansicht mit GPS-Aufzeichnung, Pause/Fortsetzen/Beenden, lokalen Abbiegehinweisen, optionaler Sprachausgabe und Abweichungsanzeige. Der Tab „Fahren“ startet eine berechnete Planung direkt. Die Karte folgt der Fahrtrichtung, zeigt ungefähr 300 m voraus und verwendet die Belagsfarben auch bei Fahrten und gespeicherten Touren. Eine Live-Aktivität hält eine fahrtrichtungsorientierte Routengrafik mit Position, Abbiegestelle, echten OSM-Nebenstraßen, Belagsfarben, Entfernung und verbleibender Strecke auf dem Sperrbildschirm aktuell; die Dynamic Island zeigt eine kompakte Fassung. Der Pi lädt die Kreuzungsarme beim Berechnen und speichert sie in der Route für die Offline-Fahrt.
- Bei deutlicher, mindestens zehn Sekunden anhaltender Abweichung von mehr als 80 m wird eine neue Verbindung vom aktuellen Standort berechnet. Noch offene Zwischenziele bleiben erhalten; zwischen Anfragen liegen mindestens 90 Sekunden.
- Gespeicherte Orte mit frei wählbaren Namen wie „Zuhause“ oder „Arbeit“. Sie stehen bei der Ortssuche zur Auswahl und können dort umbenannt oder gelöscht werden.
- Nach einem App-Neustart kann eine gespeicherte unterbrochene Fahrt aus einem pausierten Zustand fortgesetzt werden. Während der Unterbrechung werden keine GPS-Punkte erfunden.
- FastAPI-Backend mit eigener PostgreSQL-Datenbank auf dem Pi; API-Zugang per Bearer-Token, private HTTPS-Verbindung über Tailscale.
- Optimistischer Versionsabgleich, idempotente Übertragungen, synchronisierte Löschungen und Erhalt einer lokalen Konfliktkopie.
- Manueller Datenbank-Backup- und Wiederherstellungstest auf einem separaten temporären Datenbankbestand.

## Einschränkungen dieser Fassung

- Eigene Protomaps-Kartenpakete auf dem Pi sind noch einzurichten. Die Online-Karte funktioniert; der Offline-Downloadcode ist vorhanden, aber bis zur Einrichtung einer erlaubten eigenen Quelle deaktiviert.
- Gespeicherte Orte liegen derzeit nur auf dem iPhone; ihr zentraler Abgleich mit dem Pi folgt.
- Touristisches Suchen nach Namen funktioniert. Eigene POI-Kategorien, eine Liste entlang der Strecke und der zusätzliche Fahrweg zu einem POI folgen noch.
- Die öffentliche ORS-API unterstützt keine frei definierbaren Belagsgewichtungen. „Befestigte Wege bevorzugen“ vergleicht die erhaltene Fahrradroute mit einer Rennradroute und bewertet bekannte unbefestigte bzw. unbekannte Abschnitte schlechter. Das ist keine vollständige Suche über alle möglichen Wege.
- „Nur bekannte befestigte Wege“ verwirft Kandidaten mit unbekannten oder als unbefestigt gemeldeten Abschnitten. Es umfasst auch Pflaster und ist keine Garantie für Asphalt oder den tatsächlichen Zustand vor Ort.
- Gravel verwendet zunächst das Tourenradprofil. E-Unterstützung wählt beim Tourenrad das ORS-E-Bike-Profil; Kombinationen für alle Fahrradarten sind noch zu verfeinern.
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
