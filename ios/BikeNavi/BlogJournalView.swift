import SwiftUI
import PhotosUI
import AVFoundation
import WebKit

struct BlogPointEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var rideID: UUID
    var existingPoint: BlogPoint?
    var fromJournal = false
    @State private var otherPoints: [BlogPoint] = []
    @State private var position = 0
    private var photoLocationRequired: Bool { fromJournal && existingPoint == nil }
    @FocusState private var editing: Bool
    @State private var coordinate: Coordinate?
    @State private var capturedAt = Date().timeIntervalSince1970
    @State private var title = ""
    @State private var note = ""
    @State private var photo: Data?
    @State private var selection: PhotosPickerItem?
    @State private var showCamera = false
    @State private var loadingPhoto = false
    @State private var locating = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(existingPoint == nil ? "Ein kleiner Stopp. Eine große Erinnerung." : "Deine Station bearbeiten.").font(.title2.bold())
                    Text(photoLocationRequired ? "Wähle ein Foto mit gespeichertem Standort und platziere die Station in deiner Tour." : "Titel, Notiz und Foto bleiben offline gespeichert und werden bei erreichbarem Pi übertragen.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Dein Moment") {
                    TextField("Name des Ortes", text: $title).focused($editing).accessibilityIdentifier("blogPointTitle")
                    TextField("Was möchtest du dir merken?", text: $note, axis: .vertical).focused($editing)
                        .lineLimit(3...8).accessibilityIdentifier("blogPointNote")
                    if let photo, let image = UIImage(data: photo) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 250)
                        Button("Foto entfernen", role: .destructive) { self.photo = nil; selection = nil; if photoLocationRequired { coordinate = nil } }
                    }
                    PhotosPicker(selection: $selection, matching: .images, preferredItemEncoding: .current) { Label("Foto auswählen", systemImage: "photo") }
                        .disabled(loadingPhoto)
                    if !fromJournal && UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { Task { await openCamera() } } label: { Label("Foto aufnehmen", systemImage: "camera") }
                    }
                    if loadingPhoto { ProgressView("Foto wird vorbereitet …") }
                }
                Section("Standort der Station") {
                    if let coordinate {
                        Label(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude), systemImage: "mappin.circle.fill")
                            .accessibilityIdentifier("blogPointCoordinate")
                    } else {
                        Text(photoLocationRequired ? "Wähle ein Bild mit GPS-Standort. Fotos ohne Standort können nicht als Nachtrag gespeichert werden." : "Für diesen Ort wird eine aktuelle GPS-Position benötigt.").foregroundStyle(.secondary)
                    }
                    if !fromJournal {
                        Button("Aktuellen Standort übernehmen") { Task { await refreshLocation() } }.disabled(locating)
                        if locating { ProgressView("Standort wird aktualisiert …") }
                    }
                    Text(fromJournal ? "Bei einem Foto mit GPS-Daten wird dessen Standort übernommen. Ohne Bildstandort bleibt beim Bearbeiten der bisherige Ort erhalten." : "Der Standort wird beim Öffnen festgehalten. Wähle nur Fotos, die zu diesem Ort gehören.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if fromJournal {
                    Section("Reihenfolge im Blog") {
                        Picker("Station einfügen", selection: $position) {
                            Text("1 · An den Anfang").tag(0)
                            ForEach(Array(otherPoints.enumerated()), id: \.element.id) { index, point in
                                Text("\(index + 2) · Nach \(point.title)").tag(index + 1)
                            }
                        }.accessibilityIdentifier("blogPointPosition")
                        Text("Die gewählte Reihenfolge gilt für das Tagebuch und die nächste Blogfassung.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let message { Section { Text(message).foregroundStyle(.red) } }
            }.navigationTitle(existingPoint != nil ? "Station bearbeiten" : (fromJournal ? "Station hinzufügen" : "Blog-Ort festhalten")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Text fertig") { editing = false }.accessibilityIdentifier("blogKeyboardDone")
                    }
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") { save() }.accessibilityIdentifier("saveBlogPoint")
                            .disabled(coordinate == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (photo == nil && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || loadingPhoto)
                    }
                }
                .task {
                    do {
                        let points = try state.store.blogPoints(rideID: rideID)
                        otherPoints = points.filter { $0.id != existingPoint?.id }
                        position = existingPoint.flatMap { point in points.firstIndex(where: { $0.id == point.id }) } ?? otherPoints.count
                        if let point = existingPoint {
                            coordinate = point.coordinate; capturedAt = point.capturedAt
                            title = point.title; note = point.note; photo = point.photo
                        } else if !fromJournal { await refreshLocation() }
                    } catch { message = error.localizedDescription }
                }
                .onChange(of: selection) { _, item in
                    guard let item else { return }
                    loadingPhoto = true
                    Task {
                        defer { loadingPhoto = false }
                        do {
                            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                                throw APIError(status: 0, message: "Dieses Foto konnte nicht gelesen werden.")
                            }
                            let prepared = try compressed(image)
                            if fromJournal {
                                if let location = BlogPhotoLocation.coordinate(in: data) {
                                    coordinate = location
                                    message = nil
                                } else if photoLocationRequired {
                                    coordinate = nil
                                    message = "Dieses Foto enthält keinen GPS-Standort. Bitte wähle das Originalfoto mit Standortdaten."
                                } else { message = nil }
                            } else { message = nil }
                            photo = prepared
                        } catch { message = error.localizedDescription }
                    }
                }
                .sheet(isPresented: $showCamera) {
                    JournalCamera { image in
                        showCamera = false
                        guard let image else { return }
                        do { photo = try compressed(image); message = nil } catch { message = error.localizedDescription }
                    }.ignoresSafeArea()
                }
        }
    }

    private func refreshLocation() async {
        guard !locating else { return }
        locating = true; message = nil
        defer { locating = false }
        do {
            coordinate = try await state.location.journalCoordinate()
            capturedAt = Date().timeIntervalSince1970
            message = nil
        } catch is CancellationError { }
        catch { message = error.localizedDescription }
    }

    private func compressed(_ image: UIImage) throws -> Data {
        let ratio = min(1, 1280 / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * ratio), height: max(1, image.size.height * ratio))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.8, 0.6, 0.4, 0.2] {
            if let data = rendered.jpegData(compressionQuality: quality), data.count <= 768 * 1024 { return data }
        }
        throw APIError(status: 0, message: "Dieses Foto ist zu groß. Bitte ein anderes Bild wählen.")
    }

    private func openCamera() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var granted = status == .authorized
        if status == .notDetermined { granted = await AVCaptureDevice.requestAccess(for: .video) }
        if granted { showCamera = true }
        else { message = "Erlaube den Kamerazugriff in den iPhone-Einstellungen oder wähle ein vorhandenes Foto." }
    }

    private func save() {
        guard let coordinate else { return }
        do {
            var point = existingPoint ?? BlogPoint(rideID: rideID, coordinate: coordinate, capturedAt: capturedAt, title: "", note: "")
            point.coordinate = coordinate
            point.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            point.note = String(note.prefix(4000)); point.photo = photo
            var insertionPosition: Int?
            if fromJournal {
                let current = try state.store.blogPoints(rideID: rideID).filter { $0.id != point.id }
                if position == 0 { insertionPosition = 0 }
                else if otherPoints.indices.contains(position - 1),
                        let index = current.firstIndex(where: { $0.id == otherPoints[position - 1].id }) {
                    insertionPosition = index + 1
                } else { throw APIError(status: 0, message: "Die Reihenfolge wurde inzwischen geändert. Bitte das Formular erneut öffnen.") }
            }
            try state.saveBlogPoint(point, at: insertionPosition, original: existingPoint)
            dismiss()
        } catch { message = error.localizedDescription }
    }
}

private struct JournalCamera: UIViewControllerRepresentable {
    var completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) { }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var completion: (UIImage?) -> Void
        init(_ completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion(info[.originalImage] as? UIImage)
        }
    }
}

/// Shared actions at the top of both the ride detail and its journal.
struct RideBlogActions: View {
    @EnvironmentObject var state: AppState
    var rideID: UUID
    var showJournalLink = true
    @State private var draft: BlogDraft?
    @State private var exportURL: URL?
    private var job: BlogGenerationProgress? { state.blogGeneration[rideID] }
    private var generating: Bool { job?.isRunning == true }
    @State private var showPreview = false
    @State private var previewLoading = true
    @State private var message: String?
    private var finished: Bool { state.records.first(where: { $0.id == rideID && !$0.deleted })?.document.recordingState == .finished }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Dein Tourblog", systemImage: "book.pages.fill").font(.headline).foregroundStyle(Theme.accent)
            if let job {
                VStack(alignment: .leading, spacing: 6) {
                    Text(job.title).font(.subheadline.bold())
                    if job.isRunning {
                        if job.step > 0 {
                            ProgressView(value: Double(job.step - 1), total: 4).tint(Theme.forest)
                            Text("Schritt \(job.step) von 4 · die Schritte dauern unterschiedlich lange").font(.caption).foregroundStyle(.secondary)
                        } else { ProgressView() }
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let elapsed = max(0, Int(context.date.timeIntervalSince1970 - job.startedAt))
                            Text("Seit \(elapsed / 60):\(String(format: "%02d", elapsed % 60)) min · Du kannst diese Ansicht verlassen.")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        if job.connectionInterrupted {
                            Text("Verbindung kurz unterbrochen · der Pi-Auftrag läuft unabhängig weiter. Rückmeldung wird erneut abgerufen.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let error = job.message { Text(error).font(.caption).foregroundStyle(.red) }
                }.accessibilityIdentifier("blogGenerationProgress")
            }
            if let draft {
                Button { previewLoading = true; showPreview = true } label: {
                    Label("Blog ansehen", systemImage: "doc.richtext").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).tint(Theme.forest).accessibilityIdentifier("previewBlog")
            }
            Button { Task { await generate() } } label: {
                Label(draft == nil ? "Blog erstellen" : "Neue Blogfassung erstellen", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.bordered).tint(Theme.forest)
                .disabled(generating || !finished).accessibilityIdentifier("generateBlog")
            if let draft {
                Text(draft.mode == "openai" ? "KI-Blog · \(draft.sourceCount) Ortsquellen" : "Vorlagenentwurf · \(draft.sourceCount) Ortsquellen").font(.caption).foregroundStyle(.secondary)
                if let exportURL { ShareLink(item: exportURL) { Label("HTML exportieren", systemImage: "square.and.arrow.up") } }
                if !generating {
                    ForEach(draft.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if !finished { Text("Bitte die Fahrt zuerst speichern und beenden.").font(.caption).foregroundStyle(.secondary) }
            if showJournalLink {
                NavigationLink { BlogJournalView(rideID: rideID) } label: {
                    Label("Orte & Notizen öffnen", systemImage: "photo.on.rectangle")
                }.accessibilityIdentifier("openBlogJournal")
            }
            if let message { Text(message).font(.caption).foregroundStyle(.red) }
        }
        .task(id: rideID) {
            load()
            await state.resumeBlogGeneration(rideID: rideID)
            load()
            guard let api = state.api else { return }
            do {
                let remote: BlogDraft = try await api.request("/v1/rides/\(rideID.uuidString)/blog")
                try state.store.saveBlogDraft(remote)
                load()
            } catch let error as APIError where error.status == 404 { }
            catch { message = "Blog vom Pi gerade nicht abrufbar. Eine lokale Fassung bleibt verfügbar." }
        }
        .onChange(of: job?.phase) { _, phase in if phase == "completed" { load() } }
        .onChange(of: state.synchronizing) { _, syncing in if !syncing { load() } }
        .sheet(isPresented: $showPreview) {
            NavigationStack {
                if let draft {
                    JournalHTMLPreview(html: draft.html, loading: $previewLoading)
                        .overlay { if previewLoading { ProgressView("Blog wird geöffnet …").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
                        .navigationTitle("Dein Blog").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showPreview = false } } }
                }
            }
        }
    }
    private func load() {
        do { draft = try state.store.blogDraft(rideID: rideID); exportURL = try draft?.export() }
        catch { message = error.localizedDescription }
    }
    private func generate() async {
        message = nil
        defer { load() }
        do { _ = try await state.generateBlog(rideID: rideID); load(); previewLoading = true; showPreview = true }
        catch { if job?.message == nil { message = error.localizedDescription } }
    }
}

struct BlogJournalView: View {
    @EnvironmentObject var state: AppState
    var rideID: UUID
    @State private var points: [BlogPoint] = []
    @State private var pending = 0
    @State private var showAdd = false
    @State private var editingPoint: BlogPoint?
    @State private var message: String?
    var body: some View {
        List {
            Section("Dein Blog") { RideBlogActions(rideID: rideID, showJournalLink: false) }
            Section {
                Text("\(points.count) \(points.count == 1 ? "Ort" : "Orte") · \(pending) zur Übertragung vorgemerkt").font(.caption).foregroundStyle(.secondary)
                Button { Task { await state.sync(); load() } } label: { Label("Mit Pi abgleichen", systemImage: "arrow.triangle.2.circlepath") }
                    .disabled(state.synchronizing)
            }
            Section("Deine Lieblingsmomente") {
                Button { showAdd = true } label: { Label("Station hinzufügen", systemImage: "plus.circle") }
                    .accessibilityIdentifier("addBlogPoint").disabled(points.count >= 50)
                if points.isEmpty { Text("Sammle Stationen während der Fahrt oder füge nachträglich ein Foto mit Standort hinzu.").foregroundStyle(.secondary) }
                ForEach(Array(points.enumerated()), id: \.element.id) { i, point in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(i + 1). \(point.title)").font(.headline)
                        Button { editingPoint = point } label: { Label("Station bearbeiten", systemImage: "pencil") }
                            .accessibilityIdentifier("editBlogPoint-\(i)")
                        if let data = point.photo, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        if !point.note.isEmpty { Text(point.note) }
                        Text(Date(timeIntervalSince1970: point.capturedAt), format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.red) }
        }.navigationTitle("Tourtagebuch & Blog").navigationBarTitleDisplayMode(.inline)
            .task { load() }
            .sheet(isPresented: $showAdd, onDismiss: load) { BlogPointEditor(rideID: rideID, fromJournal: true) }
            .sheet(item: $editingPoint, onDismiss: load) { point in BlogPointEditor(rideID: rideID, existingPoint: point, fromJournal: true) }
            .onChange(of: state.synchronizing) { _, syncing in if !syncing { load() } }
    }
    private func load() {
        do {
            points = try state.store.blogPoints(rideID: rideID)
            pending = try state.store.blogPoints(rideID: rideID, pendingOnly: true).count
        } catch { message = error.localizedDescription }
    }
}

private struct JournalHTMLPreview: UIViewRepresentable {
    var html: String
    @Binding var loading: Bool
    func makeCoordinator() -> Coordinator { Coordinator($loading) }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loading: Binding<Bool>
        init(_ loading: Binding<Bool>) { self.loading = loading }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.accessibilityIdentifier = "blogHTMLReady"
            loading.wrappedValue = false
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loading.wrappedValue = false }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loading.wrappedValue = false }
    }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.accessibilityIdentifier = "blogHTMLLoading"
        view.loadHTMLString(html, baseURL: nil)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) { }
}
