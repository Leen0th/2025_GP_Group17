import SwiftUI
import GoogleMaps

struct GoogleMapView: UIViewRepresentable {

    var latitude: Double
    var longitude: Double

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(
            withLatitude: latitude,
            longitude: longitude,
            zoom: 14
        )

        let mapView = GMSMapView(frame: .zero, camera: camera)

        let marker = GMSMarker()
        marker.position = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        marker.map = mapView

        return mapView
    }

    func updateUIView(_ uiView: GMSMapView, context: Context) {}
}
