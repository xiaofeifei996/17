import SwiftUI
import MapKit
import CoreLocation

/// MapKit bridge used because the iOS 15 SwiftUI Map API cannot rotate its camera.
struct RotatingMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let markets: [Market]
    let selectedMarketID: String?
    let onSelectMarket: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = false
        map.pointOfInterestFilter = .excludingAll
        map.setRegion(region, animated: false)
        map.addAnnotations(makeAnnotations())
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self

        // Keep the map north-up. Only update the visible region and center;
        // no compass or device-heading data is used.
        let centerChanged = abs(map.region.center.latitude - region.center.latitude) > 0.0001 ||
            abs(map.region.center.longitude - region.center.longitude) > 0.0001
        let spanChanged = abs(map.region.span.latitudeDelta - region.span.latitudeDelta) > 0.001 ||
            abs(map.region.span.longitudeDelta - region.span.longitudeDelta) > 0.001
        if spanChanged {
            map.setRegion(region, animated: false)
        } else if centerChanged {
            var camera = map.camera
            camera.centerCoordinate = region.center
            map.setCamera(camera, animated: false)
        }

        let old = map.annotations.compactMap { $0 as? GanJiAnnotation }
        let desired = makeAnnotations()
        let desiredIDs = Set(desired.map(\.key))
        let oldIDs = Set(old.map(\.key))
        map.removeAnnotations(old.filter { !desiredIDs.contains($0.key) })
        map.addAnnotations(desired.filter { !oldIDs.contains($0.key) })
        let desiredByID = Dictionary(uniqueKeysWithValues: desired.map { ($0.key, $0) })
        for annotation in map.annotations.compactMap({ $0 as? GanJiAnnotation }) {
            if let updated = desiredByID[annotation.key],
               abs(annotation.coordinate.latitude - updated.coordinate.latitude) > 0.000001 ||
               abs(annotation.coordinate.longitude - updated.coordinate.longitude) > 0.000001 {
                annotation.coordinate = updated.coordinate
            }
            if let view = map.view(for: annotation) as? GanJiAnnotationView {
                view.configure(annotation: annotation, selected: annotation.key == selectedMarketID)
            }
        }
    }

    private func makeAnnotations() -> [GanJiAnnotation] {
        var result = markets.map { market in
            GanJiAnnotation(key: market.id, title: market.name,
                coordinate: CLLocationCoordinate2D(latitude: market.lat, longitude: market.lon),
                isUser: market.id == "__user_location__")
        }
        if let lat = regionUserLatitude, let lon = regionUserLongitude,
           !result.contains(where: { $0.isUser }) {
            result.append(GanJiAnnotation(key: "__user_location__", title: "当前位置",
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), isUser: true))
        }
        return result
    }

    // The user marker is supplied in `markets` by ContentView; these remain nil as a fallback.
    private var regionUserLatitude: Double? { nil }
    private var regionUserLongitude: Double? { nil }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RotatingMapView
        init(_ parent: RotatingMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let item = annotation as? GanJiAnnotation else { return nil }
            let id = "GanJiAnnotationView"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? GanJiAnnotationView)
                ?? GanJiAnnotationView(annotation: item, reuseIdentifier: id)
            view.annotation = item
            view.onTap = { [weak self] key in self?.parent.onSelectMarket(key) }
            view.configure(annotation: item, selected: item.key == parent.selectedMarketID)
            return view
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Keep the SwiftUI region in sync with map gestures.
            let newRegion = mapView.region
            DispatchQueue.main.async { self.parent.region = newRegion }
        }
    }
}

private final class GanJiAnnotation: NSObject, MKAnnotation {
    let key: String
    let title: String?
    var coordinate: CLLocationCoordinate2D
    let isUser: Bool
    init(key: String, title: String?, coordinate: CLLocationCoordinate2D, isUser: Bool) {
        self.key = key; self.title = title; self.coordinate = coordinate; self.isUser = isUser
    }
}

private final class GanJiAnnotationView: MKAnnotationView {
    var onTap: ((String) -> Void)?
    private let marker = UIView()
    private let titleLabel = UILabel()
    private let cone = CAShapeLayer()
    private var configuredKey: String?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        addSubview(marker)
        marker.layer.cornerRadius = 17
        marker.layer.borderWidth = 2
        marker.layer.borderColor = UIColor.white.cgColor
        marker.layer.shadowColor = UIColor.black.cgColor
        marker.layer.shadowOpacity = 0.22
        marker.layer.shadowRadius = 5
        marker.layer.shadowOffset = CGSize(width: 0, height: 2)
        titleLabel.font = .systemFont(ofSize: 10, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.textColor = UIColor(red: 0.16, green: 0.23, blue: 0.19, alpha: 1)
        titleLabel.backgroundColor = UIColor(red: 0.99, green: 0.97, blue: 0.89, alpha: 1)
        titleLabel.layer.cornerRadius = 8
        titleLabel.layer.masksToBounds = true
        addSubview(titleLabel)
        layer.addSublayer(cone)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(annotation: GanJiAnnotation, selected: Bool) {
        configuredKey = annotation.key
        if annotation.isUser {
            frame = CGRect(x: 0, y: 0, width: 64, height: 64)
            centerOffset = CGPoint(x: 0, y: 0)
            marker.frame = CGRect(x: 24, y: 24, width: 16, height: 16)
            marker.layer.cornerRadius = 8
            marker.backgroundColor = UIColor(red: 0.02, green: 0.52, blue: 0.98, alpha: 1)
            marker.layer.borderWidth = 4
            marker.layer.borderColor = UIColor.white.cgColor
            titleLabel.isHidden = true
            cone.isHidden = false
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 32, y: 25)); path.addLine(to: CGPoint(x: 13, y: 2))
            path.addQuadCurve(to: CGPoint(x: 51, y: 2), controlPoint: CGPoint(x: 32, y: -5)); path.close()
            cone.path = path.cgPath
            cone.fillColor = UIColor(red: 0.05, green: 0.52, blue: 0.98, alpha: 0.25).cgColor
            cone.frame = bounds
            displayPriority = .required
        } else {
            frame = CGRect(x: 0, y: 0, width: 130, height: 66)
            centerOffset = CGPoint(x: 0, y: -28)
            marker.frame = CGRect(x: 48, y: 0, width: 34, height: 34)
            marker.layer.cornerRadius = 17
            marker.backgroundColor = selected
                ? UIColor(red: 0.90, green: 0.34, blue: 0.19, alpha: 1)
                : UIColor(red: 0.16, green: 0.29, blue: 0.23, alpha: 1)
            marker.layer.borderWidth = 2
            let glyph = UILabel(frame: marker.bounds)
            glyph.text = selected ? "◎" : "市"
            glyph.textAlignment = .center
            glyph.font = .boldSystemFont(ofSize: selected ? 18 : 12)
            glyph.textColor = .white
            marker.subviews.forEach { $0.removeFromSuperview() }; marker.addSubview(glyph)
            titleLabel.isHidden = false
            titleLabel.text = "  \(annotation.title ?? "集市")  "
            titleLabel.sizeToFit()
            titleLabel.frame = CGRect(x: max(0, (130 - min(titleLabel.intrinsicContentSize.width, 130)) / 2), y: 38,
                                      width: min(max(titleLabel.intrinsicContentSize.width, 42), 130), height: 20)
            cone.isHidden = true
            displayPriority = selected ? .required : .defaultHigh
        }
    }

    @objc private func tapped() {
        guard let item = annotation as? GanJiAnnotation, !item.isUser else { return }
        onTap?(item.key)
    }
}
