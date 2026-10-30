import SwiftUI
import MapKit
import CoreLocation
import AVFoundation

// MARK: - Design System
struct DesignSystem {
    static let primary = Color(red: 0.13, green: 0.59, blue: 0.95)
    static let secondary = Color(red: 0.30, green: 0.69, blue: 0.31)
    static let error = Color(red: 0.96, green: 0.26, blue: 0.21)
    static let shadowColor = Color.black.opacity(0.15)
    static let cornerRadius: CGFloat = 16
    static let spacing: CGFloat = 8
    static let spacingMedium: CGFloat = 16
    static let spacingLarge: CGFloat = 24
    static let titleFont = Font.system(size: 22, weight: .bold, design: .rounded)
    static let captionFont = Font.system(size: 13, weight: .medium)
}

struct ContentView: View {
    @StateObject private var navManager = NavigationManager()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )

    var body: some View {
        ZStack {
            // MapKit map (iOS 14 compatible)
            MapView(region: $region, navManager: navManager)
                .edgesIgnoringSafeArea(.all)

            // UI overlay
            VStack(spacing: 0) {
                if navManager.isNavigating {
                    navigationCard
                        .padding(.top, 60)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                bottomControls
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            navManager.requestPermission()
            navManager.onLocationUpdate = { location in
                region.center = location.coordinate
            }
        }
        .preferredColorScheme(.dark)
    }

    private var navigationCard: some View {
        VStack(spacing: DesignSystem.spacing) {
            HStack(spacing: DesignSystem.spacingMedium) {
                Image(systemName: navManager.instructionIcon)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(DesignSystem.primary)
                    .frame(width: 48, height: 48)
                    .background(DesignSystem.primary.opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(navManager.currentInstruction)
                        .font(DesignSystem.titleFont)
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    Text(navManager.remainingDistance)
                        .font(DesignSystem.captionFont)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(DesignSystem.spacingMedium)

            ProgressView(value: navManager.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: DesignSystem.secondary))
                .padding(.horizontal, DesignSystem.spacingMedium)
                .padding(.bottom, DesignSystem.spacingMedium)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .fill(.ultraThinMaterial)
                .shadow(color: DesignSystem.shadowColor, radius: 8, y: 4)
        )
        .padding(.horizontal, DesignSystem.spacingMedium)
    }

    private var bottomControls: some View {
        HStack(spacing: DesignSystem.spacingMedium) {
            Button(action: {
                if let location = navManager.currentLocation {
                    region.center = location.coordinate
                }
            }) {
                Image(systemName: "location.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(DesignSystem.primary)
                    .clipShape(Circle())
                    .shadow(color: DesignSystem.shadowColor, radius: 8, y: 4)
            }

            Spacer()

            if navManager.destination != nil {
                Button(action: { navManager.startNavigation() }) {
                    HStack(spacing: DesignSystem.spacing) {
                        Image(systemName: navManager.isNavigating ? "stop.fill" : "play.fill")
                        Text(navManager.isNavigating ? "停止" : "ナビ開始")
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, DesignSystem.spacingLarge)
                    .padding(.vertical, 16)
                    .background(navManager.isNavigating ? DesignSystem.error : DesignSystem.secondary)
                    .clipShape(Capsule())
                    .shadow(color: DesignSystem.shadowColor, radius: 8, y: 4)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, DesignSystem.spacingLarge)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: navManager.destination != nil)
    }
}

// MARK: - MapView (iOS 14 compatible)
struct MapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @ObservedObject var navManager: NavigationManager

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true

        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapGesture)

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.setRegion(region, animated: true)

        // Update annotations
        uiView.removeAnnotations(uiView.annotations)

        if let dest = navManager.destination {
            let annotation = MKPointAnnotation()
            annotation.coordinate = dest
            annotation.title = "目的地"
            uiView.addAnnotation(annotation)
        }

        // Update route overlay
        uiView.removeOverlays(uiView.overlays)

        if let route = navManager.route {
            uiView.addOverlay(route.polyline)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView

        init(_ parent: MapView) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.navManager.setDestination(coordinate)
        }

        // MKMapViewDelegate
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(DesignSystem.primary)
                renderer.lineWidth = 8
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            let identifier = "Destination"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
            } else {
                annotationView?.annotation = annotation
            }

            if let markerView = annotationView as? MKMarkerAnnotationView {
                markerView.markerTintColor = UIColor(DesignSystem.error)
                markerView.glyphImage = UIImage(systemName: "flag.fill")
            }

            return annotationView
        }
    }
}

// MARK: - Navigation Manager
class NavigationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var destination: CLLocationCoordinate2D?
    @Published var route: MKRoute?
    @Published var isNavigating = false
    @Published var currentInstruction = ""
    @Published var remainingDistance = ""
    @Published var progress: Double = 0.0
    @Published var instructionIcon = "arrow.up"
    @Published var currentLocation: CLLocation?

    var onLocationUpdate: ((CLLocation) -> Void)?

    private let locationManager = CLLocationManager()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpokenInstruction = ""

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.startUpdatingLocation()
    }

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func setDestination(_ coordinate: CLLocationCoordinate2D) {
        destination = coordinate
        fetchRoute()
    }

    func fetchRoute() {
        guard let dest = destination,
              let userLoc = currentLocation?.coordinate else { return }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLoc))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
        request.transportType = .walking

        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            guard let route = response?.routes.first else {
                print("Route error: \(error?.localizedDescription ?? "unknown")")
                return
            }
            DispatchQueue.main.async {
                self?.route = route
                self?.updateInstruction(route: route)
            }
        }
    }

    func startNavigation() {
        isNavigating.toggle()
        if isNavigating, let route = route {
            speak("ナビゲーションを開始します。\(Int(route.expectedTravelTime / 60))分のルートです。")
        } else {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    func updateInstruction(route: MKRoute) {
        guard let step = route.steps.first else { return }

        let distance = step.distance
        let instruction: String
        let icon: String

        let stepInstruction = step.instructions

        if stepInstruction.contains("左") {
            instruction = "左に曲がってください"
            icon = "arrow.turn.up.left"
        } else if stepInstruction.contains("右") {
            instruction = "右に曲がってください"
            icon = "arrow.turn.up.right"
        } else if stepInstruction.contains("直進") || stepInstruction.contains("Continue") {
            instruction = "まっすぐ進んでください"
            icon = "arrow.up"
        } else {
            instruction = stepInstruction.isEmpty ? "まっすぐ進んでください" : stepInstruction
            icon = "arrow.up"
        }

        currentInstruction = instruction
        remainingDistance = "あと\(Int(distance))メートル"
        instructionIcon = icon
        progress = route.distance > 0 ? 1.0 - (distance / route.distance) : 0

        if instruction != lastSpokenInstruction {
            speak("\(instruction)。あと\(Int(distance))メートル")
            lastSpokenInstruction = instruction
        }
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.5
        speechSynthesizer.speak(utterance)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        onLocationUpdate?(location)

        if isNavigating, let route = route {
            updateInstruction(route: route)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}
