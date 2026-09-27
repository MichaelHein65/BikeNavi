# BikeNavi Android – eigenständig

Die Android-App nutzt **keinen Raspberry Pi, kein Tailscale, kein Konto und keinen
BikeNavi-Server**. Routenberechnung, Cache, Fahrtaufzeichnung und Tourenarchiv
liegen auf dem Telefon. Für neue Gebiete lädt sie OSM-Fahrradwege direkt von
öffentlichen Overpass-Instanzen; die Grundkarte lädt Kacheln aus dem Internet.
Bereits heruntergeladene Gebiete und gespeicherte Routen lassen sich ohne
Verbindung erneut nutzen, sofern die Start- und Zielpunkte innerhalb des einen
zuletzt gespeicherten Gebiets liegen. Das Kartenbild ist nur im Umfang des
Android-Kachelcache offline vorhanden.

## Bauen und installieren

Android Studio öffnen → Verzeichnis `android/` wählen → Gradle-Synchronisation →
`app` auf einem Android-Gerät ab Version 8.0 (API 26) ausführen. Für den
Gradle-Build werden Android SDK 35, JDK 17, Android Gradle Plugin 8.7.3,
Kotlin 2.0.21 und die deklarierten Maven-Abhängigkeiten benötigt. Ein
Gradle-Wrapper ist nicht eingecheckt; die Gradle-Installation von Android
Studio verwenden. Tests: `gradle :app:testDebugUnitTest`.

## Bedienung

1. Standort erlauben oder die Karte für den Start lange drücken.
2. Für das Ziel nochmals lange drücken; **Route** berechnet die Fahrradstrecke.
3. **Fahrt** beginnt die GPS-Aufzeichnung mit sichtbarer Systembenachrichtigung;
   ein zweiter Druck beendet und speichert die Tour.
4. **Touren** wählt eine gespeicherte Tour und exportiert sie als GPX über den
   Android-Dateidialog. Die berechnete Route bleibt nach Neustart erhalten.

Ein neuer Start ersetzt die bisherige Planung. Für den nächsten Download sind
Etappen mit maximal 0,15° Breite und Länge möglich. Ein Downloadbereich enthält
jeweils einen Rand von 0,01°; nur das zuletzt geladene Gebiet wird derzeit
aufbewahrt. GPS-Aufzeichnungen liegen ausschließlich im privaten App-Speicher.

## Grenzen dieser Android-Fassung

- Die App ist eine eigenständige, nutzbare Grundfassung, keine vollständige
  Portierung aller iPhone-Ansichten. Favoriten, Ortsuche, Bosch-Bluetooth,
  Sprachanweisungen, automatische Neuberechnung und synchronisierte
  iPhone-Touren sind noch nicht implementiert.
- Navigation zeigt Reststrecke und Abweichung vom Weg, aber noch keine
  Abbiegehinweise. Eine Abweichung führt nicht automatisch zu einer neuen Route.
- Die Route beginnt am nächsten OSM-Knoten im Umkreis von 500 m; der Anschluss
  vom exakten Start beziehungsweise bis zum exakten Ziel wird nicht gezeichnet.
  Sie eignet sich damit nicht als präzise Führung abseits des Wegenetzes.
- Das konservative OSM-Regelwerk sperrt bedingte Zugänge und nicht unterstützte
  Restriktionen. Es wertet Brückenöffnungszeiten und aktuelle Sperrungen nicht
  aus. Vor Ort gelten Beschilderung und Verkehrsregeln.
- Es gibt keine vollständigen Offline-Kartenpakete. Neue Gebiete benötigen
  Internet und verfügbare öffentliche Overpass-Dienste. Der zuletzt geladene
  Graph kann groß sein; Android kann für sehr ausgedehnte Gebiete Speicher
  benötigen. Die App ist nur für private, moderate Downloads vorgesehen.
- Der GPX-Export enthält die Geometrie, derzeit keine Zeitstempel.
- Ein Geräte- oder Feldtest und ein Android-Build müssen auf einer Umgebung
  mit Android SDK nachgeholt werden.

OSM-Daten: © OpenStreetMap contributors, ODbL.
