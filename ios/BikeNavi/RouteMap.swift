import SwiftUI
import MapLibre
import CoreLocation

extension Coordinate {
    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

final class SavedPlaceAnnotation: MLNPointAnnotation {
    let place: SavedPlace
    init(place: SavedPlace) {
        self.place = place
        super.init()
        coordinate = place.coordinate.cl
        title = place.name
        subtitle = "Gespeicherter Ort"
    }
    required init?(coder: NSCoder) { nil }
}

final class NavigationMapView: MLNMapView {
    var onSizeChange: (() -> Void)?
    private var previousSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != previousSize else { return }
        previousSize = bounds.size
        onSizeChange?()
    }
}

struct RouteMap: UIViewRepresentable {
    var styleURL: String
    var route: CalculatedRoute?
    var waypoints: [Waypoint] = []
    var savedPlaces: [SavedPlace] = []
    var track: [TrackPoint] = []
    var modeSections: [RideModeSection]?
    var focus: Coordinate?
    var pointOverviewZoom: Double?
    var fitRevision: UUID?
    var follow = false
    var followHeading = false
    var marineNavigation = false
    var carNavigation = false
    var hikingNavigation = false
    var showWaterDepths = false
    var navigationPosition: Coordinate?
    var navigationHeading: Double?
    var navigationLookAhead = 500.0
    var navigationProgress: Double?
    var navigationResumeID = 0
    var colorBySurface = false
    var topOverlayInset: CGFloat = 65
    var hasStart = true
    var onNavigationSuspended: ((Bool) -> Void)?
    var onTap: ((Coordinate) -> Void)?
    var onSavedPlaceTap: ((SavedPlace) -> Void)?
    var onError: ((String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MLNMapView {
        let map = NavigationMapView(frame: .zero, styleURL: URL(string: styleURL))
        map.onSizeChange = { [weak coordinator = context.coordinator] in
            coordinator?.updateNavigationCamera()
        }
        map.delegate = context.coordinator
        map.setCenter(CLLocationCoordinate2D(latitude: 51.1, longitude: 10.2), zoomLevel: 5, animated: false)
        map.compassViewPosition = .topRight
        map.logoView.isHidden = true
        // MapLibre's attribution button remains visible, including data/style attribution.
        map.attributionButtonPosition = .bottomLeft
        map.tintColor = UIColor(Theme.forest)
        map.isRotateEnabled = !marineNavigation
        map.isPitchEnabled = !marineNavigation
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        for gesture in map.gestureRecognizers ?? [] {
            if let other = gesture as? UITapGestureRecognizer, other.numberOfTapsRequired > 1 { tap.require(toFail: other) }
        }
        map.addGestureRecognizer(tap)
        context.coordinator.map = map
        return map
    }
    static func dismantleUIView(_ map: MLNMapView, coordinator: Coordinator) {
        coordinator.resumeNavigation?.cancel()
        (map as? NavigationMapView)?.onSizeChange = nil
        map.delegate = nil
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let c = context.coordinator
        let wasFollowing = c.parent.follow
        let wasMarine = c.parent.marineNavigation
        c.parent = self
        if c.navigationResumeID != navigationResumeID {
            c.navigationResumeID = navigationResumeID
            c.resetNavigationInteraction()
        }
        map.isRotateEnabled = !marineNavigation
        map.isPitchEnabled = !marineNavigation
        if wasFollowing != follow || wasMarine != marineNavigation { c.resetNavigationInteraction() }
        if map.styleURL?.absoluteString != styleURL { map.styleURL = URL(string: styleURL) }
        let auth = CLLocationManager().authorizationStatus
        map.showsUserLocation = !(carNavigation && followHeading) && navigationPosition == nil && (auth == .authorizedAlways || auth == .authorizedWhenInUse)
        if follow && !followHeading && map.showsUserLocation {
            map.userTrackingMode = .follow
        }
        c.updateWaterDepths()
        c.redraw()
        c.updateNavigationPosition()
        if c.focus != focus, let focus {
            c.focus = focus
            map.setCenter(focus.cl, zoomLevel: pointOverviewZoom ?? 13, animated: true)
        }
        if c.fitRevision != fitRevision, let fitRevision {
            c.fitRevision = fitRevision
            c.fit()
        }
    }
    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: RouteMap
        weak var map: MLNMapView?
        let navigationPin = MLNPointAnnotation()
        var surfaceSections: [RouteSurfaceSection]?
        var routeID: UUID?
        var routeCoordinates: [Coordinate] = []
        var bicycleParking: Coordinate?
        private var routeAnnotations: [MLNAnnotation] = []
        private var trackAnnotations: [MLNAnnotation] = []
        private var waypointAnnotations: [MLNAnnotation] = []
        private var placeAnnotations: [MLNAnnotation] = []
        private var gpxAnnotations: [MLNAnnotation] = []
        private var gpxWaypoints: [GPXPoint] = []
        var points: [Waypoint] = []
        var savedPlaces: [SavedPlace] = []
        var modeSections: [RideModeSection]?
        var track: [TrackPoint] = []
        var colorBySurface = false
        var hasStart = true
        var resumeNavigation: DispatchWorkItem?
        var navigationSuspended = false
        var lastNavigationHeading: CLLocationDirection = 0
        var applyingNavigationCamera = false
        var focus: Coordinate?
        var fitRevision: UUID?
        var hasLoadedStyle = false
        var navigationResumeID = 0
        init(_ parent: RouteMap) { self.parent = parent }
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let map, gesture.state == .ended else { return }
            let location = gesture.location(in: map)
            let nearbyPlace = (map.annotations ?? []).compactMap { annotation -> (SavedPlace, CGFloat)? in
                guard let pin = annotation as? SavedPlaceAnnotation else { return nil }
                let point = map.convert(pin.coordinate, toPointTo: map)
                return (pin.place, hypot(point.x - location.x, point.y - location.y))
            }.min { $0.1 < $1.1 }
            if let nearbyPlace, nearbyPlace.1 <= 34 {
                parent.onSavedPlaceTap?(nearbyPlace.0)
                return
            }
            let c = map.convert(location, toCoordinateFrom: map)
            parent.onTap?(Coordinate(latitude: c.latitude, longitude: c.longitude))
        }
        // Recording updates must never remove the unchanged navigation route.
        // Style reloads explicitly refresh every group; ordinary updates only
        // replace the group whose geometry or appearance actually changed.
        func redraw(force: Bool = false) {
            guard let map else { return }
            let routeChanged = force || routeID != parent.route?.id
                || routeCoordinates != (parent.route?.coordinates ?? [])
                || surfaceSections != parent.route?.surfaceSections
                || colorBySurface != parent.colorBySurface
                || bicycleParking != parent.route?.bicycleParking
            if routeChanged {
                var annotations: [MLNAnnotation] = []
                if let route = parent.route, route.coordinates.count > 1 {
                    if parent.colorBySurface {
                        for section in route.coloredSections {
                            var coordinates = route.coordinates[section.startIndex...section.endIndex].map(\.cl)
                            let line = MLNPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
                            line.title = "surface:\(section.surface)"
                            annotations.append(line)
                        }
                    } else {
                        var coordinates = route.coordinates.map(\.cl)
                        let line = MLNPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
                        line.title = "route"
                        annotations.append(line)
                    }
                }
                if let parking = parent.route?.bicycleParking {
                    let pin = MLNPointAnnotation()
                    pin.coordinate = parking.cl
                    pin.title = "Rad abstellen"
                    pin.subtitle = "Zu Fuß weiter zum Ziel"
                    annotations.append(pin)
                }
                replace(&routeAnnotations, with: annotations, on: map)
                surfaceSections = parent.route?.surfaceSections
                routeID = parent.route?.id
                routeCoordinates = parent.route?.coordinates ?? []
                colorBySurface = parent.colorBySurface
                bicycleParking = parent.route?.bicycleParking
            }
            if force || modeSections != parent.modeSections || track != parent.track {
                var annotations: [MLNAnnotation] = []
                if let sections = parent.modeSections {
                    for section in sections where section.coordinates.count > 1 {
                        var coordinates = section.coordinates.map(\.cl)
                        let line = MLNPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
                        line.title = "mode:\(section.mode ?? -1)"
                        annotations.append(line)
                    }
                } else {
                    for group in Dictionary(grouping: parent.track, by: \.segment).values where group.count > 1 {
                        var coordinates = group.map { $0.coordinate.cl }
                        let line = MLNPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
                        line.title = "track"
                        annotations.append(line)
                    }
                }
                replace(&trackAnnotations, with: annotations, on: map)
                modeSections = parent.modeSections
                track = parent.track
            }
            if force || points != parent.waypoints || hasStart != parent.hasStart {
                var annotations: [MLNAnnotation] = []
                for (index, point) in parent.waypoints.enumerated() {
                    let pin = MLNPointAnnotation()
                    pin.coordinate = point.coordinate.cl
                    pin.title = point.name
                    pin.subtitle = index == 0 && parent.hasStart ? "Start" : (index == parent.waypoints.count - 1 ? "Ziel" : "\(index + (parent.hasStart ? 0 : 1))")
                    annotations.append(pin)
                }
                replace(&waypointAnnotations, with: annotations, on: map)
                points = parent.waypoints
                hasStart = parent.hasStart
            }
            if force || savedPlaces != parent.savedPlaces {
                replace(&placeAnnotations, with: parent.savedPlaces.map { SavedPlaceAnnotation(place: $0) }, on: map)
                savedPlaces = parent.savedPlaces
            }
            let imported = parent.route?.gpxTrack?.waypoints ?? []
            if force || gpxWaypoints != imported {
                replace(&gpxAnnotations, with: imported.enumerated().map { index, point in
                    let pin = MLNPointAnnotation()
                    pin.coordinate = point.coordinate.cl
                    pin.title = point.details.name ?? "GPX-Wegpunkt \(index + 1)"
                    pin.subtitle = "GPX"
                    return pin
                }, on: map)
                gpxWaypoints = imported
            }
        }

        private func replace(_ old: inout [MLNAnnotation], with new: [MLNAnnotation], on map: MLNMapView) {
            // Register the replacement before retiring the previous geometry.
            if !new.isEmpty { map.addAnnotations(new) }
            if !old.isEmpty { map.removeAnnotations(old) }
            old = new
        }
        func fit() {
            guard let map else { return }
            if let zoom = parent.pointOverviewZoom, parent.route == nil, parent.waypoints.count == 1, parent.track.isEmpty {
                map.setCenter(parent.waypoints[0].coordinate.cl, zoomLevel: zoom, animated: false)
                return
            }
            guard let annotations = map.annotations, !annotations.isEmpty else { return }
            let routeAnnotations = annotations.filter { !($0 is SavedPlaceAnnotation) }
            let target = routeAnnotations.isEmpty ? annotations : routeAnnotations
            map.showAnnotations(target, edgePadding: UIEdgeInsets(top: parent.topOverlayInset, left: 40, bottom: 45, right: 40), animated: true, completionHandler: nil)
        }
        func updateNavigationPosition() {
            if let map, let position = parent.navigationPosition {
                navigationPin.coordinate = position.cl
                if !(map.annotations ?? []).contains(where: { ($0 as AnyObject) === navigationPin }) {
                    map.addAnnotation(navigationPin)
                }
            } else {
                map?.removeAnnotation(navigationPin)
            }
            updateNavigationCamera()
            updateCarMarker()
        }

        private func updateCarMarker() {
            guard parent.carNavigation, let map, let view = map.view(for: navigationPin),
                  let arrow = view.viewWithTag(71404) else { return }
            arrow.transform = CGAffineTransform(rotationAngle: (lastNavigationHeading - map.camera.heading) * .pi / 180)
        }

        func resetNavigationInteraction() {
            resumeNavigation?.cancel()
            resumeNavigation = nil
            let wasSuspended = navigationSuspended
            navigationSuspended = false
            if wasSuspended { notifySuspension(false) }
        }

        private func notifySuspension(_ suspended: Bool) {
            let callback = parent.onNavigationSuspended
            DispatchQueue.main.async { callback?(suspended) }
        }

        func updateNavigationCamera() {
            // Remember actual travel direction even while the user explores the map.
            if let heading = parent.navigationHeading, heading.isFinite, heading >= 0 {
                lastNavigationHeading = heading
            }
            guard parent.follow, (parent.followHeading || parent.marineNavigation), !navigationSuspended,
                  !applyingNavigationCamera, let map,
                  map.bounds.width > 0, map.bounds.height > 0,
                  let position = parent.navigationPosition?.cl ?? map.userLocation?.location?.coordinate,
                  CLLocationCoordinate2DIsValid(position) else { return }
            applyingNavigationCamera = true
            defer { applyingNavigationCamera = false }
            map.userTrackingMode = .none
            map.automaticallyAdjustsContentInset = false
            if parent.marineNavigation {
                map.contentInset = .zero
                let zoom = hasLoadedStyle ? map.zoomLevel : 14
                let camera = map.camera
                camera.centerCoordinate = position
                camera.pitch = 0
                camera.heading = 0
                map.setCamera(camera, animated: false)
                map.setZoomLevel(zoom, animated: false)
                return
            }
            // The camera target (our position) sits at 80% of the map's height.
            map.contentInset = UIEdgeInsets(top: map.bounds.height * 0.6, left: 0, bottom: 0, right: 0)
            // Use a shallower car perspective; MapLibre caps both modes for the padded viewport.
            let camera = MLNMapCamera(lookingAtCenter: position, altitude: 100,
                                      pitch: parent.carNavigation ? 45 : parent.hikingNavigation ? 30 : 60, heading: lastNavigationHeading)
            let location = CLLocation(latitude: position.latitude, longitude: position.longitude)
            let lookAhead = parent.carNavigation ? min(3000, max(180, parent.navigationLookAhead)) : parent.hikingNavigation ? 150 : 500
            // Calibrate using the actual projection, including pitch, latitude and viewport size.
            // All changes are synchronous so intermediate cameras never render as animations.
            for _ in 0..<4 {
                map.setCamera(camera, animated: false)
                let farEdge = map.convert(CGPoint(x: map.bounds.midX, y: 0), toCoordinateFrom: map)
                let distance = location.distance(from: CLLocation(latitude: farEdge.latitude, longitude: farEdge.longitude))
                guard distance.isFinite, distance > 0 else { break }
                if abs(distance - lookAhead) < 0.1 { break }
                camera.altitude *= lookAhead / distance
            }
            // Curved approaches need lateral room as well as forward distance.
            // Include the upcoming path in the viewport while retaining the low anchor.
            if parent.carNavigation, let route = parent.route, let traveled = parent.navigationProgress {
                let distances = LocalRouteMetrics.distances(route)
                let indices = distances.indices.filter { distances[$0] >= traveled && distances[$0] <= traveled + lookAhead }
                let stride = max(1, indices.count / 40)
                let selected = indices.enumerated().filter { $0.offset % stride == 0 || $0.offset == indices.count - 1 }.map { $0.element }
                for _ in 0..<6 {
                    map.setCamera(camera, animated: false)
                    let outside = selected.contains { index in
                        let point = map.convert(route.coordinates[index].cl, toPointTo: map)
                        return point.x < 28 || point.x > map.bounds.width - 28 || point.y < 36 || point.y > map.bounds.height * 0.94
                    }
                    if !outside { break }
                    camera.altitude *= 1.3
                }
            }
            map.setCamera(camera, animated: false)
            updateCarMarker()
        }

        private func isManualChange(_ reason: MLNCameraChangeReason) -> Bool {
            let gestures: MLNCameraChangeReason = [.gesturePan, .gesturePinch, .gestureRotate,
                .gestureZoomIn, .gestureZoomOut, .gestureOneFingerZoom, .gestureTilt, .resetNorth]
            return !reason.intersection(gestures).isEmpty
        }

        private func suspendNavigation() {
            guard parent.follow, (parent.followHeading || parent.marineNavigation), !applyingNavigationCamera else { return }
            if !navigationSuspended { notifySuspension(true) }
            navigationSuspended = true
            resumeNavigation?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                // A finger held on the map must not trigger an automatic camera jump.
                if self.map?.gestureRecognizers?.contains(where: { $0.state == .began || $0.state == .changed }) == true {
                    self.suspendNavigation()
                    return
                }
                self.resetNavigationInteraction()
                self.updateNavigationCamera()
            }
            resumeNavigation = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
        }

        func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            if isManualChange(reason) { suspendNavigation() }
        }

        func mapView(_ mapView: MLNMapView, regionIsChangingWith reason: MLNCameraChangeReason) {
            if isManualChange(reason) { suspendNavigation() }
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            if isManualChange(reason) { suspendNavigation() }
        }

        func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
            updateNavigationCamera()
        }

        func updateWaterDepths() {
            guard let map, let style = map.style else { return }
            let identifier = "emodnet-depth"
            if parent.showWaterDepths && style.source(withIdentifier: identifier) == nil {
                let template = "https://ows.emodnet-bathymetry.eu/wms?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=emodnet:mean_multicolour,emodnet:contours&STYLES=&FORMAT=image/png&TRANSPARENT=TRUE&SRS=EPSG:3857&BBOX={bbox-epsg-3857}&WIDTH=256&HEIGHT=256"
                let source = MLNRasterTileSource(identifier: identifier, tileURLTemplates: [template], options: [
                    .tileSize: 256, .maximumZoomLevel: 14,
                    .attributionHTMLString: "Tiefen: <a href=\"https://emodnet.ec.europa.eu/en/bathymetry\">EMODnet Bathymetry Consortium · DTM 2024 · CC BY 4.0</a> · Nicht zur Navigation geeignet"
                ])
                style.addSource(source)
                let layer = MLNRasterStyleLayer(identifier: identifier, source: source)
                layer.rasterOpacity = NSExpression(forConstantValue: 0.7)
                if let marks = style.layer(withIdentifier: "seamarks") { style.insertLayer(layer, below: marks) }
                else { style.addLayer(layer) }
            }
            style.layer(withIdentifier: identifier)?.isVisible = parent.showWaterDepths
            let tag = 71304
            if parent.showWaterDepths && map.viewWithTag(tag) == nil {
                let label = UILabel()
                label.tag = tag
                label.text = "EMODnet · nicht zur Navigation geeignet"
                label.font = .systemFont(ofSize: 10, weight: .semibold)
                label.textColor = .label
                label.backgroundColor = .secondarySystemBackground.withAlphaComponent(0.95)
                label.layer.cornerRadius = 4
                label.clipsToBounds = true
                label.accessibilityIdentifier = "waterDepthNotice"
                label.translatesAutoresizingMaskIntoConstraints = false
                map.addSubview(label)
                NSLayoutConstraint.activate([label.trailingAnchor.constraint(equalTo: map.trailingAnchor, constant: -8), label.bottomAnchor.constraint(equalTo: map.bottomAnchor, constant: -8)])
            }
            map.viewWithTag(tag)?.isHidden = !parent.showWaterDepths
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            updateWaterDepths()
            redraw(force: true)
            updateNavigationPosition()
            if !hasLoadedStyle && !(parent.follow && (parent.followHeading || parent.marineNavigation)) { fit() }
            hasLoadedStyle = true
        }
        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            parent.onError?("Karte konnte nicht geladen werden. Prüfe die Verbindung oder dein Offline-Paket.")
        }
        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            if let title = annotation.title, title.hasPrefix("surface:"), let code = Int(title.dropFirst(8)) {
                return UIColor(SurfaceKind(code: code).color)
            }
            if let title = annotation.title, title.hasPrefix("mode:"), let code = Int(title.dropFirst(5)) {
                return UIColor(BikeTelemetryView.modeColor(code) ?? .gray)
            }
            return annotation.title == "track" ? .systemOrange : parent.carNavigation ? .systemBlue : parent.marineNavigation ? UIColor(red: 0.04, green: 0.18, blue: 0.27, alpha: 1) : UIColor(Theme.forest)
        }
        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat { parent.marineNavigation ? 3 : parent.carNavigation ? 7 : 5 }
        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            if (annotation as AnyObject) === navigationPin {
                let view = MLNAnnotationView(reuseIdentifier: "navigation-position")
                let size: CGFloat = parent.carNavigation ? 34 : 20
                view.frame = CGRect(x: 0, y: 0, width: size, height: size)
                view.backgroundColor = .systemBlue
                view.layer.cornerRadius = size / 2
                view.layer.borderColor = UIColor.white.cgColor
                view.layer.borderWidth = 3
                if parent.carNavigation {
                    let arrow = UIImageView(image: UIImage(systemName: "location.north.fill"))
                    arrow.tag = 71404
                    arrow.frame = view.bounds.insetBy(dx: 8, dy: 8)
                    arrow.tintColor = .white
                    arrow.contentMode = .scaleAspectFit
                    view.addSubview(arrow)
                    view.accessibilityLabel = "Aktuelle Fahrtrichtung"
                }
                return view
            }
            guard annotation is MLNPointAnnotation else { return nil }
            if annotation.title == "Rad abstellen" {
                let view = MLNAnnotationView(reuseIdentifier: "bicycle-parking")
                view.frame = CGRect(x: 0, y: 0, width: 42, height: 42)
                view.backgroundColor = .systemOrange
                view.layer.zPosition = 100
                view.layer.cornerRadius = 21
                view.layer.borderWidth = 3
                view.layer.borderColor = UIColor.white.cgColor
                let icon = UIImageView(image: UIImage(systemName: "bicycle"))
                icon.frame = view.bounds.insetBy(dx: 8, dy: 8)
                icon.tintColor = .white
                icon.contentMode = .scaleAspectFit
                view.addSubview(icon)
                view.accessibilityLabel = "Rad abstellen · zu Fuß weiter zum Ziel"
                return view
            }
            if annotation is SavedPlaceAnnotation {
                let view = MLNAnnotationView(reuseIdentifier: "saved-place")
                view.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
                view.backgroundColor = UIColor(Theme.lime)
                view.layer.cornerRadius = 10
                view.layer.borderWidth = 2
                view.layer.borderColor = UIColor(Theme.forest).cgColor
                let image = UIImageView(image: UIImage(systemName: "bookmark.fill"))
                image.frame = view.bounds.insetBy(dx: 7, dy: 7)
                image.tintColor = UIColor(Theme.forest)
                image.contentMode = .scaleAspectFit
                view.addSubview(image)
                return view
            }
            let view = MLNAnnotationView(reuseIdentifier: "waypoint")
            view.frame = CGRect(x: 0, y: 0, width: 34, height: 34)
            view.backgroundColor = UIColor(Theme.forest)
            view.layer.cornerRadius = 17
            view.layer.borderWidth = 3
            view.layer.borderColor = UIColor.white.cgColor
            let label = UILabel(frame: view.bounds)
            label.text = (annotation.subtitle ?? "") == "Start" ? "S" : ((annotation.subtitle ?? "") == "Ziel" ? "Z" : (annotation.subtitle ?? ""))
            label.textColor = .white
            label.textAlignment = .center
            label.font = .boldSystemFont(ofSize: 13)
            view.addSubview(label)
            return view
        }
        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool { true }
    }
}
