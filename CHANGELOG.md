# Änderungen

Alle veröffentlichten Fassungen erhalten einen Git-Tag und einen GitHub-Release. Versionsnummern folgen `MAJOR.MINOR.PATCH`; vor 1.0 kennzeichnet eine neue Minor-Version einen größeren Entwicklungsschritt. Die iOS-Buildnummer steigt unabhängig davon. Details zum Ablauf: [Versionierung](docs/VERSIONIERUNG.md).

## 0.3.0 — 6. Oktober 2026

Entwicklungsfassung, iOS-Build 3. Zweiter getaggter Release mit Koordinaten- und Plus-Code-Suche, Höhenprofilen, Rad&Wandern/Wandern, aktualisierten HeiGIT-Diensten, Belagskorrekturen und Kartenansichten. Für die Release-Version erfolgreich geprüft: 134 Backend-Tests, 125 Swift-Kerntests und Simulator-Debug-Build. Die nachfolgenden Einträge dokumentieren Verhalten, weitere Prüfungen und bekannte Grenzen. Pi-Deployment, Geräteinstallation und Simulatorprüfungen ersetzen keinen Feldtest.

### Tourtagebuch und Blogentwurf (06.10.2026)

- Während einer laufenden Fahrt lassen sich besondere Orte mit aktuellem Standort, Notiz und optionalem verkleinertem JPEG festhalten. Die Orte bleiben zunächst lokal und werden nach der Fahrtsynchronisation an den privaten Pi übertragen; pro Fahrt gelten höchstens 50 Orte, 768 KB je Bild und 20 MB Bilddaten insgesamt.
- Beendete, vollständig synchronisierte Fahrten erhalten im Archiv ein Tourtagebuch. Der Pi erzeugt daraus eine portable HTML-Fassung mit eigener Streckenübersicht, Höhenprofil, eingebetteten Bildern und optionalen topografischen Ausschnitten. Die Fassung kann auf dem iPhone angesehen und als HTML geteilt werden.
- Ohne konfigurierte optionale `BLOG_OPENAI_API_KEY` und `BLOG_OPENAI_MODEL` entsteht ein Vorlagenentwurf. Bei aktivierter KI werden ausschließlich Tourtitel, Titel und Notizen der Orte sowie recherchierte Quellen übermittelt; Fotos und vollständige GPS-Spuren bleiben auf dem Pi. Jeder Entwurf verlangt vor Veröffentlichung eine redaktionelle Prüfung.
- Prüfung: API-Test für Zugriffsschutz, fehlende Elternfahrt, idempotente Übertragung und paginierte Rückgabe; Swift-Test für lokale Persistenz und vollständiges Löschen der privaten Blogdaten zusammen mit der Fahrt.

## Unveröffentlicht

### Kartenansichten mit festem Startstandard (05.10.2026)

- Auswahl über Ebenensymbol in Planung/Fahrt und Einstellungen: bisherige deutsche Standardkarte, Hell, Detailreich, Dunkel, Satellit (Esri World Imagery) und Topografisch (OpenTopoMap mit Höhenlinien). Eigene Stiladresse bleibt konfigurierbar und gespeichert.
- Bei jedem vollständigen App-Start immer die bisherige deutsche Darstellung wählen. Andere Ansichten gelten nur während der Sitzung, einschließlich Tabwechsel und Hintergrundpause. Stilwechsel erhalten Route, Marker und Kartenausschnitt; Navigationsnachführung bleibt aktiv.
- Rasterstile samt Quellenhinweisen im App-Bundle über Projektgenerator eingebunden. Öffentliche Kartenansichten vom Offline-Paketdownload ausgeschlossen; eigener Kartenstil und freigegebener eigener Server erforderlich. Satellit ohne Ortsbeschriftungen; Rasterauflösung und Verfügbarkeit abhängig von der Quelle.
- Prüfung: Simulator-Build und abschließend zwei gezielte UI-Tests erfolgreich (alle Ansichten, gemeinsame Auswahl, Hintergrundpause, Neustartstandard sowie Fahrt/Pause). Zehn echte Simulatoraufnahmen an gekennzeichneten öffentlichen Beispieldaten erneuert bzw. ergänzt und visuell geprüft. HTTPS-Probekacheln für Satellit und Topografisch erfolgreich. Erster Galeriewiederholungslauf wegen abweichendem Titel des Höhenbeispiels fehlgeschlagen bzw. übersprungen; Testvoraussetzung auf beide öffentlichen Beispieltitel korrigiert, abschließender Lauf ohne Fehler oder übersprungene Tests. Anschließend auf Nutzerwunsch: signierter iPhone-Build erfolgreich, App und Live-Aktivität 0.2.0 (2) sowie beide Rasterstil-Ressourcen im Bundle geprüft. Installation auf Michaels iPhone 15 Pro erfolgreich und über die installierten Apps bestätigt. Automatischer Start vom Gerät wegen gesperrtem Bildschirm abgelehnt; Bedienung der neuen Ansichten auf dem iPhone noch durch den Nutzer zu prüfen. Kein Pi-Deployment oder Feldtest; Version/Build weiterhin 0.2.0 (2).

### Kurze Straßen-Belagslücken tolerieren (05.10.2026)

- Nutzerfall an der Put Vodica reproduziert: Fahrradroute enthält rund 223 m unbekannten Belag zwischen Asphaltabschnitten auf erfasster Straße. Das bisherige gemeinsame 100-m-Budget ließ den Übergang zum Fußanteil zu früh beginnen.
- Online bei „Nur bekannte befestigte Wege“ zusätzliche begrenzte Toleranz: fehlende Belagsangaben auf Straße zwischen unmittelbar bekannten befestigten Straßenabschnitten, höchstens 250 m je Lücke und 500 m insgesamt. Rohbelag bleibt unbekannt; Warnung nennt tolerierte Meter. Sand/Schotter, Pfade, fehlende Wegarten, Anfangs-/Endlücken und ungemeldete Surface-Distanzen erhalten diese Ausnahme nicht. Das zusätzliche bisherige 100-m-Budget bleibt gemeinsam für die übrigen unbekannten/unbefestigten Abschnitte.
- Auch die Auswahl der Kombinations-Anschlüsse berücksichtigt diese begrenzten Lücken. Lokale Offline-Radplanung bleibt beim bisherigen konservativen 100-m-Budget, da ihr Graph die nötige Wegarteninformation nicht enthält; Profiltext und Dokumentation erklären dies.
- Prüfung: 122 Backend-Tests erfolgreich (kurze/lange Lücken, Wegarten, beidseitige bekannte Beläge, Gesamtbudget, unveränderte Schottergrenze und unbekannte Rohbeläge). Live-ORS und aktualisierter Pi mit der privaten Nutzerplanung: 1.158,3 m Rad / 1.101,1 m Wandern; die rund 223 m Straßen-Belagslücke wird berücksichtigt statt früherem Übergang nach 576,7 m. Private Koordinaten bleiben in ignorierten Builddateien; keine Testtour gespeichert. Simulator- und signierter Gerätebuild, zwei gezielte UI-Tests für Auswahl/Persistenz und Profilhinweis erfolgreich. Galerie 06/24 aktualisiert und visuell geprüft; für den vollständigen langen Hinweis erneut mit weiter gescrolltem Profil aufgenommen. Backend/Datenbank gesund. App auf Michaels iPhone installiert und gestartet. Weiterhin 0.2.0 (2), kein Release oder Feldtest.

### Belagsauswahl in der Planung eindeutig anzeigen (05.10.2026)

- „Befestigte Wege bevorzugen“ und „Nur bekannte befestigte Wege“ standen bisher beide verkürzt als „Befestigte Wege“ in der Planung. Jetzt den tatsächlichen vollständigen Auswahltext in einer eigenen Zeile unter den Profiltasten anzeigen, bei Bedarf mehrzeilig. Dadurch ist erkennbar, ob unbefestigte Zufahrten erlaubt bleiben oder unbekannte Beläge das strenge gesamte 100-m-Budget verbrauchen.
- Nutzer-Testplanung auf dem iPhone geprüft: strenge Belagsoption aktiv, deshalb Übergang nach 25,5 m. Dieselben privaten Wegpunkte mit bevorzugt befestigten Wegen über den Pi: 984,1 m Rad bis zum Gipfelpfad und 743,1 m Wandern. Nur lesende Diagnose und ungespeicherte Berechnung; keine Änderung der Nutzerplanung und keine private Beispieldaten in der Galerie.
- Prüfung: Simulator- und signierter Gerätebuild sowie gezielter UI-Test für beide Anzeigen und Persistenz erfolgreich. Ein paralleler Gerätebuild lief zunächst in die gemeinsame Xcode-Builddatenbanksperre; getrennte Wiederholung erfolgreich. Galerie 22/23 mit öffentlichen Beispieldaten erneuert und visuell geprüft; Warnungsdialog vor Aufnahme geschlossen. Korrigierte App auf Michaels iPhone installiert und gestartet. Keine Routingänderung, kein Pi-Deployment erforderlich; weiterhin 0.2.0 (2), kein Release oder Feldtest.

### ORS-Kontingent und aktuelle HeiGIT-API (05.10.2026)

- Nutzerfehler direkt reproduziert: veralteter ORS-Endpunkt antwortete mit 403 `Quota exceeded`. Betreiber hat das Kontingent dort nach der Migration reduziert. Routing/Snap, Ortsnamen und Höhen auf die offiziell genannten aktuellen HeiGIT-Endpunkte umgestellt; vorhandener API-Schlüssel bleibt gültig.
- Routing-/Snap-Antworten fünf Minuten im Arbeitsspeicher wiederverwenden (höchstens 128 Einträge, Anfragekörper und Pfad vollständig vergleichen, defensive Kopien, keine private Speicherung auf Platte). Fehler nicht puffern. Für abgewiesene Radpräfixe keine Fußroute mehr anfragen. Tageskontingentmeldung von fehlender Freigabe unterscheiden.
- Prüfung: 109 Backend-Tests erfolgreich, einschließlich aktueller Ortsnamen-/Höhen-URLs, Cache-Schlüssel, Ablauf, Kopien und nicht gepufferter Kontingentfehler. Beide Nutzer-Testvarianten am aktuellen Anbieterendpoint erfolgreich. Aktualisiertes Backend auf Pi bereitgestellt; Ortsnamen, Höhen, HTTPS/Zugangsschutz und Rad-/Wanderstrecke in beiden Belagseinstellungen über den Pi erfolgreich. Erster Pi-Routenaufruf mit vorübergehendem 502, Wiederholung erfolgreich. Backend/Datenbank gesund. Keine Appänderung oder Neuinstallation notwendig, weiterhin 0.2.0 (2), kein Release oder Feldtest.

### Wanderanteil am Gipfel und strenge Belagswahl (05.10.2026)

- Gemeldete Gipfelstrecke reproduziert: ORS führte die vollständige Radroute über einen rund 743 m langen allgemeinen Pfad mit unbekanntem Belag. Rad&Wandern prüft jetzt lückenlose Wegarten auch an allen Radpräfixen; allgemeine Pfade, Fußwege und Treppen benötigen vorsichtig einen Wanderanteil. Ausgewiesene Radwege bleiben erlaubt. Reines Radprofil unverändert.
- Übergang genau am Beginn des Wanderpfads prüfen. Suchplätze nicht mit Punkten auf Fußwegen/Pfaden belegen; frühere Anschlüsse über die Zufahrt verteilen. Strenge Belagswahl verwirft anhand der Wanderreferenz offensichtlich ungeeignete Suchbereiche, prüft aber weiterhin das tatsächliche gesamte 100-m-Budget jeder Radanfahrt. Fußrest unterliegt nicht der Fahrrad-Belagsregel.
- Falls bei einer Planung ohne Zwischenziele kein geprüfter Radpräfix das strenge Budget erfüllt, vollständige Wanderroute mit Radanteil 0 m und ausdrücklicher Erklärung anzeigen. Unbekannte Beläge bleiben unbekannt; Zwischenziele werden nicht in einen Fußanteil verschoben.
- Prüfung: 106 Backend- und 121 Swift-Kerntests erfolgreich. Live-ORS mit den privaten Test-POIs: „Befestigte Wege bevorzugen“ 1.000,4 m Rad und 743,1 m Wandern; „Nur bekannte befestigte Wege“ 41,8 m Rad innerhalb der bestehenden Toleranz und 1.701,2 m Wandern. Der anfängliche unbekannte Straßenbelag verhindert eine längere strenge Radanfahrt. Beim ersten strengen Test ORS-Anfragelimit (429), erneuter Lauf nach Ablauf erfolgreich. Private Koordinaten und Rohantworten ausschließlich in ignorierten Builddateien; keine Testtour gespeichert. Korrigiertes Backend auf Pi neu gebaut und gestartet; beide Varianten über die authentifizierte HTTPS-API erneut erfolgreich mit denselben Rad-/Fußdistanzen. Die installierte iPhone-App verwendet die Korrektur bei neuer Berechnung; für diese reine Backendänderung kein neuer Appbuild. Kein Gelände-/Feldtest.

### Korrektur: POI-Ziel außerhalb des Wegenetzes (05.10.2026)

- Fehler mit den vom Nutzer angelegten Test-POIs reproduziert: reine Radanfahrt 7,38 km erfolgreich, Ziel rund 319 m vom letzten Rad-/Fußnetzpunkt entfernt. Die neue 20-m-Prüfung blockierte Rad&Wandern und Wandern. Ein Fehler des reinen Radprofils war im direkten API-Aufruf nicht reproduzierbar.
- POI-Zuordnung im Fußprofil bis 500 m erlauben; über 20 m verbleibenden Abstand ausdrücklich als fehlende Wegdaten nennen. Bei identischem Rad-/Fußnetzende bleibt die vorhandene Radanfahrt im Kombinationsmodus nutzbar und das Ende wird als Abstellpunkt markiert. Keine erfundene Fußverbindung, keine Aussage über Kletterfreiheit des unerfassten Zugangs; Reststrecke/-zeit sind nicht berechnet.
- Neues optionales Routenfeld `unmappedDestinationDistance`, validierte terminale Abstellmarker sowie sichtbarer Hinweis in Planung und Routendetails. Bedienung, Architektur und Altbestands-Quittungsprüfung angepasst. Private POI-Koordinaten, lokale App-Datenbank und Diagnosen bleiben ausschließlich unter dem ignorierten Build-Verzeichnis.
- Prüfung: 95 Backend- und 121 Swift-Kerntests erfolgreich. Live-ORS mit den tatsächlichen POI-Koordinaten vom Mac: Rad und Rad&Wandern jeweils 7.380 m, Wandern 7.350 m; fehlender Zielzugang jeweils rund 319 m. Keine Testplanung im Archiv gespeichert. Simulator-Build und gezielter UI-Test für erhaltene Route, Abstellmarker und fehlenden Zugang erfolgreich; neue Galeriebilder 20/21 visuell geprüft. Signierter Gerätebuild erfolgreich, korrigierte App auf Michaels iPhone installiert und gestartet. Pi-Backend neu gebaut und gestartet; Backend/Datenbank gesund, HTTPS und Zugangsschutz geprüft. Alle drei Modi mit den tatsächlichen Test-POIs über den aktualisierten Pi erneut erfolgreich, ohne Testtour im Archiv. Kein Gelände-/Feldtest. Version weiterhin 0.2.0 (2), kein Release oder Feldtest.


### Rad&Wandern und Wandern (05.10.2026)

- Neue Auswahl unter „Unterwegs“ im Fahrprofil; „Rad“ bleibt der Standard älterer Planungen. „Wandern“ blendet Fahrrad- und Belagswünsche aus und nutzt ORS `foot-walking` auf einfachen Wegen, höchstens SAC T1. Bekannte anspruchsvollere Berg-/Kletterabschnitte sowie unvollständige Anbieter-Schwierigkeitsbereiche werden abgewiesen. Unbekannte OSM-Tags werden ausdrücklich als Datengrenze genannt.
- „Rad&Wandern“ versucht zuerst die ganze Radstrecke, sonst einen finalen Fußrest. Bis zu acht tatsächliche Rad-/Fußanschlüsse entlang der letzten 10 km der Wanderannäherung vergleichen; kürzesten geprüften Fußrest wählen. Zwischenziele bleiben im Radanteil. Verbundene Geometrie, gemeinsame Dauer, Höhen, Beläge, Manöver und Wegpunktindizes speichern. Keine globale Optimalitätsgarantie.
- Berechneten Übergang als orangefarbenes Fahrrad „Rad abstellen“ auf Planungs-/Fahrtkarte markieren, mit Ansage und getrennten Entfernungen/Koordinaten in den Routendetails. Kein bestätigter Stellplatz. Vollständige Radstrecken haben keinen Übergangsmarker.
- Neue optionale Profil-/Routenfelder mit Altbestand- und Quittungskompatibilität. Beide neuen Profile benötigen zur Planung das aktualisierte Backend; gespeicherte Strecke samt Navigation und Aufzeichnung offline nutzbar. Fahrrad-Offlinegraph wird nicht zur Wanderplanung/-Rückführung verwendet.
- Freie Wanderübersicht Waymarked Trails im Profil verlinkt; OSM liefert bereits Wanderwege. Keine zusätzliche Kachelquelle eingebunden. Bedienung und Architektur ergänzt; Version bleibt 0.2.0 (2), kein Release, Pi-Deployment oder Geräteinstallation.
- Prüfung: 93 Backend-Tests und 120 Swift-Kerntests erfolgreich, Simulator-Build erfolgreich. Live-ORS vom Mac: öffentliche Heidelberger Wanderroute 846 m, vollständige Radroute im Kombinationsmodus 852 m und Rad-Snapping erfolgreich, ohne Speicherung einer Tour. Tatsächlicher kombinierter Fußrest mit kontrollierten Anbieterantworten geprüft; kein Feldtest. Beide gezielten Simulator-UI-Tests erfolgreich (Auswahl/Persistenz und Offline-Anzeige der Rad-/Wanderaufteilung). Profilbild 06 und neue Galeriebilder 17–19 aktualisiert und visuell geprüft. Ein früher Detailtest scrollte über den Abstellbereich hinaus; korrigierter Lauf erfolgreich. Der neue Auswahltext bleibt auch im engen Planungsbereich in einer Zeile; Abstellmarker liegt über nahen Favoriten. Zwei bestehende Backend-Deprecation-Warnungen und bestehende AppIntents-Buildwarnung ohne Fehler.


- Anschließend am 05.10.2026 auf Nutzerwunsch bereitgestellt: signierter Debug-Gerätebuild erfolgreich, auf Michaels iPhone 15 Pro installiert und gestartet; App-Zugang über das vorhandene Startskript konfiguriert. Pi-Backend erfolgreich neu gebaut und gestartet, Backend und bestehende Datenbank gesund. HTTPS-Healthcheck, Zugangsschutz (401 ohne Schlüssel), authentifizierter Status sowie beide Profilwerte im laufenden Container geprüft. Öffentliche Heidelberger Beispiele über den aktualisierten Pi: Wanderroute 846 m und vollständige Radroute im Kombinationsmodus 852 m erfolgreich; keine Testtour gespeichert. Die tatsächliche Kombination mit Fußrest und Nutzung am Gerät bleiben Praxistests. Version/Build weiterhin 0.2.0 (2), kein Tag oder GitHub-Release.

### Tolerante Koordinaten- und Plus-Code-Suche

- Die Ortssuche erkennt WGS84-Dezimalgrad, Grad/Minuten und Grad/Minuten/Sekunden direkt auf dem iPhone. Punkt/Komma als Dezimalzeichen, zusätzliche Leerzeichen, Zeilenumbrüche, typografische Zeichen, Doppelpunkte und N/S/E/W/O werden unterstützt. Treffer stehen direkt unter dem Suchfeld vor den Favoriten; die Tastatur wird beim Suchen geschlossen. Sie können wie andere Orte zur Tour hinzugefügt oder gespeichert werden, auch ohne Pi. Ungültige Werte und verbleibende Mehrdeutigkeiten erhalten einen Hinweis statt eines geratenen Ziels; reine Postleitzahlen bleiben normale Suchanfragen.
- Vollständige Plus Codes funktionieren offline. Verkürzte Codes mit Ortsangabe, etwa `2WF2+8F Rodgau`, suchen den Bezugsort über den Pi und ergänzen den Code relativ zu jedem gefundenen Ortskandidaten. Ohne Ortsangabe erscheint ein Hinweis. Keine automatische Verwendung eines möglicherweise unpassenden GPS-Standorts.
- Neue Swift-Dateien über den Projektgenerator eingebunden; Bedienung und Architektur dokumentiert. UTM/MGRS, andere Bezugssysteme und beliebige Kartenlinks sind nicht unterstützt. Version/Build bleiben 0.2.0 (2); kein Release oder Pi-Deployment.
- Prüfung am 01.10.2026: 116 Swift-Kerntests erfolgreich, darunter 8 neue Tests mit üblichen Schreibweisen, Fehlerfällen, Rodgau-Ortsauflösung mit Testantworten, 35 vollständigen Plus-Code-Referenzfällen und Wiederherstellung an Zellgrenzen. Referenzwerte unabhängig mit Googles Open-Location-Code-Implementierung berechnet. Zusätzlich bestehen alle 4 Koordinaten-Parsertests nach Ergänzung der Nutzereingabe `43.80104 N, 15.78955 E` und ihrer Varianten. Kein Live-Test der Rodgau-Geocodierung über den Pi und kein Feldtest. Simulator- und signierter Gerätebuild sowie abschließender UI-Test erfolgreich: Tastatur geschlossen, Treffer auswählbar und in die Tour übernommen. Galeriebild 05 aktualisiert und visuell geprüft. Frühe Läufe deckten verdeckte Treffer auf; der UI-Test verwendet jetzt eine eindeutige Trefferkennung und wartet auf das Schließen der Ansicht. Ein Zwischenlauf scheiterte am Sichtbarkeitsattribut, ein weiterer an einer zu frühen Abfrage während des Schließens. Auf Michaels iPhone 15 Pro installiert; tatsächliche Nutzung am Gerät noch vom Nutzer zu prüfen.

### Einstellungen ohne Titelbox

- Überflüssige BikeNavi-Box mit Fahrradlogo und „Deine Tour. Deine Wege. Deine Daten.“ entfernt. Die Pi-Server-Einstellungen folgen direkt auf die Lautstärke.
- Simulator-/Gerätebuild und bestehender Einstellungs-UI-Test erfolgreich; Galeriebild 11 aktualisiert. Am 29.09.2026 als Debug-App auf Michaels iPhone installiert. Version bleibt 0.2.0 (2), kein Release oder Pi-Deployment.

### Korrektur: ein gemeinsamer iPhone-Lautstärkeregler

- Nach Rückmeldung vom Gerät den zusätzlichen App-Lautstärkefaktor entfernt. Die erste Einstellungsbox verwendet jetzt Apples `MPVolumeView` für die tatsächliche System-Medienlautstärke. Frühere lokal gespeicherte Sprachlautstärken werden gelöscht und dämpfen Ansagen nicht mehr.
- Änderungen der Systemlautstärke in den Einstellungen lösen den Kinderreim aus; zusätzlich kann die Hörprobe per Taste gestartet werden. Navigation und Probe verwenden volle interne Lautstärke. Beobachtung und Probe enden beim Verlassen der Einstellungen oder Hintergrundwechsel.
- Prüfung: Simulator-UI-Test für erste Box, Hörprobenknopf und Tabwechsel sowie Simulator- und signierter iPhone-Build erfolgreich. Korrigierte App auf Michaels iPhone 15 Pro installiert und gestartet. Systemlautstärke/Hardwaretasten und Klang sind noch am Gerät durch den Nutzer zu bestätigen; kein Feldtest. Version bleibt 0.2.0 (2).
- Im Simulator ist die Systemlautstärke nicht regelbar; die Galerie zeigt diese Grenze ausdrücklich. Bedienungs- und Architekturdokumentation angepasst.

### Sprachlautstärke mit Kinderreim

- Erste Box in den Einstellungen: Sprachlautstärke von 0 bis 100 %, automatisch lokal gespeichert und auch für neue Navigationsansagen verwendet.
- Nach kurzer Bewegungspause spricht eine deutsche Stimme einen kurzen Kinderreim. Weitere Regleränderungen ersetzen die vorige Probe; 0 % bleibt stumm. Tabwechsel und Hintergrundwechsel stoppen die Probe. Navigationsansagen haben Vorrang. Die iPhone-Medienlautstärke wirkt zusätzlich.
- Prüfung am 29.09.2026: 108 Swift-Kerntests und gezielter Simulator-UI-Test erfolgreich (erste Box, 0/100 %, Zwischenwert, Speicherung nach App-Neustart). Simulator- und signierter Gerätebuild erfolgreich; auf Michaels iPhone 15 Pro installiert und gestartet. Ein anfänglicher Build-Verzeichniskonflikt wurde durch getrennte Geräte-Buildpfade behoben. Der UI-Test erforderte die native Prozentanzeige und eine zusätzliche Wischbewegung bis zum Endanschlag. Bestehende AppIntents-/Debug-Signaturwarnungen ohne Buildfehler.
- Bedienungs- und Architekturdokumentation sowie Galeriebild 11 aktualisiert. Version bleibt 0.2.0 (2); kein Pi-Deployment oder Release. Der tatsächliche Klang am iPhone ist noch vom Nutzer zu prüfen; kein Feldtest.

### Standort beim Fahrtstart erholen

- Fahrtstart wartet bis zu 15 Sekunden auf eine aktuelle Position, statt sofort eine allgemeine Standortfehlermeldung zu zeigen. Veraltete Positionen reichen nicht mehr aus; Standortsuche kann abgebrochen werden.
- Standortfehler werden mit der tatsächlichen Berechtigung abgeglichen; ein veralteter Fehlerzustand blockiert spätere Starts nicht dauerhaft. Beim Aktivieren der App wird die Standortabfrage erneuert.
- Ausstehende Starts werden bei Tabwechsel, Verlassen des aktiven App-Zustands und Änderung der Planungs-/Routen-ID verworfen. Verspätete Messungen starten keine abgebrochene Fahrt; Mehrfachtippen startet keine zweite Anfrage.
- Prüfung: 108 Swift-Kerntests und sechs gezielte Simulator-UI-Tests erfolgreich, einschließlich verzögertem Fix bei veraltetem Standort/Fehlerzustand, Abbruch mit verspätetem Fix, Zeitlimit mit erneutem Versuch, verweigerter Berechtigung, Tabwechsel und Hintergrundwechsel. Simulator-Build erfolgreich; Bildschirmbild 16 visuell geprüft. Bestehende AppIntents-Metadatenwarnung ohne Buildfehler. Kein GPS-Feldtest, keine Versionsänderung oder Veröffentlichung. Anschließend am 25.09.2026 signierten Debug-Gerätebuild erfolgreich erstellt, auf Michaels iPhone 15 Pro installiert und gestartet. Ein anfänglicher CoreDevice-Verbindungsabbruch wurde durch erneute Installation behoben. Version bleibt 0.2.0 (2); kein Pi-Deployment.

### Zeitlimit bei langen ORS-Strecken

- Fehler für eine öffentliche Beispielstrecke Rodgau–Göteborg reproduziert: Pi-Abbruch nach 35,1 Sekunden mit „Der Kartendienst ist gerade nicht erreichbar“, während ORS direkt nach 60,5 Sekunden eine 1.214,63-km-Route lieferte. Verwendet wurden Ortsmittelpunkte, nicht die private Startadresse aus der Planung.
- ORS-Routenaufrufe erhalten 75 Sekunden Lesezeit und 10 Sekunden Verbindungszeit. Profilvergleiche laufen parallel unter einer gemeinsamen 80-Sekunden-Grenze, passend zum 90-Sekunden-Limit der App. Belagsregeln bleiben aktiv; andere Dienste behalten ihre bisherigen Zeitlimits.
- Prüfung: 67 Backend-Tests erfolgreich, darunter paralleler Profilvergleich mit Belagsauswahl, Abbruch aller Anbieteranfragen am gemeinsamen Zeitlimit und unverändertes Suchzeitlimit. Zwei bestehende Deprecation-Warnungen. Keine iOS-Code- oder Layoutänderung; kein Geräte- oder Feldtest.
- Am 25.09.2026 ausschließlich die geprüfte Providerkorrektur auf den Pi übertragen und das Backend erfolgreich neu gebaut/gestartet. HTTPS und Zugangsschutz geprüft; Beispielroute Rodgau–Göteborg über den aktualisierten Pi erfolgreich in 63,0 Sekunden mit 1.214,63 km, 22.117 Geometriepunkten und 1.585 Abbiegehinweisen, ohne Kreuzungsumfelder. Keine Testtour gespeichert. Version bleibt 0.2.0 (2); kein neuer Release und keine iPhone-Installation erforderlich.

### Lange Strecken mit lokalem 3-km-Umfeld

- Streckenplanung mit eingerichtetem Pi verwendet den vorhandenen ORS-Routingdienst, ohne durchgehenden Wegenetzdownload und ohne Overpass-Kreuzungsumfelder. Dafür ist wieder ein ORS-Schlüssel auf dem Pi erforderlich. Lokale Planung aus dem Cache bleibt ohne eingerichteten API-Client verfügbar.
- Rückführung lädt unabhängig davon nur das aktuelle Umfeld (3 km Suchradius, 500 m Vorladepuffer und vollständige Randkacheln). Unterwegs werden neue Bereiche bei frischen, genauen GPS-Messungen nachgeladen. Fehler erhalten Route und letztes vollständiges Paket; die Bereitschaftsanzeige bezieht sich nur auf das geladene Umfeld.
- Aktiver Graph wächst nicht mit der Tour. Nicht mehr referenzierte Kacheldateien werden bei Bedarf innerhalb des 250-MB-Caches verdrängt; bestehende Pakete und laufende Downloads bleiben geschützt. Pause, Fahrtende und Fahrtwechsel sichern die Übernahme ausstehender Ergebnisse ab.
- Prüfung: 108 Swift-Kerntests, 64 Backend-Tests und Simulator-Build erfolgreich. Neue Tests für synthetische 600-km-Planung ohne Umfeld, 3-km-Abdeckung/Datumsgrenze, Fensterwechsel, Abbruch und Cache-Verdrängung ohne Beschädigung vorhandener Pakete. Simulator-UI-Test für Anzeige und Wiederöffnung erfolgreich; Galeriebilder 01/07 aktualisiert und visuell geprüft. Zwei bestehende Python-Deprecation-Warnungen. Kein Feldtest; Routinganbietergrenzen und Netzverfügbarkeit bleiben relevant. Anschließend am 24.09.2026 signierten Debug-Gerätebuild erfolgreich erstellt, auf Michaels iPhone 15 Pro installiert und gestartet sowie Backend auf dem Pi aktualisiert. HTTPS, Zugangsschutz und ORS-Konfiguration erfolgreich geprüft. Eine öffentliche Beispielstrecke Heidelberg–Frankfurt wurde über den aktualisierten Pi in 1,56 Sekunden mit 89,23 km ohne Kreuzungsumfelder berechnet; keine Testtour gespeichert. Das ist ein API-Test vom Mac, kein GPS-Feldtest. Version bleibt 0.2.0 (2), kein Release.

### Zwischenziele bei Abweichungen überspringen

- Bestätigte Abweichungen bieten das nächste offene Zwischenziel zum Überspringen an; beim Wiedereinstieg hinter mehreren Zwischenzielen können diese gemeinsam angeboten werden. Beide Ja-/Nein-Tasten sind mindestens 96 Punkte hoch.
- Zustimmung wird in der Fahrt gespeichert und bei der lokalen Rückführung berücksichtigt. Alte Fahrten bleiben lesbar; Planung, Originalroute und Fahrtziel bleiben erhalten. Eine Ablehnung unterdrückt dieselbe Nachfrage in der laufenden Sitzung.
- Ein Wiedereinstieg außerhalb des bisherigen kurzen Tracker-Fensters ist bei passender GPS-Genauigkeit und Richtung möglich, ohne weitere verpflichtende Zwischenziele zu übergehen.
- Prüfung: 103 Swift-Kerntests erfolgreich, darunter Rückführung hinter zwei ausgelassenen Zwischenzielen, Pflichtziel, Fallback-Zuordnung und Speicherung/Legacy-Decodierung. 63 Backend-Tests einschließlich Synchronisation und Schutz des Fahrtziels erfolgreich (zwei bestehende Deprecation-Warnungen). Simulator-Build und UI-Test mit beiden Antworten und Prüfung der Mindesthöhe erfolgreich. Neues Galeriebild visuell geprüft. Anschließend am 24.09.2026 signierten Debug-Gerätebuild erfolgreich erstellt, auf Michaels iPhone 15 Pro installiert und gestartet; BikeNavi-Backend auf dem Pi aktualisiert. HTTPS-Healthcheck und neues Zwischenziel-Datenfeld im laufenden Backend erfolgreich geprüft. Die öffentliche OpenAPI-URL ist deaktiviert (404), daher wurde das Modell direkt im laufenden Container geprüft. Ein vorübergehender CoreDevice-Verbindungsabbruch wurde durch erneute Installation behoben. Kein Feldtest.

### Korrekturen für Höhenlücken und widersprüchliche Kartenstände

- Einzelne vom Höhendienst ausgelassene Punkte verwerfen nicht mehr das gesamte Profil. Kleine innere Lücken werden positionsgetreu und entlang der Weglänge interpoliert: höchstens zwei Punkte je Lücke, maximal 100 m zwischen gültigen Nachbarn und höchstens acht Punkte je Profil. Die Datenquelle kennzeichnet die Schätzung. Randlücken, größere Lücken und ungültige Antworten bleiben Fehler.
- Höhenfehler unterscheiden nun einen unerreichbaren Pi, eine nicht verfügbare Höhenquelle und unpassende Antworten.
- Wegenetz-Compilerrevision 3 übernimmt OSM-Knotenversionen. Widersprüchliche Positionen werden anhand der höheren Version aufgelöst, nicht anhand des Downloadzeitpunkts; Zugangssperren bleiben erhalten. Unauflösbare Konflikte lösen einmal eine vollständige Gebietserneuerung aus und erhalten anschließend eine eigene Fehlermeldung.
- Vorhandene Pakete werden bei Verbindung zum aktualisierten Pi erneuert. Contributor-Metadaten werden nicht in die App-Kacheln übernommen.
- Prüfung am 24.09.2026: 100 Swift-Tests und 62 Backend-Tests erfolgreich, signierter iPhone-Build erfolgreich. Pi aktualisiert, App auf Michaels iPhone installiert und gestartet. Die unveränderte gemeldete Tribunj-Geometrie liefert über den laufenden Pi alle 591 Höhenwerte (ein interpolierter Punkt); Anwendung und Serialisierung mit dem Swift-Kern erfolgreich. Die ursprünglichen Rodgau-Wegpunkte ergeben mit sechs frisch geladenen Bereichen eine Route von 2.197 m (24.652 Knoten, 52.410 gerichtete Kanten). Diese beiden Reproduktionen liefen mit dem App-Kern auf dem Mac und dem echten Pi, nicht als Feldtest auf dem iPhone. Keine privaten Tourdaten versioniert; kein neuer Release.

### Höhenprofile für lokale Planungen

- Fertige lokale Routen erhalten im Hintergrund ein Höhenprofil aus dem SRTM-Geländemodell über den Pi und den vorhandenen openrouteservice-Zugang. Die Routensuche bleibt auf dem iPhone; Wegverlauf, Belags- und Abbiegeindizes bleiben unverändert.
- Bestehende Planungen ohne Höhen werden beim Öffnen ergänzt. Anstieg und Abstieg werden datenabhängig angezeigt, nicht mehr anhand des Routinganbieters ausgeblendet. Fehlgeschlagene Abfragen lassen die Route nutzbar und können über „Höhendaten laden“ wiederholt werden.
- Abtastung etwa alle 30 m, höchstens 2.000 Punkte; Dreipunktglättung und 3-m-Schwelle für Höhensummen. Null und negative Höhen bleiben gültig; ungültige oder unvollständige Antworten werden nicht als ebene Strecke dargestellt.
- Profil und Quelle werden mit der Tour lokal und auf dem Pi gespeichert; Wiederöffnen ist offline möglich. Originalkoordinaten erhalten interpolierte Höhen für GPX. Lokale Rückführungen übernehmen keine unzutreffenden Gesamthöhen der ursprünglichen Tour.
- Dokumentation und die beiden betroffenen Bildschirmbilder mit öffentlichem Heidelberg-Höhenbeispiel aktualisiert. Neue Swift-Datei über den Projektgenerator aufgenommen.
- Prüfungen am 24.09.2026: 97 Swift-Tests und 55 Backend-Tests erfolgreich (zwei bestehende Deprecation-Warnungen). Simulator-/UI-Testbuild und signierter iPhone-Debug-Build erfolgreich. UI-Test für Höhenanzeige und Wiederöffnen ohne Serverzugang erfolgreich; Bilder visuell geprüft. Echte Höhenabfragen für öffentliche Heidelberg- und Tisno-Testpunkte erfolgreich, einschließlich neuem Pi-Endpunkt und Zugangsschutz. App auf Michaels iPhone installiert und gestartet; Pi aktualisiert. Automatische Ergänzung einer bestehenden Planung und anschließende Speicherung auf iPhone und Pi direkt geprüft; private Tourdaten wurden nicht in Testdateien oder Dokumentationsbilder übernommen.
- Grenzen: Geländemodell statt garantierter Fahrbahnhöhe, insbesondere bei Brücken und Tunneln; lange Strecken erhalten gröbere Abstände. Keine Änderung der Routenauswahl oder Fahrzeitschätzung, keine neue Höhenabfrage während lokaler Rückführung. Kein Feldtest und kein neuer Release. Der zusätzliche Legacy-Server-Smoke-Test lieferte bei diesem Lauf keine OSM-Kreuzungsdetails und brach an dieser Prüfung ab; die unabhängige Höhenabfrage war erfolgreich.

### Routing über freigegebene Schranken

- Fehler an der Brücke Tisno/Murter behoben: Die OSM-Schranken an beiden Enden waren trotz `access=yes` gesperrt worden. Bewegliche Schranken mit ausdrücklicher Fahrrad-, Fahrzeug- oder allgemeiner Zugangsfreigabe werden nun nach der bestehenden Zugangshierarchie berücksichtigt. Verbote, verschlossene Schranken und nicht unterstützte bedingte Beschränkungen bleiben wirksam; keine geografische Ausnahme und keine Lockerung der Belagsgrenzen.
- Kacheln erhalten die zusätzliche Compilerrevision 2. Neuer Server-Cacheschlüssel verhindert die Wiederverwendung alter Ausschlüsse. Die App erneuert alte Gebietsdaten bei der nächsten Vorbereitung/Planung mit API-Client; gespeicherte Offline-Pakete bleiben lesbar. Für die Korrektur im Betrieb müssen Pi und App aktualisiert werden.
- Reproduzierbare öffentliche OSM-Beispieldaten der Brücke, beider Zufahrten und Schranken hinzugefügt (ODbL, Abruf 24.09.2026). Regression prüft beide Richtungen und alle drei Belagsprofile sowie Zugangshierarchie, Cachemigration und Altbestände.
- Prüfung am 24.09.2026: 90 Swift-Tests und 45 Backend-Tests erfolgreich; zwei bestehende Deprecation-Warnungen der Backend-Testabhängigkeiten. iOS-Debug-Simulator-Build erfolgreich. Keine sichtbare UI-Änderung; Architektur und Bedienungsdokumentation aktualisiert.
- Installation und Betrieb: Am 24.09.2026 signierter iPhone-Debug-Build erfolgreich, auf Michaels iPhone 15 Pro installiert und gestartet; Pi aktualisiert. Live-Prüfung von HTTPS, Zugangsschutz, Beispielrouting, Kreuzungsdaten und Speicherung/Synchronisation erfolgreich; technischen Testeintrag wieder entfernt. Ausgelieferte Tisno-Kachel mit Compilerrevision 2, beiden freigegebenen Schranken und asphaltierter Verbindung in beiden Richtungen direkt am Pi geprüft. Kein neuer Release.
- Rückmeldung am 24.09.2026: Michael bestätigt nach Installation und Pi-Update, dass die Routenplanung an der Tisno-Brücke funktioniert.
- Grenzen: Keine dokumentierte Testfahrt über die Brücke, keine Auswertung des aktuellen Brückenzustands oder von Öffnungszeiten; Wartezeiten bleiben möglich.

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
