import SwiftUI
import MapLibre
import CoreLocation

extension Coordinate {
    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

struct RouteMap: UIViewRepresentable {
    var styleURL: String
    var route: CalculatedRoute?
    var waypoints: [Waypoint] = []
    var track: [TrackPoint] = []
    var focus: Coordinate?
    var fitRevision: UUID?
    var follow = false
    var followHeading = false
    var colorBySurface = false
    var topOverlayInset: CGFloat = 65
    var hasStart = true
    var onTap: ((Coordinate) -> Void)?
    var onError: ((String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: URL(string: styleURL))
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
    func updateUIView(_ map: MLNMapView, context: Context) {
        let c = context.coordinator
        c.parent = self
        if map.styleURL?.absoluteString != styleURL { map.styleURL = URL(string: styleURL) }
        let auth = CLLocationManager().authorizationStatus
        map.showsUserLocation = auth == .authorizedAlways || auth == .authorizedWhenInUse
        if follow && map.showsUserLocation {
            if followHeading { c.beginNavigation() }
            else { map.userTrackingMode = .follow }
        }
        if c.routeID != route?.id || c.points != waypoints || c.trackCount != track.count || c.colorBySurface != colorBySurface || c.hasStart != hasStart {
            c.redraw()
        }
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
        var routeID: UUID?
        var points: [Waypoint] = []
        var trackCount = -1
        var colorBySurface = false
        var hasStart = true
        var navigationActive = false
        var focus: Coordinate?
        var fitRevision: UUID?
        init(_ parent: RouteMap) { self.parent = parent }
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let map, gesture.state == .ended else { return }
            let c = map.convert(gesture.location(in: map), toCoordinateFrom: map)
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
            for group in Dictionary(grouping: parent.track, by: \.segment).values where group.count > 1 {
                var coordinates = group.map { $0.coordinate.cl }
                let line = MLNPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
                line.title = "track"
                map.addAnnotation(line)
            }
            for (index, point) in parent.waypoints.enumerated() {
                let pin = MLNPointAnnotation()
                pin.coordinate = point.coordinate.cl
                pin.title = point.name
                pin.subtitle = index == 0 && parent.hasStart ? "Start" : (index == parent.waypoints.count - 1 ? "Ziel" : "\(index + (parent.hasStart ? 0 : 1))")
                map.addAnnotation(pin)
            }
            routeID = parent.route?.id
            points = parent.waypoints
            trackCount = parent.track.count
            colorBySurface = parent.colorBySurface
            hasStart = parent.hasStart
        }
        func fit() {
            guard let map, let annotations = map.annotations, !annotations.isEmpty else { return }
            map.showAnnotations(annotations, edgePadding: UIEdgeInsets(top: parent.topOverlayInset, left: 40, bottom: 45, right: 40), animated: true, completionHandler: nil)
        }
        func beginNavigation() {
            guard let map else { return }
            if !navigationActive {
                navigationActive = true
                // At this scale a portrait iPhone view shows about 300 m ahead.
                map.setZoomLevel(15.7, animated: true)
            }
            map.userTrackingMode = .followWithHeading
        }
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            redraw()
            if parent.follow && parent.followHeading { beginNavigation() } else { fit() }
        }
        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            parent.onError?("Karte konnte nicht geladen werden. Prüfe die Verbindung oder dein Offline-Paket.")
        }
        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            if let title = annotation.title, title.hasPrefix("surface:"), let code = Int(title.dropFirst(8)) {
                return UIColor(SurfaceKind(code: code).color)
            }
            return annotation.title == "track" ? .systemOrange : UIColor(Theme.forest)
        }
        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat { 5 }
        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard annotation is MLNPointAnnotation else { return nil }
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
