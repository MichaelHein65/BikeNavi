# BikeNavi

Native iPhone-App für Fahrradtouren mit einem privaten Raspberry-Pi-Backend. Produktentscheidungen stehen in [docs/KONZEPT.md](docs/KONZEPT.md), die technische Struktur in [docs/ARCHITEKTUR.md](docs/ARCHITEKTUR.md) und der tatsächliche Entwicklungsstand in [docs/UMSETZUNG.md](docs/UMSETZUNG.md).

## Starten

1. `BikeNavi.xcodeproj` in Xcode öffnen und das Scheme **BikeNavi** wählen.
2. Für den Simulator ein iPhone mit iOS 17 oder neuer auswählen und starten.
3. Für ein echtes iPhone unter **Signing & Capabilities** das eigene Development Team wählen. Das iPhone muss Zugriff auf das private Tailscale-Netz haben.
4. In der App unter **Einstellungen** die eigene Tailscale-HTTPS-Adresse und den BikeNavi-Zugangsschlüssel aus der lokalen `.env` eintragen.
5. **Speichern und Verbindung prüfen** antippen. Danach Start und Ziel auf der Karte setzen oder über die Suche auswählen.

Der openrouteservice-Schlüssel gehört ausschließlich in `ORS_API_KEY` der `.env` auf dem Backend, nicht in die iPhone-App.

Wird zuerst ein Ziel gewählt, übernimmt die App automatisch den aktuellen Standort als Start. Solange ein frisches GPS-Signal fehlt, bleibt das Ziel gespeichert; die Route wird nach Eingang des Standorts berechnet. Ein ausdrücklich gewählter Start bleibt unverändert. Ohne Standortfreigabe kann der Start weiterhin auf der Karte gewählt werden.

Sobald Start und Ziel gesetzt sind, erhält die Planung automatisch den Namen „Start → Ziel“. Bei Kartenpunkten werden die Ortsnamen online ergänzt. Ein selbst eingetragener Name wird beibehalten; das Leeren des Namens und Bestätigen mit **Fertig** aktiviert wieder die Automatik. Ohne verfügbare Ortsnamen verwendet die App vorübergehend die Koordinaten.

Den unteren Datenbereich nach unten wischen, um nur den Tourtitel stehen zu lassen und mehr Karte zu sehen; nach oben wischen zeigt wieder alle Daten. Der kleine Pfeil neben dem Titel funktioniert ebenso.

Orte lassen sich beim Kartenpunkt oder bei einem Suchtreffer als Favorit speichern. Beim Speichern kann ein frei gewählter Name wie „Zuhause“ oder „Arbeit“ vergeben werden. Das Lesezeichen oben rechts öffnet **Meine Orte**: Dort wird der Einsatzzweck Start, Zwischenziel oder Ziel gewählt; Orte lassen sich zudem umbenennen oder löschen.

In der Fahrtansicht startet der Tab **Fahren** eine berechnete Planung. Die Karte zeigt die Belagsfarben, folgt der Fahrtrichtung und weist auf den nächsten Abbieger hin. Weicht die Fahrt mindestens 80 m für zehn Sekunden von der Route ab, berechnet die App über den Pi eine neue Verbindung; noch offene Zwischenziele bleiben erhalten. Weitere automatische Berechnungen warten mindestens 90 Sekunden.

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
BIKENAVI_TOKEN=eigener_langer_Zugangsschlüssel
POSTGRES_PASSWORD=eigenes_Datenbankpasswort
BIKENAVI_PORT=8093
BIKENAVI_SERVER_URL=https://dein-pi.tailnet.ts.net:10443
```

Die letzten beiden Zugangsdaten wurden beim Einrichten zufällig erzeugt. Keine echten Werte in Quellcode, Screenshots, Logs oder Git übernehmen. Die App speichert ihren Zugangsschlüssel im iOS-Schlüsselbund.

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

Online-Karten kommen zunächst von OpenFreeMap auf Basis von OpenStreetMap. MapLibre stellt sie dar. Die App speichert berechnete Routen und Aufzeichnungen lokal; Navigation entlang einer gespeicherten Route benötigt keinen Routingserver.

Vollständige Offline-Karten sind erst verfügbar, wenn der eigene Kartenserver samt Stil, Symbolen und Schriftzeichen eingerichtet ist. Der Downloadcode ist vorhanden, die entsprechende Einstellung bleibt bis dahin ausgeschaltet. **Eine lokal gespeicherte Route allein ist noch kein vollständiges Offline-Kartenpaket.**

Quellen: [OpenStreetMap](https://www.openstreetmap.org/copyright), [OpenFreeMap](https://openfreemap.org/), [MapLibre](https://maplibre.org/), [openrouteservice / HeiGIT](https://openrouteservice.org/).
