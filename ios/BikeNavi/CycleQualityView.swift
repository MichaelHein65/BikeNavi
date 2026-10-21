import SwiftUI

struct CycleQualityView: View {
    let route: CalculatedRoute
    var body: some View {
        Section("Wegequalität") {
            Text("Verkehrsbelastung: unbekannt. Straßenklassen sind keine Verkehrsmessung.").font(.caption)
            if let sections = route.cycleQuality, !sections.isEmpty {
                NavigationLink("Abschnitte und Datenquelle") {
                    List(Array(sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Punkt \(section.startIndex+1)–\(section.endIndex+1)").font(.headline)
                            Text("\(section.roadClass ?? "Straßenklasse unbekannt") · \(SurfaceKind(code: section.surface).title)")
                            Text(section.cycleway == true ? "Eigenständiger Radweg" : section.cycleway == false ? "Kein eigenständiger Radweg; Radstreifen nicht bewertet" : "Radwegstatus unbekannt")
                            Text(section.incline.map { "Steigung: \(Int($0.rounded())) % (OSM)" } ?? "Steigung unbekannt")
                            Text(section.source).font(.caption).foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine)
                    }.navigationTitle("Wegeabschnitte")
                }
            } else {
                Text("Für diese Route fehlen Straßenklasse und Radwegstatus. Vorhandene Beläge stehen oben; GPX-Geometrie wird nicht nachträglich klassifiziert.").font(.subheadline)
            }
        }
    }
}
