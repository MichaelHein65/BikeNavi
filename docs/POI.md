# Orte entdecken und Dieselpreise

Entwicklungsstand vom **15. Oktober 2026**, **0.4.0 (4), Unveröffentlicht**. Kein CarPlay. Die POI-Fassung ist auf Michaels iPhone und dem Pi installiert; die anschließende Tankerkönig-Strategie und ihre Bereitstellung sind im [Prüfstand](UMSETZUNG.md) dokumentiert. Ein Deployment ist kein neuer Release.

## Bedienung

Die Detailkarte unter **Karte & Details** startet als Umgebungsübersicht (Zoomstufe 14), nicht als extreme Nahaufnahme des Markers. Du kannst anschließend nach Bedarf zoomen und verschieben. Der weiter gefasste Ausschnitt gilt in allen Anwendungen und für alle Kategorien.

In **allen fünf Anwendungen** öffnet **Planen → Orte entdecken** bzw. **Fahren / Gehen / Segeln → Orte** eine gemeinsame Seite mit sechs farbigen Clay-Kacheln: Tankstelle, Supermarkt, Flughafen, Bahnhof, Strand und Parkplatz. Die sechs transparenten Clay-Illustrationen folgen der vom Nutzer gelieferten Startbildschirm-Vorlage; Farben, linke Textausrichtung und Druckanimation entsprechen den Home-Kacheln. Die Seite scrollt bei kleinen Bildschirmen oder großer Schrift. Zurück/Fertig erhält die laufende Fahrt; Aufzeichnung und Sprachführung laufen weiter.

### Fahrrad, Wandern, Fahrrad & Wandern und Segeln

- Umkreissuche (10/25 km) mit **Luftlinie**, ohne Pkw-Anfahrt oder Reisezeit. In der Planung sind Standort, Start oder Ziel wählbar; unterwegs ein frischer Standort. Keine Zusage „entlang der Route“ oder „ohne Rückweg“ für diese Profile.
- Die Karte zeigt den originalen kartierten Ort. In Fahrrad-/Wanderplanungen wird er mit **Als Ziel verwenden** oder **Als Zwischenstopp einfügen** übernommen und danach mit dem jeweiligen Profil berechnet. Wegezugang bleibt bis zur Routenprüfung unbestätigt.
- In laufenden Rad-/Wandertouren: suchen, Details ansehen und **Ort speichern**. Kein automatischer Umbau der laufenden Route; gespeicherte Orte sind anschließend in der Planung verfügbar. Aufzeichnung und bestehende Ziele bleiben unangetastet.
- Beim Segeln dienen die Landorte dem **Landgang**. Speichern ist möglich, aber keine automatische Übernahme in die Wasserroute: Landtankstellen sind keine bestätigten Bootstankstellen, Strände keine bestätigten Anlegestellen. Einen sicheren Wasserwegpunkt separat planen.
- Dieselpreise verwenden dieselben Länderquellen und dasselbe gemeinsame Minutenbudget wie im Auto. Bis zu drei preislich sortierte verfügbare Treffer, unbekannte Preise getrennt; keine Pkw-Erreichbarkeitsprüfung außerhalb des Auto-Modus.

### Auto

**Tankstelle** sucht Standarddiesel in Deutschland, Österreich, Slowenien und Kroatien. In der Planung stehen aktueller Standort, vorhandener Start oder Ziel als Suchzentrum sowie 10/25 km Umkreis zur Wahl. Ohne frischen Standort wird der vorhandene Start vorgewählt; sonst erscheint ein Standort-Hinweis. Eine erfolgreiche Suche bietet bis zu drei preislich sortierte, per Pkw erreichbare Treffer. Preisgleiche geprüfte Treffer werden nach Anfahrtszeit geordnet. Geschlossene Stationen entfallen, unbekannter Öffnungsstatus wird ausdrücklich angezeigt. Stationspreise ohne gültigen Betrag bleiben separat unter **Ohne bestätigten Dieselpreis**. Ein fehlender Preis wird niemals als 0 € behandelt.

Details zeigen Kartenpunkt, Adresse, Quelle, gegebenenfalls unbearbeitete Öffnungszeiten der Quelle und Abrufzeitpunkt. Keine der derzeit ausgewerteten Preisantworten liefert einen verlässlichen Zeitstempel der einzelnen Preismeldung. Daher steht **Preisstand unbekannt** bereits am Angebot; ein neuer Abruf bestätigt keine neue Preismeldung. Die App verspricht weder Preisgültigkeit bei Ankunft noch vollständige Marktübersicht.

**Als Ziel verwenden** ersetzt das Planungsziel. **Als Zwischenstopp einfügen** erhält das bisherige Ziel und löst die normale Neuberechnung aus. In der Fahrt wird vom dann aktuellen Standort eine neue Anfahrt geprüft und der Ort vor dem nächsten offenen Ziel eingefügt. Originalplanung, aufgezeichneter Track und übrige Ziele bleiben erhalten. **Entfernen** in der Fahrt entfernt den zuletzt hinzugefügten, noch offenen POI-Stopp erst nach erfolgreicher Weiterberechnung. War er das einzige Ziel einer vorher freien Fahrt, wird diese ohne Ziel weiter aufgezeichnet. Kopien von Fahrten mit Ersatzroute werden frisch berechnet, statt eine nicht mehr zu den Wegpunkten passende Originalroute zu übernehmen.

## Suche während der Autofahrt

- Frischer GPS-Fix (unter fünf Sekunden, höchstens 25 m Genauigkeit), bestätigte Routenposition und abgeschlossene Neuberechnung erforderlich.
- Suchabschnitt maximal 50 km voraus; Anbieterabfrage in einem 25-km-Kreis um dessen Streckenmittelpunkt. Anbieterabdeckung und dieser Kreis begrenzen die Auswahl; außen liegende Seitenzufahrten werden nicht vollständig abgedeckt.
- Kandidaten höchstens 3 km seitlich der Referenzroute, mindestens 50 m voraus. Die geometrische Prüfung nutzt den gespeicherten geodätischen Routenfortschritt, nicht die Luftlinie in Kompassrichtung. Auch auf langen Reisen wird nur der lokale Abschnitt ab 500 m hinter dem Standort bis 50 km voraus projiziert und auf 3 m vereinfacht; weit entfernte Routenpunkte beeinflussen diese Prüfung nicht.
- Echte ORS-Pkw-Anfahrt und Weiterfahrt über alle offenen Ziele; Auto-Einstellungen für Maut, Autobahnen und Fähren bleiben wirksam. Tankstellen müssen höchstens 25 m vom gerouteten Stopp liegen. Bei anderen Orten wird ein gerouteter Pkw-Zielpunkt bis höchstens 350 m Luftlinie vom kartierten Ort verwendet; ein Abstand über 20 m wird ausdrücklich genannt, ohne einen Fußweg oder Zugang zu behaupten. Auch der Pkw-Zielpunkt muss vorausliegen.
- Höchstens zehn Minuten zusätzliche Fahrzeit gegenüber einer neu berechneten Fahrt ohne den Stopp. Aufenthalt/Tanken ist nicht enthalten. U-Turn-Anweisungen und Rückbewegungen von mehr als 60 m entlang der Referenzroute werden ausgeschlossen; kurze gemeinsame Zufahrten bleiben möglich.
- Höchstens 18 Kandidaten werden geprüft. Anbieterkontingente, fehlende Zufahrten, große Schleifen und uneindeutige Straßenprojektionen können die Auswahl verkleinern. Das ist eine konservative Prüfung der verfügbaren Routingdaten, keine Garantie der tatsächlichen Beschilderung oder Fahrbahnzugänglichkeit. Keine Live-Sperrungen enthalten.
- Bei Übernahme werden Routen-ID, Fahrt, Ziele, Profil, Aufzeichnungszustand und aktueller GPS-Abgleich erneut geprüft. Überholte Antworten werden verworfen; Fehler lassen die alte Route bestehen.
- Ohne Route gilt eine Umkreissuche; ein ausgewählter Ort startet die Zielführung innerhalb derselben Aufzeichnung. Richtungstreue wird ohne Referenzroute nicht behauptet.

Alle Fahrzeiten und die Ankunft bleiben **Schätzungen ohne Live-Verkehr**.

## Quellenprüfung am 15. Oktober 2026

### Deutschland

[Tankerkönig-Dokumentation](https://creativecommons.tankerkoenig.de/?page=info), [Registrierung/AGB](https://onboarding.tankerkoenig.de/geschaeftsbedingungen).

`GET /json/list.php`, `type=diesel`. Die Dokumentation begrenzt den Radius auf 25 km und den Zugriff auf eine Abfrage pro Minute. Deshalb wird nicht jede Tankstelle einzeln abgefragt:

- Ein bedarfsgesteuerter **25-km-Sammelabruf** liefert die verfügbaren Dieselangebote. Die gewählten 10/25 km, die günstigsten drei Treffer und der Routenkorridor werden anschließend lokal gefiltert. Detailansicht und Routenübernahme verbrauchen keine weitere Tankerkönig-Abfrage.
- Eine gemeinsame Sperre auf dem Pi lässt frühestens nach **61 Sekunden** eine neue Anbieteranfrage zu, unabhängig von Planung/Fahrt, Suchzentrum, Radius oder mehreren verbundenen Geräten. Fehlgeschlagene Abrufe zählen ebenfalls. Es gibt keine automatische Minutentakt-Abfrage und keinen sofortigen Wiederholungsversuch.
- Die nächste zulässige Abfrage wird vor dem Netzwerkzugriff atomar in PostgreSQL reserviert (`provider_budgets`). Dadurch umgehen gleichzeitige Backendprozesse oder Neustarts das Limit nicht. Gespeichert wird nur der Freigabezeitpunkt, kein API-Schlüssel und kein Suchort.
- Räumlich abgedeckte Ergebnisse werden **zwei Minuten** wiederverwendet; kleine Standortänderungen lösen keinen neuen Preisabruf aus. Während einer Sperre oder eines Anbieterausfalls darf eine höchstens **fünf Minuten** alte Auswahl weiterverwendet werden. Ursprüngliche Abrufzeit, Alter und teilweise Gebietsabdeckung sind ausdrücklich gekennzeichnet. Ab zwei Minuten wird der Öffnungsstatus nicht mehr als aktuell übernommen; nach fünf Minuten entfallen die gespeicherten Preise.
- Maximal acht Gebietsantworten bleiben ausschließlich im RAM. Nach Neustart fehlen gegebenenfalls Preise bis zum nächsten erlaubten Abruf. Ein neues, noch nicht abgedecktes Gebiet zeigt einen Wartehinweis und gegebenenfalls OSM-Standorte ohne Preis, statt das Limit zu umgehen.
- Der Schlüssel soll ausschließlich von diesem zentralen Pi-Dienst verwendet werden. Gleichzeitige Direktabfragen mit demselben Schlüssel durch andere Apps oder Browser lassen sich nicht durch unsere lokale Sperre koordinieren.

Keine Demo-Preise in der normalen App. Authentifizierung und Fehlerantworten werden kontrolliert. Quellenhinweis **Tankerkönig · MTS-K · CC BY 4.0** samt Link. Die zusätzlichen Statushinweise verwenden die vorhandene Hinweisfläche der POI-Ergebnisse; Kacheln und Bedienung bleiben unverändert.

Der Nutzer hat den persönlichen Schlüssel inzwischen erhalten und privat eingetragen. Antwortverarbeitung, fehlender Schlüssel, Gebietswechsel, parallele Suche, Neustart, Abrufbegrenzung und veraltete Daten werden mit synthetischen Tests geprüft. Den tatsächlichen Freischaltungs-/Live-Prüfstand dokumentiert [UMSETZUNG.md](UMSETZUNG.md). Ein fehlender Schlüssel erscheint in der App. Wenn keine Preisstationen geliefert werden, versucht die Suche OSM-Tankstellen ohne bestätigten Preis oder Dieselangebot.

Nach abschließender Freischaltung durch den Nutzer echte Pi-HTTPS-Suche in Deutschland erfolgreich: drei Dieselangebote mit gerouteter Anfahrt. Ein unmittelbarer Wechsel von 10 auf 25 km am selben öffentlichen Heidelberger Suchpunkt übernimmt dieselbe Abrufzeit und bestätigt die Wiederverwendung ohne zusätzlichen Preisabruf.

`TANKERKOENIG_API_KEY` in der privaten Server-`.env` setzen und den Backend-Container mit aktualisierter Compose-Konfiguration neu erstellen. Das Deployment erhält einen bereits auf dem Pi gespeicherten Schlüssel auch dann, wenn die lokale `.env` keinen Wert dafür enthält. Der Schlüssel wird nicht an das iPhone geliefert oder versioniert. Freischaltung/Anbieterbedingungen gehören zur Registrierung des Nutzers.

### Österreich

[Dokumentierte öffentliche E-Control-API](https://api.e-control.at/sprit/1.0/api-docs?group=public-api), [Spritpreisrechner](https://www.spritpreisrechner.at/).

`GET /sprit/1.0/search/gas-stations/by-address`, `fuelType=DIE`, `includeClosed=false`. Tatsächliche öffentliche Wiener Abfrage: **10 Stationen, davon 5 mit Dieselpreis**. Die API liefert nicht für jede zurückgegebene Station einen Preis; fehlende Werte bleiben erhalten. Kein API-Schlüssel für diesen geprüften Abruf erforderlich.

### Slowenien

[Staatliche Beschreibung](https://www.gov.si/teme/cene-naftnih-derivatov/), [goriva.si](https://goriva.si/).

Das öffentliche Portal verwendet `GET /api/v1/search/` mit `position=Breite,Länge`, `radius` in **Metern** und Seitennummer. Standarddiesel steht unter `prices.dizel`; `dizel-premium`, HVO und andere Produkte werden nicht vermischt. Paginierung mit festen eigenen URLs, fremde `next`-Links werden nicht verfolgt. Maximal 20 Seiten; größere/unvollständige Abfragen werden nicht als vollständige Ergebnisse ausgegeben.

Tatsächliche öffentliche Ljubljana-Abfrage in 10 km: **43 Stationen, 42 Standarddieselpreise**. Öffnungszeiten sind Freitext; daraus wird kein verlässlicher Geöffnet-Status erfunden. Die technisch geprüfte Webportal-Schnittstelle ist kein bestätigter stabiler Drittanbieter-Vertrag und ist als experimentell gekennzeichnet. Nutzungs-/Weitergabebedingungen vor öffentlicher/kommerzieller Veröffentlichung gesondert klären.

### Kroatien

[Öffentliches Min2Go-Portal](https://www.mzoe-gor.hr/) und dessen tatsächlich verwendeter Feed `https://webservis.mzoe-gor.hr/data.gz`.

Der Feed enthält Stations-, Produkt- und Preislisten. Seine Koordinatenfelder sind entgegen ihren Namen belegt: **`long` enthält die Breite, `lat` die Länge**. Produktzuordnung über `vrsta_gorivas` und `gorivos`. Nur eindeutig als **Eurodizel bez aditiva** zugeordnete Angebote ohne Premium-/MaxPower-/Class-/Plavi-/Test-/Auslaufkennzeichnung werden verglichen. Das ist bewusst eine Teilmenge; additive Standardprodukte und widersprüchliche Zuordnungen sind nicht automatisch gleichgesetzt. Nullnamen/fehlende Koordinaten einzelner Einträge werden abgefangen. Fehlende Preiszeitstempel werden nicht durch HTTP-Abrufzeiten ersetzt.

Tatsächliche öffentliche Zagreb-Abfrage in 10 km: **90 Stationen, 19 eindeutig zugeordnete Standarddieselpreise**. Der Feed wird maximal alle zwei Minuten geladen, komprimierte und entpackte Größe werden begrenzt. Öffnungsstatus unbekannt. **Experimentelle Portalanbindung**, ohne bestätigten Schnittstellenvertrag oder zugesagte Verfügbarkeit. Nutzungs-/Weitergabebedingungen vor öffentlicher/kommerzieller Veröffentlichung klären.

### Weitere Orte

**Geoapify Places ersetzt den öffentlichen Overpass-Dienst für Supermarkt, Flughafen, Bahnhof, Strand und Parkplatz.** Die Daten stammen weiterhin überwiegend aus OpenStreetMap, werden aber von einer eigenständigen kommerziell betriebenen API geliefert. Es ist kein bloßer Wechsel zwischen kostenlosen Overpass-Servern. [API-Dokumentation](https://apidocs.geoapify.com/docs/places/), [Preise und SLA](https://www.geoapify.com/pricing/), [Nutzungsbedingungen](https://www.geoapify.com/terms-and-conditions/), geprüft am 15. Oktober 2026.

Auswahlgrund: dokumentierte Kategorien, Umkreisfilter und Entfernungssortierung, eigener API-Schlüssel, Cache-Erlaubnis und klarer Tarif. Der ebenfalls geprüfte ORS-POI-Dienst ist öffentlich auf 2 km Suchradius begrenzt und ersetzt deshalb nicht die vorhandenen 10-/25-km-Suchen ([ORS-Grenzen](https://openrouteservice.org/restrictions/)). Geoapify Free bietet 3.000 Credits pro Tag und bis zu fünf Anfragen pro Sekunde, ohne Kreditkarte. Je 20 gelieferte Orte kostet ein Abruf einen Credit; BikeNavi fordert höchstens 20 an, also höchstens einen Credit pro Suchabruf. **Free hat keine SLA-Zusage**; bezahlte Tarife nennen 99,5 % monatliche Verfügbarkeit. Kein Bezahltarif wurde gebucht. Auch dieser Anbieter kann ausfallen oder unvollständige Daten liefern.

Zuordnung: `commercial.supermarket`, `airport.terminal`, `public_transport.train`, `beach`, `parking`. Die Flughafensuche liefert **kartierte Terminals**, nicht Startbahnen, Privat-/Militärflugplätze oder den Mittelpunkt eines Flughafengeländes. Separat als Bahnsteig klassifizierte Einträge und ausdrücklich private/gesperrte Orte werden ausgeschlossen; unbekannter Zugang wird nicht zu einer Zugangsbestätigung. Keine Live-Öffnungszeiten oder Parkplatzbelegung. Quelle **Geoapify · © OpenStreetMap-Mitwirkende · ODbL** und Anbieterlink in den Details, Quellen-/Lizenzhinweis auch in der Ergebnisliste.

Pro Suche ein bedarfsgesteuerter `GET /v2/places` mit 10/25-km-Kreis, maximal 20 Kandidaten und Nähepräferenz zur aktuellen Suchposition. Während der Fahrt bleibt der bisherige vorausliegende Routenkorridor wirksam. Keine automatische Paginierung, Hintergrundabfragen oder vollständige Markt-/Orteübersicht. Bis zu 18 Kandidaten erhalten eine Pkw-Prüfung; maximal drei passende Angebote werden angezeigt. Antworten einschließlich leerer Ergebnisse liegen bis zu fünf Minuten im begrenzten RAM-Cache. Gemeinsames atomar gespeichertes Ein-Sekunden-Budget für Geoapify, unabhängig vom Tankerkönig-Minutenbudget. Fehlerpause mindestens 30 Sekunden, bei Zugangssperre fünf Minuten; längeres `Retry-After` wird beachtet. Kein automatischer Rückfall auf Overpass.

Bei Gebäude-/Flächenpunkten endet die Pkw-Route an einem tatsächlich gerouteten Straßenpunkt in höchstens 350 m Luftlinie. **Karte, Zielübernahme und Zwischenstopp verwenden diesen Pkw-Zielpunkt.** Der Originalpunkt bleibt als `placeCoordinate`, die Luftliniendistanz als `accessDistance` in der Antwort. Ab 20 m Abstand steht der Hinweis zusätzlich in der Adresse, damit auch die bereits installierte App ihn in den Details zeigt. Fußweg, tatsächliche Zutrittsmöglichkeit und Restzeit bleiben ungeprüft; keine künstliche Verbindung über Zäune/Wasserflächen. Für Fahrtstopps wird zuerst der Zielpunkt ermittelt, anschließend Anfahrt und Weiterfahrt mit allen offenen Zielen geprüft. Die Rückfahrts-/Wende-/Umwegprüfung wird nicht gelockert. Tankstellen behalten die strengere 25-m-Grenze.

Einrichtung: kostenloses Projekt unter [Geoapify MyProjects](https://myprojects.geoapify.com) erstellen, Schlüssel privat als `GEOAPIFY_API_KEY` setzen, Backend neu erstellen. Der Schlüssel bleibt auf dem Pi und wird bei späterem Deployment aus der Pi-Konfiguration erhalten, falls lokal leer. Details, Zielführung und Übernahme benötigen keinen weiteren Geoapify-Aufruf. Eine neue iPhone-Installation ist für den Anbieterwechsel nicht erforderlich; der vorhandene Antwortvertrag bleibt kompatibel. Konkrete Live-Ergebnisse und Bereitstellung: [Prüfstand](UMSETZUNG.md).

Historischer Fehler: Der frühere Overpass-Dienst lieferte HTTP 406/Zeitüberschreitungen, eine unabhängige Alternative HTTP 500. `POI_OVERPASS_URL` bzw. ersatzweise `OVERPASS_URL` bleibt nur für den optionalen **preislosen Tankstellen-Rückfall** bestehen; Rad-/Seewegquellen werden nicht verändert. Die Geoapify-Umstellung repariert deren etwaige Overpass-Ausfälle nicht.

## Betrieb und Grenzen

Der Pi stellt die authentifizierten Endpunkte `POST /v1/pois/search` und `POST /v1/pois/route` bereit. App und Backend müssen gemeinsam aktualisiert werden. Eingaben sind begrenzt, Suche hat ein Zeitbudget von 85 Sekunden und maximal zwei gleichzeitig arbeitende Suchen. Preis-/POI-Daten liegen nur in einem begrenzten RAM-Cache; keine neue Preisdatenbank. Die vorhandene ORS-Anbindung benötigt weiterhin ihren eigenen Schlüssel und ihr Routingkontingent. Suchkoordinaten gehen an die jeweiligen öffentlichen Anbieter; vollständige private Aufzeichnungen werden nicht an Preisportale übertragen. ORS erhält die für die Anfahrt benötigten Wegpunkte.

Spurführung, Tempolimits, Live-Verkehr und vollständiges Offline-Pkw-Routing sind weitere Ausbaustufen. **CarPlay entfällt auf Nutzerwunsch.** Noch keine praktische Fahrprüfung der POI-Funktion. Simulatorbilder verwenden ausdrücklich synthetische öffentliche Angebote; Installation und Live-Serverprüfungen sind separat dokumentiert.
