# P5: Audit realer Bosch-Fahrdaten

21.10.2026, ausschließlich lesender Export aus BikeNavi auf dem Pi; Rohdaten lokal unter ignoriertem `artifacts/energy-audit/`, nicht im Repository. Keine Fahrtpositionen, Namen oder Gerätekennungen in diesem Bericht. Auswertung mit dem tatsächlich in der App verwendeten `EnergyAudit.inspect` über `scripts/audit_energy.swift`.

## Bestand und Messgüte

51 Fahrrad-Fahrten, 274.396 sparse Messpakete; 250.595 davon mit zugeordnetem GPS-Punkt. 805 Akku-, 191.292 Modus-, 63.189 Motorleistungs- und 27.018 Fahrerleistungswerte. Keine gespeicherten Ladeflags, Kadenz-/Geschwindigkeitswerte aus Bosch in diesem Bestand. Fehlen bedeutet unbekannt; ein Ladeereignis lässt sich hier nur indirekt durch SOC-Anstieg erkennen. GPS-Geschwindigkeit gehört zur separaten Positionsaufzeichnung.

| Messgröße | Median Paketabstand | 95. Perzentil | Größte Lücke innerhalb einer Fahrt |
| --- | ---: | ---: | ---: |
| Akku-Prozent | 82,68 s | 347,01 s | 1.957,71 s |
| Unterstützungsmodus | 0,49 s | 0,65 s | 1.626,85 s |
| Motorleistung | 0,81 s | 2,37 s | 1.863,65 s |
| Fahrerleistung | 2,02 s | 7,38 s | 1.864,82 s |

Abstände pro Messgröße und Fahrt, nur positive Differenzen, keine Überbrückung zwischen verschiedenen Touren. Empfangszeiten sind keine garantierten Sensorabtastzeiten. Akku ist ganzzahliges SOC (%), Leistungen W, GPS-Distanz m. Nutzbare Wh-Kapazität und elektrischer Energiezähler fehlen. Mechanische Motorleistung darf nicht als entnommene Akkuenergie integriert werden.

## Ergebnis der konservativen Qualifikation

| Erste nicht erfüllte Bedingung | Fahrten |
| --- | ---: |
| GPS-Abdeckung oder Genauigkeit unzureichend | 16 |
| Zu wenige Akku-Stützstellen | 12 |
| Akkuabnahme unter fünf Prozentpunkten | 8 |
| Bike-Zuordnung fehlt oder wechselt | 6 |
| GPS-Lücke/Pausenwechsel im Akkubereich | 4 |
| Fahrmodus wechselt/ist unzureichend belegt | 3 |
| Akkuanstieg oder über 30 Minuten Messlücke | 1 |
| Geeignet | 1 |

**Keine validierbare Kalibriergruppe.** Deshalb bleibt die numerische Zielakku-Prognose gesperrt. Es gibt auf diesen Daten keinen seriös berichtbaren Holdout-MAE, Bias oder Intervallabdeckungswert; synthetische Tests werden nicht als reale Validierung ausgegeben. Das ist der kritische Dateneinwand für P5, nicht ein Grund, Navigation zu blockieren.

## Implementierte Freigabe und nächste Datengrundlage

`EnergyEstimate.swift` qualifiziert ganze Fahrten und verhindert Mehrfachverwendung derselben Fahrt. Mindestens acht geeignete Fahrten desselben Bikes und Modus; neueste mindestens drei als Holdout. Medianverbrauch ist zugleich die konstante Verbrauchs-Baseline. Kein komplexeres Modell wird als besser ausgegeben. Bandbreite aus Trainingsminimum/-maximum mit Zuschlag; Holdout darf die Trainingsgrenzen nicht beeinflussen. Freigabe bei ≥80 % Abdeckung und MAE ≤max(0,5 Prozentpunkte/km, 35 % Medianverbrauch). Geländedichte (Anstieg/km) der Reststrecke muss im Trainingsbereich ±5 m/km liegen; Modus, aktueller SOC und verbleibende Distanz werden geprüft. Höhen aus GPS bleiben verrauscht, eine 3-m-Schwelle dämpft kleine Schwankungen. Die resultierende Spanne ist empirisch, keine kalibrierte Wahrscheinlichkeitsaussage.

Für die nächste reale Abnahme werden mindestens sieben weitere geeignete Fahrten der betreffenden Bike-/Modusgruppe benötigt, davon mindestens drei zeitlich zurückgehalten. Ausreichend lang, ohne Ladung oder Akkuwechsel; GPS und Bluetooth durchgehend, unterschiedliche normale Reststrecken und passende Geländeformen. Kein künstliches Entladen nötig. Nutzbare Kapazität erst bei verlässlichem Nutzer-/Gerätenachweis ergänzen; Akkuwechsel, Wind, Temperatur und Fahrstil separat erfassen. Vor Freigabe Fehler nach ganzen Touren einschließlich Bias, MAE und Abdeckung berichten. Im jetzigen Stand bleibt die Anzeige bei fehlender Evidenz stumm bezüglich Zahlen.
