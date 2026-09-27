# BikeNavi für Android

Die Android-App arbeitet eigenständig: **kein Raspberry Pi, kein BikeNavi-Server,
kein Tailscale, kein Konto**. Routing, Fahrtaufzeichnung und Archiv laufen auf
dem Telefon. Neue Wege lädt sie bei Bedarf direkt aus OpenStreetMap über
Overpass; die Ortssuche nutzt einen einstellbaren Photon-HTTPS-Dienst. Die
Grundkarte benötigt Internet, soweit keine Kacheln bereits im Cache liegen.

## Installation

1. Auf GitHub unter **Actions → Android** den neuesten erfolgreichen Lauf
   öffnen und das Artefakt **BikeNavi-Android-debug** herunterladen.
2. Das darin enthaltene `app-debug.apk` auf Android 8 oder neuer installieren.
   Android kann eine einmalige Freigabe für die Installation aus der gewählten
   Datei-App verlangen. Das Debug-APK ist eine Entwicklungsfassung.
3. Standort und, falls gewünscht, Benachrichtigungen erlauben. Für Bosch-Daten
   zusätzlich Bluetooth-Berechtigungen erteilen.

Quellprojekt: `android/` in Android Studio öffnen. JDK 17, Android SDK 35
und Gradle 8.9 werden benötigt. CI führt
`gradle -p android :app:testDebugUnitTest :app:assembleDebug` aus.

## Planung und Fahrt

- **Standort** verwendet eine frische GPS-Messung. Alternativ Start und Ziel
  durch langes Drücken auf die Karte wählen; ein weiterer langer Druck bietet
  Zwischenziel, neuen Start/Zielpunkt oder Favorit an.
- **Suche** fragt Photon nur nach einem ausdrücklichen Suchauftrag ab.
  **Orte** verwaltet lokale Favoriten. **Wegpunkte** kann eine Tour umkehren,
  Zwischenziele entfernen und die Planung zurücksetzen.
- **Profil** wählt Radtyp, E-Unterstützung, Belagswunsch und Hügelpräferenz.
  **Route** lädt fehlende OSM-Gebiete und rechnet lokal. Straßenregeln,
  Sperren, Einbahnstraßen und unterstützte Abbiegebeschränkungen werden
  berücksichtigt. **Details** zeigt Länge und Belagsverteilung.
- **Plan speichern** legt die Tour mit Wegpunkten und Profil im Archiv ab.
  Die aktuelle Planung bleibt nach App-Neustart erhalten.
- **Fahrt** startet die GPS-Aufzeichnung im Vordergrunddienst. Der nächste
  Abbieger, die Reststrecke und eine Benachrichtigung sind sichtbar; wahlweise
  spricht die App den Hinweis. Erneutes Drücken bietet Pause, Speichern und
  Verwerfen an. Bei bestätigter Routenabweichung sucht das Telefon lokal einen
  Anschluss bis zum nächsten noch offenen Zwischenziel. GPS-Rohpunkte bleiben
  unverändert.
- **Touren** enthält Pläne und Fahrten. Für Fahrten gibt es Karte,
  Höhen-/Leistungsdiagramme und GPX mit Uhrzeiten und verfügbaren Höhenwerten.
- **Bike** sucht nach Bosch-Smart-System-Bikes und liest verfügbare Live-Daten
  über Bluetooth. Akku, Unterstützungsmodus, Fahrer-/Motorleistung, Kadenz und
  Geschwindigkeit werden nur angezeigt, wenn ein passendes Datenpaket
  empfangen wurde. Während der Fahrt werden empfangene Werte lokal gesichert.

OSM-Graphen bleiben in mehreren Gebietsdateien auf dem Telefon. Eine gespeicherte
Route kann ohne erneuten Download navigiert werden. Nicht gespeicherte Gebiete,
Ortssuche und bisher nicht geladene Kartenkacheln benötigen Internet. Der
Photon-Dienst ist unter Einstellungen austauschbar. Öffentliche Dienste sind
für einzelne private Anfragen gedacht; große Touren können an Downloadlimits
stoßen.

## Technische Grenzen

- Die Android-Ansichten und die flache Rasterkarte sind eigenständig gestaltet;
  die perspektivische iPhone-MapLibre-Kamera, die grafische iPhone-Live-Aktivität
  und die genauen Kreuzungsarme auf dem Sperrbildschirm sind nicht portiert.
  Die Android-Benachrichtigung zeigt stattdessen Text.
- Start und Ziel werden am nächsten OSM-Knoten bis 500 m angesetzt.
  Der ungeprüfte Abstand zum gewählten Kartenpunkt wird derzeit nicht als
  Wegstück gezeichnet. Eine Fahrprobe muss diesen Anschluss und die
  Neuberechnung überprüfen. Brückenöffnungszeiten und aktuelle Sperren
  werden nicht bestimmt.
- Höhen für berechnete Routen und vollständige Offline-Kartenpakete sind nicht
  vorhanden; gespeicherte GPS-Höhen können im Fahrtarchiv angezeigt werden.
- Bosch-BLE ist lesend implementiert; die Verbindung und deren Datenformat
  müssen mit einem echten kompatiblen Bike getestet werden. Der
  Benachrichtigungs-Deskriptor wird für BLE-Notifications aktiviert;
  Motorsteuerung wird nicht angesprochen.
- Android und iPhone haben wegen der Pi-freien Architektur getrennte Archive.
  Ein automatischer Import der bereits auf dem iPhone oder Pi gespeicherten
  Touren ist noch nicht vorhanden.
- Build und Unit-Tests laufen in CI. Android-Gerätetest, längere Fahrt,
  Bluetooth-Gerätetest und Prüfung bei gesperrtem Bildschirm stehen aus.

Karten- und Wegenetzdaten: © OpenStreetMap contributors (ODbL). Ortssuche:
[Photon](https://github.com/komoot/photon). Beim Fahren gelten immer die
Beschilderung und die tatsächlichen Bedingungen vor Ort.
