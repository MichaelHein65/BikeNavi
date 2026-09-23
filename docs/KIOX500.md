# Bosch Kiox 500: Bluetooth und Fahrdaten

Stand: 20. September 2026. Recherche und eigener Verbindungstest mit Michaels Bike und iPhone 15 Pro. Direkter Akkudatenempfang am iPhone bestätigt; Leistungswerte noch nicht am fahrenden Bike geprüft.

## Bestätigter Kontext

Michael verwendet ein **Bosch Kiox 500 am smarten System**. Gewünscht ist eine direkte Bluetooth-Verbindung zwischen Bike und iPhone zur Anzeige von Bike-Daten in BikeNavi. Am 20.09.2026 wurde dafür ein begrenzter Diagnosebildschirm eingebaut und auf Michaels iPhone installiert.

Nach der Machbarkeitsprüfung wurde der Umfang am 19.09.2026 konkretisiert: **Der Akkustand genügt als erste Funktion.** Fahrmodus sowie Motor- und Fahrerleistung sind optionale Zusatzwerte. Die zuvor untersuchte Ausgabe von Navigationshinweisen auf dem Kiox wird vorerst nicht weiterverfolgt; die Recherche dazu bleibt unten als Hintergrund erhalten.

| Wert | Priorität | Stand der bekannten Schnittstelle |
| --- | --- | --- |
| Akkustand in Prozent | Erstes Ziel | **Direkt am iPhone empfangen: 88 %, später 89 %**, über den Smartphone-Statuskanal. 88 % separat mit dem Pi abgeglichen. |
| Fahrmodus, z. B. Eco oder Turbo | Optional | Direkter Empfang des Codes **3** bestätigt. Zuordnung zu Michaels Modusnamen und Wechsel zwischen Modi noch offen. |
| Fahrerleistung in Watt | Optional | LDI am Pi liefert im Stand 0 W. Auswertung des Smartphone-Feldes vorbereitet; am iPhone im bisherigen Ladeversuch nicht empfangen. |
| Motorleistung in Watt | Optional | Feld des Smartphone-Protokolls aus öffentlicher Referenz bekannt und Auswertung vorbereitet; am eigenen iPhone noch nicht empfangen. |

Quelle für die Felder: [Boschs Protobuf-Schema, Kopie im Referenzprojekt](https://github.com/rweijnen/bosch-bes3-reader/blob/main/docs/ebike_live_data.proto). Fahrerleistung und Motorleistung sind getrennte Werte. Nicht empfangene oder veraltete Werte sollen als nicht verfügbar erkennbar bleiben; fehlende Leistung ist kein gemessener Wert von 0 W.

## Eigener iPhone-Test am 20.09.2026

Bike eingeschaltet, Ladegerät angeschlossen, bestehende Flow-Verbindung auf Michaels iPhone. Der Shelly-Pi-Empfänger lief unverändert weiter. Keine Kopplungen gelöscht, keine Fahrrad-Einstellungen oder Steuerbefehle geschrieben.

1. CoreBluetooth findet `smart system eBike` über `retrieveConnectedPeripherals(withServices:)`. BikeNavi kann sich zur bestehenden Systemverbindung anmelden und die Bosch-Dienste auflisten.
2. Der offizielle LDI-Dienst `eb21` lässt sich abonnieren und lesen, liefert über diese iPhone-Verbindung aber **leere Antworten**. Dieselbe Characteristic liefert dem Pi gleichzeitig vollständige LDI-Daten. Erfolgreiches Verbinden allein genügt also nicht.
3. Die Notify-Characteristic `00000011-eaa2-11e9-81b4-2a2ae2dbcce4` liefert direkt ans iPhone gerahmte Smartphone-Statusdaten. Für den Empfang wurden nur Benachrichtigungen aktiviert, keine Anwendungsbefehle geschrieben.
4. Konkrete Messungen: wiederholt `30 04 98 09 08 03` (Moduscode 3); um **15:33:05 MESZ** `30 04 80 88 08 58` (**88 % Akku**). Das sind iPhone-Bluetooth-Aufzeichnungen, keine vom Pi in die App übernommenen Werte. Der Pi bestätigte 88 % unabhängig.
5. Akku wird nicht in jedem Paket gesendet. Die Testansicht zeigt nach 30 Sekunden „Zuletzt … %“ plus Empfangszeit, statt einen neuen Messzeitpunkt zu behaupten. Fehlende Leistungsfelder bleiben „Nicht verfügbar“.
6. Nach Installation der auswertenden Testversion: automatische Wiederverbindung zur gespeicherten Bike-Kennung erfolgreich. Um **15:38:11 MESZ** folgte `30 04 80 88 08 59` (**89 %**), direkt im App-Status ausgewertet. Keine Decoderfehler in dieser Sitzung.
7. Michael bestätigte die Bildschirmsperre. Während des kurzen Sperrtests lief der Empfang weiter: zwischen den Statusabfragen um 15:38:34 und 15:39:02 stieg die Zahl ausgewerteter Pakete von 212 auf 266, mit jeweils neuen Modus-Zeitstempeln. Das bestätigt den kurzen Versuch am Entwicklungsgerät, noch keinen mehrstündigen Tourbetrieb.

Ausgelesene Geräteinformationen betreffen die Bedieneinheit **BRC3600**, nicht die Kiox-Display-Firmware: Software 20.9.0, Firmware 6.1.14.1114.5.13, Hardware 8.0.2.

Das Smartphone-Format und die Feldkennungen stammen aus der [Protokollbeschreibung des Bosch-eBike-Monitor-Autors](https://github.com/RobbyPee/Bosch-Smart-System-Ebike-Garmin-Android/blob/main/BLEdata.md). Eigener Swift-Decoder mit strikter Längen-/Werteprüfung; unbekannte Felder werden nicht als Messwerte interpretiert. Bekannte IDs: Akku `8088`, Modus `9809`, Fahrerleistung `985B`, Motorleistung `985D`. Die Namenszuordnung der Modi wird bewusst nicht aus fremden Bike-Konfigurationen übernommen.

Zugang in der App: **Fahren → Dein Bike**, sowohl während einer Tour als auch vor dem Tourstart. Die Karte zeigt Bike-Akku, Fahrmodus, Fahrerleistung und Motorleistung. Fehlende oder mehr als 15 Sekunden alte Modus-/Leistungswerte erscheinen als „—“. Ein älterer Akkustand bleibt mit „Akku zuletzt um …“ erkennbar. Modusnamen werden bis zum Abgleich am Kiox als „Stufe …“ angezeigt.

Die Verbindung startet beim Öffnen von „Fahren“ und verwendet das zuvor ausgewählte Bike. Während einer aktiven oder pausierten Tour bleibt sie auch bei Tabwechsel bestehen. Die Verbindungsdetails lassen sich über „Dein Bike“ oder **Einstellungen → Bosch Kiox 500 · Verbindung testen** öffnen und verwenden denselben zentralen Bluetooth-Dienst. Das Schließen der Details beendet deshalb keine laufende Tourverbindung. Ohne Tour und außerhalb von „Fahren“ endet der Empfang, sobald auch die Details geschlossen sind. Bei einer Trennung wird das gespeicherte Bike erneut gesucht.

Die verdichtete Fahransicht verwendet zwei Datenzeilen (Reststrecke, gefahrene Strecke, Tempo, Fahrzeit; darunter Akku, Fahrmodus, Fahrer- und Motorleistung). Pause/Fortsetzen, Höhenprofil, Ton und Stopp liegen in einer gemeinsamen Tastenleiste mit mindestens 44 Punkten großen Tasten. Die Bike-Verbindungsdetails öffnet das Fahrrad-Symbol rechts neben den Bike-Werten.

Nach Michaels Rückmeldung zu verschwindendem Akkustand wird jeder tatsächlich empfangene Akkumesswert mit Bike-Kennung und ursprünglichem Empfangszeitpunkt gespeichert. Neustarts und Wiederverbindungen löschen ihn nicht mehr. Der vorhandene Diagnoseverlauf des frühen Prototyps wird einmalig auf eindeutig diesem Bike zugeordnete Akkumesswerte geprüft. Wiederhergestellte Werte werden als letzter Stand gekennzeichnet, niemals als neuer Bluetooth-Empfang. Andere Bike-Daten werden nicht aus alten Sitzungen übernommen. Der Statuspunkt ist bei aktuellen Daten grün und bei einer Bluetooth-Verbindung ohne aktuelle Daten orange. 19 gezielte Decoder-, Anzeige- und Speicher-/Wiederherstellungstests bestanden.

Diagnoselog und Status liegen im App-Dokumentenordner unter `BikeBluetooth/`; das Log ist auf zwei Dateien von ungefähr je 1 MB begrenzt. Außerhalb der geöffneten Verbindungsdetails werden Rohdaten höchstens alle 30 Sekunden protokolliert.

Validierung der Fahransicht: 16 gezielte Decoder-/Anzeige-Tests bestanden. Ein iPhone-Simulator-Bedientest prüft alle vier Anzeigen bei fehlendem Bike, das Öffnen und Schließen der Verbindungsdetails sowie Tabwechsel. Die Darstellung während einer aktiven Tour wurde anhand des Screenshots geprüft; Karte und Fahrtasten bleiben sichtbar. Simulator- und Gerätebuild erfolgreich.

Validierung: zwölf gezielte Swift-Tests für LDI und Smartphone-Decoder bestanden, darunter reale eigene Datenpakete, fehlende Werte, explizite Nullen, unbekannte Felder und beschädigte Pakete. Debug-Build für Michaels iPhone erfolgreich, installiert und am Gerät geprüft. Langzeitbetrieb während einer Fahrt, Moduswechsel und Betrieb ohne Flow bleiben gesonderte Praxistests. Lokale Testaufzeichnungen liegen im ignorierten Ordner `artifacts/bike-bluetooth-20260920/`.

Das Referenzprojekt liegt unter `/Users/michaelhein/30_Entwicklung/20_VSCode/20260827 Shelly`.

## Was im Shelly-Projekt funktioniert

Die dortige Verbindung verläuft vom Bike über Bluetooth zum Pi5; die iPhone-App fragt den Pi über HTTP(S) ab. Eine direkte Bluetooth-Verbindung der Shelly-iPhone-App zum Bike ist damit nicht nachgewiesen.

- `docs/BIKE-ZUGRIFF.md`, Nachtrag vom 07.09.2026: Kopplung und LDI auf dem konfigurierten Bike bestätigt; erster dokumentierter Akkustand 74 % um 19:32 Uhr. Die älteren Absätze am Dateianfang beschreiben noch den vorherigen, ungekoppelten Zustand.
- `bike/bridge.py`: BlueZ-Empfänger; veröffentlicht ein Zubehörsignal mit Service Solicitation und Cycling Appearance, liest die Live-Data-Characteristic und abonniert Änderungen.
- `bike/ldi.py`: decodiert insbesondere Protobuf-Feld 10 (Akkustand) und 22 (Ladegerät verbunden).
- `ShellyBike/APIClient.swift`: `bikeStatus()` ruft `/bike/status` auf.

## Grenze der vorhandenen Schnittstelle

Boschs Dokument **The smart system – Live Data Interface**, V1.0 vom 01.05.2026, beschreibt in Abschnitt 1 lesenden Datenzugriff. Abschnitt 2.2.3, Tabelle 2-10 auf Seite 14, nennt für Live Data ausschließlich `Read` und `Notify`. Das Schema enthält Fahr- und Systemdaten, keine Navigations- oder Display-Kommandos. Ein Schreiben des Benachrichtigungs-Descriptors aktiviert lediglich den Datenempfang.

Technische Kennungen aus der Spezifikation und dem Shelly-Code:

- Service: `0000eb20-eaa2-11e9-81b4-2a2ae2dbcce4`
- Live Data: `0000eb21-eaa2-11e9-81b4-2a2ae2dbcce4`

Die Spezifikation sieht das Bike als GAP Central/GATT Server und das Zubehör als GAP Peripheral/GATT Client vor. Das Zubehör muss beim erstmaligen Verbinden unter anderem Service Solicitation und Appearance aussenden. Abschnitt 2.1.5 auf Seite 7 beschreibt Smartphone-Unterstützung ausdrücklich als außerhalb des Spezifikationsumfangs und nennt mögliche Betriebssystembeschränkungen.

Quelle: [Bosch-Spezifikation, Kopie im BEStie-Projekt](https://github.com/bestie-org/BEStie/blob/master/proto/20260501_LiveDataInterface_V1_28042026.pdf). Die relevanten Seiten 7, 8 und 14 wurden zusätzlich visuell geprüft. [Boschs Ankündigung](https://www.bosch-presse.de/pressportal/de/de/lieblingsgeraete-verbinden-ebike-fahrerlebnis-erweitern-282688.html) beschreibt ebenfalls die Ausgabe von Live-Fahrdaten an Fremdgeräte.

**Ergebnis:** Die erfolgreiche Shelly-Verbindung ist ein Beleg für den Empfang von Bike-Daten. Über diese dokumentierte LDI-Schnittstelle können wir keine eigenen Abbiegehinweise auf dem Kiox anzeigen.

## Direkte Verbindung mit dem iPhone

Eine unveränderte Portierung des Pi-Verfahrens ist kein belastbarer Implementierungsweg: Apples öffentliches `CBPeripheralManager.startAdvertising` unterstützt nur lokalen Namen und Service-UUIDs. Eine angebotene Service-UUID ist kein Ersatz für eine Service-Solicitation-UUID. Die vom Pi gesetzten Advertising-Felder lassen sich über diese API nicht entsprechend vorgeben. [Apple-Dokumentation](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/startadvertising(_:))

Es gibt einen konkreten experimentellen Ansatz über den Smartphone-Verbindungsweg: Ein Entwickler berichtet von einem funktionierenden iOS-LiveData-Client an einem Bosch CX mit Kiox 300 und Firmware 20.27.0. Sein Ablauf beginnt mit der Suche nach bereits auf Systemebene verbundenen Geräten, gefolgt von Service-Ermittlung und Benachrichtigungen auf der verschlüsselten Characteristic. Das ist ein Bericht aus erster Hand, keine von uns reproduzierte Zusage und kein Test mit Michaels Kiox 500. Er belegt außerdem keine Display-Ansteuerung. [Entwicklerbericht, Beitrag von radiohound vom 24.07.2026](https://www.emtbforums.com/threads/looking-for-bosch-smart-system-developers-and-ble-experts-open-source-bikebridge-project.48075/)

Dieser Ansatz muss getrennt vom offiziellen LDI-Zubehörprofil untersucht werden. Firmware, Bluetooth-Rolle, zugängliche Services und Verhalten mit aktiver/inaktiver Flow-App sind am eigenen Bike zu prüfen. Aus widersprüchlichen Erfahrungsberichten lässt sich keine pauschale Aussage über parallele Verbindungen ableiten.

## Eigene Hinweise auf dem Kiox

Die Bosch Flow App kann auf dem Kiox 500 Navigation anzeigen. In den geprüften öffentlichen Unterlagen und Referenzimplementierungen wurde jedoch kein verwendbarer Befehlssatz für eigene Texte, Pfeile, Abbiegeentfernungen oder Navigationsgrafiken gefunden. Das ist eine Recherchegrenze, kein Beweis technischer Unmöglichkeit.

Für eine direkte BikeNavi-Ausgabe wäre ein dokumentierter Bosch-Zugang oder eine gesonderte Untersuchung des Navigationsprotokolls erforderlich. Erfolgreiches Pairing, eine beschreibbare Bluetooth-Characteristic oder empfangene Telemetrie allein beweisen keine solche Fähigkeit.

Der dokumentierte Weg zur Kiox-Navigation bleibt der GPX-Import in Flow. Dabei führt Bosch die Navigation aus. Bei „Originalroute folgen“ werden laut Bosch nur die Routenlinie und keine Abbiegehinweise angezeigt. Bei anderer Verarbeitung muss vor der Fahrt kontrolliert werden, ob der Verlauf der BikeNavi-Planung erhalten bleibt. [Bosch GPX-Import](https://help.bosch-ebike.com/en/help-center/asset-ast-00019), [Navigation mit Kiox 300/500](https://help.bosch-ebike.com/be-en/connect/help-center/asset-ast-00017)

## Noch ausstehende Praxistests

Sobald Michael direkt beim Bike ist, werden ohne Ladegerät im Stand zwei oder drei Fahrmodi mit dem Kiox abgeglichen. Während einer späteren Fahrt werden Fahrer- und Motorleistung auf Empfang und Bedeutung geprüft. Weitere Prüfpunkte sind längerer Betrieb mit gesperrtem iPhone, mit/ohne laufende Flow-App und erneutes Einschalten des Bikes. Der bisherige Test fand im Ladezustand statt; Michael konnte währenddessen nicht zum Bike im Keller gehen.

BikeNavi besitzt bereits eigene Navigationsdaten (`RouteProgress.nextManeuver`, `distanceToManeuver`) sowie GPX-Export; deren Übertragung an das Kiox gehört nicht zum aktuellen Umfang. Der aktuelle Prototyp liest ausschließlich Daten und aktiviert dazu Bluetooth-Benachrichtigungen.
