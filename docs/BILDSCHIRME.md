# BikeNavi – Bildschirmgalerie

## POIs in allen Anwendungen (15. Oktober 2026)

**82 und 85 nach Zoomkorrektur erneuert:** Der Marker bleibt im Mittelpunkt, umliegende Straßen und Stadtteile sind bei Zoomstufe 14 sichtbar. Die zuvor übervergrößerte Rasterkarte war eine Folge der automatischen Anpassung auf nur einen Marker, nicht allein fehlender Kartendaten. Native Kameraprüfung und beide Detail-UI-Abläufe erfolgreich; neue Aufnahmen visuell geprüft.

**83–86** zeigen die neuen Einstiege außerhalb des Autos, die Luftlinien-Suche und den sicheren Landgang-Hinweis. Öffentliche Heidelberger Koordinaten, ausdrücklich synthetische Orte/Entfernungen und GPS im Stand; keine privaten Fahrten oder realen Anbieterangebote. Automatischer UI-Lauf öffnet die sechs Kategorien in Fahrrad, Wandern, Fahrrad & Wandern und Segeln und prüft Suche, Speichern und unveränderte laufende Aufzeichnung. **82** wurde wegen der zusätzlichen Speicheraktion ebenfalls erneuert. Die Bilder wurden visuell geprüft; keine Feldprüfung.

| Fahrrad: Planung | Wandern: Umkreissuche |
| --- | --- |
| <img src="images/83-fahrrad-poi-einstieg.png" width="300" alt="Fahrradplanung mit neuem Orte-entdecken-Button und öffentlichem UI-Beispiel"> | <img src="images/84-wandern-poi-umkreis.png" width="300" alt="Synthetische Supermarkt-Treffer mit 750 Metern Luftlinie statt Pkw-Anfahrtszeit"> |

| Segeln: Landgang-Ort | Wandern: unterwegs |
| --- | --- |
| <img src="images/85-segeln-poi-landgang.png" width="300" alt="Landort zum Speichern mit ausdrücklichem Hinweis auf fehlende Anlegestellenbestätigung"> | <img src="images/86-wandern-poi-unterwegs.png" width="300" alt="Freie Wanderung im simulierten Stand mit Orte-Button und weiter laufender Aufzeichnung"> |

Die Raster-Hintergrundkarten hängen weiterhin vom externen Kartendienst ab; die korrigierte **85** zeigt nun die Umgebung statt einzelner vergrößerter Pixel. Die POI-Aktionen benötigen keine fertig geladene Hintergrundkarte. Wiederholbar über `POIUITests` und den lokalen HTTPS-Beispielserver. [Prüfstand und Installation](UMSETZUNG.md#profilübergreifende-pois-15-oktober-2026).

## Auto-POIs im Clay-Stil (15. Oktober 2026)

**82** ergänzt den Anbieterwechsel zu Geoapify: Die bestehende Detailansicht zeigt den gerouteten Pkw-Zielpunkt und ausdrücklich **125 m Luftlinie**, nicht berechneten Fußweg/Restzeit und Quellenangabe. Öffentlicher Heidelberger Straßenpunkt, frei erfundener Bahnhof und Abstand; **synthetisches UI-Beispiel, keine reale Geoapify-Antwort oder Zufahrtsbestätigung**. Der UI-Test öffnet alle fünf Nicht-Kraftstoffkategorien, prüft die Warnung und fügt das Bahnhofbeispiel in die Planung ein. Bild visuell geprüft; keine privaten Daten. Live-Anbieterprüfung getrennt im [Prüfstand](UMSETZUNG.md).

<img src="images/82-auto-poi-zielpunkt.png" width="300" alt="Synthetisches Bahnhofsbeispiel mit Pkw-Zielpunkt und Warnung zum nicht berechneten Restweg">

**79–81** zeigen die tatsächlich laufende POI-Seite. Sechs plastische Motive folgen der vom Nutzer gelieferten Home-Referenz; [Bildherkunft und Prompts](POI_BILDER.md). Angebote, Preise und Anfahrtswerte sind ausdrücklich **synthetische öffentliche Beispieldaten**, keine echten Tankstellenangebote oder bestätigten Zufahrten. **68/70** wurden mit den neuen POI-Einstiegen aktualisiert. Die ursprüngliche öffentliche Heidelberger Straßenroute bleibt echt; GPS und Tempo sind simuliert. Kein Feldtest.

| Kategorien | Diesel in der Planung | Diesel entlang der Route |
| --- | --- | --- |
| <img src="images/79-auto-poi-kacheln.png" width="250" alt="Sechs pastellfarbene Kacheln mit modellierten Clay-Motiven für Tankstelle, Supermarkt, Flughafen, Bahnhof, Strand und Parkplatz"> | <img src="images/80-auto-diesel-angebote.png" width="250" alt="Gekennzeichnete synthetische Dieselangebote mit Suchort, Radius, Preis und Anfahrtszeit"> | <img src="images/81-auto-diesel-route.png" width="250" alt="Synthetische Dieselangebote während der Fahrt mit zusätzlicher Fahrzeit"> |

Reproduzierbar mit dem lokalen HTTPS-Beispielserver `tests/fixtures/poi_server.py` und `POIUITests`. [Bedienung und Quellenprüfung](POI.md). Die Portale in Slowenien/Kroatien sind experimentell; Deutschlands Schlüssel ist inzwischen privat eingerichtet und live geprüft. Die neuen Bilder verwenden keine privaten Fahrten, Zugangsdaten oder das private Referenzfoto. Die nachfolgende Serverkorrektur verändert die gezeigten Kacheln/Angebote nicht; Ausfall-/Wartehinweise erscheinen in der vorhandenen Hinweisfläche. Die Galerie belegt nicht die aktuelle Verfügbarkeit des gestörten OSM-Diensts.

Auf dem iPhone-SE-Simulator (3. Generation) wurde zusätzlich geprüft, dass alle sechs Kacheln durch Scrollen erreichbar sind, die Parkplatzsuche geöffnet und die Planung wieder erreicht werden kann. Anders als der Home-Bildschirm ist diese POI-Seite bewusst scrollbar.

Version **0.4.0 (4)** · iPhone-Simulator, helle Darstellung. Planung und Routendetails am 24. September 2026 mit Höhenprofil und getrenntem lokalem Umfeld aktualisiert; Planungs-/Fahrtkarten und Einstellungen am 5. Oktober 2026 mit Kartenansichten aktualisiert; Ortssuche am 1. Oktober 2026 mit lokaler Koordinatenerkennung aktualisiert; Fahrprofile und maritime Ansichten am 14. Oktober 2026 mit Seeweg ergänzt; übrige Bilder vom 23. September 2026.

Die Bilder zeigen die tatsächlich laufende App. Die Straßenroute stammt aus dem öffentlichen Heidelberg-Beispiel von openrouteservice. Die Seekartenbilder verwenden öffentliche Tribunj-Beispielpunkte; die Seewegplanung Tribunj–Šibenik wird aus OSM-Küsten automatisch berechnet. Die gespeicherte **Beispielaufzeichnung**, ihre Zeit-/GPS-Samples und ihre Bike-Messwerte sind synthetische Demonstrationsdaten. In der Live-Fahrt ist kein echtes Bike verbunden: fehlende Messwerte bleiben leer. Persönliche Touren und Zugangsdaten sind nicht enthalten. Die Serveradresse `beispiel.invalid` ist ein nicht erreichbarer Platzhalter; ein vorbereitetes lokales Wegenetz ist für dieses alte ORS-Beispiel nicht vorhanden.

Die aktualisierten Ansichten **01** und **07** zeigen die nachträglich über SRTM ergänzten und lokal gespeicherten Höhen der öffentlichen Heidelberg-Beispielgeometrie. Der UI-Test hat Anzeige und Wiederöffnen ohne konfigurierten Serverzugang geprüft. Das Beispiel enthält kein vorbereitetes Offline-Wegenetz; der entsprechende Hinweis in der Planung ist daher erwartet. Die Aufnahmen wurden nach der Umstellung auf das mitwandernde 3-km-Umfeld erneut erstellt und geprüft. Die gespeicherte Route und der Fahrtstart bleiben auch ohne Umfelddaten verfügbar.


Am **9. Oktober 2026** wurden **01** (belagsabhängige Fahrzeit), **12/14** (ETA während Fahrt/Pause) und **42/43** (Blogfortschritt) aktualisiert bzw. ergänzt. Alle verwenden ausschließlich die öffentliche Heidelberger Beispielgeometrie und synthetische Aufzeichnungsdaten. **42/43** zeigen einen kontrolliert verzögerten lokalen HTTPS-Testserver, keinen echten Pi-/KI-Lauf. Die Anzeige „auf dem Pi gespeichert“ steht dort für den protokollgleichen lokalen Beispielserver. Der UI-Test prüft die echte HTTP-Auftragsannahme, Phasen, gesperrte Erstellungstaste und Wiederaufnahme nach Ansichtswechsel und App-Neustart; die Screenshots wurden visuell geprüft.

| Blog: Vorbereitung mit Zeitrückmeldung | Blog: Schreibphase nach App-Neustart |
| --- | --- |
| <img src="images/42-blog-fortschritt.png" width="300" alt="Öffentliche Beispieltour mit sichtbarem ersten Arbeitsschritt und verstrichener Zeit"> | <img src="images/43-blog-schreiben.png" width="300" alt="Öffentliche Beispieltour mit drittem Arbeitsschritt beim Schreiben und gesperrter Erstellungstaste"> |

## Universeller Startbildschirm

Neu am **14. Oktober 2026**: Der App-Start zeigt fünf bunte Clay-Kacheln. Eine Auswahl öffnet den eigenen Planungsbereich; ein sichtbarer Rückweg **Start** führt zur Auswahl. Die bisherigen Modusschalter entfallen. **Fahrt fortsetzen** öffnet die laufende/pausierte Aufzeichnung; eine andere Kachel ersetzt diese Fahrt nicht. **Alle Touren** zeigt das globale Archiv, innerhalb einer Anwendung sind deren eigene Touren sichtbar.

| Einstieg mit fünf Anwendungen | Bestehende Fahrt fortsetzen |
| --- | --- |
| <img src="images/72-start-clay.png" width="300" alt="Pastellfarbener Startbildschirm mit Clay-Bildern für Fahrrad, Auto, Wandern, Fahrrad und Wandern sowie Segeln"> | <img src="images/74-start-fortsetzen.png" width="300" alt="Startbildschirm mit direkter Rückkehr zur öffentlichen Heidelberger Auto-Beispielfahrt"> |

Auch auf dem **iPhone SE (3. Generation, 4,7 Zoll)** passen alle fünf Kacheln auf eine Seite. Die UI-Prüfung kontrolliert vollständig sichtbare und antippbare Kachelrahmen ohne ScrollView, mit und ohne fortsetzbare Autofahrt. Auf kompakten Bildschirmen erhält die Auswahl mehr Platz, indem Zusatztexte und Bilder kürzer bzw. kleiner werden; mit aktiver Fahrt entfällt gegebenenfalls die Fragezeile.

| Kompaktes iPhone | Kompaktes iPhone mit fortsetzbarer Fahrt |
| --- | --- |
| <img src="images/77-start-kompakt.png" width="300" alt="Alle fünf Clay-Kacheln vollständig auf einem 4,7-Zoll-iPhone ohne Scrollen"> | <img src="images/78-start-kompakt-fortsetzen.png" width="300" alt="Alle fünf Kacheln und die Fortsetzen-Aktion gemeinsam auf einem kompakten iPhone"> |

Die fünf Illustrationen wurden mit dem **eingebauten Imagegen-Werkzeug** generiert und als transparente PNGs in den Assetkatalog übernommen. [Vollständige Prompts und Bildpfade](../design/startbildschirm-prompts.json). Die Bilder zeigen die echte native Oberfläche im Simulator. Es werden ausschließlich öffentliche Beispielplanungen bzw. synthetische GPS-Daten verwendet. Die App wurde anschließend auf dem iPhone installiert und gestartet; diese Aufnahmen bleiben Simulatorbilder und sind kein Feldtest. Alle fünf Kacheln bleiben gleichzeitig auf einer Seite sichtbar. Höhe und Zusatztexte passen sich der Bildschirmgröße und einer vorhandenen Fahrt an. Auch eine sehr große Systemschrift erzeugt auf Home keine zweite Seite; die Kachelbeschriftungen behalten hier eine begrenzte Größe und vollständige VoiceOver-Namen.

**01/02, 06/17, 11–14, 57, 68–71** wurden mit dem neuen Einstieg und den passenden Anwendungseinstellungen erneuert. Die übrigen älteren Galerieaufnahmen dokumentieren ihren jeweils genannten Entwicklungsstand und können noch die frühere Moduswahl zeigen.

## Planung

Die drei Aktionen am unteren Kartenrand haben eine gemeinsame Höhe und Kapsel-Form. Höhenprofil als kompakte Symboltaste, **Beschreibung** und **Tour starten** als gleich breite Texttasten; abgestufte Grüntöne verdeutlichen die Hauptaktion. Bild 01 am 11. Oktober 2026 mit öffentlichen Beispieldaten erneuert, per Simulator-UI-Lauf erfasst und visuell geprüft.

| Tour planen | Karte mit eingeklappten Daten |
| --- | --- |
| <img src="images/01-planen.png" width="300" alt="Planungsansicht mit einer Heidelberger Beispielroute"> | <img src="images/02-karte.png" width="300" alt="Große Karte mit eingeklapptem Tourdatenbereich"> |

| Wegpunkte | Gespeicherte Orte |
| --- | --- |
| <img src="images/03-wegpunkte.png" width="300" alt="Start, Ziel und Aktionen für die Wegpunkte"> | <img src="images/04-orte.png" width="300" alt="Beispielorte als Favoriten"> |

| Ortssuche | Fahrprofil |
| --- | --- |
| <img src="images/05-suche.png" width="300" alt="Koordinatensuche mit einem öffentlichen Heidelberger Beispielpunkt und gespeicherten Beispielorten"> | <img src="images/06-profil.png" width="300" alt="Fahrrad-Einstellungen mit Fahrradtyp und Belagswünschen, ohne weitere Modusauswahl"> |

| Routendetails |
| --- |
| <img src="images/07-routendetails.png" width="300" alt="Höhenprofil und Wegbeschaffenheit der Beispielroute"> |

Die Ortssuche **05** zeigt die Eingabe `49,4100; 8,7000` und den lokal normalisierten Treffer eines öffentlichen **Beispielpunkts** in Heidelberg. Treffer stehen vor den gespeicherten Orten; beim Suchen schließt sich die Tastatur. Der Simulator-Test prüft die Suche ohne Server sowie die Übernahme in die Tour. Auch die Nutzereingabe `43.80104 N, 15.78955 E` und der kurze Plus Code `2WF2+8F Rodgau` sind durch Kerntests abgedeckt; die Abbildung verwendet ausschließlich den Heidelberger Beispielbestand.

## Rad&Wandern und Wandern

**06/17** am 14. Oktober 2026 mit dem universellen Einstieg erneuert. **06** enthält ausschließlich Fahrrad-Einstellungen, **17** das konservative Wanderprofil und die externe Wanderübersicht Waymarked Trails. Die passende Anwendung wird auf dem Startbildschirm gewählt. **73** zeigt Fahrrad & Wandern mit Radprofil und Erklärung des Abstellpunkts.

<img src="images/73-rad-wandern-profil.png" width="300" alt="Fahrrad-und-Wandern-Einstellungen mit Radprofil, Belagswunsch und Erklärung des Übergangs zu Fuß">

<img src="images/17-wandern-profil.png" width="300" alt="Wanderprofil ohne bekannte Kletterpassagen mit Hinweis auf fehlende OSM-Angaben und externe Wanderkarte">

**75** zeigt die vollständige Auswahl bei sehr großer Systemschrift ohne Scrollen, **76** die freie Wanderung mit näherer topografischer Karte, **Gegangen** und **Gehzeit**, ohne Fahrradwerte. Für 76 liefert das Debug-Standortszenario nach fünf Sekunden einen synthetischen frischen GPS-Punkt in Heidelberg. Keine berechnete Wanderstrecke und keine tatsächliche Wanderung.

| Einstieg mit großer Schrift | Freie Wanderung |
| --- | --- |
| <img src="images/75-start-grosse-schrift.png" width="300" alt="Alle fünf Clay-Kacheln auf einer Seite bei sehr großer Systemschrift"> | <img src="images/76-wandern-unterwegs.png" width="300" alt="Freie Wanderung mit topografischer Karte, Gehzeit und zurückgelegter Strecke ohne Fahrradtelemetrie"> |

Die Aufnahmen **18** und **19** verwenden ausschließlich eine **synthetische Rad-/Wanderaufteilung** der öffentlichen Heidelberger Beispielgeometrie für die Darstellung. Der Titel und die Routenwarnung kennzeichnen dies; die dargestellte Abstellposition ist kein live berechneter Stellplatz und kein Feldtest. Der UI-Test prüft getrennte Entfernungen und Abstellkoordinaten ohne Serverzugang. In echten Berechnungen entsteht der Übergang nur aus verbundenen Rad-/Fußrouten.

| Abstellpunkt auf der Planungskarte | Rad-/Wanderabschnitte in den Details |
| --- | --- |
| <img src="images/18-rad-wandern-karte.png" width="300" alt="Synthetisches UI-Beispiel mit orangefarbenem Rad-Abstellmarker auf der Heidelberger Beispielroute"> | <img src="images/19-rad-wandern-details.png" width="300" alt="Synthetisches UI-Beispiel mit Radstrecke, Fußrest und Abstellkoordinaten"> |

### POI außerhalb des erfassten Wegenetzes

Neue Aufnahmen **20** und **21** vom 5. Oktober 2026 zeigen die Korrektur für Ziele abseits des erfassten Wegenetzes. Ausschließlich **synthetisches UI-Beispiel** auf Basis der öffentlichen Heidelberger Route: Zielpunkt um etwa 319 m versetzt, kein tatsächlicher Fußweg und keine private POI-Position. Der Test prüft sichtbare Radanfahrt, terminalen Abstellmarker und ausdrücklichen Hinweis auf den nicht berechneten Fußrest. Die tatsächlichen privaten Testkoordinaten sind weder in der Galerie noch in den Fixtures enthalten.

| Fehlende Wegdaten zum POI | Nicht berechneter Fußrest |
| --- | --- |
| <img src="images/20-zielzugang-karte.png" width="300" alt="Synthetisches Zielzugang-Beispiel mit erhaltener Route, Abstellpunkt und sichtbarem Hinweis auf fehlende Wegdaten"> | <img src="images/21-zielzugang-details.png" width="300" alt="Synthetisches Zielzugang-Beispiel mit 319 m Luftlinie, nicht berechnetem Fußrest und Abstellkoordinaten"> |

## Kartenansichten

Neu am 5. Oktober 2026: Das Ebenensymbol in Planung und Fahrt öffnet die Kartenwahl; dieselbe Auswahl steht unter Einstellungen → Karten zur Verfügung. Beim App-Start erscheint die Anwendungsauswahl. Fahrrad/Auto/Kombination öffnen **Standard · Deutsch**, Wandern **Topografisch**, Segeln **Seekarte**. Tabwechsel und kurze Hintergrundpausen erhalten die gewählte Ansicht. Bilder 01/02, 11, 12/14 sowie 25–29 wurden im Simulator mit der öffentlichen, gekennzeichneten Heidelberg-Beispieltour aktualisiert. Satellit ist eine Online-Luftbildkarte ohne Ortsbeschriftungen; Topografisch zeigt OpenTopoMap-Gelände und Höhenlinien. Die übrigen Grundkartenstile ändern Routing und Wanderprüfung nicht; Die Segel-Kachel bestimmt Seewege; der Kartenstil ändert keine Anwendung.

| Hell | Detailreich | Dunkel |
| --- | --- | --- |
| <img src="images/25-karte-hell.png" width="260" alt="Öffentliche Heidelberg-Beispieltour mit heller Positron-Karte"> | <img src="images/26-karte-detailreich.png" width="260" alt="Öffentliche Heidelberg-Beispieltour mit detailreicher Bright-Karte"> | <img src="images/27-karte-dunkel.png" width="260" alt="Öffentliche Heidelberg-Beispieltour mit dunkler Karte"> |

| Satellit | Topografisch |
| --- | --- |
| <img src="images/28-karte-satellit.png" width="300" alt="Öffentliche Heidelberg-Beispieltour auf Esri-Satellitenbildern"> | <img src="images/29-karte-topografisch.png" width="300" alt="Öffentliche Heidelberg-Beispieltour auf OpenTopoMap mit Höhenlinien"> |

Am **14. Oktober 2026** mit **Seekarte · OpenSeaMap**, automatischer **Seeweg**-Profilwahl und optionalen **EMODnet-Wassertiefen** aktualisiert. **55** zeigt öffentliche Tribunj-Beispielpunkte mit absichtlich nicht erreichbarer Beispiel-API: keine berechnete Route und ein ausdrücklicher Serverhinweis. Die ältere Aufnahme zeigt die damalige automatische Seewegwahl über den Kartenstil. Im aktuellen Einstieg öffnet die Segel-Kachel direkt die Seekarte; Kartenstile ändern keine Anwendung mehr. **56/62** zeigen die korrigierten sichtbaren Bootsfelder mit **2 m / 5,5 kn** und der Tiefenebene; **57** zeigt dieselbe Bearbeitung im Segelprofil mit **2,7 m / 5,5 kn**; die tatsächlichen Standardwerte sind **2 m / 4 kn**. Keine privaten Zugangswerte oder Fahrtdaten.

| Seekarte · OpenSeaMap | Auswahl in den Einstellungen |
| --- | --- |
| <img src="images/55-karte-seekarte.png" width="300" alt="Öffentliche Beispielpunkte am Meer um Tribunj mit OpenSeaMap-Seezeichen über der OpenStreetMap-Grundkarte"> | <img src="images/56-einstellungen-seekarte.png" width="300" alt="Bootseinstellungen und gewählte Seekarte mit zuschaltbaren EMODnet-Wassertiefen"> |

Seekarte: © [OpenStreetMap-Mitwirkende](https://www.openstreetmap.org/copyright), Seezeichen © [OpenSeaMap](https://www.openseamap.org). [Nutzungshinweise](https://www.openseamap.org/index.php?id=imprint&L=1). Die ältere Karte verwendet öffentliche Tribunj-Beispielpunkte; die korrigierten Einstellungen verwenden synthetische Bootswerte. Kein Feldtest. Wiederholen mit `scripts/seed_gallery.py --device DEVICE --elevation --seamap` und `MapStyleTests/testSeaMapExampleAndSettingsScreenshots`; die übrigen Kartenstilaufnahmen verwenden weiter Heidelberg.

### Seeweg planen und auf See fahren

Aktuelle Aufnahmen **57–65** vom **14. Oktober 2026**: öffentliche Planung **Tribunj–Šibenik · Seeweg-Beispiel** mit zwei Start-/Zielpunkten. Der echte Wasserweg-Algorithmus berechnet rund **6,9 sm und zwölf Kursabschnitte** anhand des öffentlichen OSM-Snapshots und nativer EMODnet-Zellen. Fährlinien erhalten keinen Vorteil; die gesamte Linie wird gegen Wasserfläche und Tiefenmaske geprüft. Unbekannte Tiefen sind sichtbar gekennzeichnet. Die lokale HTTPS-Test-API ersetzt nur die Geodatenabrufe durch öffentliche Snapshots; sie ist kein installierter Pi.

| Seewegprofil | Automatische Wasserroute | Wegpunkte und Kurse |
| --- | --- | --- |
| <img src="images/57-seeweg-profil.png" width="250" alt="Seewegprofil mit Küstenprüfung und ohne Fahrradoptionen"> | <img src="images/58-seeweg-planung.png" width="250" alt="Automatisch berechnete öffentliche Wasserroute von Tribunj nach Šibenik mit 6,9 Seemeilen und zwölf Kursabschnitten"> | <img src="images/59-seeweg-kurse.png" width="250" alt="Automatisch erzeugte Kurswechsel mit rechtweisenden Kursen, Seemeilen und Koordinaten"> |

| Maritime Fahrt | Aufzeichnung pausiert |
| --- | --- |
| <img src="images/60-seekarte-fahren.png" width="300" alt="Gekennzeichnetes GPS-Beispiel auf der Seekarte mit großem Kurs über Grund, Knoten und Peilung zum nächsten Wegpunkt"> | <img src="images/61-seekarte-pause.png" width="300" alt="Pausierte maritime Aufzeichnung mit Seekarte und Fortsetzen ohne Fahrradkommunikation"> |

**60/61** zeigen ausdrücklich synthetisches **GPS-Beispiel · Tribunj–Šibenik**, das der berechneten Route folgt. Kurs über Grund stammt aus dieser Bewegung, nicht aus dem Telefonkompass. Bei Pause kann sich das Boot weiter bewegen; die Aufzeichnung bleibt unterbrochen. Norden bleibt oben; Fahrradverbindung, Höhenprofil und Straßenansagen entfallen. Alle übernommenen Aufnahmen visuell geprüft. Gesamtstrecke und Reststrecke bleiben sichtbar; ETA verwendet das Durchschnittstempo aus Einstellungen und bleibt in Pause leer. EMODnet-Rasterprüfung ist keine bestätigte nautische Befahrbarkeit; keine reale Seefahrt oder Hindernisprüfung.

Wiederholen: `seed_gallery.py --device DEVICE --elevation --seamap`, lokaler HTTPS-Beispielserver `tests/fixtures/marine_server.py` auf Port 18445, danach `MarineRoutingUITests/testAutomaticWaterRouteAndMarineRideAcrossPauseAndRestart`. Der Test prüft die echte automatische Berechnung, Kursanzeige, Streckenaufzeichnung, Pause, Neustart, Fortsetzen und Speichern. [Testdaten und Herkunft](../tests/fixtures/README.md) · [Algorithmus und Grenzen](ARCHITEKTUR.md#seeweg-und-maritime-navigation-13-oktober-2026).

### Bootseinstellungen, EMODnet und lange Törns

**56/57/62** wurden nach der Eingabekorrektur am 14. Oktober neu aufgenommen und visuell geprüft. **62** zeigt die gespeicherten Beispielwerte 2 m/5,5 kn, mit absichtlich eingegebenem Dezimalpunkt im Tiefgangsfeld; Komma ist ebenfalls möglich. Der zugehörige UI-Test prüft anschließend die Speicherung über Neustart. Aufnahme aus dem dedizierten Dokumentationssimulator mit öffentlichen/synthetischen Beispielen und ohne Serverzugang; keine reale Nutzerfahrt. Die neuen Felder und „Bootswerte speichern“ stehen in Einstellungen und Segelprofil bereit. Wiederholen mit `MarineRoutingUITests/testBoatSettingsAllowClearingDecimalInputAndValidateOnCompletion`. Für **63/64** wurden wieder 2 m und 4 kn eingestellt. Die grobe Tiefenebene liegt unter den Seezeichen; ihr Hinweis **nicht zur Navigation geeignet** bleibt sichtbar. Gesamtstrecke und ETA erscheinen in der maritimen Fahrt. **65** zeigt eine zuvor mit echten Anbieterdaten berechnete, gespeicherte Beispielplanung zum Wasserpunkt vor Ancona: **98,8 sm / zwei Abschnitte / etwa 24 h 41 min bei 4 kn**. Der UI-Test prüft ihre Darstellung; die getrennte abschließende Pi-Liveberechnung ergab 98,17 sm und drei Abschnitte. Beide sind öffentliche technische Beispiele, keine Freigabe einer Seeroute.

| Gespeicherte Bootswerte | Tiefen in der Planung |
| --- | --- |
| <img src="images/62-boot-einstellungen.png" width="300" alt="Editierbare Bootswerte mit Beispiel 2 Meter Tiefgang, 5,5 Knoten und Speichertaste"> | <img src="images/63-emodnet-planung.png" width="300" alt="EMODnet-Tiefen über der Tribunj-Planung mit Hinweis auf unbekannte Tiefen"> |

| Gesamtstrecke und ETA | Langer Törn nach Ancona |
| --- | --- |
| <img src="images/64-emodnet-fahren-eta.png" width="300" alt="Maritime Fahransicht mit Gesamtstrecke, Reststrecke und geschätzter Ankunft"> | <img src="images/65-seeweg-ancona.png" width="300" alt="Öffentliche Ancona-Beispielplanung mit 98,8 Seemeilen und rund 24 Stunden 41 Minuten"> |

Tiefen: **EMODnet DTM 2024**, [CC BY 4.0 / Nutzungsbedingungen](https://emodnet.ec.europa.eu/en/terms-use-emodnet-online-services-data-and-data-products). Nicht zur Navigation geeignet. Wiederholen zusätzlich mit `MarineRoutingUITests/testBoatSettingsPersistAndDepthLayerWorksAfterRestart` und dem damaligen Test für die gespeicherte Ancona-Route (seit Routenrevision 2 ersetzt durch `testOutdatedAnconaExampleRequiresRecalculation`). Alle Bilder visuell geprüft; keine privaten Nutzerbilder übernommen.

Satellitenbilder: Esri World Imagery · Source: Esri, Vantor, Earthstar Geographics, and the GIS User Community. Topografische Kartendaten: © OpenStreetMap-Mitwirkende, SRTM; Kartendarstellung: © [OpenTopoMap](https://opentopomap.org/about) ([CC-BY-SA](https://creativecommons.org/licenses/by-sa/3.0/)). Die Quellhinweise sind zusätzlich über die Karteninformation der App erreichbar. Die Rasterauflösung ist quellenabhängig; größere Zoomstufen vergrößern vorhandene Bildkacheln. Keine Offline-Pakete oder Feldtests.

## Unterwegs

### Freie Fahrt ohne Strecke

Seit 13. Oktober 2026 startet **Fahren** auch ohne berechnete Strecke die Aufzeichnung. Die aktuelle Karte folgt dem Standort, die gefahrene Spur erscheint orange. Gefahrene Strecke, Tempo und Fahrzeit bleiben sichtbar; Pause, Fortsetzen und Beenden funktionieren wie bei einer geplanten Tour. Ohne Route entfallen Abbiegehinweise, Reststrecke, ETA, Höhenprofil und Sprachsteuerung. Während der GPS-Suche bleibt die Karte sichtbar.

<img src="images/54-freie-fahrt.png" width="300" alt="Beispieldaten Heidelberg: freie Fahrt ohne Route mit aktueller Karte und Aufzeichnung">

Aufnahme aus dem Simulator mit ausdrücklich synthetischen öffentlichen Heidelberg-Beispielkoordinaten; kein GPS-Feldtest.

### Standort beim Fahrtstart

Neu am 25. September 2026: Der Fahrtstart wartet bis zu 15 Sekunden auf eine frische Position. Die Standortsuche kann abgebrochen werden. Aufnahme aus dem Simulator mit ausdrücklich synthetischen Standort-Testdaten einer **Beispieltour** in Heidelberg; kein GPS-Feldtest. Die UI-Prüfung liefert den Beispielstandort verzögert und prüft den anschließenden automatischen Fahrtstart.

<img src="images/16-standortsuche.png" width="300" alt="Beispiel: Standortsuche vor dem Fahrtstart mit Fortschrittsanzeige und Abbrechen-Taste">


Die laufende Fahrt verwendet den Standort im unteren Fünftel, 500 m Vorausschau und die maximal mögliche Schrägansicht. Im Simulator fehlen echte Kompass- und Bike-Sensorwerte. Die Pause zeigt absichtlich keine aktive Nachführung.

| Laufende Tour | Pause | Bike-Verbindung |
| --- | --- | --- |
| <img src="images/12-fahren.png" width="260" alt="Laufende Navigation mit Karte, Abbiegehinweis und Fahrtasten"> | <img src="images/14-pause.png" width="260" alt="Pausierte Tour mit Fortsetzen-Taste"> | <img src="images/13-bike.png" width="260" alt="Bike-Diagnose ohne verbundenes Fahrrad"> |

### Zwischenziele überspringen

<img src="images/15-zwischenziele.png" width="300" alt="Nachfrage für zwei Beispiel-Zwischenziele mit großen Ja- und Nein-Tasten">

Am 24. September 2026 im Simulator aufgenommen. Beide Tasten sind mindestens 96 Punkte hoch. Die zwei zusätzlich eingefügten Zwischenziele sind ausdrücklich als Beispiele gekennzeichnet. Der Debug-Einstieg `BIKENAVI_PREVIEW_SKIP=1` erzeugt die Dialogsituation für `DocumentationScreenshotsTests/testWaypointSkipLargeButtons`; er ist kein GPS-Feldtest und in Release-Builds nicht enthalten. Der Test prüft beide Tasten und ihre Mindesthöhe. Zum Wiederholen zuerst den normalen Galerie-Beispielbestand neu einspielen.

## Tourenarchiv und Auswertung

Die Diagramme und Fahrmodusfarben demonstrieren ausschließlich die Darstellung. Sie sind kein Nachweis gemessener Leistungswerte bei einer realen Fahrt.

| Gespeicherte Touren | Fahrt mit Modusfarben | Höhen- und Leistungsverlauf |
| --- | --- | --- |
| <img src="images/08-touren.png" width="260" alt="Archiv der Beispielplanung"> | <img src="images/09-fahrtdetails.png" width="260" alt="Synthetische Beispielaufzeichnung mit Fahrmodusfarben"> | <img src="images/10-auswertung.png" width="260" alt="Diagramme für synthetische Höhen- und Leistungsdaten"> |

## Einstellungen und Logo

Die zusätzliche BikeNavi-Titelbox wurde entfernt; die Pi-Server-Einstellungen folgen direkt auf die Lautstärke. Die erste Box regelt auf dem echten iPhone direkt die System-Medienlautstärke über Apples nativen Regler. Die Aufnahme vom 29. September 2026 zeigt den ausdrücklichen Simulatorhinweis, da iOS im Simulator keinen funktionsfähigen Systemregler bereitstellt. Der UI-Test prüft die Position der Box, den Hörprobenknopf und den Wechsel zwischen Reitern. Kopplung mit den Hardwaretasten und hörbare Lautstärke sind am iPhone zu prüfen.

| Einstellungen | App-Logo |
| --- | --- |
| <img src="images/11-einstellungen.png" width="300" alt="Einstellungen ohne echte Serveradresse oder Schlüssel"> | <img src="../ios/BikeNavi/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="220" alt="BikeNavi-Logo mit Fahrrad und Navigationspfeil"> |

Original und Entstehung des Logos: [AppIcon.md](../design/AppIcon.md). Die Screenshots zeigen Karten von OpenFreeMap mit Daten von [© OpenStreetMap-Mitwirkenden](https://www.openstreetmap.org/copyright). Quellen des Routenbeispiels: [Testdaten](../tests/fixtures/README.md).

## Bilder erneut erstellen

1. Einen eigenen iPhone-Simulator mit iOS 26.1 starten. Keine persönlichen App-Daten oder Serverzugänge verwenden.
2. Das Scheme `BikeNavi` mit `xcodebuild build-for-testing` für diesen Simulator bauen und die App mit `xcrun simctl install DEVICE APP_PATH` installieren. Bei Bedarf einen eindeutigen `CONFIGURATION_BUILD_DIR` angeben und beim Testlauf denselben Wert verwenden.
3. Beispielbestand vorbereiten:

   ```sh
   python3 scripts/seed_gallery.py --device DEVICE
   xcrun simctl privacy DEVICE grant location-always de.michaelhein.BikeNavi
   xcrun simctl ui DEVICE appearance light
   xcrun simctl status_bar DEVICE override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
   ```

4. Nur `BikeNaviUITests/DocumentationScreenshotsTests` mit `xcodebuild test-without-building`, `-parallel-testing-enabled NO`, dem konkreten Simulatorziel und einem neuen `-resultBundlePath` ausführen. Die Testklasse verwendet eine lokale Beispielplanung und einen simulierten Standort. Für die Fahrtansicht setzt sie `BIKENAVI_PREVIEW_LOCATION=49.414601,8.681496` als ausdrücklich aktivierte Debug-Testposition; Release-Builds enthalten diesen Einstieg nicht. Ohne vorbereiteten Beispielbestand überspringt sie die Galerie.
5. Anhänge mit `xcrun xcresulttool export attachments --path RESULT.xcresult --output-path OUTPUT` exportieren. Die im Manifest benannten `Gallery-…`-Bilder als `01-planen.png` usw. nach `docs/images/` übernehmen.
   Für die Höhen-Erweiterung zunächst `scripts/seed_gallery.py --device DEVICE --elevation` ausführen und gezielt `DocumentationScreenshotsTests/testCaptureSavedElevationOffline` starten. Dieser Lauf erzeugt die aktualisierten Bilder 01 und 07 und prüft das erneute Öffnen des Profils ohne Serverzugang.

   Für die Kartenwahl den öffentlichen Bestand mit `--elevation` vorbereiten und `MapStyleTests/testStylesSwitchAcrossTabsAndRestartWithGermanDefault` ausführen. Der Test erzeugt Bilder 01/02, 11 und 25–29 und prüft Auswahl, Tabwechsel, Hintergrundpause und Neustartstandard. `DocumentationScreenshotsTests/testCaptureRideScreenshots` erneuert 12/14 mit dem Ebenensymbol in der Fahrt.

   Für den Lautstärkeregler gezielt `SettingsVolumeTests/testSystemVolumeBoxIsFirstAndOffersPreview` ausführen; dessen Anhang `Gallery-11-einstellungen` aktualisiert Bild 11.

   Für die Koordinatensuche `CoordinateSearchTests/testCoordinateSearchWithoutServerAndSelection` ausführen. Der Anhang `Gallery-05-suche` aktualisiert Bild 05; der Test verwendet den öffentlichen Heidelberger Beispielpunkt, ohne Serverzugang.

6. Jedes Bild auf vollständige Ansicht, geladene Karte, korrekte Beschriftung und fehlende private Daten prüfen. Nach Abschluss kann der ausschließlich dafür angelegte Simulator entfernt werden.

Die Galerie zeigt die zentralen Ansichten, nicht jeden Dialog, jede Fehlermeldung oder die separate Live-Aktivität auf dem Sperrbildschirm.


## Belagswunsch eindeutig in der Planung

Die Aufnahmen **22** und **23** zeigen dieselbe gekennzeichnete synthetische Heidelberg-Beispielplanung. Die Planung nennt den vollständigen Belagswunsch in einer eigenen Zeile unter den Profiltasten, sodass die strenge Auswahl von der bloßen Bevorzugung unterscheidbar ist. Der Simulator-Test prüft beide Anzeigen und die Persistenz der strengen Auswahl nach Neustart. Die Beispielroute dient hier nur der Darstellung der Auswahl, nicht als Berechnung mit der dargestellten Belagsoption.

| Nur bekannte befestigte Wege | Befestigte Wege bevorzugen |
| --- | --- |
| <img src="images/22-belagswahl-streng.png" width="300" alt="Planungsansicht mit vollständiger strenger Belagsoption an öffentlichen Beispieldaten"> | <img src="images/23-belagswahl-bevorzugen.png" width="300" alt="Planungsansicht mit vollständiger bevorzugter Belagsoption an öffentlichen Beispieldaten"> |

Für diese Bilder den synthetischen Bestand mit `seed_gallery.py --bike-and-hike` vorbereiten und gezielt `WalkingOptionsTests/testPlanningDistinguishesPreferredAndStrictPaving` ausführen.


## Toleranz für kurze Straßen-Belagslücken

Aufnahme **24** zeigt im Profil die Online-Ausnahme für fehlende Beläge zwischen bekannten befestigten Straßenabschnitten (250 m je Lücke, 500 m insgesamt) sowie die weiterhin strengere lokale Offlinegrenze. Der Simulator-Test prüft den sichtbaren Hinweis anhand derselben öffentlichen, gekennzeichneten Beispielplanung. Profilbild **06** wurde mit dem aktuellen Text ebenfalls erneuert.

<img src="images/24-belagsluecken-profil.png" width="300" alt="Fahrprofil mit Erklärung der begrenzten Online-Toleranz für unbekannte Straßenbeläge und der Offlinegrenze">


## Tourtagebuch und Blog

Aufnahme **12** wurde mit der Taste **Blog-Ort festhalten** erneuert. **30** zeigt eine rein synthetische Notiz an einem öffentlichen Heidelberger Standort; im Simulator wird die Kameraaufnahme mangels Kamera nicht angeboten. **31** zeigt gespeicherte, noch nicht übertragene Beispielstationen sowie die neuen Aktionen zum Hinzufügen und Bearbeiten im Tourtagebuch. Der UI-Test prüft Speicherung ohne Server, Erhalt nach Neustart und einen verständlichen Hinweis bei Blogerstellung ohne Pi-Konfiguration.

| Ort festhalten | Tourtagebuch |
| --- | --- |
| <img src="images/30-blog-ort.png" width="300" alt="Blog-Ort mit synthetischer Beispielnotiz und öffentlichem Heidelberger Standort"> | <img src="images/31-tourtagebuch.png" width="300" alt="Tourtagebuch mit synthetischen Beispielstationen, Hinzufügen, Bearbeiten und ausstehender Übertragung"> |

Die Blogvorschau verwendet einen auf dem Pi tatsächlich erzeugten KI-Blog zu öffentlichen Heidelberger Orten. Die Erinnerungen und Fahrtaufzeichnung sind synthetisch; das als Beispielbild gekennzeichnete BikeNavi-Icon ist kein Reisefoto. Kartenkacheln und Recherchequellen sind real. Das [portable HTML-Beispiel](examples/heidelberg-blog.html) enthält alle Bilder und Karten direkt.

**32–34** zeigen den Titelbereich, die große topografische Streckenübersicht und einen Detailausschnitt mit markiertem Beispielort. Die Vorschauprüfung wartet auf den abgeschlossenen HTML-Ladevorgang und prüft den sichtbaren Kartenausschnitt. Die Aufnahme der großen Karte scrollt zusätzlich gezielt zur vollständigen Übersicht. Alle Aufnahmen wurden visuell kontrolliert.

| KI-Blogvorschau | Topografische Streckenübersicht | Topografische Details |
| --- | --- | --- |
| <img src="images/32-blog-vorschau.png" width="250" alt="Bunter KI-Blogtitel und motivierende Einleitung zur öffentlichen Heidelberger Beispieltour"> | <img src="images/33-blog-karte.png" width="250" alt="Topografische Beispielstrecke mit nummerierten Erinnerungsorten"> | <img src="images/34-blog-topografie.png" width="250" alt="Eingebettete topografische Karte am öffentlichen Beispielort mit ausdrücklich synthetischer Notiz"> |

Topografische Kartendaten: © [OpenStreetMap-Mitwirkende](https://www.openstreetmap.org/copyright), SRTM · Darstellung: © [OpenTopoMap](https://opentopomap.org), [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/). Lizenz- und Quellenangaben sind im HTML ebenfalls enthalten.

Für reproduzierbare Aufnahmen: Dokumentationssimulator mit `seed_gallery.py --device UUID --elevation --blog docs/examples/heidelberg-blog.html` vorbereiten; gezielt `DocumentationScreenshotsTests/testBlogPointOfflineAndJournalScreens` und `DocumentationScreenshotsTests/testBlogHTMLPreviewWithPublicExample` ausführen. Kein Feldtest.


## Direkter Blogzugang und beschriftetes Höhenprofil

**35** zeigt den direkten Bloglink unter den Kennzahlen einer gefahrenen Beispieltour. **36** zeigt denselben Zugang in der zugehörigen archivierten Planung. **31** wurde erneuert: „Blog erstellen“ steht im Tourtagebuch vor den Bildern. **37** zeigt die numerischen Achsen: Höhe in Metern links, Strecke in Kilometern unten. Die große Streckenkarte **33** nutzt jetzt eingebettete OpenTopoMap-Kacheln mit der Route.

| Gefahrene Tour | Zugehörige Planung | Profil mit m/km |
| --- | --- | --- |
| <img src="images/35-tour-blog-direkt.png" width="250" alt="Direkter Bloglink unter den Fahrtdaten einer öffentlichen Beispielaufzeichnung"> | <img src="images/36-plan-blog-direkt.png" width="250" alt="Blogzugang zur zugehörigen Beispielaufzeichnung in einer archivierten Planung"> | <img src="images/37-blog-profilachsen.png" width="250" alt="Höhenprofil mit numerischer Höhe-y in Metern und Strecke-x in Kilometern"> |

Alle Aufnahmen mit öffentlichen, gekennzeichneten Heidelberger Beispielen geprüft. Der UI-Test prüft zusätzlich die Wiederherstellung einer veralteten Positionsmeldung durch einen verzögert gelieferten frischen Beispiel-Fix. Kameraberechtigung und tatsächliche GPS-Erneuerung im Stand bleiben Geräteprüfungen.


## Versionsanzeige 0.4.0

Die Blogaufnahmen 30–37 wurden für Release 0.4.0 (4) mit dem aktualisierten öffentlichen HTML-Beispiel erneuert. Die Einstellungen **11** wurden ebenfalls erneuert. **38** zeigt die tatsächliche Versions- und Buildnummer aus dem Simulator-App-Bundle. Kein Feldtest und keine echte Serveradresse/Zugangsdaten im Bild.

<img src="images/38-version-0-4.png" width="300" alt="Einstellungen mit tatsächlicher App-Version 0.4.0 und Build 4 sowie öffentlichen Kartenquellen">

## Stationen nachtragen und bearbeiten

**39** zeigt den Nachtrag einer Station aus einem Bild mit GPS-Standort. **40** zeigt die gewählte Position nach einer vorhandenen Station; das sichtbare Bild ist ein ausdrücklich beschriftetes synthetisches GPS-Testbild am öffentlichen Heidelberger Standort. **41** zeigt die Positionswahl beim Bearbeiten einer bestehenden Station und deren Verschiebung an den Anfang. Nach **Speichern** bleiben die Änderungen offline und nach Neustart erhalten; eine neue Blogfassung übernimmt sie nach dem Pi-Abgleich.

| Station hinzufügen | Position des Nachtrags | Station bearbeiten |
| --- | --- | --- |
| <img src="images/39-blog-station-hinzufuegen.png" width="250" alt="Nachträgliche Station aus einem GPS-Foto hinzufügen"> | <img src="images/40-blog-station-position.png" width="250" alt="Synthetischer GPS-Fotonachtrag wird nach dem ersten Beispielort eingefügt"> | <img src="images/41-blog-station-bearbeiten.png" width="250" alt="Position einer bearbeiteten Beispielstation an den Anfang ändern"> |

Reproduzierbar mit `seed_gallery.py --device UUID --elevation --blog docs/examples/heidelberg-blog.html --journal` und `DocumentationScreenshotsTests/testBlogStationInsertEditOrderAndOfflineRestart`. Der Test verwendet den echten System-Fotopicker im Simulator. GPS-Extraktion, fehlende/ungültige Bildkoordinaten, alte Ortsdaten und revisionsgeprüfter Abgleich werden zusätzlich durch Swift-/Backendtests geprüft. Reale iPhone-/iCloud-Fotoauswahl bleibt separat zu prüfen; kein Feldtest.

## Routenbeschreibung vor der Tour

**01** wurde mit der neuen Taste **Beschreibung** mit Funkel-Symbol in der Planung erneuert. Sie öffnet eine gespeicherte Beschreibung der aktuellen Routenfassung; für neue oder geänderte Routen startet mit Pi direkt die Erstellung. **44** zeigt den Einstieg ohne eingerichteten Pi, **45** die offline gelesene Beschreibung der gekennzeichneten öffentlichen Heidelberger Planung mit Strecken-/Anstiegssymbolen. **46** zeigt kompakte Belags-/Steigungshinweise mit Symbolen und Streckenpositionen. **47** zeigt ein eingebettetes Commons-Bild mit Quellen-/Lizenzhinweis. Die Erstellung verwendet echte Wikipedia-/Commons-/OpenTopoMap-Abfragen und einen ausdrücklich gekennzeichneten Vorlagentext; ohne KI nur kurze deutsche Ortsauszüge, kein Feldtest.

| Einstieg vor dem Start | Gespeicherte Routenbeschreibung |
| --- | --- |
| <img src="images/44-routenbeschreibung.png" width="300" alt="Eigenständige Routenbeschreibung vor der Tour mit Hinweis auf die benötigte Pi-Verbindung"> | <img src="images/45-routenbeschreibung-vorschau.png" width="300" alt="Offline gelesene Routenbeschreibung einer öffentlichen Heidelberger Beispielplanung"> |

| Streckenhinweise | Bild am Wegesrand |
| --- | --- |
| <img src="images/46-routenbeschreibung-abschnitt.png" width="300" alt="Kompakte Hinweise mit Symbolen für Untergrund, Anstieg und Abfahrt im öffentlichen Beispiel"> | <img src="images/47-routenbeschreibung-bild.png" width="300" alt="Eingebettetes Commons-Bild zur Pädagogischen Hochschule Heidelberg mit Quellen- und Lizenzangaben"> |

Die Simulatorprüfung verwendet einen separaten lokalen HTTPS-Testserver und öffentliche Beispieldaten. Geprüft werden Erstellung durch die Planungstaste, Fortschritt, Schließen der Ansicht/App während des Pi-Auftrags, Wiederaufnahme nach Neustart, Speicherung und Lesen ohne Pi-Zugang sowie der Hinweis nach Änderung des Tourtitels. Der echte Pi wird nicht angesprochen; kein iPhone-Deployment. Quelle und Lizenz stehen bei jedem Bild im HTML, zusätzlich Wikipedia-Auszüge unter CC BY-SA 4.0. [Portables Beispiel](examples/heidelberg-routenbeschreibung.html) · [Bedienung und Grenzen](ROUTENBESCHREIBUNG.md).

Zur Reproduktion den separaten Dokumentationssimulator mit `seed_gallery.py --device UUID --elevation` vorbereiten und lokale Beispieldaten in `route_descriptions` zurücksetzen. `tests/fixtures/route_description_server.py` mit temporärem, ausschließlich im Testsimulator vertrautem TLS-Zertifikat auf `https://127.0.0.1:18444` starten. Danach `RouteDescriptionUITests` ausführen und die `Gallery-01`-/`Gallery-44`–`47`-Anhänge exportieren. Server, temporäre Datenbank, Zertifikat und Protokolle bleiben außerhalb von Git. Ohne Testserver nur `testPreTourDescriptionWithoutPiAndPlanningScreenshot` ausführen.

| Topografische Übersicht | Geänderte Route ohne alten Text | Neue Beschreibung zur aktuellen Fassung |
| --- | --- | --- |
| <img src="images/51-routenbeschreibung-topografie.png" width="250" alt="Geplante Heidelberger Route und nummerierte Wegpunkte auf eingebettetem OpenTopoMap-Hintergrund"> | <img src="images/52-routenbeschreibung-neue-route.png" width="250" alt="Nach Änderung des öffentlichen Planungssnapshots wird der vorige Routentext nicht mehr angezeigt"> | <img src="images/53-routenbeschreibung-aktuelle-route.png" width="250" alt="Automatisch erzeugte Beschreibung mit dem geänderten Titel der öffentlichen Beispielplanung"> |

**51** zeigt die topografische Übersicht offline nach App-Neustart; Quellen- und Lizenzangaben sind im HTML direkt unter der Karte eingebettet. **52** zeigt den Einstieg nach geänderter Planung ohne eine unpassende alte Vorschau. **53** zeigt die anschließend zur aktuellen Fassung neu erzeugte Beschreibung. Topografie-/Offline-Lauf und fokussierter Wechseltest `testChangedRouteOpensFreshDescriptionInsteadOfPreviousText` mit lokalem HTTPS-Testserver erfolgreich; alle Bilder visuell geprüft. Der neue Titel dient im UI-Lauf als sichtbarer Snapshotwechsel, Änderungen an Geometrie/Route-ID und anderen Plandaten werden zusätzlich im Swift-Kern geprüft. Kein Feldtest.

## Highlights einfügen und weiterlesen

**48** zeigt **Als Zwischenziel einfügen** an einem recherchierten öffentlichen Heidelberger Ort. **49** zeigt zwei ausgewählte Orte während der Neuberechnung: Die Beschreibung bleibt an der gelesenen Stelle geöffnet, weitere Highlight-Aktionen bleiben bedienbar. **50** zeigt beide Ziele zwischen dem unveränderten Beispielstart und -ziel; die Reihenfolge bleibt nach App-Neustart erhalten.

| Ort auswählen | Weiterlesen während der Berechnung | Eingefügte Zwischenziele |
| --- | --- | --- |
| <img src="images/48-highlight-einfuegen.png" width="250" alt="Ein recherchierter öffentlicher Heidelberger Ort lässt sich mit einem Tippen einplanen"> | <img src="images/49-highlights-hintergrund.png" width="250" alt="Weitere Highlights lesen und auswählen, während die Route im Hintergrund aktualisiert wird"> | <img src="images/50-highlight-zwischenziele.png" width="250" alt="Zwei neue Zwischenziele zwischen unverändertem Beispielstart und Beispielziel"> |

Der Simulatorlauf `RouteDescriptionUITests/testHighlightsInsertAndRouteInBackgroundWithoutLeavingTheArticle` verwendet echte Wikipedia-Ortsrecherche und einen kontrollierten Router mit 25 Sekunden Verzögerung, damit Auswahlen während der Berechnung geprüft werden können. Seine Verbindungen sind ausdrücklich synthetisch, keine echte Straßenroute oder bestätigte POI-Zufahrt. Kein ORS-, Pi-, iPhone- oder Feldtest. Geprüft sind zwei Einfügungen ohne Verlassen der Beschreibung, erhaltene Start-/Zielpunkte, nicht modale Rückmeldung, fertig berechneter letzter Planungsstand und Speicherung nach Neustart. Die Bilder wurden visuell kontrolliert.

Zur Reproduktion den öffentlichen Bestand und `route_descriptions` wie oben zurücksetzen, denselben HTTPS-Testserver starten und gezielt diesen Test ausführen. Der Testserver enthält seit dieser Erweiterung einen ausdrücklich synthetischen Router und ruft keine externen Routing-/Wegenetzdienste auf.

## Kartierte Untiefen und alte Seewege

**66/67** vom 14. Oktober 2026 zeigen den Stand mit Gefahrenprüfung und Routenrevision 2. **66** zeigt die berechnete öffentliche Ropotnica-Beispielroute um die kartierte Untiefe, 0,54 sm und drei Abschnitte, mit zugeschalteter EMODnet-Ebene. **67** zeigt das ältere Ancona-Beispiel ohne alte Linie und ohne Fahrtstart: zunächst neu berechnen. Die älteren Bilder 55–65 stammen vor dieser Gefahrenprüfung und belegen keine Prüfung der dort dargestellten Linien nach dem aktuellen Verfahren.

| Kartierte Untiefe umgehen | Alten Seeweg neu berechnen |
| --- | --- |
| <img src="images/66-ropotnica-untiefen.png" width="300" alt="Öffentliches Ropotnica-Testbeispiel: drei Kursabschnitte um die kartierte Untiefe"> | <img src="images/67-seeweg-neuberechnung.png" width="300" alt="Alte Ancona-Beispielplanung ohne Kurslinie, mit Route berechnen"> |

`seed_gallery.py --seamap --device UUID` auf dem dedizierten Dokumentationssimulator, danach `MarineRoutingUITests/testRopotnicaHazardDetourAndOutdatedRoute`. Kein Testserver erforderlich; `beispiel.invalid` verhindert Pi-Zugriff. Beide Aufnahmen aus bestandenem UI-Lauf exportiert und visuell geprüft. Öffentliche OSM-/EMODnet-Daten wie oben attribuiert; keine privaten Nutzerbilder und kein nautischer Feldtest.


## Auto-Modus und Auto-Zoom

**68–71** zeigen den lokalen Auto-Modus vom 14. Oktober 2026 mit einer **tatsächlich von openrouteservice berechneten öffentlichen Pkw-Straßenroute in Heidelberg**. Nur GPS-Standpunkt und Tempo sind für die Bedienungsprüfung simuliert; die Linie folgt dem gerouteten Straßennetz. Das ist kein Feldtest oder Nachweis aktueller Beschilderung. Mit dem universellen Einstieg zeigt **06** nur die Radoptionen und **69** nur die Autooptionen; die Auswahl der Anwendung erfolgt auf Home.

| Pkw-Planung | Auto-Profil |
| --- | --- |
| <img src="images/68-auto-planung.png" width="300" alt="Öffentliche Heidelberger Pkw-Straßenroute: schnellste Pkw-Route und Fahrzeit ohne Live-Verkehr"> | <img src="images/69-auto-profil.png" width="300" alt="Auto-Profil im öffentlichen Testbeispiel mit getrennten Optionen für Autobahnen, Maut und Fähren"> |

| Fahren mit Auto-Zoom | Automatische Nachtansicht |
| --- | --- |
| <img src="images/70-auto-fahren.png" width="300" alt="Öffentliche Pkw-Beispielroute mit simuliertem Standort: große Abbiegeanweisung, Straßenroute, Auto-Zoom, Restzeit und Ankunft"> | <img src="images/71-auto-nacht.png" width="300" alt="Dieselbe öffentliche Pkw-Beispielroute mit simuliertem Standort und dunkler Karte und dunkler Fahrtoberfläche"> |

Die beiden `CarModeUITests` prüfen Auto-Profiloptionen einschließlich Erhalt beim erneuten Öffnen der Einstellungen, fehlende Bike-Anzeigen, manuelle Kartenbewegung mit **Fahransicht**, Pause/Fortsetzen und Speichern ins Archiv. Der Fahrtlauf wurde zusätzlich mit dunkler iPhone-Darstellung erfolgreich geprüft. Alle fünf neuen/aktualisierten Bilder wurden visuell geprüft. Die App bleibt **0.4.0 (4)**. Nach diesen Simulatoraufnahmen wurden App und Pi aktualisiert und eine öffentliche Pkw-Route über den Pi geprüft; die Bilder sind keine Geräteaufnahmen und kein Feldtest.

Zur Reproduktion auf dem separaten Dokumentationssimulator `CarModeUITests` ausführen. Das Debug-Startflag `BIKENAVI_CAR_PREVIEW=1` lädt die öffentliche Straßenroute aus `ios/BikeNavi/PreviewData/heidelberg-car-route.json` und erzeugt laufende simulierte GPS-Fixes auf ihrem Startpunkt; Pi-Adresse und Token bleiben leer. Helle/dunkle Systemdarstellung vor dem jeweiligen Lauf wählen und die `Gallery-68`–`70`-Anhänge exportieren; der dunkle Fahrtanhang wird als **71** geführt. Karten: OpenFreeMap/OpenMapTiles, Daten © OpenStreetMap-Mitwirkende; Quellen über die sichtbare Karten-Attribution. Simulatoraufzeichnungen, Testprotokolle und Buildprodukte bleiben außerhalb von Git.


Zur Reproduktion des neuen Einstiegs `HomeUITests` auf dem Dokumentationssimulator ausführen. Die Kachel-/Profilprüfung verwendet `BIKENAVI_CAR_PREVIEW=1`, einen leeren Server und die öffentliche ORS-Pkw-Route. Die entstehenden anderen Entwürfe enthalten keine erfundenen Rad-/Wander-/Seewegverbindungen. Getrennte Kern-/AppState-Tests prüfen wiederholtes Öffnen und Neustart der gespeicherten Entwürfe sowie Erhalt bestehender Aufzeichnungen. Simulatoranhänge als Gallery-72–76 exportieren; kompakte Wiederholung von 72/74 als 77/78 führen; allgemeine Profile als 06/17/57/73. Allgemeine Archiv-/Bedienungstests gehen ebenfalls durch den echten Startbildschirm.
