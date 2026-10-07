# Änderungen

Alle veröffentlichten Fassungen erhalten einen Git-Tag und einen GitHub-Release. Versionsnummern folgen `MAJOR.MINOR.PATCH`; vor 1.0 kennzeichnet eine neue Minor-Version einen größeren Entwicklungsschritt. Die iOS-Buildnummer steigt unabhängig davon. Details zum Ablauf: [Versionierung](docs/VERSIONIERUNG.md).

## Unveröffentlicht

Noch keine weiteren Änderungen nach 0.4.0.

## 0.4.0 — 7. Oktober 2026

Entwicklungsfassung, iOS-Build 4. Tourtagebuch mit direkt sichtbaren Blogaktionen, topografischer Streckenkarte, numerischem Höhenprofil und gehaltvollen KI-Hintergrundkapiteln. Bedienung, Architektur, Galerie mit öffentlichen Beispieldaten und portabler HTML-Beispielblog gemeinsam versioniert. Release-Prüfung: 144 Backend- und 126 Swift-Kerntests, relevante Simulator-UI-Prüfungen, Simulator-Testbuild und signierter iPhone-Release-Build erfolgreich; App/Live-Aktivität 0.4.0 (4). Neuer öffentlicher Beispielblog mit zwölf Ortsquellen und drei Hintergrundkapiteln, zusätzliche Websuche während dieses Laufs nicht erreichbar und im Entwurf gekennzeichnet. Einzelheiten und verbleibende Grenzen: [Versionierung](docs/VERSIONIERUNG.md). Historische Prüfungen der Funktionsentwicklung stehen nachfolgend. Dieser GitHub-Release führt kein automatisches Pi-/iPhone-Deployment aus.


### Blogtext: Hintergrund erzählen statt Floskeln (06.10.2026)

- Neuester privater Blog gelesen: ohne gesammelte Stopps bislang fast ausschließlich Einleitung/Schluss, recherchierte Ortsdetails nur im Quellenanhang. Jetzt zwei bis vier eigenständige Hintergrundkapitel zu Strecke und Region, auch ohne Fotostopps. Zusammenhänge, Ursachen und heutige Bedeutung in gut lesbaren Absätzen; trockener Humor, keine erfundenen eigenen Erlebnisse oder Dialoge.
- Recherche sammelt konkrete historische, kulturelle und landschaftliche Geschichten mit Quellen; Schreibauftrag verlangt passende Details im Haupttext, unterscheidet aufgezeichnete Kilometer von geplanter Strecke und vermeidet wiederkehrende Motivationsfloskeln. Quellen bleiben im Text verlinkt, ältere Blogfassungen erhalten.
- Bereits recherchierte Quellen bleiben je Fahrt für weitere Fassungen verfügbar; bei einem vorübergehenden Rechercheausfall gehen die gehaltvollen Hintergründe nicht wieder verloren. Quellen aus alten Fassungen werden aus der Quellenrubrik übernommen, nicht aus persönlichen Notizen. Explizite Quellennummern sichern die Zuordnung im Schreibauftrag.
- Mehrere Absätze innerhalb der KI-Textfelder werden im HTML sichtbar dargestellt. Kapiteltexte bleiben escaped, einschließlich Überschriften; keine Fotos oder vollständigen GPS-Spuren an die KI.
- 144 Backend-Tests einschließlich Ableitung vorhandener Routenhöhen und Wiederverwendung gespeicherter/älterer Quellen, sicherer Absätze und expliziter Quellennummern erfolgreich. Erster neuer privater Entwurf mit drei Hintergrundkapiteln und acht Quellen als weitere Fassung erhalten; explizite Quellennummern im Schreibkontext zur besseren Zuordnung ergänzt. Abschließende, redaktionell geprüfte neue Pi-Fassung mit drei Hintergrundkapiteln und neun Quellen gespeichert und über API erneut abgerufen. Ein erneuter Webrechercheausfall wurde mit den bereits vorhandenen Quellen aufgefangen; Zuordnung der im Haupttext verwendeten Quellen geprüft, Titel ohne unbelegten Wetterbezug. Vorhandene Routenhöhen in der aktuellen privaten Fassung als m/km-Profil ergänzt und API-Abruf bestätigt. Frühere Fassungen bleiben erhalten; private Blogdaten bleiben ausschließlich unter ignorierten `artifacts/`.


### Blog: topografische Streckenkarte und lesbare Profilachsen (06.10.2026)

- Große HTML-Streckenkarte mit eingebetteten OpenTopoMap-Kacheln, aufgezeichneter bzw. ausdrücklich geplanter Route und nummerierten Blog-Orten. Zoom passend zum gesamten Ausschnitt; maximal zwölf Übersichtskacheln plus vier bestehende Ortsdetails, drei gleichzeitige Kartenabrufe und 20 Sekunden Zeitbudget für die Übersicht. Bei Kartenausfall ausdrücklich gekennzeichnete Ersatzübersicht; Segmentpausen weiterhin nicht überbrücken. Bisherige Blogfassungen bleiben erhalten; neue Darstellung bei erneuter Erstellung.
- Höhenprofil auch aus vollständig vorhandenen Routenpunkthöhen ableiten, wenn das optionale separate Profil fehlt; bisher enthielt die private Route Höhen an allen Punkten, aber kein separat gespeichertes Profil. Keine Interpolation bei fehlenden Höhen.
- Höhenprofil mit numerischer y-Achse „Höhe (m)“, x-Achse „Strecke (km)“ und Raster. Runde Achsenschritte, deutscher Dezimaltrenner und sinnvoller Wertebereich auch bei flachem Profil oder Höhen unter null. Das Profil bleibt als geplante Route gekennzeichnet.
- Prüfung: 140 Backend-Tests erfolgreich, einschließlich Kartenabrufbudget/Geometrie und Profilachsen; zwei Deprecation-Warnungen aus Testabhängigkeiten. Öffentlicher Pi-Live-Beispielblog mit 17 Quellen in 35,3 s, ohne Ersatzentwurf/Ausfallhinweis, erfolgreich erstellt; technische Pi-Daten danach entfernt. Profilbeschriftung für Mobilansicht vergrößert. Zusätzlicher Simulator-UI-Test für eingebettete Topografie, Profilachsen und Fahrt-/Planungslink erfolgreich; Galerie mit öffentlichen Beispieldaten aktualisiert und visuell geprüft. Ein zuvor fehlgeschlagener Screenshotlauf übersprang den kurzen Kartenausschnitt; kleinere Scrollschritte und dekorative Kacheln ohne eigene Accessibility-Einträge, abschließender Lauf erfolgreich.


### Blog nach Testfahrt: sichtbare Tasten und GPS im Stand (06.10.2026)

- In gefahrenen Touren direkt unter den Tourdaten eine Blogkarte mit „Blog erstellen“, bei vorhandener Fassung „Blog ansehen“ sowie HTML-Export und Zugang zu Orten/Notizen. Dieselben Aktionen im Tourtagebuch vor den gesammelten Bildern; dadurch bleibt die Erzeugung auch bei vielen Fotos sichtbar.
- Auch archivierte Planungen zeigen den Blogzugang zur zugehörigen letzten beendeten Fahrt; ein späterer leerer Fahrteintrag verdrängt eine vorhandene Fahrt mit GPS-Aufzeichnung oder Blog-Orten dabei nicht. Reine Planungen ohne Fahrt erhalten keinen Erzeugungsauftrag.
- Standortübernahme bei einem Stopp erneuert einen veralteten GPS-Fix ohne Bewegungsfilter, wartet bis zu 15 Sekunden und übernimmt ihn automatisch. Ladeanzeige, erneuter Versuch und Erhalt von Foto/Notiz bei fehlendem GPS; Bewegungsfilter danach entsprechend dem aktuellen Fahrtzustand wiederherstellen. Kein Rückgriff auf veraltete Positionsdaten.
- Private Testfahrt auf dem Pi geprüft: Aufzeichnung, Bike-Messungen und fünf Foto-Orte vollständig vorhanden, kein Blogentwurf. Zusätzlicher späterer leerer Fahrteintrag unverändert erhalten. Lokale Diagnosekopie mit Pi-Orten abgeglichen, alle Uploads bestätigt, Inhalte identisch und erneute lokale Übernahme erfolgreich. Private Fahrt-/Foto-/Diagnosedaten ausschließlich unter ignorierten `artifacts/`, nicht in öffentlichen Beispielen oder Git.
- Die konkrete ursprünglich angezeigte Fehlermeldung wurde beim Nutzer angefragt; eine Ursache im Speichern/Abgleich der fünf vorhandenen Orte wurde nicht reproduziert. Standstill-GPS-Schwachstelle anhand des bisherigen Bewegungsfilters und der sofortigen Frischeprüfung korrigiert. 126 Swift-Kerntests, beide gezielten Simulator-UI-Tests einschließlich verzögertem GPS-Fix/Offline-Neustart und signierter Gerätebuild erfolgreich. App auf Michaels iPhone installiert und gestartet. Zusätzliche UI-Prüfung für direkte Fahrt-/Planungslinks, eingebettete Topografie und m/km-Profilachsen erfolgreich; Galerie 31–37 aktualisiert/ergänzt und visuell geprüft; tatsächlicher GPS-Feldtest am Gerät weiterhin offen.


### App-Start nach Entsperren (06.10.2026)

- Die bereits installierte BikeNavi-App auf Michaels iPhone 15 Pro nach Entsperren erfolgreich gestartet; CoreDevice bestätigt den Start. Keine erneute Installation oder Codeänderung, kein Feldtest.

### Tourtagebuch: Pi-Betrieb und laufende Fahrten (06.10.2026)

- Blog-Orte können nach einer synchronisierten Fahrtsnapshot bereits während einer laufenden Fahrt zum erreichbaren Pi übertragen werden. Lokale Exportkopien tragen die Fahrt-ID und werden beim Löschen der Fahrt mit entfernt.
- KI-Recherche kann optional einen begrenzten Websuchschritt zu Geschichte, Kultur und Landschaft nutzen. Der Schreibschritt erhält weiterhin keine Fotos oder vollständigen GPS-Spuren. [BLOG.md](docs/BLOG.md) beschreibt Datenfluss, Konfiguration, Quellen und Grenzen.
- Das Deployment erhält vorhandene Pi-lokale Blog-Konfiguration, wenn die Mac-`.env` dafür keine Werte enthält. Der Schlüssel wird nicht ausgegeben oder auf den Mac übertragen.
- Abruf der neuesten Pi-Blogfassung lädt nur diese eine Fassung, um den Arbeitsspeicher bei vielen Bildfassungen zu begrenzen; gegen SQLite und PostgreSQL geprüft. Quellenhintergründe im HTML aufklappbar, damit der Reisebericht leicht lesbar bleibt; Quellenverweise bleiben direkt anklickbar. Formular erhält eine Taste zum Abschließen der Texteingabe. Neue dokumentierte Simulatorabläufe für Ortserfassung, Offline-Neustart und HTML-Vorschau.
- Prüfung: 137 Backend-Tests und nach Exportbereinigung 126 Swift-Kerntests erfolgreich; gezielte abschließende Blog-/Deployment-Prüfung 15 Tests erfolgreich. Zwei Deprecation-Warnungen aus Testabhängigkeiten. Simulator-Testbuild, beide gezielten UI-Tests (Offline-Erfassung/Neustart und HTML-Vorschau) sowie signierter Gerätebuild erfolgreich. Nach visueller Prüfung zusätzliche Ladeanzeige beim Öffnen des Blogs; erneuter Vorschau-UI-Test mit abgeschlossenem Ladevorgang und sichtbarer Topografie erfolgreich. Ein vorheriger Textselektor im UI-Test fand das HTML-Badge nicht; Testbereitschaft auf den echten WebKit-Ladeabschluss umgestellt. Xcode hing bei der Protokollfinalisierung dieses fehlgeschlagenen Laufs; separaten Dokumentationssimulator neu gestartet, abschließender Lauf vollständig erfolgreich. Galerie 12 erneuert und 30–34 ergänzt, alle visuell geprüft. Aktualisierter signierter Gerätebuild und strenge Signaturprüfung erfolgreich.
- Pi-Datenbank vor Deployment gesichert und durch Wiederherstellung in einer separaten Datenbank geprüft. Backend aktualisiert, vorhandener Pi-lokaler OpenAI-Schlüssel erhalten, Modell/Websuche im Container bestätigt. Zwei echte KI-Blogläufe mit ausschließlich öffentlichen Heidelberger Beispielen: 18 Quellen / 35,1 s und 16 Quellen / 37,2 s. Beide mit Topografie, ohne Ersatzentwurf/Ausfallhinweis; technische Fahrten samt Blogdaten danach entfernt. [HTML-Beispiel](docs/examples/heidelberg-blog.html). Blogfassung 0.3.0 (3) auf Michaels iPhone 15 Pro installiert. Automatischer Start wegen gesperrtem iPhone abgewiesen; nach Entsperren manuell öffnen. Kein neuer Tag/GitHub-Release durch diesen Arbeitslauf und kein Feldtest.


## 0.3.0 — 6. Oktober 2026

Entwicklungsfassung, iOS-Build 3. Zweiter getaggter Release mit Koordinaten- und Plus-Code-Suche, Höhenprofilen, Rad&Wandern/Wandern, aktualisierten HeiGIT-Diensten, Belagskorrekturen und Kartenansichten. Für die Release-Version erfolgreich geprüft: 134 Backend-Tests, 125 Swift-Kerntests und Simulator-Debug-Build. Die nachfolgenden Einträge dokumentieren Verhalten, weitere Prüfungen und bekannte Grenzen. Pi-Deployment, Geräteinstallation und Simulatorprüfungen ersetzen keinen Feldtest.

### Tourtagebuch und Blogentwurf (06.10.2026)

- Während einer laufenden Fahrt lassen sich besondere Orte mit aktuellem Standort, Notiz und optionalem verkleinertem JPEG festhalten. Die Orte bleiben zunächst lokal und werden nach der Fahrtsynchronisation an den privaten Pi übertragen; pro Fahrt gelten höchstens 50 Orte, 768 KB je Bild und 20 MB Bilddaten insgesamt.
- Beendete, vollständig synchronisierte Fahrten erhalten im Archiv ein Tourtagebuch. Der Pi erzeugt daraus eine portable HTML-Fassung mit eigener Streckenübersicht, Höhenprofil, eingebetteten Bildern und optionalen topografischen Ausschnitten. Die Fassung kann auf dem iPhone angesehen und als HTML geteilt werden.
- Ohne konfigurierte optionale `BLOG_OPENAI_API_KEY` und `BLOG_OPENAI_MODEL` entsteht ein Vorlagenentwurf. Bei aktivierter KI werden ausschließlich Tourtitel, Titel und Notizen der Orte sowie recherchierte Quellen übermittelt; Fotos und vollständige GPS-Spuren bleiben auf dem Pi. Jeder Entwurf verlangt vor Veröffentlichung eine redaktionelle Prüfung.
- Prüfung: API-Test für Zugriffsschutz, fehlende Elternfahrt, idempotente Übertragung und paginierte Rückgabe; Swift-Test für lokale Persistenz und vollständiges Löschen der privaten Blogdaten zusammen mit der Fahrt.

## 0.2.0 — 23. September 2026

Entwicklungsfassung, iOS-Build 2. Erster zusammenhängend dokumentierter und getaggter Release. Enthält sämtliche bis zu diesem Release noch unversionierten Erweiterungen seit Commit `eda039f`.

### Navigation und Kartenansicht

- Standort während der laufenden Tour bei 80 % der Kartenhöhe; 500 m Vorausschau bis zum oberen Kartenrand in Blickrichtung.
- Maximal mögliche Perspektive: 60° angefordert; MapLibre begrenzt die Neigung zusätzlich für den nach unten versetzten Kartenmittelpunkt.
- Gemeinsame Steuerung von Position, Richtung, Perspektive und Maßstab; Neuberechnung bei Größenänderungen.
- Freies Verschieben, Zoomen, Drehen und Neigen; automatische Rückkehr zehn Sekunden nach dem letzten manuellen Kartenwechsel, auch ohne neuen GPS-Punkt.
- GPS-Fahrtrichtung ab 1 m/s bei höchstens fünf Sekunden alten Messungen. Bei geringerer Geschwindigkeit oder fehlendem aktuellem Kurs übernimmt ein gültiger Kompasswert. iPhone-Drehungen aktualisieren die Ansicht unabhängig von der Track-Aufzeichnung.
- Kompass wird nur während einer laufenden Aufzeichnung verwendet. Wahre Nordrichtung wird bevorzugt, magnetische Nordrichtung dient als Ersatz. Ungültige, ungenaue oder alte Messungen werden verworfen.
- Routenmagnet bis 25 m bei passender Genauigkeit und Richtung; originale GPS-Aufzeichnung bleibt unverändert.

### Planung und lokale Rückführung

- Routenplanung auf dem iPhone aus gespeicherten OSM-Wegedaten; kein Routingaufruf an den Pi für neue Planungen.
- Versionierte Gebietsdaten, atomare Cache-Manifeste, wiederverwendbare Graphen, Einbahnrichtungen und Abbiegebeschränkungen.
- Lokale Rückführung nach drei genauen Messungen über mindestens fünf Sekunden ab etwa 35 m Abweichung; Prüfung von Position, Aktualität und laufender Fahrt vor Übernahme.
- Wiedereinstieg berücksichtigt Anschluss und verbleibende Tour, noch offene Zwischenziele sowie ein gemeinsames Belagsbudget. Originaltour und temporärer Anschluss werden getrennt gespeichert.
- „Nur bekannte befestigte Wege“ erlaubt insgesamt höchstens 100 m unbefestigte oder unbekannte Abschnitte über die gesamte Tour. Die ältere Server-Routenberechnung verwendet dieselbe Toleranz.
- Belagsindizes bleiben beim Ergänzen von Zugängen und mehreren Etappen gültig. Betroffene gespeicherte lokale Routen werden anhand des Wegenetzes repariert.
- Zielwahl startet die Planung automatisch; ein fehlender Standort wird nachgereicht. Standortanforderungen funktionieren auch im Stillstand nach Zurücksetzen der Planung.
- Warte-, Lade- und Fehlermeldungen bleiben bei eingeklapptem Datenbereich sichtbar. Die Tastatur kann über „Fertig“ geschlossen werden.
- Orte aus Suche und Favoriten werden direkt zur Tour hinzugefügt. Auswahl, Umbenennen und bestätigtes Löschen von Favoriten sind getrennte Aktionen.

### Bike-Daten und Tourenarchiv

- Gemeinsamer Bluetooth-Dienst für Fahrtansicht und Verbindungsdiagnose, Auswahl und Wiederverbindung eines Bosch-Bikes sowie begrenzte Diagnoseprotokolle.
- Decoder für LDI-, Protobuf- und Smartphone-Statusdaten; Anzeige von Akku, Fahrmodus sowie Fahrer- und Motorleistung. Nicht empfangene Werte bleiben als nicht verfügbar erkennbar.
- Letzter Akkumesswert bleibt mit Empfangszeit und Bike-Zuordnung über Neustarts erhalten; gespeicherte Werte werden nicht als neuer Empfang ausgegeben.
- Modusdarstellung: OFF, ECO, TOUR+, AUTO und TURBO mit zugeordneten Farben; unbekannte Codes bleiben erkennbar.
- Kompakte Fahrtansicht mit gut erreichbaren Tasten für Pause, Höhenprofil, Ton und Fahrtende. Abschlussdialog bietet Speichern, Verwerfen und Weiterfahren.
- Neue Bike-Messungen werden während der Aufzeichnung separat in SQLite gespeichert: Fahrt-/Planungs-ID, Zeit, Segment und gegebenenfalls frischer GPS-Bezug. Pausen erzeugen keine Messungen.
- Idempotenter Upload in Paketen bis 500 Messungen, Wiederholungen nach Offline-Phasen und alle 60 Sekunden im laufenden App-Betrieb; Bestätigungen löschen keine lokalen Messungen.
- Tourenarchiv mit Datum und Uhrzeit, farbigen Fahrmodusabschnitten, aufgezeichnetem Höhenprofil sowie getrennten Leistungskurven für Fahrer und Motor. Diagramme unterstützen Verschieben und Vergrößern; Lücken und Pausen bleiben sichtbar.

### Backend und Betrieb

- Authentifizierte Endpunkte für Bike-Messungen und versionierte Offline-Wegedaten; neue Tabellen für Messungen und Gebietscache.
- Messungs-IDs verhindern Duplikate; widersprüchliche Wiederholungen werden abgewiesen. Gelöschte Fahrten verlieren ihre Bike-Messungen; Dokumenthistorie folgt weiterhin dem vorhandenen Synchronisationskonzept.
- Overpass-Ausweichdienst bei Ausfall der öffentlichen Standardquelle; unvollständige Antworten werden nicht als vollständiger Cache gespeichert. Vorhandene Daten bleiben bei fehlgeschlagenem Refresh erhalten.
- Längeres Download-Zeitbudget auf dem iPhone; zusätzliche IPv6-Ausleitung für den BikeNavi-Container über eine eigene Bridge und idempotente Betriebsregeln.
- Legacy-Routing bleibt für ältere Clients verfügbar. Server-Paket, API-Versionsauskünfte, App und Live-Aktivität tragen Version 0.2.0.

### Dokumentation und Prüfung

- README mit bestehendem App-Logo, Hauptansichten und vollständiger [Bildschirmgalerie](docs/BILDSCHIRME.md).
- Explizite Debug-Testposition für reproduzierbare Fahrtansichten; aus Release-Builds ausgeschlossen.
- Reproduzierbare Simulator-Bilder mit öffentlicher Heidelberg-Route und ausdrücklich synthetischer Beispielaufzeichnung; keine persönlichen Touren oder Zugangsdaten.
- Dauerhafte Projektregeln in `AGENTS.md` verpflichten weitere Änderungen zu Änderungsprotokoll, passenden Tests und aktueller Bildschirmdokumentation.
- Aktualisierte Architektur, Umsetzungsübersicht sowie Anleitungen für lokale Rückführung, Bosch-Anbindung und iPhone-Installation.
- UI-Test für Favoriten berücksichtigt sowohl den Abbrechen-Knopf als auch die Popover-Darstellung unter iOS 26.
- Erweiterte Swift-, Backend- und UI-Tests für Routing, Beläge, Standort, Favoriten, Bike-Daten, Speicherung, Auswertung und Kompasssteuerung. Ergebnisse dieses Releases stehen in [Versionierung](docs/VERSIONIERUNG.md).

### Bekannte Grenzen

- Vollständige Offline-Karten mit eigenem Kartenserver sind noch nicht eingerichtet. Ein lokales Wegenetz ersetzt kein Offline-Kartenbild.
- Erste Gebietsdaten-Downloads benötigen eine Verbindung und verfügbare Datenquellen. Die lokale Suche ist auf geladene Gebiete begrenzt; ein vollständiges Höhenmodell fehlt.
- Bike-Messungen werden zum Pi hochgeladen; der Rückimport auf ein neues iPhone fehlt noch. Favoriten werden noch nicht zentral synchronisiert.
- Langzeitbetrieb mit GPS, Kompass, Bluetooth und gesperrtem Bildschirm muss weiter auf echten Touren geprüft werden. Ein erfolgreicher Build oder Simulatorlauf ersetzt diesen Praxistest nicht.

## Vor 0.2.0

Die bisherige Entwicklung trug intern Version 0.1.0, Build 1, ohne Release-Tag. Enthalten waren die Grundlagen für Planung, Speicherung, Pi-Abgleich, Favoriten, Belagsfarben und Sperrbildschirm-Navigation. Die vollständige Einzelhistorie bleibt in Git erhalten.
