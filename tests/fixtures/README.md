# Routing-Testdaten

`heidelberg-route.json` ist eine echte, am 18. September 2026 über openrouteservice berechnete öffentliche Beispielroute in Heidelberg. Sie enthält keine aufgezeichnete Fahrt und keine persönlichen Standortdaten.

Quelle: [openrouteservice / HeiGIT](https://openrouteservice.org/), Kartendaten [© OpenStreetMap-Mitwirkende](https://www.openstreetmap.org/copyright), Höhendaten gemäß [ORS-Datenquellen](https://giscience.github.io/openrouteservice/run-instance/data).

Das Fixture wird von `scripts/smoke_backend.py` erzeugt und prüft die tatsächliche Antwortstruktur gegen die Swift-Modelle. `scripts/preview_simulator.py` verwendet es für eine ausdrücklich als Beispiel bezeichnete Planung.

`heidelberg-surface-route.json` wurde am 19. September 2026 mit `scripts/check_surfaces.py` erzeugt. Diese öffentliche Beispielroute enthält tatsächlich gelieferte Abschnitte mit Asphalt und festem Schotter; die Indizes beziehen sich auf die unveränderte Routengeometrie. `scripts/preview_simulator.py --local-only --surfaces` zeigt sie ausschließlich im Simulator.

`heidelberg-elevation-route.json` verwendet dieselbe öffentliche Geometrie wie `heidelberg-surface-route.json`. Am 24. September 2026 wurden die ursprünglichen Höhen entfernt und die neue Nachladefunktion mit echten Höhen aus [openrouteservice Elevation / SRTM](https://github.com/GIScience/openelevationservice) geprüft: 175 entlang der Strecke verteilte Punkte, Dreipunktglättung und 3-m-Schwelle für die Summen. Die Darstellung als lokale Planung demonstriert die Höhenanreicherung; die Beispielgeometrie selbst stammt weiterhin aus der älteren ORS-Beispielroute. Keine privaten Standort- oder Fahrtaufzeichnungen. `scripts/seed_gallery.py --elevation` lädt diese Planung für die Bildschirmprüfung; die synthetische Beispielaufzeichnung bleibt unverändert.

- `BIKENAVI_START_LOCATION_TEST` ist eine reine Debug-UI-Fixture: synthetische Beispieltour in Heidelberg, 120 Sekunden alte Ausgangsposition, veraltete Fehlermarkierung und wahlweise frischer Fix nach fünf Sekunden (`delayed`), kein Fix (`timeout`) oder verweigerte Berechtigung (`denied`). Sie ersetzt die echte Standortquelle ausschließlich für die Simulatorregression in `RideLocationTests`; keine Aussage über realen GPS-Empfang. Die Tests auf einem dedizierten Simulator ausführen.

`blog-photo-gps-example.jpg` ist ein vollständig synthetisches, beschriftetes Testbild mit dem öffentlichen Heidelberger GPS-Punkt 49.414601, 8.681496. Kein privates Reisefoto. `seed_gallery.py --journal` importiert es ausschließlich in den Dokumentationssimulator, um die echte Fotoauswahl und die GPS-Übernahme zu prüfen.


`blog_progress_server.py` ist ein ausschließlich lokaler, künstlich verzögerter HTTPS-Backendserver für `BlogProgressUITests`. Er verwendet eine temporäre SQLite-Datei, kontrollierte 503-Anbieterantworten und einen Vorlagentext, keine echten Schlüssel, Pi-Zugriffe oder KI-Anfragen. Auf dem dedizierten Dokumentationssimulator vorher `seed_gallery.py --elevation --journal --blog docs/examples/heidelberg-blog.html` ausführen. Temporäres TLS-Zertifikat für `127.0.0.1` erzeugen und dort über `simctl keychain add-root-cert` vertrauen; mit `.venv/bin/python -m uvicorn blog_progress_server:app --app-dir tests/fixtures --host 127.0.0.1 --port 18443 --ssl-keyfile KEY --ssl-certfile CERT` starten. Der Test überspringt sich ohne den erreichbaren Fixture-Server. Zertifikat/Schlüssel/Datenbank bleiben außerhalb von Git.
