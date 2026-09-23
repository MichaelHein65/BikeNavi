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
    var fitRevision: UUID?
    var follow = false
    var followHeading = false
    var navigationPosition: Coordinate?
    var navigationHeading: Double?
    var colorBySurface = false
    var topOverlayInset: CGFloat = 65
    var hasStart = true
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
        c.parent = self
        if wasFollowing != follow { c.resetNavigationInteraction() }
        if map.styleURL?.absoluteString != styleURL { map.styleURL = URL(string: styleURL) }
        let auth = CLLocationManager().authorizationStatus
        map.showsUserLocation = navigationPosition == nil && (auth == .authorizedAlways || auth == .authorizedWhenInUse)
        if follow && !followHeading && map.showsUserLocation {
            map.userTrackingMode = .follow
        }
        if c.routeID != route?.id || c.surfaceSections != route?.surfaceSections || c.points != waypoints || c.savedPlaces != savedPlaces || c.trackCount != track.count || c.modeSections != modeSections || c.colorBySurface != colorBySurface || c.hasStart != hasStart {
            c.redraw()
        }
        c.updateNavigationPosition()
        if c.focus != focus, let focus {
            c.focus = focus
            map.setCenter(focus.cl, zoomLevel: 13, animated: true)
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
        var points: [Waypoint] = []
        var savedPlaces: [SavedPlace] = []
        var modeSections: [RideModeSection]?
        var trackCount = -1
        var colorBySurface = false
        var hasStart = true
        var resumeNavigation: DispatchWorkItem?
        var navigationSuspended = false
        var lastNavigationHeading: CLLocationDirection = 0
        var applyingNavigationCamera = false
        var focus: Coordinate?
        var fitRevision: UUID?
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
        func redraw() {
            guard let map else { return }
            if let annotations = map.annotations { map.removeAnnotations(annotations) }
            if let route = parent.route, route.coordinates.count > 1 {
                if parent.colorBySurface {
                    for section in route.coloredSections {
                        var coordinates = route.coordinates[section.startIndex...section.endIndex].map(\.cl)
                        let line = MLNPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
                        line.title = "surface:\(section.surface)"
                        map.addAnnotation(line)
                    }
                } else {
                    var coordinates = route.coordinates.map(\.cl)
                    let line = MLNPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
                    line.title = "route"
                    map.addAnnotation(line)
                }
            }
            if let sections = parent.modeSections {
                for section in sections where section.coordinates.count > 1 {
                    var coordinates = section.coordinates.map(\.cl)
                    let line = MLNPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
                    line.title = "mode:\(section.mode ?? -1)"
                    map.addAnnotation(line)
                }
            } else {
            for group in Dictionary(grouping: parent.track, by: \.segment).values where group.count > 1 {
                var coordinates = group.map { $0.coordinate.cl }
                let line = MLNPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
                line.title = "track"
                map.addAnnotation(line)
            }
            }
            for (index, point) in parent.waypoints.enumerated() {
                let pin = MLNPointAnnotation()
                pin.coordinate = point.coordinate.cl
                pin.title = point.name
                pin.subtitle = index == 0 && parent.hasStart ? "Start" : (index == parent.waypoints.count - 1 ? "Ziel" : "\(index + (parent.hasStart ? 0 : 1))")
                map.addAnnotation(pin)
            }
            for place in parent.savedPlaces {
                map.addAnnotation(SavedPlaceAnnotation(place: place))
            }
            surfaceSections = parent.route?.surfaceSections
            routeID = parent.route?.id
            points = parent.waypoints
            savedPlaces = parent.savedPlaces
            modeSections = parent.modeSections
            trackCount = parent.track.count
            colorBySurface = parent.colorBySurface
            hasStart = parent.hasStart
        }
        func fit() {
            guard let map, let annotations = map.annotations, !annotations.isEmpty else { return }
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
        }

        func resetNavigationInteraction() {
            resumeNavigation?.cancel()
            resumeNavigation = nil
            navigationSuspended = false
        }

        func updateNavigationCamera() {
            // Remember actual travel direction even while the user explores the map.
            if let heading = parent.navigationHeading, heading.isFinite, heading >= 0 {
                lastNavigationHeading = heading
            }
            guard parent.follow, parent.followHeading, !navigationSuspended,
                  !applyingNavigationCamera, let map,
                  map.bounds.width > 0, map.bounds.height > 0,
                  let position = parent.navigationPosition?.cl ?? map.userLocation?.location?.coordinate,
                  CLLocationCoordinate2DIsValid(position) else { return }
            applyingNavigationCamera = true
            defer { applyingNavigationCamera = false }
            map.userTrackingMode = .none
            map.automaticallyAdjustsContentInset = false
            // The camera target (our position) sits at 80% of the map's height.
            map.contentInset = UIEdgeInsets(top: map.bounds.height * 0.6, left: 0, bottom: 0, right: 0)
            // Request the SDK maximum; MapLibre also caps pitch for the padded viewport
            // so the visible ground cannot cross the horizon.
            let camera = MLNMapCamera(lookingAtCenter: position, altitude: 100,
                                      pitch: 60, heading: lastNavigationHeading)
            let location = CLLocation(latitude: position.latitude, longitude: position.longitude)
            // Calibrate using the actual projection, including pitch, latitude and viewport size.
            // All changes are synchronous so intermediate cameras never render as animations.
            for _ in 0..<4 {
                map.setCamera(camera, animated: false)
                let farEdge = map.convert(CGPoint(x: map.bounds.midX, y: 0), toCoordinateFrom: map)
                let distance = location.distance(from: CLLocation(latitude: farEdge.latitude, longitude: farEdge.longitude))
                guard distance.isFinite, distance > 0 else { break }
                if abs(distance - 500) < 0.1 { break }
                camera.altitude *= 500 / distance
            }
            map.setCamera(camera, animated: false)
        }

        private func isManualChange(_ reason: MLNCameraChangeReason) -> Bool {
            let gestures: MLNCameraChangeReason = [.gesturePan, .gesturePinch, .gestureRotate,
                .gestureZoomIn, .gestureZoomOut, .gestureOneFingerZoom, .gestureTilt, .resetNorth]
            return !reason.intersection(gestures).isEmpty
        }

        private func suspendNavigation() {
            guard parent.follow, parent.followHeading, !applyingNavigationCamera else { return }
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

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            redraw()
            updateNavigationPosition()
            if !(parent.follow && parent.followHeading) { fit() }
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
            return annotation.title == "track" ? .systemOrange : UIColor(Theme.forest)
        }
        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat { 5 }
        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            if (annotation as AnyObject) === navigationPin {
                let view = MLNAnnotationView(reuseIdentifier: "navigation-position")
                view.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
                view.backgroundColor = .systemBlue
                view.layer.cornerRadius = 10
                view.layer.borderColor = UIColor.white.cgColor
                view.layer.borderWidth = 3
                return view
            }
            guard annotation is MLNPointAnnotation else { return nil }
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
