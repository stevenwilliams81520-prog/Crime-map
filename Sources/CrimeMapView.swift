import SwiftUI
import MapKit

// MARK: - Annotation

final class CrimeAnnotation: NSObject, MKAnnotation {
    let crime: Crime
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(_ crime: Crime) {
        self.crime = crime
        self.coordinate = CLLocationCoordinate2D(latitude: crime.latitude, longitude: crime.longitude)
        self.title = crimeName(crime.category)
        self.subtitle = [crime.street, monthLabel(crime.month), crime.outcome ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        super.init()
    }
}

// MARK: - Pin views

final class CrimePinView: MKAnnotationView {
    private static var cache: [String: UIImage] = [:]

    static func image(for category: String) -> UIImage {
        if let img = cache[category] { return img }
        let size = CGSize(width: 16, height: 16)
        let img = UIGraphicsImageRenderer(size: size).image { _ in
            let r = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: r).fill()
            crimeColor(category).setFill()
            UIBezierPath(ovalIn: r.insetBy(dx: 2, dy: 2)).fill()
        }
        cache[category] = img
        return img
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = true
        collisionMode = .circle
        displayPriority = .defaultHigh
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        clusteringIdentifier = "crime"
        if let a = annotation as? CrimeAnnotation {
            image = Self.image(for: a.crime.category)
        }
    }
}

final class CrimeClusterView: MKMarkerAnnotationView {
    override func prepareForDisplay() {
        super.prepareForDisplay()
        markerTintColor = UIColor(hex: 0xE5484D)
        canShowCallout = false
        displayPriority = .required
        if let c = annotation as? MKClusterAnnotation {
            glyphText = "\(c.memberAnnotations.count)"
        }
    }
}

// MARK: - Map

struct CrimeMapView: UIViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.pointOfInterestFilter = .excludingAll
        map.showsUserLocation = true
        map.showsCompass = false
        map.isRotateEnabled = false
        map.register(CrimePinView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
        map.register(CrimeClusterView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 53.32, longitude: -3.83),
                                         latitudinalMeters: 8000, longitudinalMeters: 8000),
                      animated: false)

        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.longPress(_:)))
        press.minimumPressDuration = 0.5
        map.addGestureRecognizer(press)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.model = model

        // Pins
        let visible = model.visible
        let ids = visible.map(\.id)
        if ids != c.shownIDs {
            map.removeAnnotations(map.annotations.filter { $0 is CrimeAnnotation })
            map.addAnnotations(visible.map { CrimeAnnotation($0) })
            c.shownIDs = ids
        }

        // Search radius circle
        if let centre = model.centre, !c.isCircle(at: centre) {
            if let old = c.circle { map.removeOverlay(old) }
            let circle = MKCircle(center: centre, radius: 1609)
            map.addOverlay(circle)
            c.circle = circle
        }

        // Move the map
        if let f = model.focus, f.id != c.lastFocus {
            c.lastFocus = f.id
            let rect = MKCircle(center: f.coordinate, radius: 1609).boundingMapRect
            map.setVisibleMapRect(rect,
                                  edgePadding: UIEdgeInsets(top: 100, left: 16, bottom: 240, right: 16),
                                  animated: true)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var model: AppModel
        var shownIDs: [UUID] = []
        var circle: MKCircle?
        var lastFocus: UUID?

        init(model: AppModel) { self.model = model }

        func isCircle(at c: CLLocationCoordinate2D) -> Bool {
            guard let o = circle?.coordinate else { return false }
            return o.latitude == c.latitude && o.longitude == c.longitude
        }

        @objc func longPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map = g.view as? MKMapView else { return }
            let coord = map.convert(g.location(in: map), toCoordinateFrom: map)
            let m = model
            Task { @MainActor in await m.load(coord, place: "Map point") }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let cluster = annotation as? MKClusterAnnotation {
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: cluster)
            }
            return mapView.dequeueReusableAnnotationView(
                withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier, for: annotation)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                let r = MKCircleRenderer(circle: circle)
                r.strokeColor = UIColor(hex: 0xE5484D, alpha: 0.8)
                r.fillColor = UIColor(hex: 0xE5484D, alpha: 0.06)
                r.lineWidth = 1.5
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let cluster = view.annotation as? MKClusterAnnotation else { return }
            let crimes = cluster.memberAnnotations
                .compactMap { ($0 as? CrimeAnnotation)?.crime }
                .sorted { $0.month != $1.month ? $0.month > $1.month : crimeName($0.category) < crimeName($1.category) }
            mapView.deselectAnnotation(cluster, animated: false)
            let m = model
            Task { @MainActor in m.list = CrimeList(crimes: crimes) }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let centre = mapView.centerCoordinate
            let m = model
            Task { @MainActor in m.mapCentre = centre }
        }
    }
}
