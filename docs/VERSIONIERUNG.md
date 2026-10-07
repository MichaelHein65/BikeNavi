# Versionierung und Releases

## Version 0.4.0

Datum: 7. Oktober 2026. App und Live-Aktivität: **0.4.0 (4)**. Backend: **0.4.0**. Git-Tag: **v0.4.0**. Entwicklungsfassung vor 1.0, kein App-Store-Release.

Dieser Release enthält die Weiterentwicklung des Tourtagebuchs: direkt sichtbare Blogaktionen, GPS-Neuerfassung im Stand, große topografische Blogkarte, numerische Profilachsen sowie ausführliche Hintergrundkapitel und wiederverwendbare Recherchequellen. [Bedienung](BLOG.md), [Bildschirmgalerie](BILDSCHIRME.md#tourtagebuch-und-blog) und [öffentlicher HTML-Beispielblog](examples/heidelberg-blog.html).

Die Funktionsfassungen wurden am 6. Oktober bereits auf Pi und iPhone bereitgestellt. Die neue Release-Version wird in diesem Arbeitslauf geprüft und auf Git/GitHub veröffentlicht; damit ist kein neues Geräte- oder Pi-Deployment verbunden. Die installierten Entwicklungsfassungen werden nicht allein durch den GitHub-Release aktualisiert.

### Prüfung für 0.4.0

- Vollständige Backend-Suite: **144 Tests erfolgreich**; zwei bekannte Deprecation-Warnungen aus Testabhängigkeiten.
- Vollständige Swift-Kerntests: **126 Tests erfolgreich**.
- Blog-UI-Prüfungen erfolgreich: Erfassung mit verzögertem frischem Beispiel-Fix, Offline-Neustart, sichtbare Blogaktionen in Fahrt/Planung, HTML-Vorschau, topografische Karte und m/km-Achsen.
- Simulator-Testbuild und signierter iPhone-Release-Build erfolgreich; App und Live-Aktivität jeweils **0.4.0 (4)**, Signaturprüfung erfolgreich.
- Zusätzlicher Versions-UI-Test mit Anzeige 0.4.0 (4) erfolgreich. Der erste Selektor suchte nur nach einer getrennten Textzelle; für Apples kombinierte Beschriftung/Wert-Darstellung korrigiert und erneut geprüft.
- Initiale parallele Builds kollidierten im gemeinsam eingestellten Xcode-Buildverzeichnis; Simulator-Build mit eigenem `SYMROOT`/`OBJROOT` erneut erfolgreich.
- Öffentlicher Heidelberger KI-Beispielblog am 7. Oktober auf dem bestehenden Pi erzeugt: **12 Ortsquellen, drei Hintergrundkapitel, 62,5 Sekunden**. Zusätzliche Websuche nicht erreichbar, Wikipedia-Quellen und KI-Schreibschritt erfolgreich; Ausfallhinweis im HTML. Technische Beispielaufzeichnung samt Pi-Blogdaten wieder entfernt.
- Bilder 12 und 30–37 mit dem aktuellen öffentlichen Beispiel erneuert; Einstellungen 11 und Versionsanzeige 38 ergänzt/erneuert. Alle vor Commit visuell geprüft. Keine privaten Fahrt-/Fotodaten, Zugangswerte, Datenbanken, Logs oder Buildprodukte im Release.
- Kamera-/GPS-Erneuerung im tatsächlichen Stand, lange Offline-Fahrten und die konkrete ursprüngliche Fehlermeldung benötigen weitere Geräteprüfung. Simulatorprüfungen sind kein Feldtest.
- **Kein Geräte- oder Pi-Deployment durch diesen Release-Arbeitslauf.** Die zuvor installierten Entwicklungsfassungen bleiben von Tag/GitHub-Release unabhängig.


## Version 0.3.0

Datum: 6. Oktober 2026. App und Live-Aktivität: **0.3.0 (3)**. Backend: **0.3.0**. Git-Tag: **v0.3.0**. Entwicklungsfassung vor 1.0, kein App-Store-Release.

- [Änderungsprotokoll](../CHANGELOG.md)
- [GitHub-Releases](https://github.com/MichaelHein65/BikeNavi/releases)
- [Bildschirmgalerie](BILDSCHIRME.md)

`VERSION` ist die Vorgabe für das Xcode-Generierungsskript. `CURRENT_PROJECT_VERSION` im Skript ist die fortlaufende iOS-Buildnummer. Die Einstellungen lesen Version und Buildnummer aus dem tatsächlich gebauten App-Bundle. Der Server führt seine Paketversion in `server/pyproject.toml` und seine API-Version in `server/bikenavi/__init__.py`; beide werden bei einem Release gemeinsam angehoben.

## Prüfung für 0.3.0

- Vollständige Backend-Suite: 134 Tests erfolgreich. Zwei bekannte Deprecation-Warnungen stammen aus Starlette/TestClient und AnyIO; keine Testfehler.
- Vollständige Swift-Kerntests: 125 Tests erfolgreich.
- Xcode-Projekt über `python3 scripts/generate_project.py` neu erzeugt. Simulator-Debug-Build für iOS 26.1 erfolgreich; App und Live-Aktivität tragen 0.3.0 (3).
- Die im Änderungsprotokoll dokumentierten Simulator-UI-Tests und die visuelle Galerieprüfung liefen vor dem Versionsbump mit derselben Funktionsrevision. Kein neuer Gerätebuild, Pi-Deployment oder Feldtest für diesen GitHub-Release.
- Versionsangaben in `VERSION`, Projektgenerator/Xcode-Projekt, Server-Paket, API und Healthcheck-Test abgeglichen.

## Entwicklungszeitraum von 0.2.0 bis 0.3.0

Am 24. September 2026 wurde die Korrektur für freigegebene Schranken an der Tisno-Brücke als Debug-App auf Michaels iPhone 15 Pro installiert und der Pi aktualisiert. Michael hat die funktionierende Routenplanung anschließend bestätigt. 90 Swift-Tests, 45 Backend-Tests, Simulator- und signierter Gerätebuild sowie die Live-Prüfungen am Pi waren erfolgreich. Details stehen unter „Unveröffentlicht“ im [Änderungsprotokoll](../CHANGELOG.md).

Anschließend wurde am selben Tag die Höhenanreicherung ergänzt und auf iPhone und Pi installiert: 97 Swift- und 55 Backend-Tests, Simulator-/Gerätebuild sowie der UI-Test für gespeicherte Höhenprofile ohne Serverzugang erfolgreich. Die beiden betroffenen Galeriebilder wurden aktualisiert. Der zusätzliche Legacy-Smoke-Test für Kreuzungsdaten war bei diesem Lauf nicht vollständig erfolgreich; Details und Grenzen stehen im Änderungsprotokoll.

App-/Backend-Version bleiben 0.2.0, iOS-Buildnummer 2. Diese installierte Entwicklungsfassung enthält zusätzliche Änderungen gegenüber dem unveränderten Release-Tag `v0.2.0`. Die Kachel-Compilerrevision 2 ist davon unabhängig. Es wurde kein neuer Git-Tag oder GitHub-Release erstellt.

Am 24. September 2026 wurde außerdem die Nachfrage zum Überspringen von Zwischenzielen als signierte Debug-App auf Michaels iPhone 15 Pro installiert und gestartet. Das zugehörige Backend-Datenfeld wurde auf dem Pi bereitgestellt; HTTPS-Healthcheck und Modellprüfung im laufenden Container erfolgreich. 103 Swift-Tests, 63 Backend-Tests und der Simulator-UI-Test für beide großen Antworttasten erfolgreich. Version und Buildnummer bleiben 0.2.0 (2); kein neuer Release und kein Feldtest.

Am 25. September 2026 wurde die Zeitlimitkorrektur für lange ORS-Routen ausschließlich auf dem Pi bereitgestellt. 67 Backend-Tests und Backend-Containerbuild erfolgreich; öffentliche Beispielstrecke Rodgau–Göteborg über den aktualisierten Pi in 63,0 Sekunden mit 1.214,63 km berechnet. Keine Testtour gespeichert, kein iPhone-Build und kein Feldtest. App/Backend bleiben 0.2.0, iOS-Buildnummer 2; kein Tag oder Release.

Am 25. September 2026 wurde die Korrektur der Standortbehandlung beim Fahrtstart als signierte Debug-App auf Michaels iPhone 15 Pro installiert und gestartet. 108 Swift-Kerntests und sechs gezielte Simulator-UI-Tests sowie Simulator- und Gerätebuild erfolgreich. Ein vorübergehender CoreDevice-Verbindungsabbruch wurde durch erneute Installation behoben. Version/Build bleiben 0.2.0 (2); kein Pi-Deployment, kein neuer Tag oder Release und noch kein GPS-Feldtest.

Am 29. September 2026 wurde der Sprachlautstärkeregler mit Kinderreim-Hörprobe als signierte Debug-App auf Michaels iPhone 15 Pro installiert und gestartet. Version/Build bleiben 0.2.0 (2); kein Pi-Deployment, Tag oder GitHub-Release. Die tatsächliche Hörprobe am Gerät ist noch durch den Nutzer zu prüfen.

Am selben Tag nach Nutzerprüfung korrigiert: nativer iPhone-Systemlautstärkeregler statt zusätzlichem App-Faktor, mit Kinderreim-Hörprobe. Simulator-UI-Test und Simulator-/Gerätebuild erfolgreich; korrigierte Debug-App auf Michaels iPhone installiert und gestartet. Die Kopplung mit den Hardwaretasten und der Klang benötigen eine erneute Geräteprüfung. Weiterhin 0.2.0 (2), kein Release oder Pi-Deployment.

Am 1. Oktober 2026 wurde die tolerante Koordinaten- und Plus-Code-Suche als signierte Debug-App auf Michaels iPhone 15 Pro installiert. Swift-Kerntests, Simulator-Build und abschließender Such-UI-Test erfolgreich; Galeriebild 05 aktualisiert. Version/Build bleiben 0.2.0 (2), kein Pi-Deployment oder Release. Gerätebedienung und Live-Ortsauflösung für kurze Plus Codes sind noch durch den Nutzer zu prüfen.

Am 5. Oktober 2026 wurden „Rad&Wandern“ und „Wandern“ in der lokalen Entwicklungsfassung ergänzt. 120 Swift-Kerntests, 93 Backend-Tests, Simulator-Build und zwei gezielte Simulator-UI-Tests erfolgreich; Galeriebild 06 sowie neue Bilder 17–19 geprüft. Live-ORS-Prüfung vom Mac mit öffentlichen Heidelberger Punkten für Fußprofil, vollständiges Radprofil und Rad-Snapping erfolgreich. Tatsächliche Kombination mit Fußrest bisher durch kontrollierte Anbieterantworten geprüft, kein Feldtest. Version/Build bleiben 0.2.0 (2); keine Installation auf dem iPhone, kein Pi-Deployment, Tag oder Release.

Am selben Tag anschließend auf Nutzerwunsch: Pi-Backend neu gebaut und gestartet, Backend und Datenbank gesund; HTTPS, Zugangsschutz, Profilmodell und beide Routenmodi mit öffentlichen Beispielen erfolgreich geprüft. Signierter Debug-Gerätebuild erstellt, auf Michaels iPhone 15 Pro installiert und gestartet. Version/Build weiterhin 0.2.0 (2), kein Git-Tag oder GitHub-Release; kein Feldtest. Keine Testplanung im Archiv gespeichert.

Am 5. Oktober 2026 anschließend die POI-Zugangskorrektur auf Pi und iPhone bereitgestellt: 121 Swift- und 95 Backend-Tests, gezielter Simulator-UI-Test, Simulator- und signierter Gerätebuild erfolgreich. App auf Michaels iPhone installiert und gestartet; Pi-Backend/Datenbank gesund, HTTPS/Zugangsschutz geprüft. Die vom Nutzer benannte Teststrecke über den Pi in Rad, Rad&Wandern und Wandern erfolgreich bis zum erfassten Netzende; rund 319 m unerfasster Zielzugang ausdrücklich als nicht berechnet angezeigt. Private Koordinaten bleiben außerhalb der versionierten Dateien. Galeriebilder 20/21 zeigen synthetische öffentliche Beispiele. Weiterhin 0.2.0 (2), kein Release oder Feldtest.

Am 5. Oktober 2026 danach die Gipfelpfad-Korrektur auf dem Pi bereitgestellt. 106 Backend- und 121 Swift-Kerntests erfolgreich. Private Nutzer-Teststrecke über die aktualisierte HTTPS-API: bevorzugt befestigt 1.000,4 m Rad / 743,1 m Wandern; nur bekannte befestigte Wege 41,8 m Rad / 1.701,2 m Wandern wegen unbekannter Beläge bereits am Start. Backend und Datenbank gesund, Zugangsschutz geprüft. Diese Änderung betrifft ausschließlich die Serverberechnung; die zuvor installierte iPhone-App nutzt sie bei erneuter Planung, kein neuer Gerätebuild notwendig. Weiterhin 0.2.0 (2), kein Release oder Feldtest.

## Ablauf für weitere Releases

1. Alle vorgesehenen Änderungen prüfen und in `CHANGELOG.md` mit Datum, Verhalten, Grenzen und Tests dokumentieren.
2. `VERSION`, Buildnummer im Generierungsskript sowie beide Server-Versionsangaben aktualisieren. Versionsprüfung im Backend-Test und Dokumentations-UI-Versionsprüfung anpassen.
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

Am 24.09.2026 wurden zusätzlich kurze SRTM-Lücken und widersprüchliche OSM-Knotenstände korrigiert (Compilerrevision 3, weiterhin Kachelschema 1). 100 Swift- und 62 Backend-Tests sowie der signierte iPhone-Build sind erfolgreich. Die beiden gemeldeten Strecken wurden mit dem Swift-Kern und dem aktualisierten Pi reproduziert; App installiert und gestartet. Änderungen bleiben unter „Unveröffentlicht“ bei 0.2.0 (2), ohne neuen Tag oder GitHub-Release.

Am 24.09.2026 wurde die Trennung von Streckenplanung und mitwanderndem 3-km-Umfeld als signierte Debug-App auf Michaels iPhone 15 Pro installiert und gestartet. Backend auf dem Pi aktualisiert; HTTPS, Zugangsschutz und ORS-Konfiguration erfolgreich geprüft. Öffentliche Beispielstrecke Heidelberg–Frankfurt: 89,23 km in 1,56 Sekunden über die API ohne Kreuzungsumfelder, vom Mac geprüft und nicht als Tour gespeichert. Vorher 108 Swift-Tests, 64 Backend-Tests und Simulator-UI-Test erfolgreich. Version/Build bleiben 0.2.0 (2); kein neuer Release und kein Feldtest.


Am 5. Oktober 2026 anschließend die HeiGIT-Migration auf dem Pi installiert: der alte ORS-Endpunkt meldete ausdrücklich `Quota exceeded`, während der vorhandene Schlüssel am aktuellen Endpoint funktioniert. 109 Backend-Tests erfolgreich; Ortsnamen, Höhen und beide Nutzer-Rad-/Wandervarianten über die aktualisierte Pi-API geprüft. Erster Routenaufruf vorübergehend 502, Wiederholung erfolgreich; Backend/Datenbank gesund. Erfolgreiche Routing-/Snap-Antworten werden fünf Minuten nur im Arbeitsspeicher gepuffert. Keine iPhone-Codeänderung; die installierte App nutzt die aktualisierten Dienste bei neuer Berechnung. Unverändert 0.2.0 (2), kein Release oder Feldtest.


Am 5. Oktober 2026 die eindeutige Anzeige der strengen bzw. bevorzugten Belagswahl in der Planung auf Michaels iPhone installiert und gestartet. Simulator- und signierter Gerätebuild sowie gezielter UI-Test beider Anzeigen und Persistenz erfolgreich; Galerie 22/23 an ausschließlich öffentlichen Beispieldaten geprüft. Keine Backendänderung notwendig. Die aktuellen privaten Nutzer-Wegpunkte mit bevorzugt befestigten Wegen über Pi geprüft: 984,1 m Rad / 743,1 m Wandern. Nutzerplanung nicht verändert. Weiterhin 0.2.0 (2), kein Release oder Feldtest.


Am 5. Oktober 2026 anschließend begrenzte Online-Toleranz für unbekannte Straßenbeläge auf dem Pi und aktualisierten Profilhinweis auf Michaels iPhone installiert. 122 Backend-Tests, Simulator- und signierter Gerätebuild und zwei gezielte UI-Tests erfolgreich. Nutzerplanung über den Pi: 1.158,3 m Rad / 1.101,1 m Wandern; rund 223 m fehlende Belagsangabe zwischen Asphaltabschnitten als begrenzte Straßenlücke toleriert. Rohbeläge bleiben unbekannt; lokale Offline-Radplanung bleibt vorsichtiger. Galerie 06/24 an öffentlichen Beispielen aktualisiert. Version/Build unverändert 0.2.0 (2), kein Release oder Feldtest.


Am 5. Oktober 2026 die Kartenwahl mit deutschem Standard bei jedem vollständigen App-Start ergänzt: Hell, Detailreich, Dunkel, Satellit und Topografisch über Ebenensymbol in Planung/Fahrt und Einstellungen. Simulator-Build und zwei abschließende UI-Tests erfolgreich, zehn Galeriebilder an öffentlichen Beispieldaten aktualisiert bzw. ergänzt und visuell geprüft. Keine Geräteinstallation, kein Pi-Deployment, Tag oder GitHub-Release; weiterhin 0.2.0 (2), kein Feldtest.


Am 5. Oktober 2026 anschließend auf Nutzerwunsch die Kartenwahl auf Michaels iPhone 15 Pro installiert. Signierter Debug-Gerätebuild erfolgreich; App und Live-Aktivität sowie eingebundene Rasterstile geprüft, Installation und Geräte-App-Liste erfolgreich. Automatischer App-Start wegen gesperrtem iPhone abgelehnt; die neue Kartenwahl muss nach Entsperren am Gerät geprüft werden. Weiterhin 0.2.0 (2), kein Pi-Deployment, Tag, GitHub-Release oder Feldtest.


Am 6. Oktober 2026 nach Entsperren die bereits installierte BikeNavi-App auf Michaels iPhone 15 Pro erfolgreich gestartet (CoreDevice-Start bestätigt). Keine erneute Installation oder Codeänderung in diesem Schritt; Bedienung der Kartenansichten am Gerät durch den Nutzer noch zu prüfen, kein Feldtest.


Am 6. Oktober 2026 wurde die Blogfunktion in der Entwicklungsfassung 0.3.0 (3) auf Pi und Michaels iPhone 15 Pro bereitgestellt. Vorher 137 Backend- und 126 Swift-Kerntests, gezielte Simulator-UI-Tests einschließlich Offline-Neustart und abschließender HTML-/Topografievorschau sowie Simulator- und signierter Gerätebuild erfolgreich. Pi-Datenbank gesichert und Wiederherstellung separat geprüft; vorhandenen OpenAI-Schlüssel ausschließlich auf dem Pi übernommen, zwei öffentliche KI-Beispielblogs erfolgreich erstellt und technische Pi-Einträge danach gelöscht. Appinstallation erfolgreich; automatischer Start wegen gesperrtem iPhone abgewiesen, nach Entsperren manuell öffnen. Kamera-/Fotoauswahl am echten iPhone, längere Offline-Fahrten und GPS-Feldtest weiterhin offen. Kein zusätzlicher Git-Tag oder GitHub-Release durch diesen Arbeitslauf; weitere Korrekturen unter „Unveröffentlicht“.


Am 6. Oktober 2026 anschließend nach Nutzer-Testfahrt die Blogtasten direkt in Fahrt und zugehöriger Planung ergänzt und GPS-Neuerfassung im Stand überarbeitet. 126 Swift-Kerntests, gezielte Simulator-UI-Tests (verzögerter frischer Beispiel-Fix, Offline-Neustart und Blogzugang), Simulator-/signierter Gerätebuild und Signaturprüfung erfolgreich. Korrigierte Entwicklungsfassung 0.3.0 (3) auf Michaels iPhone installiert und gestartet. Pi erhält große topografische Streckenkarte, m/km-Profilachsen und gehaltvollere Hintergrundkapitel mit gespeicherten Recherchequellen; abschließend 143 Backend-Tests erfolgreich. Private neueste Tour als weitere Blogfassung erhalten, Quellenzuordnung redaktionell geprüft. Abschließende Karte-/Profil-/Planungs-UI-Prüfung und visuelle Galerieprüfung erfolgreich. Kein weiterer Tag oder GitHub-Release; konkrete ursprüngliche Fehlermeldung der Ortserfassung nicht reproduziert, erneuter tatsächlicher GPS-/Kamerafeldtest noch offen.
