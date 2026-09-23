# Lokale Planung und Rückführung auf dem iPhone

Implementiert, Stand 22.09.2026.

## Bedienung

Wird zuerst ein Ziel gesetzt, startet die Planung sofort mit dem frischen Standort als Start. Fehlt GPS, wird das Ziel gespeichert und die Berechnung nach der ersten brauchbaren Messung automatisch gestartet. Ein ausdrücklich gesetzter Start bleibt erhalten.

Die komplette Routensuche läuft auf dem iPhone. Der Pi dient als Datenlieferant und Archiv; `/v1/route` wird von der App nicht mehr aufgerufen. Für neue Gebiete lädt die App das Wegenetz in einem etwa 2 km breiten Korridor beiderseits der Verbindungen zwischen den Wegpunkten. Bereits geladene Daten und der zuletzt aufgebaute Graph werden wiederverwendet. Ohne vollständige lokale Wegedaten ist zunächst der Pi erforderlich. Dieser erste Download ist weiterhin von Verbindung und Overpass abhängig.

Die Planung verwendet A* mit Luftlinie als unterer Kostenschranke, getrennt pro Etappe, mit maximal acht Sekunden Suchzeit pro Etappe. Fahrradzugang, Einbahnregeln, Abbiegebeschränkungen und Belagspräferenzen gelten auch für die Planung. Zwischenziele erhalten exakte Indizes. Kreuzungsarme und Belagsübersicht entstehen aus den lokalen Daten. Höhenmodell fehlt: Die Oberfläche zeigt für An-/Abstieg „–“ statt irreführender 0 m; Fahrzeit ist eine Schätzung mit 4,5 m/s.

Nach der Berechnung ist dasselbe Wegenetz sofort für die Rückführung bereit und wird mit der Route verknüpft gespeichert. Bestehende ältere Touren können weiterhin über **„Lokale Rückführung vorbereiten“** ergänzt werden. Offline-Kartenbilder sind eine separate Funktion.

## Verhalten während der Fahrt

- Abweichung ab 35 m, bei höherer GPS-Ungenauigkeit entsprechend mehr Abstand; mindestens drei genaue, aufeinanderfolgende Messungen über fünf Sekunden. Alte Messungen, doppelte Zeitstempel und Genauigkeiten über 25 m lösen keine Berechnung aus.
- Wiedereinstieg an einem vorausliegenden Routenpunkt: Bewertet werden die Kosten des Anschlusses **plus der gesamten verbleibenden Originalroute**. Alle abgedeckten Routenstützpunkte bis zum nächsten offenen Zwischenziel und innerhalb von 3 km Luftlinie kommen infrage, auch wenn sie entlang einer Schleife deutlich mehr als 1,2 km vorausliegen. Belagspräferenzen gehen in Anschluss und Reststrecke ein. Ein offenes Zwischenziel darf nicht übersprungen werden.
- Magnet: Bis 25 m Abstand wird die projizierte Position auf der Route für Karte und Fortschritt verwendet, wenn GPS auf höchstens 25 m genau und die Fahrtrichtung höchstens 65° von der Route abweicht. Bei schlechtem oder altem GPS wird nicht eingerastet. Die echte GPS-Aufzeichnung bleibt unverändert. Zwischen Magnet und Neuberechnung liegt ein Toleranzbereich bis 35 m.
- Die Originaltour bleibt unverändert. Der Anschluss und sein Wiedereinstieg werden separat in der Fahrt gespeichert. Die angezeigte Navigation kombiniert Anschluss und Originalrest. Abbiegehinweise am Wiedereinstieg werden für die tatsächliche neue Anfahrtsrichtung berechnet.
- Bei Rückkehr auf die Tour endet die Rückführung. Wiederholte Berechnungen starten frühestens nach zehn Sekunden und laufen niemals gleichzeitig. Pause, Ende und Fahrtwechsel brechen die Suche ab. Aktuelle Position und Fahrtrichtung werden vor Übernahme noch einmal geprüft; ein bereits gefahrener Anfang des Anschlusses wird abgeschnitten.
- Die Suche läuft außerhalb des UI-Threads, mit zwei Sekunden Suchbudget. Ist beim Ablauf bereits ein gültiger Anschluss vorhanden, wird der beste bisher gefundene verwendet; ein globales Optimum wird bei Budgetablauf nicht behauptet. Bei fehlenden Daten, unklarer Zuordnung zu parallelen Wegen oder fehlendem geeigneten Anschluss bleibt die Tour sichtbar und die App zeigt den Grund.

## Daten und Suchverfahren

Eigene, begrenzte, abbiegebewusste Dijkstra-Suche mit mehreren Wiedereinstiegen. Keine neue externe Routingbibliothek. Der Pi bereitet OSM-Daten als gerichteten Fahrradgraphen vor; er führt unterwegs keine Suche für die App aus.

Der Download umfasst einen Korridor von etwa zwei Kilometern beiderseits der Tour, gespeichert in 0,05°-Teilbereichen. Vollständige OSM-Wege und ihre Knoten werden übernommen, ohne an geometrischen Kreuzungen künstliche Verbindungen anzulegen. Berücksichtigt werden Fahrradzugang, Einbahnstraßen einschließlich Fahrradausnahmen, richtungsabhängiger Zugang, Schranken, Treppen, Belag und einfache knotenbasierte Abbiegebeschränkungen einschließlich Wendeverboten. Motorstraßen, Treppen und nicht freigegebene Fußwege werden ausgeschlossen. Nicht unterstützte bedingte Beschränkungen oder Abbieger über mehrere Wege schließen die betroffenen Wege konservativ aus. Das kann zu Umwegen oder ausbleibenden Anschlüssen führen; solche Beschränkungen werden nicht ignoriert. Es handelt sich um einen begrenzten Fahrradgraphen, nicht um eine vollständige weltweite Verkehrsvorschriften-Engine.

Bei „Nur bekannte befestigte Wege“ gilt das gemeinsame 100-m-Budget für bereits berücksichtigte Abschnitte, ausgegebene Anschlüsse und den verbleibenden Originalrest. Unbekannte Oberflächen und kleine geometrische Anschlusslücken zählen dazu. Ein ausgegebener Anschluss reserviert seinen Anteil vollständig; bei einem späteren Abbruch wird dieser Anteil vorsichtshalber nicht wieder freigegeben. Dadurch kann die App strenger sein als die tatsächlich gefahrene Schotterlänge, gibt aber nicht bei jeder Neuberechnung neue 100 m frei. „Befestigte Wege bevorzugen“ gewichtet unbefestigte Wege höher. Steigungsgewichtung ist nur möglich, soweit OSM `incline` enthält; für neue Anschlüsse gibt es noch kein vollständiges Höhenmodell.

Grenzen: 120 Teilbereiche pro Tour, 250 MB lokaler Cache, 350.000 Knoten/800.000 gerichtete Kanten pro geladenem Graphen, Für Rückführungen gelten 5 km Suchweglänge und 3 km räumlicher Suchradius ab Position; Planungen haben diese Rückführungsgrenzen nicht, bleiben aber auf den geladenen Graphen und maximal 300 km Suchweglänge pro Etappe begrenzt. Bei Überschreitung wird die Funktion für diese Vorbereitung begrenzt, statt die App unbegrenzt zu belasten. Bereits gespeicherte Pakete bleiben nutzbar.

## Speicherung und Aktualisierung

Der Pi hält Teilbereiche in PostgreSQL (`offline_tiles`), normalerweise 30 Tage wiederverwendbar. Die App hält unveränderliche Dateiversionen in ihrem Application-Support-Verzeichnis. Ein Manifest wird erst nach vollständigem Download, Prüfung und Aufbau des Graphen atomar ersetzt. Ein abgebrochenes Update lässt das bisher vollständige Paket bestehen. Fehlgeschlagene temporäre Downloads werden begrenzt wiederholt und können anschließend erneut gestartet werden. Vorhandene Pakete erfordern beim Öffnen keine Netzverbindung und werden ausdrücklich über die Aktualisierungsfunktion erneuert.

Abweichende Knotenpositionen in gemischten Kartenständen werden nicht stillschweigend verbunden. Gesperrte Knoten/Wege und widersprüchliche Freigaben bleiben beim Zusammenführen konservativ gesperrt. Bei nicht vereinbaren Datenständen muss das Paket erneuert werden.

## Prüfung

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
