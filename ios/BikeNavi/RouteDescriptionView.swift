import SwiftUI
import WebKit

struct RouteDescriptionView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var error: String?
    @State private var exportURL: URL?
    @State private var insertionNotice: String?
    @State private var readingReport: RouteDescriptionReport?
    private var saved: SavedRouteDescription? { state.routeDescriptions[state.plan.id] }
    private var visibleReport: RouteDescriptionReport? {
        guard let saved, let report = saved.report, report.planID == state.plan.id else { return nil }
        // A fresh opening only shows the current route. Once reading has begun,
        // inserted highlights may change the route without replacing the article.
        return saved.matches(state.plan) || (readingReport?.planID == report.planID && readingReport?.createdAt == report.createdAt) ? report : nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    if saved?.job.running == true {
                        HStack { ProgressView(); Text(saved!.job.statusText).font(.subheadline) }
                            .accessibilityIdentifier("routeDescriptionProgress")
                        Text("Die Erstellung läuft auf dem Pi weiter, wenn du diese Ansicht schließt.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Vorfreude auf deine Tour: Untergrund, steile Stellen und Highlights entlang deiner geplanten Strecke.")
                            .font(.subheadline)
                    }
                    if let saved, visibleReport != nil, !saved.matches(state.plan) {
                        Label("Die Planung wurde geändert. Diese Beschreibung gehört zur vorherigen Routenfassung.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                            .accessibilityIdentifier("routeDescriptionStale")
                    }
                    if let message = error ?? (saved?.requestMatches(state.plan) == true && ["failed", "interrupted"].contains(saved?.job.phase ?? "") ? saved?.job.message : nil) {
                        Text(message).font(.caption).foregroundStyle(.red)
                            .accessibilityIdentifier("routeDescriptionError")
                    }
                    if let insertionNotice {
                        Text(insertionNotice).font(.caption).foregroundStyle(Theme.forest)
                            .accessibilityIdentifier("routeHighlightInserted")
                    }
                    if let planningError = state.planningError {
                        Text(planningError).font(.caption).foregroundStyle(.red)
                    } else if state.calculating {
                        HStack { ProgressView(); Text("Route wird im Hintergrund aktualisiert …").font(.caption) }
                            .accessibilityIdentifier("routeHighlightRouting")
                    }
                    HStack {
                        Button(saved?.job.phase == "interrupted" && saved?.requestMatches(state.plan) == true ? "Fortsetzen" : visibleReport == nil ? "Routenbeschreibung erstellen" : "Neu erstellen") {
                            error = nil
                            do { try state.startRouteDescription() } catch { self.error = error.localizedDescription }
                        }.buttonStyle(.borderedProminent).tint(Theme.forest)
                            .disabled(saved?.job.running == true || state.calculating || state.plan.route == nil)
                            .accessibilityIdentifier("generateRouteDescription")
                        if visibleReport != nil, let exportURL { ShareLink(item: exportURL) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Routenbeschreibung exportieren") }
                    }
                    if state.api == nil {
                        Text("Zum Erstellen den Pi unter Einstellungen verbinden. Gespeicherte Beschreibungen bleiben offline lesbar.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Theme.paper)
                if let report = visibleReport {
                    RouteDescriptionHTML(html: report.html) { id in
                        Task {
                            do {
                                let title = try await state.insertRouteDescriptionHighlight(id)
                                error = nil
                                insertionNotice = "„\(title)“ als Zwischenziel eingefügt."
                            } catch { self.error = error.localizedDescription }
                        }
                    }.id(report.createdAt)
                        .task(id: report.createdAt) {
                            readingReport = report
                            do {
                                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RouteDescriptions", isDirectory: true)
                                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                                let url = directory.appendingPathComponent("Routenbeschreibung-\(report.planID.uuidString).html")
                                try report.exportHTML.write(to: url, atomically: true, encoding: .utf8)
                                exportURL = url
                            } catch { self.error = error.localizedDescription }
                        }
                } else {
                    ContentUnavailableView("Deine Tour entdecken", systemImage: "sparkles", description: Text("Starte die Beschreibung, sobald Start, Zwischenziele und Ziel passen."))
                }
            }
            .navigationTitle("Routenbeschreibung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .task(id: state.plan.id) {
                readingReport = nil
                exportURL = nil
                insertionNotice = nil
                error = nil
                do {
                    try await state.openRouteDescription()
                    if let saved, saved.matches(state.plan) { readingReport = saved.report }
                }
                catch is CancellationError { }
                catch { self.error = error.localizedDescription }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { state.resumeRouteDescription() } }
            .onChange(of: state.calculating) { _, calculating in
                if !calculating, state.plan.route != nil, visibleReport == nil {
                    Task {
                        do { try await state.openRouteDescription() }
                        catch is CancellationError { }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
    }
}

private struct RouteDescriptionHTML: UIViewRepresentable {
    var html: String
    var onInsert: (UUID) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onInsert: onInsert) }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var onInsert: (UUID) -> Void
        init(onInsert: @escaping (UUID) -> Void) { self.onInsert = onInsert }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, url.scheme == "bikenavi-highlight" else { decisionHandler(.allow); return }
            decisionHandler(.cancel)
            guard action.navigationType == .linkActivated, action.sourceFrame.isMainFrame,
                  action.sourceFrame.request.url?.scheme == "about", url.host == "insert", url.query == nil, url.fragment == nil,
                  let id = UUID(uuidString: String(url.path.dropFirst())) else { return }
            onInsert(id)
        }
    }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.accessibilityIdentifier = "routeDescriptionHTML"
        view.loadHTMLString(html, baseURL: nil)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.onInsert = onInsert }
}
