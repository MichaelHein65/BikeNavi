# Routing-Testdaten

`heidelberg-route.json` ist eine echte, am 18. September 2026 über openrouteservice berechnete öffentliche Beispielroute in Heidelberg. Sie enthält keine aufgezeichnete Fahrt und keine persönlichen Standortdaten.

Quelle: [openrouteservice / HeiGIT](https://openrouteservice.org/), Kartendaten [© OpenStreetMap-Mitwirkende](https://www.openstreetmap.org/copyright), Höhendaten gemäß [ORS-Datenquellen](https://giscience.github.io/openrouteservice/run-instance/data).

Das Fixture wird von `scripts/smoke_backend.py` erzeugt und prüft die tatsächliche Antwortstruktur gegen die Swift-Modelle. `scripts/preview_simulator.py` verwendet es für eine ausdrücklich als Beispiel bezeichnete Planung.

`heidelberg-surface-route.json` wurde am 19. September 2026 mit `scripts/check_surfaces.py` erzeugt. Diese öffentliche Beispielroute enthält tatsächlich gelieferte Abschnitte mit Asphalt und festem Schotter; die Indizes beziehen sich auf die unveränderte Routengeometrie. `scripts/preview_simulator.py --local-only --surfaces` zeigt sie ausschließlich im Simulator.
