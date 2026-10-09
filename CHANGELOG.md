# Änderungen

Alle veröffentlichten Fassungen erhalten einen Git-Tag und einen GitHub-Release. Versionsnummern folgen `MAJOR.MINOR.PATCH`; vor 1.0 kennzeichnet eine neue Minor-Version einen größeren Entwicklungsschritt. Die iOS-Buildnummer steigt unabhängig davon. Details zum Ablauf: [Versionierung](docs/VERSIONIERUNG.md).

## Unveröffentlicht

### Dokumentations- und Git-Abgleich (09.10.2026)

- README, Umsetzungsstand, Bedienung, Architektur, Versionierung und öffentliche Bildschirmgalerie auf den tatsächlichen Stand nach 0.4.0 abgestimmt. Unabhängige Blogaufträge statt veralteter Anfragebindung, tatsächliche Installations-/Prüfergebnisse und offene Feldprüfungen dokumentiert. Ältere Release-Einträge bleiben erhalten.
- 102 lokale Dokument-/Bildverweise geprüft; Projektgenerator reproduziert Projekt und Scheme unverändert. Öffentliche Bilder 30/31 und 39–41 nochmals visuell geprüft; 01/12/14/42/43 im Funktionslauf geprüft. Private Blog-/Fahrt-/Fotodaten, Schlüssel, Datenbanksicherungen, Diagnoseprotokolle und Buildprodukte bleiben ausgeschlossen.
- Erweiterungen vom 7. und 9. Oktober gemeinsam als Entwicklungsstand auf `main` versioniert. Version/Build bleiben 0.4.0 (4); bestehender Release-Tag und GitHub-Release unverändert.

### iPhone während Navigation wach halten (09.10.2026)

- Automatische Bildschirmsperre zentral aus aktiver Fahrt und App-Vordergrundzustand steuern statt einzelne Start-/Pause-/Ende-Zuweisungen. Bei Rückkehr aus dem Hintergrund erneut anwenden; Tab-/Ansichtswechsel unterbrechen den Wachhalteschutz nicht. Pause, Fahrtende/Verwerfen und Hintergrund geben den normalen Idle-Timer frei. Auch eine automatisch ausgelöste Aufzeichnungspause aktualisiert ihn sofort. Manuelles Sperren über die Seitentaste bleibt möglich.
- Native UIKit-Prüfung mit echter `UIApplication.isIdleTimerDisabled` für Aufnahme, Tabwechsel, Hintergrund/Vordergrund, externes Zurücksetzen des Flags, Pause/Fortsetzung und Ende erfolgreich; insgesamt vier iOS-/MapLibre-Tests erfolgreich. Signierter Release-Gerätebuild und Signaturprüfung erfolgreich; Release-App 0.4.0 (4) erfolgreich auf Michaels iPhone installiert; automatischer Start wegen erneut gesperrtem Gerät abgewiesen. Nach Entsperren manuell öffnen. Kein Feld-/Sperrzeittest am fahrenden iPhone.

### Blog: zusammenhängende Erzählung ohne Wiederholungen (09.10.2026)

- Neueste Nutzerfassung redaktionell bewertet: gleichförmige lange Stationsaufsätze, mehrfach wiederholte Karst-/Wasser-/Hafenerklärungen, Pointe an fast jedem Abschnittsende und zusätzlich wiederholte Markdown-Überschriften im Fließtext.
- Schreibauftrag ordnet Kerninformationen einmalig über Stationen und Hintergrundkapitel zu. Neue belegte Themen ausführlich, benachbarte ähnliche Motive als kurze Übergänge; etwa 1.500–2.000 Erzählwörter bei vielen Stationen statt gleich langer Einzelaufsätze. Hintergrundkapitel vertiefen andere Aspekte, höchstens drei bis vier kurze Pointen insgesamt. Regionale Quellen nicht pauschal zur Erklärung jedes konkreten Bauwerks/Anstiegs machen.
- Optionale, geordnet validierte `stopTitles` für verständliche Blogüberschriften und vorsichtige Tippfehlerglättung; persönliche Stationstitel/Notizen in der Datenbank unverändert. Ältere strukturierte Antworten ohne Überschriftenfeld bleiben lesbar. Doppelte führende Markdown-Überschriften zusätzlich beim HTML-Rendern entfernen; Fließtext, Absatzstruktur, escaping und Quellenlinks erhalten.
- Wiederholte Unsicherheitsbesprechung im Entwurf löst eine gezielte KI-Redaktion aus: unsichere lokale Behauptungen samt Erklärung streichen statt ihre Einschränkung zur Scheinsicherheit umzudeuten; kurze Übergänge aus Originalnotizen und quellengeprüfte Themen erhalten. Erste Schreibantwort höchstens 45 Sekunden, Redaktion höchstens 25 Sekunden und nur aus dem Rest des unveränderten 60-Sekunden-Schreibbudgets. Unzureichende/ausgefallene erforderliche Redaktion erzeugt keinen neuen KI-Blog; bestehende Fassungen bleiben geschützt. Maximal vier KI-Anfragen bei notwendiger Redaktion, sonst weiterhin drei.
- Prüfung: vollständige Backend-Suite **183 Tests erfolgreich**, zwei bekannte Warnungen aus Testabhängigkeiten. Geprüft sind sichere Markdown-Bereinigung, vollständige Stationsüberschriften, ältere strukturierte Antworten, unveränderte Originalnotizen, Schreib-/Redaktionsbudget und präzise Fehler ohne freie Anbieterinformationen. Der Schreibschritt erhält einen Prüfstatus statt ausformulierter Unsicherheitsprosa; die Recherche behält ihre vollständigen Einschränkungen.
- Echte erste Pi-Fassung: 16 analysierte Fotos und 22 Quellen in 113,7 Sekunden; Erzähltext von rund 2.830 auf 1.460 Wörter reduziert. Die Sichtprüfung fand weiterhin zu viele Unsicherheitssätze. Eine danach angeforderte automatische Redaktion bestand die Qualitätsprüfung nicht; der Speicherschutz erhielt die bisherigen Fassungen.
- Endfassung durch Codex redaktionell überarbeitet und als weitere Pi-Fassung gespeichert: rund 1.120 Erzählwörter, alle 16 Fotos, 22 Recherchequellen und drei Hintergrundkapitel. Vor dem Speichern aktuelle Stationstitel/Notizen und Fotos abgeglichen; anschließend exakte Fassung über HTTPS bestätigt. Fotos, Karten und Originalnotizen bleiben bytegleich zur zugrunde liegenden KI-Fassung, die ursprüngliche Fassung weiterhin unverändert abrufbar. Neue Fassung im lokalen Browser geöffnet und sichtbar geprüft; private HTML-/Prüfdaten ausschließlich in ignorierten Artefakten und auf dem Pi.
- Diese Textänderungen benötigen kein zusätzliches iPhone-Update. Neue automatisch geschriebene Texte entstehen bei erneuter Erstellung; ältere HTML-Fassungen bleiben erhalten.


### Fahrzeitschätzung, ETA und Rückmeldung beim Blog (09.10.2026)

- Gemeinsam festgelegte Bewegungsdurchschnitte: befestigt 20 km/h, Pflaster 16, Schotter 12, unbefestigt 8, unbekannt 12, Wandern 4. Sonstige Beläge vorsichtig wie unbefestigt. Einheitliche iPhone-Schätzung für Online-/Offlineplanung, lokale Anschlüsse und gespeicherte Planungen. Zusatzzeit für Anstiege mit 600 hm/h beim E-Bike, 400 ohne Unterstützung und 300 beim Wandern; keine Beschleunigung bei Abfahrten und keine vorweggenommenen Pausen. Keine Änderung am Routingweg oder an den gespeicherten GPS-Samples.
- In „Fahren“ ETA direkt hinter Fahrzeit; verbleibende Zeit nach noch ausstehenden Belags-/Höhenabschnitten der aktiven Route, Anzeige in Ortszeit alle 15 Sekunden. Pause, fehlender frischer Standort, Abweichung über 35 m und laufende Neuberechnung zeigen „—“. Bestehende Aufzeichnungen/Fahrzeiten bleiben erhalten.
- Blogfortschritt direkt oberhalb der Aktionen: Übertragung, vier tatsächliche Pi-Phasen, Schrittbalken und verstrichene Zeit. Zentraler Zustand je Fahrt und Wiederaufnahme nach Ansicht-/App-Neustart. Die akzeptierte Erstellung läuft als eigener Pi-Auftrag unabhängig vom HTTP-Request; idempotente Auftrags-ID, ein gleichzeitiger Auftrag und maximal 32 kleine Statusobjekte. Exakte Ergebnisfassung laden; vorhandene Blogs/Revisionsschutz erhalten. Der Pi-Prozess hält Auftragsstatus nur im Arbeitsspeicher; Neustart unterbricht laufende Aufträge. Neue App braucht das aktualisierte Backend.
- Prüfung: **136 Swift-Kerntests**, **171 Backend-Tests**, drei native MapLibre-Tests, Simulator-Build und signierter Release-Gerätebuild mit strenger Signaturprüfung erfolgreich. Simulator-UI-Prüfung für Fahrt/Pause/ETA sowie abschließende Prüfung der Planung und des Blogfortschritts mit echten lokalen HTTPS-Anfragen, Ansichtswechsel und App-Neustart erfolgreich. Testbackend verwendet öffentliche synthetische Daten, kontrollierte Anbieterantworten und Vorlagentext; kein KI-/Feldtest. Erste UI-Testfassung benötigte Main-Thread-Ausführung, ein weiterer Screenshotlauf wurde nach zu weitem Scrollen abgebrochen; die finalen angepassten Abläufe sind erfolgreich.
- Galerie 01/12/14 aktualisiert und 42/43 ergänzt, alle visuell geprüft. Bedienung/Architektur mitgeführt, vorhandene lokale Änderungen erhalten. Pi nach geprüfter Sicherung/Wiederherstellung mit 242 Archivdatensätzen aktualisiert; Backend/Datenbank gesund. Echte HTTPS-/KI-Auftragsprüfung mit öffentlichen synthetischen Daten: 25 Quellen in 56,8 Sekunden, Status/Idempotenz/exakte Fassung erfolgreich, technische Tour anschließend gelöscht. Erster iPhone-Versuch von CoreDevice wegen gesperrtem Gerät abgewiesen; nach Entsperren signierte Release-App 0.4.0 (4) erfolgreich installiert und gestartet. Version/Build weiterhin 0.4.0 (4), kein Tag oder GitHub-Release. Konkrete Karten-Ausfälle und ETA-Zuverlässigkeit auf längeren echten Fahrten bleiben Feldprüfungen.

### Stabile Routenmarkierung während der Fahrt (09.10.2026)

- Konkrete Schwachstelle beim gemeldeten Verschwinden der Routenlinie: Jeder neue Trackpunkt entfernte bisher sämtliche Kartenannotationen, einschließlich unveränderter Route und Navigationsposition. Abbiegehinweise werden unabhängig aus der gespeicherten Geometrie berechnet und können dabei weiterhin funktionieren. Ob dies den beobachteten Feldausfall vollständig erklärt, ist noch nicht belegt.
- Route, Aufzeichnung, Wegpunkte und Favoriten getrennt aktualisieren. Unveränderte Route und Navigationsmarker bei GPS-Aufzeichnung erhalten; Geometrieänderungen trotz gleicher ID erkennen. Kartenstilwechsel erneuern alle Gruppen; Ersatzgeometrie vor Entfernen der Vorgänger registrieren.
- Native MapLibre-Regressionsprüfungen über ein vom Projektgenerator gepflegtes iOS-Testziel ergänzt. Drei native MapLibre-Tests erfolgreich: 100 Aufzeichnungsupdates ohne Entfernung von Route/Position, Geometrieänderung bei gleicher ID samt Routenentfernung und Stil-Erneuerung ohne Duplikate. Keine Änderung an Version/Build, keine Veröffentlichung; anschließende gebündelte Geräte-/Pi-Bereitstellung in den vorstehenden Einträgen dokumentiert.


### Blog: KI-Ausfälle nicht als kurze Standardtext-Fassung speichern (07.10.2026)

- Beanstandeten neuesten privaten Blog geprüft: Vorlagenmodus nach ausgefallener Websuche und Textgenerierung, vier gespeicherte Ortsquellen, neun Foto-Stationen, keine Hintergrundkapitel. Pi lief noch ohne die lokal ergänzte Bildanalyse. Ursprünglicher genauer Anbieterfehler wurde nicht gespeichert; erneut ausgeführte diagnostische Web-/Schreibanfragen waren erfolgreich. Private HTML-/Foto-/Diagnosedaten ausschließlich unter ignorierten `artifacts/`, keine privaten Fahrtkoordinaten oder Zugangswerte versioniert.
- Bei konfigurierter KI liefert ein fehlgeschlagener Schreibschritt HTTP 502 und speichert keine neue Fassung; vorhandene Blogs bleiben erhalten. Fehlermeldungen unterscheiden Zeitlimit, Anbieterstatus, Ausgabelimit und ungültiges Ausgabeformat ohne rohe Anbietertexte. Ohne KI-Konfiguration bleiben gekennzeichnete Vorlagenentwürfe möglich.
- Erste neue Live-Fassung analysierte alle neun Fotos, verlor jedoch das Webdossier wegen des 3.000-Token-Limits; der inhaltlich geprüfte Text blieb beim See/Schlucht zu allgemein. Webbudget deshalb auf 6.000 Tokens erhöht, belegte Teilergebnisse bei Ausgabelimit erhalten und mehrere zitierte Details derselben URL zusammengeführt. Wikipedia/Websuche parallel, Analyse 40 Sekunden, Websuche 60 Sekunden; Gesamtbudget der Anbieterphasen rund 160 Sekunden. Fehlende Belege werden nicht im Reisebericht kommentiert.
- Erfolgreiche Entwürfe erhalten additive `generationDetails` mit Zahl analysierter Orte/Fotos und Wikipedia-Quellensprachen. Schreibauftrag fordert zusammenhängende Erzählung und wechselnde Satzlängen.
- Echte Bild-/Ortsanalyse mit neun vorhandenen Stationsfotos im isolierten Pi-Prüflauf erfolgreich: 20,1 Sekunden, kroatische Recherchehinweise einschließlich Gewässer-/Karstthemen, alle Stations-IDs korrekt, keine Ausfallhinweise. Dieser Prüflauf änderte weder Backend noch Blogfassungen. Abschließende Backend-Suite **166 Tests erfolgreich**, einschließlich Erhalt mehrerer zitierter Details, belegter Teilergebnisse bei Ausgabelimit, Ausschluss des abgeschnittenen Schlussabsatzes und gleichzeitigem Wikipedia-/Weblauf; zwei bekannte Deprecation-Warnungen. Datenbanksicherung in separater temporärer Datenbank mit 233 Archivdatensätzen erfolgreich wiederhergestellt. Backend-Containerbuild und Pi-Bereitstellung erfolgreich, laufende Quelle per SHA-256 abgeglichen. Kein iPhone-Update, Versionsbump, Tag oder Release; vorhandene Blogfassungen erhalten. Abschließender echter Pi-Lauf erfolgreich: 90,4 Sekunden, alle neun Fotos analysiert, 19 Quellen einschließlich kroatischer Originalquellen, drei ausführliche Hintergrundkapitel, kein Analyse-/Web-/Schreibausfall. Haupttext gelesen; Seeökologie, Ortsgeschichte und Trockenmauer-/Olivenwirtschaft nun als belegte Hintergründe statt reiner Motivbeschreibung. Ausgewählte Aussagen gegen Originalquellen geprüft; Verwechslungen zwischen Seeboden/Wasseroberfläche sowie Gipfel-/Aussichtspunkthöhe redaktionell in einer zusätzlichen privaten Blogfassung und ihren gespeicherten Quellenauszügen korrigiert. Titel/Einleitung ohne erfundene Denkmaleigenschaft des privaten Hauses, wiederholte Unsicherheitskommentare bereinigt. Allgemeine geografische Präzisionsregel im Recherche-/Schreibauftrag ergänzt und 42 Blogtests erneut erfolgreich. Frühere Fassungen bleiben erhalten; kein Feldtest und keine vollständige unabhängige Prüfung jeder historischen Aussage. Redaktionelle neue Fassung über die authentifizierte API erneut als aktuell bestätigt: alle neun Bilder eingebettet, korrigierte Sachangaben und `editorialReview` vorhanden. Abschließende Pi-Quelle stimmt mit lokalem Stand überein; zuvor vorhandene lokale Änderungen erhalten.


### Blog: Bilder und nahes Umfeld als Recherchekontext (07.10.2026)

- Bei aktivierter KI alle verkleinerten Stationsfotos gemeinsam mit Titel und Standort an OpenAI zur strukturierten Bild-/Ortsanalyse übergeben. IDs sichern die Zuordnung; unvollständige, doppelte oder ungültige Analysehinweise werden verworfen und im Entwurf genannt. Fotos verlassen damit bei aktivierter KI den Pi; vollständige GPS-Spuren weiterhin nicht. Datenfluss, Modellanforderungen und zusätzliche Bildkosten dokumentiert.
- Abgeleitete Suchideen statt Rohbilder in Webrecherche und Schreibkontext. Nahe Gewässer, Gebäude und Landschaften gezielt mit Standort/Quellen prüfen; auch Seen berücksichtigen, deren Mittelpunkt außerhalb der engen Geosuche liegt. Landessprachliche Originalquellen ausdrücklich in der Websuche berücksichtigen; Wikipedia fragt lokale Sprachen zusätzlich zu Deutsch/Englisch ab und dedupliziert Übersetzungen nach Wikidata-ID.
- Schreibauftrag erzählt belegte Entstehung, Nutzung, Ökologie oder Ortsgeschichte auf Deutsch statt sichtbare Motive, Bildunterschriften oder Originalnotizen nachzuerzählen. Bildhinweise sind keine Faktenquelle; unbestätigte Identifikationen und erfundene Erlebnisse weglassen. Ohne passende Belege kurz bleiben.
- Bis zu drei KI-Anfragen pro Erstellung; Analyse/Kartenabruf überlappen, Phasen besitzen feste Zeitbudgets. Gefundene Wikipedia-Teilergebnisse bleiben bei späteren Sprach-Ausfällen erhalten; neue Quellen werden vor älteren Quellen in die begrenzte Auswahl aufgenommen. Stationskoordinaten und additive Artikel-/Suchpunktkoordinaten im Schreibkontext ermöglichen die geografische Zuordnung. Vorhandene Orts-/Fahrtrevisionen und HTML-Datenformate bleiben kompatibel.
- Prüfung: vollständige lokale Backend-Suite **160 Tests erfolgreich**, darunter kroatischer See mit lokalen/deutschen Artikeln, Quellenzuordnung, alle 50 Stationsfotos, Ortskontext ohne Foto und sieben ungültige/ausgefallene Analyseantworten. Abbruch einer späteren Sprachabfrage erhält bereits gefundene lokale Quellen. Zwei bekannte Deprecation-Warnungen aus Testabhängigkeiten. Backend-Wheel erfolgreich gebaut; der erste Build ohne isolierte Buildumgebung scheiterte an fehlendem `bdist_wheel`, regulärer isolierter Build anschließend erfolgreich. API-Prüfungen verwenden kontrollierte Anbieterantworten, keine echte Bilderkennung oder redaktionelle Qualitätsprüfung mit dem Pi-Modell. Ein solcher Live-Lauf steht aus; kein Feldtest. Bedienung und Architektur aktualisiert, vorhandene lokale Änderungen erhalten. Kein Pi-/iPhone-Deployment, Versionsbump, Tag oder Release durch diese Änderung.


### Blog: Stationen nachtragen und korrigieren (07.10.2026)

- Im Tourtagebuch jederzeit Stationen aus Bildern mit gültigen GPS-Metadaten hinzufügen, auch nach Fahrtende. Standort vor JPEG-Neucodierung lokal auslesen; ohne Bild-GPS verständlicher Hinweis und kein Speichern eines Nachtrags.
- Vorhandene Stationen bearbeiten: Titel/Notiz korrigieren, Foto ersetzen oder entfernen und Reihenfolge ändern. Nachträge und Änderungen über „An den Anfang“/„Nach …“ einordnen; ID und Aufnahmezeit bestehender Stationen bleiben erhalten.
- Offline-Speicherung und atomare lokale Reihenfolge, revisionsgeprüfter Pi-Abgleich einschließlich erneuter Übertragung nach verlorener Antwort und Schutz von Eingaben während eines Uploads. Änderungs-Cursor übermittelt auch Korrekturen. Alte Ortsdaten bleiben lesbar; 50 Orte/768 KB pro Foto/20 MB pro Fahrt weiterhin geprüft. Neue App benötigt das aktualisierte Backend für `PUT`.
- Neue Blogfassungen verwenden korrigierte Stationen und gewählte Reihenfolge. Änderungen während der Recherche verhindern einen veralteten Entwurf; vorhandene HTML-Fassungen bleiben erhalten.
- Prüfung: 149 Backend-Tests mit SQLite und 131 Swift-Kerntests erfolgreich; zwei bekannte Deprecation-Warnungen aus Backend-Testabhängigkeiten. Simulator-Testbuild und signierter iPhone-Release-Build samt strenger Signaturprüfung erfolgreich. Drei relevante Simulator-UI-Abläufe erfolgreich: bisherige Offline-Ortserfassung, bestehende HTML-Vorschau und neuer echter System-Fotopicker mit Nachtrag, Einordnung, Korrektur und Offline-Neustart. Zwei anfängliche Selektoren konnten den separaten iOS-Fotopicker nicht korrekt bedienen; Test auf dessen Bildkachel und Mittelpunkt umgestellt, abschließender Lauf erfolgreich. Bild-GPS innerhalb der EXIF-Rundung bestätigt; gespeichertes JPEG ohne GPS-Metadaten geprüft. Galerie 30/31 aktualisiert, 39–41 ergänzt und visuell geprüft.
- Bedienung und Architektur mitgeführt. Version bleibt 0.4.0 (4); bei Abschluss der lokalen Prüfung noch keine Installation oder Bereitstellung. Die anschließende Geräte-/Pi-Installation ist nachfolgend dokumentiert; reale iPhone-/iCloud-Fotoauswahl und GPS-Feldprüfung bleiben offen.

### Bereitstellung der Stationserweiterung (07.10.2026)

- Aktualisierte signierte Release-App 0.4.0 (4) auf Michaels iPhone 15 Pro installiert und gestartet. Erster Installationsversuch wegen gesperrtem Gerät abgewiesen; nach Entsperren erfolgreich. Vorhandene App-Daten und Zugangskonfiguration erhalten.
- Aktuelle Pi-Datenbank vor Deployment gesichert und in einer separaten temporären PostgreSQL-Datenbank erfolgreich wiederhergestellt (231 Archivdatensätze). Backend aktualisiert, Pi-lokale KI-Konfiguration durch das Deployment erhalten; Backend und Datenbank gesund.
- Neue Stationsfunktion über die echte authentifizierte Pi-/PostgreSQL-API geprüft: Nachtrag, Textkorrektur, geänderte Position, idempotente Wiederholung, Revisionsschutz und erneuter Abruf über den Änderungs-Cursor erfolgreich. Öffentlicher synthetischer KI-Beispielblog mit korrigierten Notizen in der gewählten Reihenfolge erfolgreich: 16 Quellen, 62,7 Sekunden, keine Recherche-/Erstellungshinweise. Technische Beispielaufzeichnung samt Stationen und Blog danach wieder entfernt.
- Allgemeiner Pi-Verbindungstest ebenfalls erfolgreich: HTTPS/Zugangsschutz, öffentlicher Ortsname, E-Bike-Route mit 852 m und Kreuzungen, Speicherung/Abgleich sowie idempotenter Upload geprüft; technische Testplanung anschließend entfernt.
- Reale iPhone-Fotoauswahl/iCloud und GPS-Feldtest bleiben Bedienungsprüfungen am Gerät. Version und Build unverändert, kein neuer Git-Tag oder GitHub-Release. Docker meldet eine vom Pi-Kernel nicht unterstützte Speicherbegrenzung; Dienste laufen gesund.


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
