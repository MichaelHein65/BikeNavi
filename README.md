<p align="center"><img src="ios/BikeNavi/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="144" alt="BikeNavi-Logo: Fahrrad mit Navigationspfeil"></p>

# BikeNavi

**Version 0.3.0 · iOS-Build 3 · Entwicklungsfassung vor 1.0**

[Änderungen](CHANGELOG.md) · [GitHub-Releases](https://github.com/MichaelHein65/BikeNavi/releases) · [Alle Bildschirme](docs/BILDSCHIRME.md) · [Versionierung](docs/VERSIONIERUNG.md)

Native iPhone-App für Fahrradtouren mit einem privaten Raspberry-Pi-Backend. Produktentscheidungen stehen in [docs/KONZEPT.md](docs/KONZEPT.md), die technische Struktur in [docs/ARCHITEKTUR.md](docs/ARCHITEKTUR.md) und der tatsächliche Entwicklungsstand in [docs/UMSETZUNG.md](docs/UMSETZUNG.md).

## Einblicke in die App

Echte Simulator-Aufnahmen mit öffentlicher Heidelberger Beispielroute. Die Beispielaufzeichnung und ihre Bike-Messwerte sind synthetische Demonstrationsdaten.

| Planen | Fahren | Touren | Einstellungen |
| --- | --- | --- | --- |
| <img src="docs/images/01-planen.png" width="220" alt="Planung mit Route und Tourdaten"> | <img src="docs/images/12-fahren.png" width="220" alt="Navigation mit Standort unten und 500 m Vorausschau"> | <img src="docs/images/08-touren.png" width="220" alt="Tourenarchiv"> | <img src="docs/images/11-einstellungen.png" width="220" alt="App-Einstellungen ohne Zugangsdaten"> |

Die [vollständige Galerie](docs/BILDSCHIRME.md) zeigt außerdem Karte, Wegpunkte, Favoriten, Suche, Fahrprofil, Routendetails, Fahrtaufzeichnung, Diagramme, Bike-Verbindung und Pause.

## Starten

1. `BikeNavi.xcodeproj` in Xcode öffnen und das Scheme **BikeNavi** wählen.
2. Für den Simulator ein iPhone mit iOS 17 oder neuer auswählen und starten.
3. Für ein echtes iPhone unter **Signing & Capabilities** das eigene Development Team wählen. Das iPhone muss Zugriff auf das private Tailscale-Netz haben.
4. In der App unter **Einstellungen** die eigene Tailscale-HTTPS-Adresse und den BikeNavi-Zugangsschlüssel aus der lokalen `.env` eintragen.
5. **Speichern und Verbindung prüfen** antippen. Danach Start und Ziel auf der Karte setzen oder über die Suche auswählen.

Die Streckenplanung erfolgt mit eingerichtetem Pi über openrouteservice und benötigt einen ORS-Schlüssel auf dem Pi. Dabei wird kein Wegenetz entlang der gesamten Tour heruntergeladen. Die lokale Rückführung lädt unabhängig davon das Umfeld um den Standort und hält während der Fahrt einen Suchradius von drei Kilometern bereit, soweit die Daten rechtzeitig verfügbar sind. Ohne eingerichteten API-Client bleibt die lokale Planung aus vorhandenen Gebietsdaten möglich.

## Tourtagebuch und Blog

Während einer laufenden Fahrt speichert **Blog-Ort festhalten** einen aktuellen Standort, eine Notiz und optional ein verkleinertes Foto zunächst nur auf dem iPhone. Nach der Fahrt werden diese Orte zusammen mit der Fahrt an den privaten Pi synchronisiert. Im Tourenarchiv erzeugt **Tourtagebuch & Blog** daraus eine portable HTML-Fassung mit Streckenübersicht, Höhenprofil, eigenen Bildern und optionalen topografischen Ausschnitten.

Ohne `BLOG_OPENAI_API_KEY` und `BLOG_OPENAI_MODEL` auf dem Pi erzeugt BikeNavi einen Vorlagenentwurf. Mit beiden optionalen Werten darf der Pi einen kreativen Text über die Responses API erzeugen; dabei übermittelt er nur Tourtitel sowie Titel und Notizen der Orte, niemals Fotos oder vollständige GPS-Spuren. Der HTML-Entwurf ist vor einer Veröffentlichung redaktionell zu prüfen.

Wird zuerst ein Ziel gewählt, übernimmt die App automatisch den aktuellen Standort als Start. Solange ein frisches GPS-Signal fehlt, bleibt das Ziel gespeichert; die Route wird nach Eingang des Standorts berechnet. Ein ausdrücklich gewählter Start bleibt unverändert. Ohne Standortfreigabe kann der Start weiterhin auf der Karte gewählt werden.

Sobald Start und Ziel gesetzt sind, erhält die Planung automatisch den Namen „Start → Ziel“. Bei Kartenpunkten werden die Ortsnamen online ergänzt. Ein selbst eingetragener Name wird beibehalten; das Leeren des Namens und Bestätigen mit **Fertig** aktiviert wieder die Automatik. Ohne verfügbare Ortsnamen verwendet die App vorübergehend die Koordinaten.

Den unteren Datenbereich nach unten wischen, um nur den Tourtitel stehen zu lassen und mehr Karte zu sehen; nach oben wischen zeigt wieder alle Daten. Der kleine Pfeil neben dem Titel funktioniert ebenso.

In **Deine Wegpunkte** steht **Tour umkehren** bereit. Start, Ziel und alle Zwischenziele werden dabei in umgekehrter Reihenfolge übernommen; anschließend wird die Route neu berechnet.

Orte lassen sich beim Kartenpunkt oder bei einem Suchtreffer als Favorit speichern. Beim Speichern kann ein frei gewählter Name wie „Zuhause“ oder „Arbeit“ vergeben werden. Das Lesezeichen oben rechts öffnet **Meine Orte**: Ein Ort wird dort direkt zur Tour hinzugefügt und kann zudem umbenannt oder gelöscht werden. Der erste hinzugefügte Ort wird zum Ziel; weitere Orte werden davor in die Tour eingefügt. Favoriten erscheinen außerdem als Lesezeichen auf der Planungskarte und können dort direkt gewählt werden. Liegt ein Routenendpunkt höchstens 100 m von einem Favoriten entfernt, verwendet der automatische kurze Tourname dessen Namen.

In der Fahrtansicht startet der Tab **Fahren** eine berechnete Planung. Die Karte zeigt die Belagsfarben, hält deinen Standort im unteren Fünftel und zeigt 500 m voraus in maximal möglicher Schrägansicht. Während der Fahrt folgt sie dem GPS-Kurs, im Stand und bei langsamer Bewegung der Kompassrichtung des iPhones. Nach Verschieben, Drehen oder Zoomen stellt sie diese Ansicht nach zehn Sekunden wieder her. Der nächste Abbieger steht darüber. Eine Live-Aktivität zeigt auf dem Sperrbildschirm eine fahrtrichtungsorientierte Routengrafik von ungefähr 50 m hinter bis 350 m vor der Position. Aktuelle Position, Abbiegestelle, echte OSM-Nebenstraßen der nächsten Kreuzung und Belagsfarben bleiben zusammen mit Hinweis, Entfernung und Reststrecke auf einen Blick sichtbar; die Dynamic Island verwendet eine kompaktere Fassung. Neue Serverplanungen verzichten auf den Download von OSM-Kreuzungsumfeldern; gespeicherte Kreuzungsdaten älterer Touren bleiben nutzbar. Die Anzeige bildet auch Pausen und Neuberechnungen ab und endet zusammen mit der Fahrt. Die lokale Rückführung lädt ein mitwanderndes Umfeld um die Position. Bei bestätigter Abweichung berechnet das iPhone darin kurze Anschlüsse zurück zur Tour ohne Pi oder Internet. Zum Nachladen neuer Gebiete ist eine Verbindung erforderlich; fehlende Umfelddaten verhindern weder das Speichern der Strecke noch den Fahrtstart. Die ursprüngliche Planung bleibt erhalten. Bei bestätigter Abweichung fragt die Fahrtansicht, ob das nächste Zwischenziel übersprungen werden soll. Beim Wiedereinstieg hinter mehreren offenen Zwischenzielen werden diese gemeinsam angeboten. „Ja, überspringen“ und „Nein, anfahren“ haben jeweils mindestens 96 Punkte hohe Tasten. „Nein“ behält die Ziele bei und unterdrückt dieselbe Nachfrage in der laufenden App-Sitzung; weitere betroffene Zwischenziele können erneut angeboten werden. „Ja“ speichert die ausgelassenen Zwischenziele nur in der Fahrt, auch über Pause und Neustart hinweg. Das Fahrtziel wird nie übersprungen. Ein Magnet zieht die Navigationsanzeige bei kleinen Abweichungen bis 25 m auf die Route, wenn Genauigkeit und Fahrtrichtung passen. Die Aufzeichnung bleibt unverändert. Der Wiedereinstieg berücksichtigt Anschluss plus verbleibende Tour bis zum Ziel, ohne offene Zwischenziele zu überspringen. Drei genaue Messungen über mindestens fünf Sekunden bestätigen eine Abweichung ab etwa 35 m; die lokale Suche ist auf zwei Sekunden begrenzt. Einzelheiten und Grenzen stehen in [LOKALE_NEUBERECHNUNG.md](docs/LOKALE_NEUBERECHNUNG.md). Höhenprofile werden nach der lokalen Berechnung über den Pi aus dem SRTM-Geländemodell ergänzt und mit der Tour offline gespeichert. Bestehende Planungen ohne Höhen werden beim Öffnen ergänzt; bei fehlender Verbindung bleibt die Route nutzbar und der Download kann in den Routendetails erneut gestartet werden.

Die geplante Linie zeigt den Untergrund: Blau = befestigt (z. B. Asphalt/Beton), Violett = Pflaster/Rasengitter, Ocker = Schotter, Braun = unbefestigt (z. B. Erde/Sand/Gras), Türkis = sonstige Beläge (z. B. Holz/Metall), Grau = unbekannt. Alte Routen mit ausschließlich zusammengefassten Belagsdaten bleiben grau, bis **Belagsfarben fehlen · Route neu berechnen** gewählt wird. Die ursprünglichen Indizes kommen aus [ORS Extra Info](https://giscience.github.io/openrouteservice/api-reference/endpoints/directions/extra-info/); Prozentanteile allein werden nicht auf die Karte umgerechnet.

Das [App-Icon und sein Generierungsprompt](design/AppIcon.md) liegen im Projekt; `scripts/prepare_app_icon.py` bereitet das iOS-Asset vor.

## Projektaufbau

- `ios/BikeNavi/`: SwiftUI-App, MapLibre-Karte, GPS und Offline-Downloadverwaltung.
- `ios/BikeNavi/Core/`: Modelle, SQLite-Speicher, API, Navigation und GPX-Export. Diese Dateien werden auch als Swift-Package getestet.
- `server/bikenavi/`: FastAPI, versioniertes Tourenarchiv, ORS-Anbindung und Datenbank.
- `compose.yaml`: eigener PostgreSQL- und Backend-Container für den Pi.
- `scripts/`: Projektgenerierung, Prüfungen, Deployment, Sicherung und Simulatorvorschau.

## Zugangsdaten

`.env` ist von Git ausgeschlossen und auf dem Mac nur für den Dateibesitzer lesbar. `.env.example` enthält ausschließlich die erforderlichen Variablennamen.

```dotenv
ORS_API_KEY=Schlüssel_von_HeiGIT
OVERPASS_URL=https://overpass-api.de/api/interpreter
BIKENAVI_TOKEN=eigener_langer_Zugangsschlüssel
POSTGRES_PASSWORD=eigenes_Datenbankpasswort
BIKENAVI_PORT=8093
BIKENAVI_SERVER_URL=https://dein-pi.tailnet.ts.net:10443
```

Die letzten beiden Zugangsdaten wurden beim Einrichten zufällig erzeugt. Keine echten Werte in Quellcode, Screenshots, Logs oder Git übernehmen. Die App speichert ihren Zugangsschlüssel im iOS-Schlüsselbund.

Der Pi verwendet die aktuellen HeiGIT-Endpunkte (`api.heigit.org`) für Routing, Ortsnamen und Höhen. Die alte ORS-Adresse hat ein reduziertes Kontingent und wird nicht mehr verwendet. Erfolgreiche Routing-/Snap-Antworten werden höchstens fünf Minuten im Arbeitsspeicher gepuffert (maximal 128 Einträge); identische Wiederholungen verbrauchen in dieser Zeit keine neuen Anbieteranfragen. Fehler werden nicht gepuffert. Ein ausgeschöpftes Tageskontingent wird ausdrücklich vom fehlenden Routingzugang unterschieden.

## Rad&Wandern und Wandern

Im Fahrprofil unter **Unterwegs** stehen **Rad**, **Rad&Wandern** und **Wandern** bereit. Die Planung zeigt den vollständigen Belagswunsch: „Befestigte Wege bevorzugen“ lässt unbefestigte Zufahrten zu; „Nur bekannte befestigte Wege“ begrenzt unbekannte oder unbefestigte Abschnitte streng. Radprofile und Belagswünsche bleiben für den Radanteil erhalten. Bei **Wandern** gelten sie nicht; Treppen sind erlaubt.

**Rad&Wandern** versucht zuerst, das Ziel vollständig mit dem Rad zu erreichen. Allgemeine Pfade, Fußwege und Treppen werden dabei vorsichtig dem Wanderanteil zugeordnet; ausgewiesene Radwege bleiben im Radanteil. Eine ORS-Fahrradroute allein bestätigt keine durchgängige Befahrbarkeit. Andernfalls werden Radanschlüsse entlang der letzten 10 km einer einfachen Wanderannäherung verglichen: bis zu 100 Suchpunkte und acht verschiedene Anschlüsse. Der Beginn eines Wanderpfads wird gezielt geprüft; weitere Prüfungen verteilen sich über die Zufahrt. Die verbundene Variante mit dem kürzesten geprüften Fußrest wird gewählt. Bei langen Rad-Anfahrten beginnt die Wanderannäherung im 5-km-Zielumfeld. Alle Zwischenziele bleiben im Radanteil. Die Suche ist begrenzt und garantiert keine weltweit optimale Zufahrt. „Nur bekannte befestigte Wege“ prüft ausschließlich den Radanteil mit einem gesamten 100-m-Toleranzbudget. Online werden zusätzlich kurze fehlende Belagsangaben auf Straßen zwischen bekannten befestigten Abschnitten toleriert: höchstens 250 m je Lücke und 500 m insgesamt. Der Belag bleibt als unbekannt angezeigt. Sand, Schotter, Pfade und unbekannte Anfangs-/Endabschnitte erhalten diese Ausnahme nicht. Die lokale Offline-Radberechnung bleibt beim bisherigen 100-m-Budget. Fehlt bei einer Planung ohne Zwischenziele eine passende geprüfte Radanfahrt, wird eine vollständig gewanderte Route ausdrücklich mit Radanteil 0 m angezeigt. Unbekannte Beläge werden dadurch nicht als befestigt freigegeben. Bei fehlendem Anschluss oder nicht mit dem Rad erreichbaren Zwischenzielen wird ein Fehler angezeigt. Auf der Planungs- und Navigationskarte markiert ein orangefarbenes Fahrrad **Rad abstellen**. Die Routendetails nennen Radstrecke, Fußrest und Koordinaten des Übergangs; dort gibt es auch den entsprechenden Abbiegehinweis. Der Punkt bezeichnet keinen bestätigten Fahrradständer: erlaubtes und sicheres Abstellen vor Ort prüfen. Ist das Ziel vollständig mit dem Rad erreichbar, gibt es keinen Abstellmarker. Enden Rad- und Fußnetz am selben Punkt vor einem POI (bis zu 500 m entfernt), bleibt die Radanfahrt erhalten und ihr Ende wird als Abstellpunkt markiert. Die Planung zeigt den fehlenden Zugang zum Ziel mit Luftlinienabstand. Es wird kein Fußweg erfunden; dieser Rest ist auch in Strecke und Zeit nicht enthalten.

**Wandern** verwendet OSM-Wege über ORS `foot-walking`. Nur einfache Wanderwege (SAC T1) und Wege ohne Schwierigkeitseintrag sind zugelassen; bekannte anspruchsvollere Berg-/Kletterwege werden ausgeschlossen. Fehlende oder unvollständige Schwierigkeitsbereiche in der Anbieterantwort führen zu einem Fehler. Fehlende OSM-Tags selbst sind möglich und werden als Grenze angezeigt; die Karte bestätigt keinen sicheren Zustand vor Ort. POIs dürfen bis zu 500 m vom erfassten Fußwegenetz entfernt liegen. Bei mehr als 20 m Abstand bleibt die tatsächliche Route bis zum Wegende nutzbar; die fehlenden Wegdaten zum POI werden mit Luftlinienabstand ausdrücklich genannt. Der unerfasste Zugang ist weder berechnet noch auf Kletterfreiheit geprüft.

Die Berechnung beider neuer Optionen benötigt den Pi mit aktualisiertem Backend. Gespeicherte Strecken samt Übergang, Ansagen und Aufzeichnung bleiben offline nutzbar. Das bisherige lokale Fahrrad-Wegenetz berechnet dafür keine Rückführung oder neuen Wanderstrecken; es wird nicht als Wander-Wegenetz verwendet.

OSM enthält bereits Wanderwege. Für eine freie zusätzliche Wanderübersicht verlinkt das Profil [Waymarked Trails](https://hiking.waymarkedtrails.org/): markierte OSM-Wanderrouten. Das ist eine externe Übersicht, kein zusätzlicher Offline-Kartendownload und keine Quelle für fehlende OSM-Wege. Hintergrund: [ORS-Wegfilter](https://giscience.github.io/openrouteservice/technical-details/tag-filtering), [Schwierigkeitsdaten](https://giscience.github.io/openrouteservice/api-reference/endpoints/directions/extra-info/trail-difficulty) und [OSM-SAC-Skala](https://wiki.openstreetmap.org/wiki/Key:sac_scale).

## iPhone-Lautstärke

In **Einstellungen** steht die Lautstärke als erste Box, direkt gefolgt von den Pi-Server-Einstellungen. Der Systemregler verändert direkt die iPhone-Medienlautstärke, genau wie die Lautstärketasten während der Wiedergabe. Eine zusätzliche App-Lautstärke gibt es nicht. Änderungen lösen nach kurzer Bewegungspause einen Kinderreim als Hörprobe aus. **Kinderreim anhören** spielt ihn auch ohne Lautstärkeänderung. Navigation und Hörprobe verwenden dieselbe Systemlautstärke. Beim Verlassen der Einstellungen oder Wechsel in den Hintergrund endet die Hörprobe. Mit verbundenen Kopfhörern oder AirPlay gilt der Regler für den aktuellen Audioausgang; manche Ausgänge regeln die Lautstärke selbst.

## Prüfen

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r server/requirements.lock
.venv/bin/python -m pip install --no-deps -e server
.venv/bin/python -m pytest server/tests -q
swift test --scratch-path build/SwiftTests
```

Die Simulator-Interaktionstests lassen sich in Xcode mit **Product → Test** starten. Sie prüfen Einklappen, Ausklappen, den weiterhin sichtbaren Tourtitel und die gespeicherte Panelstellung. Dabei ist die Pi-Verbindung im Simulator bewusst deaktiviert.

Optionale Integrationsprüfungen verwenden den lokalen ORS-Schlüssel und öffentliche Beispielkoordinaten in Heidelberg:

```sh
.venv/bin/python scripts/check_ors.py
.venv/bin/python scripts/smoke_backend.py
.venv/bin/python scripts/check_pi.py
```

`check_pi.py` legt eine bezeichnete technische Testplanung an und entfernt sie anschließend per synchronisierter Löschung aus dem Archiv. Die Tests geben keine Schlüssel aus.

## Xcode-Projekt aktualisieren und bauen

Das Xcode-Projekt ist direkt verfügbar. Nach dem Hinzufügen neuer Swift-Dateien kann es ohne zusätzliche globale Werkzeuge neu erzeugt werden:

```sh
python3 scripts/generate_project.py
xcodebuild -project BikeNavi.xcodeproj -scheme BikeNavi \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages \
  CONFIGURATION_BUILD_DIR="$PWD/build/Products/Debug-iphonesimulator" \
  CODE_SIGNING_ALLOWED=NO build
```

MapLibre Native ist über Swift Package Manager auf Version 6.31.0 festgelegt. Vor dem Bau auf einem echten Gerät muss in Xcode das eigene Development Team gewählt werden. Das Generierungsskript überschreibt `project.pbxproj` und das geteilte Scheme; manuelle Projekteinstellungen deshalb vorher in das Skript übernehmen.

Nach der Installation einer Debug-Fassung kann `python3 scripts/launch_device.py GERÄTE-ID` die App starten und den BikeNavi-Zugang aus der lokalen `.env` im iPhone-Schlüsselbund hinterlegen. Die Geräte-ID liefert `xcrun devicectl list devices`. Das Skript übergibt ausschließlich den App-Zugang zur Laufzeit; der ORS-Schlüssel bleibt auf dem Server, und das App-Bundle enthält keine Zugangsdaten.

## Pi-Betrieb

Das Backend läuft unter `/srv/bikenavi` als Compose-Projekt `bikenavi`. Der HTTP-Port `8093` ist ausschließlich an Loopback gebunden. Tailscale Serve bietet auf Port `10443` den privaten HTTPS-Zugang an. Die vorhandenen Tailscale-Freigaben auf 443, 8443 und 9443 werden nicht verändert.

```sh
# Nur BikeNavi aktualisieren; überträgt auch die lokale .env.
.venv/bin/python scripts/deploy_pi.py

# Nur diese Anwendung ansehen oder stoppen.
ssh pi5 'cd /srv/bikenavi && docker compose ps'
ssh pi5 'cd /srv/bikenavi && docker compose stop'
```

Die Datenbank liegt im persistenten Docker-Volume `bikenavi_database` auf der NVMe. `docker compose down -v` würde diese Daten löschen und ist kein normaler Update-Schritt. Das Backend ist zunächst für einen privaten gemeinsamen Datenbestand ausgelegt; mehrere unabhängige Benutzerkonten sind noch nicht implementiert.

## Sicherung

```sh
.venv/bin/python scripts/backup_pi.py
```

Das Skript erstellt einen PostgreSQL-Dump unter `artifacts/backups/` auf dem Mac, stellt ihn zur Prüfung in einer eigens erzeugten temporären Datenbank wieder her und entfernt diese Testdatenbank danach. Die Originaldatenbank bleibt unverändert. Automatische periodische Sicherungen sind noch nicht eingerichtet.

## Karten und Offline

Online-Karten stellt MapLibre dar. Beim vollständigen App-Start erscheint immer die bisherige **Standard · Deutsch**-Karte (OpenFreeMap Liberty mit deutschen Beschriftungen). Über das Ebenensymbol in Planung und Fahrt oder **Einstellungen → Karten → Kartenansicht** stehen außerdem **Hell** (Positron), **Detailreich** (Bright), **Dunkel**, **Satellit** (Esri World Imagery, ohne Ortsbeschriftungen) und **Topografisch** (OpenTopoMap mit Gelände und Höhenlinien) zur Verfügung. Die Auswahl gilt für alle Karten bis zum nächsten vollständigen App-Start; beim Wechsel zwischen Tabs oder nach kurzer Hintergrundpause bleibt sie erhalten. Route und Kartenausschnitt bleiben beim Stilwechsel bestehen.

Ein **Eigener Kartenstil** kann weiterhin als HTTPS-Adresse konfiguriert werden. Seine Adresse bleibt gespeichert, er wird beim Neustart jedoch nicht automatisch aktiviert. Die öffentlichen Ansichten sind Online-Karten; Offline-Paketdownloads werden ausschließlich für einen ausdrücklich gewählten eigenen Kartenstil mit freigegebenem eigenem Server angeboten. Satellitenbilder zeigen keine aktuelle Live-Aufnahme und bestätigen keine befahrbaren Wege. Die topografische Karte verändert weder Routing noch die Wander-Schwierigkeitsprüfung.

Kartenquellen: [OpenFreeMap-Stile](https://github.com/hyperknot/openfreemap-styles), [Esri World Imagery](https://www.arcgis.com/home/item.html?id=10df2279f9684e4a9f6a7f08febac2a9), [OpenTopoMap-Verwendung und CC-BY-SA](https://opentopomap.org/about#verwendung). Die App speichert berechnete Routen und Aufzeichnungen lokal; Navigation entlang einer gespeicherten Route benötigt keinen Routingserver.

Bei langen Strecken kann die Routenberechnung über den Pi ungefähr eine Minute dauern. BikeNavi wartet für die ORS-Anbieterphase bis zu 80 Sekunden; ein erforderlicher Vergleich zweier Fahrradprofile läuft parallel. Währenddessen die Berechnung abwarten. Netzprobleme und Anbietergrenzen können weiterhin einen erneuten Versuch erforderlich machen.

Vollständige Offline-Karten sind erst verfügbar, wenn der eigene Kartenserver samt Stil, Symbolen und Schriftzeichen eingerichtet ist. Der Downloadcode ist vorhanden, die entsprechende Einstellung bleibt bis dahin ausgeschaltet. **Eine lokal gespeicherte Route allein ist noch kein vollständiges Offline-Kartenpaket.**

Quellen: [OpenStreetMap](https://www.openstreetmap.org/copyright), [OpenFreeMap](https://openfreemap.org/), [MapLibre](https://maplibre.org/), [openrouteservice / HeiGIT](https://openrouteservice.org/).

### Standort beim Fahrtstart

Falls noch keine aktuelle Position vorliegt, wartet „Tour starten“ bis zu 15 Sekunden. Im Reiter „Fahren“ zeigt die App „Standort wird ermittelt …“. Die Suche lässt sich abbrechen; ein Tabwechsel oder Verlassen der App bricht den ausstehenden Fahrtstart ebenfalls ab. Nach einem Zeitlimit kann der Start erneut versucht werden. Nur bei tatsächlich verweigerter Berechtigung verweist die App auf die iPhone-Einstellungen.

### Koordinaten in der Ortssuche

Im Suchfeld sind neben Ortsnamen auch WGS84-Koordinaten möglich, ohne Pi oder Internet. Ohne Himmelsrichtungen gilt **Breite; Länge**. Beispiele: `49.4100; 8.7000`, `49,4100 8,7000`, `49°24′36″N 8°42′00″E` oder `N49 24.6 E8 42`. Punkt und Komma als Dezimalzeichen, zusätzliche Leerzeichen, Zeilenumbrüche, typografische Grad-/Minuten-/Sekundenzeichen und `O` für Osten werden erkannt. Grad/Minuten/Sekunden können auch mit Doppelpunkten getrennt werden. Negative Werte bzw. S/W stehen für Süd/West. Der Treffer zeigt die normalisierten Koordinaten und kann wie ein Ort ausgewählt oder gespeichert werden. Bei mehrdeutigen Zahlenfolgen helfen ein Semikolon zwischen den beiden Koordinaten oder Himmelsrichtungen. Dezimalgradpaare haben Vorrang vor möglichen Interpretationen mit unmarkierten Minuten.

Auch **Plus Codes** werden unterstützt: Ein vollständiger Code wie `9F2C2WF2+8F` funktioniert offline. Ein kurzer Code wie `2WF2+8F Rodgau` benötigt den Ortsnamen und eine Pi-Verbindung für dessen Suche. Bei mehreren gefundenen Bezugsorten werden entsprechend mehrere Treffer angeboten. Ein kurzer Code ohne Ortsangabe wird nicht anhand eines möglicherweise unpassenden GPS-Standorts geraten. UTM/MGRS, andere Koordinatensysteme und beliebige Kartenlinks sind nicht Bestandteil dieser Erkennung.
