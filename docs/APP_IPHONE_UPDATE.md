# BikeNavi: Änderungen bauen und auf dem iPhone installieren

## Vorabversion auf dem iPhone — 21. Oktober 2026

Signierter Release-Build **0.5.0 (5)** aus dem veröffentlichten Commit `3765b1f` / Tag `v0.5.0-rc.1` am **21. Oktober 2026 um 10:47 Uhr MESZ** auf Michaels iPhone 15 Pro installiert. Die Installation funktionierte trotz Gerätesperre; die anschließende Geräte-App-Abfrage bestätigt Version 0.5.0 und Build 5. App und Live-Aktivität waren vorher per Plist und strenger Signaturprüfung geprüft.

Der automatische Start wurde anschließend ausdrücklich mit **Locked / FBSOpenApplicationErrorDomain 7** abgelehnt. Dies ist kein fehlgeschlagener Installationsvorgang: App nach Entsperren manuell öffnen. Nach dem Pi-Update um 11:18 Uhr MESZ erneut versucht, ohne eine laufende App zu beenden: weiterhin Locked. Keine Umgehung der iOS-Sperre. Vorhandene Konfiguration und App-Daten wurden durch ein Update erhalten, nicht durch Deinstallation ersetzt. Echte Bedienungs-/GPS-/Bosch-/Flugmodus- und Langzeittests bleiben offen.

[GitHub-Vorabversion](https://github.com/MichaelHein65/BikeNavi/releases/tag/v0.5.0-rc.1) · [Automatisierter Prüfstand](UMSETZUNG.md#vorabversion-050-rc1--21-oktober-2026) · [Neue Radfunktionen](RAD_OFFLINE.md).

Diese Anleitung ist für einen Arbeits-Thread, der Änderungen an der iPhone-App umsetzt und sie auf Michaels iPhone testet. Arbeitsverzeichnis ist das Projektwurzelverzeichnis `20260918_BikeNavi`.

## Pi-Stand dieser Vorabversion

Am 21. Oktober 2026 nach erfolgreicher Sicherungs-/Wiederherstellungsprüfung von 307 Archivdatensätzen auf **0.5.0-rc.1** aktualisiert. Backend und Datenbank gesund; 20 laufende Quellmodule stimmen per SHA-256 mit Commit `3765b1f` überein. HTTPS, Anmeldung, Beispielrouting, Speicherung/Abgleich und GPX-Metadatenerhalt live erfolgreich. Technische Testtouren wieder gelöscht.

Bei der ursprünglichen RC1-Abnahme scheiterten neue OSM-Pakete zweimal mit HTTP 503. Die anschließende **Serverkorrektur unter Unveröffentlicht** verwendet für Kroatien einen lokalen geprüften Länderindex und hat die erneuten 3×3- und 5×5-Downloads über den Pi samt Swift-Verarbeitung bestanden. Die vorhandene iPhone-App **0.5.0 (5)** ist kompatibel; keine erneute Installation nötig. Außerhalb installierter Länder bleibt der Onlineanbieter erforderlich. [Korrektur und Live-Abnahme](UMSETZUNG.md#offline-regionsdownloads-korrigieren--21-oktober-2026).

## Vor dem ersten Gerätetest

1. Das iPhone per USB verbinden, entsperren und dem Mac vertrauen.
2. In Xcode ist für das Projekt das Development Team `4JDC67R76Q` eingerichtet. Der Wert wird beim Kommando unten zusätzlich gesetzt, damit die lokale Signierung eindeutig bleibt.
3. Die lokale `.env` muss vorhanden sein. Sie enthält mindestens:

   ```dotenv
   BIKENAVI_SERVER_URL=https://pi5-node.tailc0dc7c.ts.net:10443
   BIKENAVI_TOKEN=...
   ```

   Der ORS-Schlüssel gehört nur auf den Pi und wird nie in die App oder in Git eingecheckt.

## Gerät finden

```sh
xcrun devicectl list devices
```

Für Michaels iPhone lautet die CoreDevice-ID derzeit:

```text
0326F561-4FFB-5F38-BCE2-D0C3710404CD
```

Die Xcode-Ziel-ID lautet derzeit:

```text
00008130-00180D8E38C1401C
```

Bei einem anderen Gerät stets die beiden IDs aus der Ausgabe ermitteln, statt diese Werte zu übernehmen.

## App bauen

Neue Swift-Dateien zuerst in das Xcode-Projekt übernehmen:

```sh
python3 scripts/generate_project.py
```

Danach die Debug-App für das angeschlossene iPhone bauen:

```sh
xcodebuild -project BikeNavi.xcodeproj -scheme BikeNavi -configuration Debug \
  -destination 'platform=iOS,id=00008130-00180D8E38C1401C' \
  -derivedDataPath build/DerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages \
  CONFIGURATION_BUILD_DIR="$PWD/build/Products/Debug-iphoneos" \
  DEVELOPMENT_TEAM=4JDC67R76Q -allowProvisioningUpdates build
```

Erwartetes Ergebnis: `** BUILD SUCCEEDED **`. Die installierbare App liegt danach unter `build/Products/Debug-iphoneos/BikeNavi.app`.

## Installieren und starten

```sh
xcrun devicectl device install app \
  --device 0326F561-4FFB-5F38-BCE2-D0C3710404CD \
  build/Products/Debug-iphoneos/BikeNavi.app

python3 scripts/launch_device.py 0326F561-4FFB-5F38-BCE2-D0C3710404CD
```

`launch_device.py` startet die App, beendet dabei eine eventuell laufende ältere App-Version und hinterlegt `BIKENAVI_SERVER_URL` sowie `BIKENAVI_TOKEN` im iPhone-Schlüsselbund. Keine Zugangsdaten erscheinen im Terminal oder im App-Bundle.

Falls nur ein bereits konfigurierter Build neu gestartet werden soll:

```sh
xcrun devicectl device process launch \
  --device 0326F561-4FFB-5F38-BCE2-D0C3710404CD \
  --terminate-existing de.michaelhein.BikeNavi
```

## Serveränderungen auf dem Pi ausrollen

Änderungen unter `server/`, `compose.yaml` oder an serverseitigen Umgebungsvariablen erfordern zusätzlich ein Pi-Deployment:

Vorher die aktuelle Datenbank auf den Mac sichern und in einer separaten temporären Datenbank wiederherstellen. Erst nach erfolgreicher Prüfung deployen:

```sh
python3 scripts/backup_pi.py
.venv/bin/python scripts/deploy_pi.py
.venv/bin/python scripts/check_pi.py
```

Der zweite Befehl prüft HTTPS, Anmeldung, Routing, Kreuzungsdaten und Speicherung auf dem Pi. Er legt eine technische Testtour an und löscht sie anschließend wieder.

## Vor dem Commit

```sh
git diff --check
.venv/bin/python -m pytest server/tests
swift test --scratch-path build/SwiftTests
git status --short
```

Unverwandte Änderungen im Arbeitsverzeichnis niemals pauschal mit `git add .` übernehmen. Die lokale `.env` bleibt stets unversioniert.
