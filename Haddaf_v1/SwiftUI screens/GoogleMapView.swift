import SwiftUI
import GoogleMaps

struct GoogleMapView: UIViewRepresentable {

    var latitude: Double
    var longitude: Double
    var onTap: ((CLLocationCoordinate2D) -> Void)?   // 🔥 مهم

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(
            withLatitude: latitude,
            longitude: longitude,
            zoom: 15
        )

        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {

        let camera = GMSCameraPosition.camera(
            withLatitude: latitude,
            longitude: longitude,
            zoom: 15
        )

        mapView.animate(to: camera)
        mapView.clear()

        let marker = GMSMarker()
        marker.position = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        marker.map = mapView
    }

    class Coordinator: NSObject, GMSMapViewDelegate {

        var parent: GoogleMapView

        init(_ parent: GoogleMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            parent.onTap?(coordinate)   // 🔥
        }
    }
}
