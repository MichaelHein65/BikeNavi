# Lokale Planung und Rückführung auf dem iPhone

Implementiert, Stand 24.09.2026. Die Fehlerfall-Protokolle weiter unten beschreiben jeweils den damaligen Stand.

## Bedienung

Wird zuerst ein Ziel gesetzt, startet die Planung sofort mit dem frischen Standort als Start. Fehlt GPS, wird das Ziel gespeichert und die Berechnung nach der ersten brauchbaren Messung automatisch gestartet. Ein ausdrücklich gesetzter Start bleibt erhalten.

Die Streckenberechnung und das lokale Umfeld sind getrennt. Mit eingerichtetem Pi berechnet der vorhandene openrouteservice-Zugang die gesamte Strecke über `/v1/route?include_context=false`, einschließlich Zwischenzielen, Belägen und Abbiegehinweisen. Dabei werden weder ein durchgehendes lokales Wegenetz noch OSM-Kreuzungsumfelder entlang der ganzen Strecke geladen. Die bisherigen Korridor- und Graphgrößenlimits blockieren diese Planung nicht mehr; Grenzen und Verfügbarkeit des Routinganbieters gelten weiterhin. Der Pi benötigt dafür einen ORS-Schlüssel. Ohne eingerichteten API-Client bleibt die lokale Planung aus bereits gespeicherten Gebietsdaten verfügbar, mit ihren bisherigen Größenlimits. Ein unerreichbarer konfigurierter Pi liefert einen Planungsfehler.

Sobald die Route gespeichert ist, lädt die App unabhängig davon das Wegenetz um den aktuellen frischen Standort, ersatzweise um den geplanten Start. Ein fehlgeschlagener Umfelddownload verwirft die Route nicht und verhindert den Fahrtstart nicht. **„Lokale Rückführung vorbereiten“** lädt ebenfalls nur dieses Umfeld. Offline-Kartenbilder sind eine separate Funktion.

Die lokale Rückführung sucht weiterhin ausschließlich innerhalb von **3 km um die aktuelle Position**. Das Downloadfenster hat 3,5 km Radius als rechteckige Kachelauswahl: Die zusätzlichen 500 m und vollständigen Randkacheln dienen als Vorladepuffer, nicht als größerer Suchradius. Bei frischen GPS-Messungen mit höchstens 25 m Ungenauigkeit prüft die App das benötigte Fenster und lädt neue Teilbereiche nach. Damit werden die nächsten Abschnitte während der Fahrt vorbereitet, ohne das gesamte Umfeld der Tour auf einmal zu laden. Es läuft höchstens ein Fahrt-Download; neue Versuche beginnen frühestens nach 30 Sekunden. Pause, Ende und Fahrtwechsel brechen ausstehende Downloads ab beziehungsweise verhindern die Übernahme fremder Ergebnisse.

Ohne Verbindung bleiben Originalroute, Navigation und bereits gespeicherte Wegedaten verfügbar. Außerhalb der geladenen Gebiete ist keine lokale Rückführung zugesichert; die App zeigt bei einem gescheiterten Nachladeversuch einen Hinweis. Der Puffer garantiert bei langsamen Downloads keine lückenlose Abdeckung. Ein neu geladenes Fenster ersetzt den aktiven Graphen, statt ihn entlang der ganzen Tour wachsen zu lassen. Ein fehlgeschlagener Download erhält das letzte vollständige Paket. Die Bereitschaftsanzeige gilt ausdrücklich nur für das geladene Umfeld.

## Verhalten während der Fahrt

- Abweichung ab 35 m, bei höherer GPS-Ungenauigkeit entsprechend mehr Abstand; mindestens drei genaue, aufeinanderfolgende Messungen über fünf Sekunden. Alte Messungen, doppelte Zeitstempel und Genauigkeiten über 25 m lösen keine Berechnung aus.
- Wiedereinstieg an einem vorausliegenden Routenpunkt: Bewertet werden die Kosten des Anschlusses **plus der gesamten verbleibenden Originalroute**. Alle abgedeckten Routenstützpunkte bis zum nächsten offenen Zwischenziel und innerhalb von 3 km Luftlinie kommen infrage, auch wenn sie entlang einer Schleife deutlich mehr als 1,2 km vorausliegen. Belagspräferenzen gehen in Anschluss und Reststrecke ein. Ein offenes Zwischenziel darf nicht übersprungen werden.
- Magnet: Bis 25 m Abstand wird die projizierte Position auf der Route für Karte und Fortschritt verwendet, wenn GPS auf höchstens 25 m genau und die Fahrtrichtung höchstens 65° von der Route abweicht. Bei schlechtem oder altem GPS wird nicht eingerastet. Die echte GPS-Aufzeichnung bleibt unverändert. Zwischen Magnet und Neuberechnung liegt ein Toleranzbereich bis 35 m.
- Die Originaltour bleibt unverändert. Der Anschluss und sein Wiedereinstieg werden separat in der Fahrt gespeichert. Die angezeigte Navigation kombiniert Anschluss und Originalrest. Abbiegehinweise am Wiedereinstieg werden für die tatsächliche neue Anfahrtsrichtung berechnet.
- Bei Rückkehr auf die Tour endet die Rückführung. Wiederholte Berechnungen starten frühestens nach zehn Sekunden und laufen niemals gleichzeitig. Pause, Ende und Fahrtwechsel brechen die Suche ab. Aktuelle Position und Fahrtrichtung werden vor Übernahme noch einmal geprüft; ein bereits gefahrener Anfang des Anschlusses wird abgeschnitten.
- Die Suche läuft außerhalb des UI-Threads, mit zwei Sekunden Suchbudget. Ist beim Ablauf bereits ein gültiger Anschluss vorhanden, wird der beste bisher gefundene verwendet; ein globales Optimum wird bei Budgetablauf nicht behauptet. Bei fehlenden Daten, unklarer Zuordnung zu parallelen Wegen oder fehlendem geeigneten Anschluss bleibt die Tour sichtbar und die App zeigt den Grund.

## Daten und Suchverfahren

Eigene, begrenzte, abbiegebewusste Dijkstra-Suche mit mehreren Wiedereinstiegen. Keine neue externe Routingbibliothek. Der Pi bereitet OSM-Daten als gerichteten Fahrradgraphen vor; er führt unterwegs keine Suche für die App aus.

Der Umfelddownload umfasst die 0,05°-Teilbereiche des aktuellen 3,5-km-Fensters, unabhängig von der Länge der Originalroute. Vollständige OSM-Wege und ihre Knoten werden übernommen, ohne an geometrischen Kreuzungen künstliche Verbindungen anzulegen. Berücksichtigt werden Fahrradzugang, Einbahnstraßen einschließlich Fahrradausnahmen, richtungsabhängiger Zugang, Schranken, Treppen, Belag und einfache knotenbasierte Abbiegebeschränkungen einschließlich Wendeverboten. Motorstraßen, Treppen und nicht freigegebene Fußwege werden ausgeschlossen. Nicht unterstützte bedingte Beschränkungen oder Abbieger über mehrere Wege schließen die betroffenen Wege konservativ aus. Das kann zu Umwegen oder ausbleibenden Anschlüssen führen; solche Beschränkungen werden nicht ignoriert. Es handelt sich um einen begrenzten Fahrradgraphen, nicht um eine vollständige weltweite Verkehrsvorschriften-Engine.

Bei „Nur bekannte befestigte Wege“ gilt das gemeinsame 100-m-Budget für bereits berücksichtigte Abschnitte, ausgegebene Anschlüsse und den verbleibenden Originalrest. Unbekannte Oberflächen und kleine geometrische Anschlusslücken zählen dazu. Ein ausgegebener Anschluss reserviert seinen Anteil vollständig; bei einem späteren Abbruch wird dieser Anteil vorsichtshalber nicht wieder freigegeben. Dadurch kann die App strenger sein als die tatsächlich gefahrene Schotterlänge, gibt aber nicht bei jeder Neuberechnung neue 100 m frei. „Befestigte Wege bevorzugen“ gewichtet unbefestigte Wege höher. Steigungsgewichtung ist nur möglich, soweit OSM `incline` enthält; für neue Anschlüsse gibt es noch kein vollständiges Höhenmodell.

Grenzen der lokalen Offline-Planung: 120 Teilbereiche pro Planung; 250 MB lokaler Cache, 350.000 Knoten/800.000 gerichtete Kanten pro geladenem Graphen, Für Rückführungen gelten 5 km Suchweglänge und 3 km räumlicher Suchradius ab Position; Planungen haben diese Rückführungsgrenzen nicht, bleiben aber auf den geladenen Graphen und maximal 300 km Suchweglänge pro Etappe begrenzt. Bei Überschreitung wird die Funktion für diese Vorbereitung begrenzt, statt die App unbegrenzt zu belasten. Bereits gespeicherte Pakete bleiben nutzbar.

## Speicherung und Aktualisierung

Der Pi hält Teilbereiche in PostgreSQL (`offline_tiles`), normalerweise 30 Tage wiederverwendbar. Die App hält unveränderliche Dateiversionen in ihrem Application-Support-Verzeichnis. Ein Manifest beschreibt das zuletzt vollständig geladene Fenster der Route, nicht die Abdeckung der gesamten Tour. Es wird erst nach vollständigem Download, Prüfung und Aufbau des Graphen atomar ersetzt. Bei Erreichen des 250-MB-Budgets werden die ältesten nicht mehr durch Manifeste, laufende Downloads oder den vorbereiteten Graphen referenzierten Kacheldateien entfernt. Referenzierte Pakete bleiben geschützt; belegen sie bereits das Budget, wird der neue Download begrenzt. Ein abgebrochenes Update lässt das bisher vollständige Paket bestehen. Fehlgeschlagene temporäre Downloads werden begrenzt wiederholt und können anschließend erneut gestartet werden. Vorhandene Pakete erfordern beim Öffnen keine Netzverbindung. Mit konfiguriertem API-Client werden Pakete aus älteren Zugangsauswertungen beim nächsten Vorbereiten oder Planen automatisch erneuert; dafür muss der Pi erreichbar sein und die korrigierte Serverfassung ausliefern. Ohne API-Client bleiben alte Pakete lesbar, enthalten aber weiterhin ihre bisherigen Einschränkungen. Ansonsten lassen sich Pakete ausdrücklich über die Aktualisierungsfunktion erneuern.

Abweichende Knotenpositionen in gemischten Kartenständen werden nicht stillschweigend verbunden. Gesperrte Knoten/Wege und widersprüchliche Freigaben bleiben beim Zusammenführen konservativ gesperrt. Bei nicht vereinbaren Datenständen muss das Paket erneuert werden.

## Prüfung des mitwandernden Umfelds

108 Swift-Kerntests, 64 Backend-Tests (zwei bestehende Deprecation-Warnungen) und iPhone-Simulator-Build erfolgreich. Neue Regressionstests prüfen eine synthetische 600-km-Planung ohne Umfelddownload, 3-km-Abdeckung einschließlich Datumsgrenze sowie Fensterwechsel, Wiederöffnung und Erhalt des bisherigen Pakets nach fehlgeschlagenem Nachladen. Der API-Test prüft das Auslassen sämtlicher Overpass-Abfragen für die Streckenplanung. Das sind automatisierte Tests mit Beispieldaten; keine reale Langstreckenfahrt und keine Messung der Verfügbarkeit des Routinganbieters.

Am 24.09.2026 anschließend als signierte Debug-App auf Michaels iPhone 15 Pro installiert und gestartet; zugehöriges Backend auf dem Pi aktualisiert. Öffentliche Beispielstrecke Heidelberg–Frankfurt über die echte Pi-API: 89,23 km in 1,56 Sekunden, ohne Kreuzungsumfelder. HTTPS, Zugangsschutz und ORS-Konfiguration erfolgreich geprüft. Die Prüfung lief vom Mac; keine Testtour gespeichert und keine reale Fahrt durchgeführt.

## Frühere Prüfungen

Verifikation des neuen Stands: 70 Swift-Tests und der Simulator-Interaktionstest zur automatisch ausgelösten Berechnung bestanden. Auf dem Mac mit dem gespeicherten Heidelberger Graphen (83.206 Knoten, 165.525 Kanten): 5,16 km Planung in ca. 70 ms, zehn Rückführungen in ca. 74–86 ms, Indexaufbau ca. 200 ms. Diese Werte messen nur die lokale Berechnung, ohne Download; sie sind keine iPhone-Messung oder reale Testfahrt.

Der neue Loop ergänzt Regressionstests für Gesamtweg statt kürzestem Anschluss, verpflichtende Zwischenziele, komplette lokale Etappen über 5 km, Einbahnregeln bei der Planung, Planung an Kreuzungen, Planung aus dem Cache ohne API-Client, Wiederöffnung des Navigationspakets und Magnet/Fahrtrichtung/GPS-Genauigkeit. Frühere Gerätemessungen unten betreffen den vorherigen Stand; sie sind kein Leistungsnachweis für den neuen Algorithmus.


Automatisierte Prüfungen umfassen getrennte Fahrten und Speicherung, Wegzugang, Einbahnregeln, Schranken, Abbiegeverbote, konservative Behandlung komplexer Beschränkungen, fehlende Daten, Wiederanlauf nach Unterbrechung, Cache ohne API-Client, Zwischenziele, Rundtouren, Belagsbudget einschließlich Originalrest und früherer Anschlüsse, aktuelle Fahrtrichtung, Bewegen während der Suche und Abbiegerichtung am Wiedereinstieg. Eine synthetische Tour mit 10.001 Punkten prüft, dass nur ein kurzer Anschluss gesucht wird.

Reale Testdaten: Ein vollständiger Heidelberger Korridor mit sechs Teilbereichen, 83.206 Knoten und 165.525 gerichteten Kanten wurde über den Pi vorbereitet und lokal gespeichert (etwa 22,7 MB). Der Download wurde nach einer Unterbrechung erfolgreich fortgesetzt.

Auf Michaels iPhone 15 Pro wurden am 22.09.2026 zehn gespeicherte Testpositionen im echten Heidelberger Wegenetz erfolgreich berechnet. Gemessen wurden 2,74–5,33 ms je Anschluss und etwa 93 ms für den Indexaufbau des Testgraphen mit 17.322 Knoten/33.118 Kanten. Die Entwickler-Testansicht instanziiert weder Netzwerkclient noch GPS/Bike-Verbindung; sie berechnet aus lokalen Dateien. Das ist ein reproduzierbarer Gerätetest, noch keine Fahrt im Straßenverkehr und kein Test der gesamten App im Flugmodus. Ein Praxistest mit laufendem GPS und Bike-Aufzeichnung bleibt sinnvoll.

Entwickler: `scripts/check_local_routing.swift` kann öffentliche Testdaten vorbereiten und Positionsfälle erzeugen. `BIKENAVI_LOCAL_ROUTING_CHECK=1` aktiviert ausschließlich im Debug-Build die separate Geräteprüfung; anschließend wieder ohne diese Variable starten. Das Ergebnis liegt unter `Documents/LocalRoutingResult.json`, nicht im von Entwicklerwerkzeugen kopierten Eingabeordner. Messprotokolle liegen lokal unter `build/local-routing-live/`.

## Quellen zum Datenmodell

- [OSM: Zugangsbeschränkungen](https://wiki.openstreetmap.org/wiki/Key:access)
- [OSM: Fahrrad-Einbahnregeln](https://wiki.openstreetmap.org/wiki/Key:oneway:bicycle)
- [OSM: Abbiegebeschränkungen](https://wiki.openstreetmap.org/wiki/Relation:restriction)
- [openrouteservice: Ausgabeformate](https://giscience.github.io/openrouteservice/api-reference/endpoints/directions/requests-and-return-types)

Die zugrunde liegenden OSM-Daten stehen unter ODbL; die vorhandene OpenStreetMap-Attribution in der App bleibt erhalten.

## Fehlerfall: längere Strecke nach Aschaffenburg (22.09.2026)

Der gespeicherte Entwurf Rodgau → Aschaffenburg scheiterte beim Laden des ersten fehlenden Kartenbereichs, noch vor der Suche. Fünf der zwölf benötigten Bereiche fehlten auf dem iPhone. Der Standard-Overpass-Dienst war aus dem Pi-Container nicht erreichbar (IPv4-Verbindung abgewiesen; der Container hat kein IPv6). Auch die Ausweichinstanz antwortete während der Prüfung nicht rechtzeitig. Das ist kein nachgewiesenes Distanzlimit der Routensuche.

Der Download versucht bei Ausfall des öffentlichen Standarddienstes jetzt zusätzlich die [öffentliche Private.coffee-Instanz](https://wiki.openstreetmap.org/wiki/Overpass_API#Public_Overpass_API_instances). Individuell konfigurierte Anbieter bleiben unverändert. Unvollständige Antworten werden weiterhin nicht gespeichert; fehlgeschlagene Aktualisierungen lassen vorhandene Kacheln bestehen. Das iPhone wartet pro Download bis zu 100 Sekunden, damit beide begrenzten Serverversuche Platz haben. Ein Planungsfehler bleibt sowohl bei eingeklappter als auch ausgeklappter Planung sichtbar, bis eine neue Berechnung oder Planung beginnt.

Mit den über den Mac ergänzten öffentlichen Kartendaten gelang die unveränderte Planung über 19,87 km auf dem Mac (55.982 Knoten, zwölf Bereiche, etwa 7,38 Sekunden einschließlich Einlesen und Graphaufbau im nicht optimierten Diagnoseprogramm). Das ist keine Messung auf dem iPhone. Die fünf fehlenden Bereiche werden zur Wiederherstellung im Pi-Cache ergänzt; eine allgemeine Verfügbarkeit der externen Dienste ist damit nicht garantiert.

Prüfung: 72 Swift-Kerntests, 42 Servertests und iPhone-Debug-Build erfolgreich. Neue Servertests decken den Ausweichdienst nach Verbindungsfehler oder unvollständiger Antwort und die Erhaltung vorhandener Daten bei Ausfall beider Dienste ab.

### Dauerhafte IPv6-Anbindung des Pi (anschließend behoben)

Der Pi selbst konnte Overpass über IPv6 erreichen; sein BikeNavi-Container war ausschließlich per IPv4 angebunden. Der IPv4-Endpunkt wies Verbindungen ab. `compose.yaml` ergänzt deshalb nur am Backend das Netz `map_egress` mit der Bridge `bikenavi-v6` und dem privaten Präfix `fd53:ba7e:91c4:1::/64`. Datenbank und bisherige lokale Portbindung bleiben bestehen.

Die installierte Docker-Version 26.1.5 erzeugt hier keine IPv6-NAT-Regeln. `ops/bikenavi-ipv6.sh --install` installiert daher einen eigenen, beim Booten aktivierten Dienst `bikenavi-ipv6.service`. Seine drei Regeln erlauben ausschließlich ausgehenden Verkehr von dieser Bridge und Antworten auf bestehende Verbindungen über den ermittelten Internet-Uplink. UFW und Tailscale werden nicht deaktiviert; es werden keine eingehenden Ports geöffnet. Router-Advertisements werden auf dem Uplink weiterhin angenommen (`accept_ra=2`), damit die IPv6-Standardroute trotz aktivierter Weiterleitung erneuert wird. Diese Einstellung liegt dauerhaft in `/etc/sysctl.d/90-bikenavi-ipv6.conf`.

Das reguläre Pi-Deployment installiert diesen Dienst vor dem Start der Container. Installation/Anwendung sind wiederholbar; es werden keine mehrfachen Firewallregeln angelegt. Nach einem manuellen vollständigen Firewall-Reset den Dienst mit `sudo systemctl restart bikenavi-ipv6` erneut anwenden. Bei einem Wechsel des Internet-Uplinks das Installationsskript erneut ausführen. Der private IPv6-Bereich muss auf weiteren Hosts konfliktfrei sein. Hintergrund: [Docker: IPv6-Netzwerke](https://docs.docker.com/engine/daemon/ipv6/).

Live-Prüfung: Der zuvor **nicht gespeicherte** Bereich `1/3783/2799` bei Aschaffenburg wurde über die authentifizierte HTTPS-API des Pi in 3,83 Sekunden geladen: 10.399 Knoten und 21.215 gerichtete Kanten. Kein Mac-Download und keine vorab ergänzten Daten waren dafür nötig. Die 42 Servertests bestehen. Ein kompletter Neustart des Pi wurde nicht durchgeführt.

Auch nach erneutem Anwenden des IPv6-Dienstes und Neustart des Backends gelang ein ausdrücklich erzwungener neuer Overpass-Abruf (`refresh=true`) in 2,62 Sekunden. Die drei Firewallregeln waren jeweils genau einmal vorhanden, die IPv6-Standardroute wurde erneuert, HTTPS-Healthcheck antwortete mit 200 und ein Abruf ohne Token weiterhin mit 401. Die Datenbank blieb während der Umstellung durchgehend in Betrieb.

## Fehlerfall: Tribunj → Skradin (22.09.2026)

Die mit dem iPhone gespeicherte Strecke erreichte mit 26.580 Knoten und 53.005 Kanten das Variantenlimit der Suche. Auch bei „Schotter erlaubt“ wurden bisher Kosten und Schotterstrecke als unabhängige Suchressourcen behandelt. Dadurch entstanden unnötig viele nicht dominierte Varianten. Die Suche berücksichtigt Schottermeter jetzt nur beim harten Budget von „Nur bekannte befestigte Wege“ als zusätzliche Ressource; Belagspräferenzen bleiben in den Kosten enthalten. Kosten und begrenzte Suchweglänge werden weiterhin berücksichtigt. Ersetzte Varianten werden nicht erneut erweitert.

Nach dieser Korrektur zeigte sich zusätzlich, dass der anfängliche schmale Kartenkorridor keine Verbindung zum Ziel enthielt. Nach erfolgloser Suche erweitert die Planung den Korridor daher um einen Ring benachbarter Kartenbereiche, höchstens zweimal und weiterhin mit maximal 120 Bereichen. Bereits vorhandene Daten werden wiederverwendet. Das Navigationspaket speichert den tatsächlich verwendeten erweiterten Graphen; Abbruch und Downloadfehler überschreiben keine bestehenden Tourpakete.

Mit vollständig erweitertem Gebiet (31 Kartenbereiche) gelang die unveränderte Strecke über rund 28,24 km. Der vollständige Nachlade-, Planungs- und Speicherablauf wurde mit den vom iPhone übernommenen Wegpunkten auf dem Mac erfolgreich geprüft. Das ist keine Zeitmessung auf dem iPhone. Regressionstests decken die Variantenexplosion, die weiterhin gültige Belagsbegrenzung bei alternativen Wegen sowie automatische Gebietserweiterung und Wiederöffnung des erweiterten Offlinepakets ab.

## Fehlerfall: Madernobrunnen → Fregene (23.09.2026)

Der ausgewählte Brunnen liegt etwa 107 m vom nächsten erfassten Fahrrad-/Straßenanschluss entfernt. Die bisherige Zuordnung mit 100 m Radius scheiterte und gab irreführend die GPS-Meldung aus der Rückführung aus. Für geplante Orte gilt jetzt ein begrenzter Zuordnungsradius von 250 m; Live-Navigation bleibt bei ihren bisherigen engen Grenzen. Der räumliche Index berücksichtigt den tatsächlich angefragten Radius auch bei schmalen Längengradzellen. Nicht zuordenbare Wegpunkte werden mit ihrem Namen und einer Aufforderung zum Versetzen gemeldet, ohne auf GPS zu warten.

Zugangsabschnitte bleiben als unbekannter Belag in der Geometrie und im 100-m-Budget enthalten. Ab 25 m kennzeichnen Routenhinweise und Manöver den Zugang ausdrücklich als ungeprüft und weisen darauf hin, ihn vor Ort zu prüfen und gegebenenfalls zu schieben. Eine gerade Verbindung zum Wegenetz ist keine Aussage über einen tatsächlich begehbaren oder befahrbaren Weg.

Für diese Strecke fehlte zudem ein Umweg im anfänglichen Korridor. Ein vollständiger Erweiterungsring umfasste 371.884 Knoten und überschritt das Graphlimit. Die Planung versucht deshalb zunächst jeweils einen seitlichen Streifen, bevor sie einen ganzen Ring lädt. Fehlende Offline-Daten oder zu große Graphen auf einer Seite verhindern nicht die Prüfung der anderen Seite. Die bestehenden Größenlimits bleiben erhalten.

Mit den unveränderten iPhone-Wegpunkten gelang die Strecke über 32,82 km mit 21 Kartenbereichen, 224.708 Knoten und 368.330 gerichteten Kanten in rund 0,58 Sekunden reiner Suche auf dem Mac. Der vollständige Offline-Planungs-, Speicher- und Wiederöffnungsablauf war erfolgreich. Alle 80 Swift-Kerntests und der iPhone-Build bestehen. Die Messung ist keine iPhone-Laufzeitmessung oder reale Testfahrt.

## Brückenzugang Tisno (24. September 2026)

Die beiden OSM-Schranken 275001044 und 275001047 sind mit `barrier=lift_gate` und `access=yes` erfasst. Die bisherige Auswertung verlangte trotzdem zusätzlich `bicycle=yes` und trennte so die asphaltierte D121-Verbindung zur Insel Murter. Bewegliche Schranken (`gate`, `lift_gate`, `swing_gate`) berücksichtigen jetzt eine ausdrückliche Freigabe in der Reihenfolge `bicycle`, `vehicle`, `access`. Ohne Freigabe bleibt der konservative Ausschluss bestehen. Fahrradverbote, `locked=yes`, bedingte Beschränkungen und physische Hindernisse wie Mauern bleiben ausgeschlossen.

Das gilt allgemein und ist keine geografische Sonderregel. Die Belagsauswahl bleibt unverändert. Der öffentliche OSM-Testausschnitt mit Brücke und beiden Zufahrten wird in beiden Richtungen und mit allen drei Belagsprofilen geprüft. OSM-Datenquelle: [Brückenweg 25219856](https://www.openstreetmap.org/way/25219856), Abruf 24.09.2026, © OpenStreetMap-Mitwirkende, ODbL 1.0.

Öffnungszeiten und der aktuelle Brückenzustand werden nicht ausgewertet. Eine berechnete Route garantiert keine sofortige Überquerung; die bewegliche Brücke kann Wartezeiten verursachen. Aktuelle Zeiten veröffentlicht die [Gemeinde Tisno](https://tisno.hr/clanci/satnica-podizanja-i-spustanja-mosta-u-tisnom-od-1692026-do-3152027). Nach Installation auf Michaels iPhone 15 Pro und Aktualisierung des Pi hat Michael am 24.09.2026 die funktionierende Routenplanung bestätigt. Zusätzlich wurde die vom Pi gelieferte Gebietskachel mit Compilerrevision 2 und beiden freigegebenen Schranken geprüft. Eine tatsächliche Testfahrt über die Brücke ist damit nicht dokumentiert.

## Höhenprofil lokaler Planungen

Nach der lokalen Routenberechnung lädt die App die Höhen der fertigen Strecke im Hintergrund über den Pi nach (`POST /v1/elevation`). Dabei fragt der Pi mit seinem vorhandenen ORS-Schlüssel das SRTM-Geländemodell von openrouteservice ab; es findet keine zweite Routenberechnung statt. Die Abfrage enthält nur entlang der Route abgetastete Koordinaten, keine Tourtitel, Bike-Daten oder Aufzeichnungen. Auch bereits gespeicherte Planungen ohne Höhen werden beim Öffnen nachträglich ergänzt. In den Routendetails zeigt „Höhendaten werden geladen …“ den Download; nach einem Fehler steht „Höhendaten laden“ für einen erneuten Versuch bereit.

Abtastung ungefähr alle 30 m, einschließlich Start und Ziel sowie Punkten innerhalb langer Straßenabschnitte; maximal 2.000 Höhenpunkte je Route. Bei längeren Strecken vergrößert sich der Abstand. Eine Dreipunktglättung vermindert Rasterrauschen. Anstieg und Abstieg summieren Veränderungen ab 3 m gegenüber dem zuletzt übernommenen Wert; kleine fortlaufende Steigungen gehen dabei nicht verloren. Der verbleibende Höhenunterschied am Ziel wird berücksichtigt. Profil und Datenquelle werden mit der Tour auf dem iPhone und über die normale Synchronisation auf dem Pi gespeichert. Die Höhe an den ursprünglichen Geometriepunkten wird interpoliert und auch beim GPX-Export ausgegeben. Wegverlauf, Belagsindizes und Abbiegehinweise ändern sich nicht.

Nach erfolgreichem Download bleibt das Profil ohne Internet und nach App-Neustart verfügbar. Fehlen Verbindung, Datenabdeckung oder Dienstkontingent, bleibt die Route benutzbar, aber Anstieg und Abstieg zeigen „–“ statt erfundener Nullwerte. Echte ebene Strecken und Meereshöhe 0 m sind gültig. Die erstmalige Ergänzung benötigt Internet am Pi und eine Verbindung der App zum Pi. Pi und App müssen die neue Funktion unterstützen.

Die Höhen beschreiben das Gelände, nicht zuverlässig die Fahrbahnhöhe auf Brücken oder in Tunneln. Modellauflösung und Glättung machen Profil und Höhensummen zu Schätzwerten. Sie ändern weder die lokale Routenauswahl noch die bisherige grobe Fahrzeitberechnung. Lokale Rückführungen erhalten kein eigenes nachgeladenes Profil und übernehmen keine Höhensummen der gesamten Originaltour. Die Originalplanung behält ihr gespeichertes Profil. Die GPS-Höhen einer tatsächlich aufgezeichneten Fahrt bleiben davon getrennt.

### Kurze Höhenlücken und widersprüchliche Kartenstände

Bei der gemeldeten Tribunj–Betina-Strecke ließ der Höhendienst einen von 591 angefragten Punkten aus; auch die Einzelabfrage konnte diesen Modellwert nicht liefern. Die ursprüngliche Vollständigkeitsprüfung verwarf deshalb das gesamte Profil. Kurze innere Lücken werden jetzt begrenzt aus ihren Nachbarn geschätzt (höchstens zwei Punkte je Lücke, maximal 100 m zwischen den gültigen Nachbarn, insgesamt höchstens acht Punkte). Die Datenquelle im Profil kennzeichnet die Interpolation. Größere Lücken bleiben ein Fehler; Netzfehler und fehlende Höhendaten erhalten unterschiedliche Hinweise.

Die gemeldete Rodgau-Planung hatte alle sechs benötigten Kartenbereiche. Sechs gemeinsam enthaltene OSM-Knoten hatten jedoch widersprüchliche Positionen, teilweise rund 20 m auseinander. Der Graphaufbau meldete dafür bisher irreführend fehlende Daten. Compilerrevision 3 lädt die OSM-Knotenversionen mit und wählt bei abweichenden Positionen die höhere Version. Ohne eindeutigen Versionsvergleich wird das gesamte Gebiet einmal erneuert; ein verbleibender Konflikt wird ausdrücklich als widersprüchlicher Kartenstand gemeldet. Für die Migration vorhandener Pakete ist eine Verbindung zum aktualisierten Pi erforderlich.

Nach Deployment auf den Pi wurde die originale Tribunj-Geometrie erfolgreich mit 591 Höhenpunkten ergänzt (ein Punkt interpoliert). Der Swift-Kern berechnet daraus rund 314 m Anstieg und 326 m Abstieg; das sind geglättete Geländeschätzungen, keine gemessenen Fahrthöhen. Die ursprünglichen Rodgau-Wegpunkte ergeben mit sechs neu geladenen Bereichen 2.197 m Strecke bei 24.652 Knoten und 52.410 gerichteten Kanten. Beide gezielten Reproduktionen liefen auf dem Mac mit dem echten Pi. 100 Swift-Tests und 62 Backend-Tests bestehen; iPhone-Build, Installation und Start erfolgreich. Kein Feldtest.

## Bewusst ausgelassene Zwischenziele

Bei bestätigter Abweichung fragt die App nach dem Überspringen des nächsten offenen Zwischenziels. Bei einem Wiedereinstieg hinter mehreren Zwischenzielen können diese gemeinsam bestätigt werden. Die großen Ja-/Nein-Tasten sind jeweils mindestens 96 Punkte hoch. Ohne Zustimmung bleiben offene Zwischenziele verbindlich. Ausgelassene Ziele werden in der Fahrt gespeichert, nicht aus der Planung gelöscht. Das Endziel bleibt verbindlich. Eine Rückkehr weit hinter der letzten erkannten Position wird zusätzlich auf der ganzen Originalroute geprüft; Richtung und GPS-Genauigkeit müssen passen. An mehrdeutigen Schleifen/Kreuzungen bleibt die GPS-Zuordnung eine Grenze und muss praktisch geprüft werden.

## Wanderoptionen

Seit 5. Oktober 2026 gilt die lokale Rückführung ausschließlich für **Rad**. **Rad&Wandern** und **Wandern** werden mit dem Pi geplant; die gespeicherte Linie inklusive Abstellmarker bleibt offline nutzbar. Das bestehende Fahrradnetz enthält keine vollständigen Fußzugänge oder Wanderschwierigkeiten und wird deshalb bei diesen Profilen weder zur lokalen Planung noch zur Rückführung verwendet. Eine Abweichung auf dem Fußabschnitt erfordert das Prüfen der gespeicherten Karte oder eine neue Planung mit Verbindung. Details und Suchgrenzen: [Bedienung](../README.md#radwandern-und-wandern).


Die Onlineplanung toleriert seit 05.10.2026 zusätzlich kurze unbekannte Straßenbeläge zwischen befestigten Nachbarn (bis 250 m je Lücke, 500 m insgesamt). Die lokale Offlineberechnung bleibt bei obigem 100-m-Budget, weil das Offlinegraphformat die dafür benötigten Wegarten nicht enthält. Es wird keine neue Offlinefreigabe aus bloßen unbekannten Oberflächen abgeleitet. Rad&Wandern nutzt die Onlineprüfung; gespeicherte Kombinationen bleiben offline navigierbar.
