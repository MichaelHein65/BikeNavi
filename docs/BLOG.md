# Tourtagebuch und Reiseblog

Während einer Fahrt über **Blog-Ort festhalten** einen besonderen Moment sammeln: Ortsname, Foto aus Kamera/Fotomediathek und/oder Notiz. Eine aktuelle GPS-Position ist erforderlich; beim Öffnen des Formulars wird der Standort festgehalten. Bei längerer Unterbrechung lässt er sich ausdrücklich aktualisieren. Bilder sollen zu diesem Ort gehören. Fotos werden auf höchstens 1.280 Pixel und 768 KB als JPEG neu encodiert; Original-Metadaten einschließlich EXIF werden nicht übernommen. Pro Fahrt bis zu 50 Orte und 20 MB Fotos.

Alles wird zunächst dauerhaft im lokalen SQLite-Speicher abgelegt. Der Pi erhält zuerst die zugehörige Fahrt, danach die unveränderlichen Blog-Orte einzeln mit Bestätigung. Auch während einer Aufzeichnung kann eine Fahrtsnapshot für diese Übertragung synchronisiert werden. Fehlende Verbindung verliert keine Erinnerungen; erneut übertragen wird beim nächsten Abgleich, im laufenden App-Betrieb alle 60 Sekunden und beim erneuten Öffnen. iOS kann Hintergrundarbeit anhalten; eine sofortige Übertragung bei gesperrtem Gerät ist nicht zugesichert. Bestätigte Orte bleiben auf dem iPhone erhalten. Konfliktkopien erhalten eigene Orts-IDs und bewahren Fotos und Notizen.

Nach **Speichern und beenden**: unter **Touren → Gefahren → Fahrt → Tourtagebuch & Blog** die Orte ansehen, mit dem Pi abgleichen und **Blog auf dem Pi erstellen** wählen. Die App fordert die Erstellung erst bei beendeter, vollständig übertragener Fahrt an. **Blog ansehen** öffnet die HTML-Vorschau, **HTML exportieren** die Teilen-Funktion. Eine gespeicherte Vorschau bleibt lokal verfügbar. Bei verloren gegangener Antwort erneut ins Tagebuch gehen: eine auf dem Pi fertig gespeicherte Fassung wird abgerufen. **Neue Blogfassung erstellen** erhält ältere Pi-Fassungen; derzeit zeigt die App jeweils die neueste.

## Gestaltung und Recherche

Der Blog enthält einen fröhlichen farbigen Titelbereich, nummerierte Lieblingsmomente, eigene Fotos, Originalnotizen, einen motivierenden Abschluss für die nächste Folge und eine Quellenrubrik. Die Streckenübersicht verwendet die GPS-Aufzeichnung; Pausensegmente werden nicht mit einer erfundenen Verbindung überbrückt. Ohne Aufzeichnung wird ausdrücklich die geplante Route dargestellt. Ein vorhandenes Höhenprofil gehört zur **geplanten** Route und wird so beschriftet.

Wikipedia-Geosuche recherchiert an höchstens acht ausgewählten Blog-Orten und vier über die Strecke verteilten Punkten. Suchpunkte werden räumlich dedupliziert; zuerst deutsche, bei fehlenden Ergebnissen englische Artikel. Die Suche ist auf 1,5 km Umgebung und drei Artikel pro Suchpunkt begrenzt. Funde sind Hintergrund in der Umgebung, kein Beleg für einen persönlichen Besuch. Die Recherche wird nach 30 Sekunden begrenzt; bisherige Ergebnisse bleiben verwendbar.

Mit konfigurierter OpenAI-Anbindung recherchiert eine zusätzliche Responses-Anfrage mit `web_search` gezielt Geschichte, Geologie, Landschaft und Kultur. Höchstens drei Suchwerkzeugaufrufe, begrenzte Ausgabelänge und 45 Sekunden Antwortzeit. Verwendet werden nur Ergebnisse mit HTTPS-Quellenzitaten. Danach formuliert ein eigener Schreibschritt den deutschen Blog als strukturierte Texte. Eine feste HTML-Vorlage sorgt für konsistente Gestaltung; KI, Notizen und Quellen liefern keinen ausführbaren HTML-Code. Das Modell erhält die Anweisung, keine Besuche, Wetter, Gefühle oder anderen Erlebnisse zu erfinden. Modelltexte und Quellen müssen trotzdem vor Veröffentlichung redaktionell geprüft werden.

Bis zu vier kleine OpenTopoMap-Ausschnitte zeigen Landschaft/Höhenlinien und den jeweiligen markierten Ort. Kein Gebietsmassendownload; die Streckenübersicht bleibt auch bei Kartenausfall vorhanden. Fotos und Karten werden als Data-URLs eingebettet, das Höhenprofil als SVG. Das exportierte HTML benötigt keine externe JavaScript-Bibliothek und keine Serververbindung. Quellenlinks und die Lizenzangaben für OpenStreetMap, SRTM, OpenTopoMap und Wikipedia bleiben beim Weiterverwenden erhalten. Die Vorlage ist für Desktop, Mobilansicht und Druck ausgelegt.

## KI auf dem Pi

Optional in `/srv/bikenavi/.env`: `BLOG_OPENAI_API_KEY`, `BLOG_OPENAI_MODEL`, `BLOG_WEB_SEARCH=true`. Das Modell muss die Responses API, Structured Outputs und Websuche unterstützen. Ohne Schlüssel/Modell oder bei Anbieterausfall entsteht ein ausdrücklich gekennzeichneter Vorlagenentwurf. Einzelne Ausfälle von Recherche, Topografie oder KI werden im Entwurf genannt. KI-Aufrufe verwenden `store=false`; für die Websuche werden Tourtitel, ausgewählte Ortsnamen und Koordinaten sowie bekannte Ortsnamen übermittelt. Der Schreibschritt erhält Tourtitel, Ortsnamen, Notizen, geplante Höhenwerte und Recherchetexte. Fotos und vollständige GPS-Spuren werden nicht an OpenAI gesendet. Wikipedia/OpenTopoMap erhalten die jeweiligen Suchpunkte bzw. Kachelkoordinaten. API-Nutzung kann Kosten verursachen; je Erstellung bis zu zwei KI-Anfragen mit begrenzten Suchaufrufen.

Ein vorhandener Pi-Schlüssel kann ohne Übertragung auf den Mac übernommen werden:

```sh
python3 scripts/configure_blog_pi.py --source /absoluter/pi/pfad/.env --model MODELLNAME
```

Das Skript liest `OPENAI_API_KEY` nur auf dem Pi und schreibt die BikeNavi-Konfiguration mit Dateirechten 600. Die andere Anwendung wird nicht geändert. Das reguläre Deployment erhält Pi-lokale Blogwerte, wenn die Mac-`.env` dafür keine Werte vorgibt. Ein leeres Mac-Feld löscht den Pi-Schlüssel daher nicht; zum Deaktivieren auf dem Pi beide KI-Felder entfernen. Nach Konfigurationsänderungen Backendcontainer neu erstellen. Schlüssel nicht in Git übernehmen. Zum 6. Oktober 2026 wurde der vorhandene Schlüsselzugang auf dem Pi geprüft und `gpt-5.6-luna` als verfügbares Modell konfiguriert; dies allein bestätigt noch keinen Bloglauf.

## Speicherung und Grenzen

Neue additive Tabellen: lokal `blog_points` und `blog_drafts`, auf dem Pi `blog_points` und `blog_drafts`. Die Ortsdaten werden getrennt vom versionierten Fahrtdokument gehalten, damit Fotos nicht in jeder Fahrtrevision dupliziert werden. Authentifizierte Endpunkte: `POST /v1/blog-points`, `GET /v1/rides/{id}/blog-points?after=…` (fünf Orte pro Seite), `POST /v1/rides/{id}/blog` und `GET /v1/rides/{id}/blog`. Bestehende Dokument- und Messungsformate bleiben kompatibel. Alte Clients kennen die Blogfunktion nicht.

Der Pi erstellt höchstens einen Blog gleichzeitig pro Backendprozess. Die Erstellung läuft während der Anfrage, ohne dauerhafte Jobwarteschlange. Ein Containerneustart kann einen laufenden Auftrag abbrechen; fertig gespeicherte HTML-Fassungen bleiben in PostgreSQL. Änderungen oder Löschung während der Erstellung verhindern das Speichern eines veralteten Entwurfs. Löschen/Verwerfen einer Fahrt entfernt die zugehörigen Blog-Orte und Entwürfe; lokale HTML-Exportkopien werden ebenfalls entfernt. Bereits über die Teilen-Funktion in andere Apps kopierte Dateien liegen außerhalb von BikeNavi.

Die KI untersucht die eingebetteten Kartenbilder nicht visuell. Topografische Aussagen stammen aus recherchierten Quellen und vorhandenen geplanten Höhendaten. Es gibt noch keine Serienverwaltung, keine automatische Veröffentlichung und keinen Editor für bereits bestätigte Blog-Orte. Das HTML lässt sich später in einem Blogsystem redaktionell weiterbearbeiten.

Grundlagen: [MediaWiki-Geosuche](https://www.mediawiki.org/wiki/API:Geosearch), [OpenTopoMap](https://opentopomap.org/about), [OpenAI-Websuche](https://developers.openai.com/api/docs/guides/tools-web-search) und [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses).
