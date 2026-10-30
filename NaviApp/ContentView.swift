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
            // MapKit map
            Map(coordinateRegion: $region,
                showsUserLocation: true,
                annotationItems: navManager.annotations) { item in
                MapMarker(coordinate: item.coordinate, tint: item.isDestination ? .red : .blue)
            }
            .edgesIgnoringSafeArea(.all)
            .onTapGesture { location in
                // Convert tap to coordinate
                let coordinate = convertTapToCoordinate(location: location, region: region, size: UIScreen.main.bounds.size)
                navManager.setDestination(coordinate)
            }

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

    private func convertTapToCoordinate(location: CGPoint, region: MKCoordinateRegion, size: CGSize) -> CLLocationCoordinate2D {
        let lat = region.center.latitude - region.span.latitudeDelta * Double(location.y / size.height - 0.5)
        let lon = region.center.longitude + region.span.longitudeDelta * Double(location.x / size.width - 0.5)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
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

// MARK: - Annotation Item
struct MapAnnotationItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let isDestination: Bool
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
    @Published var annotations: [MapAnnotationItem] = []
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
        annotations = [MapAnnotationItem(coordinate: coordinate, isDestination: true)]
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

        // Parse instruction for Japanese
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

    // CLLocationManagerDelegate
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
