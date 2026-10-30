import SwiftUI
import MapboxMaps
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

    var body: some View {
        ZStack {
            MapViewRepresentable(navManager: navManager)
                .edgesIgnoringSafeArea(.all)

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
            Button(action: { navManager.centerOnUser() }) {
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

struct MapViewRepresentable: UIViewRepresentable {
    @ObservedObject var navManager: NavigationManager

    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.mapboxMap.style.uri = StyleURI.streets
        mapView.location.options.puckType = .puck2D()
        mapView.location.locationProvider.requestLocationUpdates()

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapGesture)

        context.coordinator.mapView = mapView
        context.coordinator.navManager = navManager

        return mapView
    }

    func updateUIView(_ uiView: MapView, context: Context) {
        context.coordinator.updateRoute()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        var mapView: MapView?
        var navManager: NavigationManager?

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = mapView, let navManager = navManager else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.mapboxMap.coordinate(for: point)
            navManager.setDestination(coordinate)
        }

        func updateRoute() {
            guard let mapView = mapView, let navManager = navManager else { return }

            if let existing = try? mapView.mapboxMap.style.getSource(identifier: "route-source") {
                try? mapView.mapboxMap.style.removeSource(existing)
            }
            if let existing = try? mapView.mapboxMap.style.getLayer(identifier: "route-layer") {
                try? mapView.mapboxMap.style.removeLayer(existing)
            }

            if let route = navManager.route {
                var feature = Feature(geometry: .lineString(route.shape))
                feature.properties = ["id": .string("route")]

                var source = GeoJSONSource()
                source.data = .feature(feature)
                try? mapView.mapboxMap.style.addSource(source, id: "route-source")

                var layer = LineLayer(id: "route-layer", source: "route-source")
                layer.lineColor = .constant(.init(UIColor(DesignSystem.primary)))
                layer.lineWidth = .constant(8)
                layer.lineCap = .constant(.round)
                layer.lineJoin = .constant(.round)
                try? mapView.mapboxMap.style.addLayer(layer)
            }

            if let dest = navManager.destination {
                var point = Feature(geometry: .point(Point(dest)))
                point.properties = ["id": .string("dest")]

                var source = GeoJSONSource()
                source.data = .feature(point)
                try? mapView.mapboxMap.style.addSource(source, id: "dest-source")

                var layer = CircleLayer(id: "dest-layer", source: "dest-source")
                layer.circleColor = .constant(.init(UIColor(DesignSystem.error)))
                layer.circleRadius = .constant(12)
                layer.circleStrokeColor = .constant(.init(.white))
                layer.circleStrokeWidth = .constant(4)
                try? mapView.mapboxMap.style.addLayer(layer)
            }
        }
    }
}

class NavigationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var destination: CLLocationCoordinate2D?
    @Published var route: Route?
    @Published var isNavigating = false
    @Published var currentInstruction = ""
    @Published var remainingDistance = ""
    @Published var progress: Double = 0.0
    @Published var instructionIcon = "arrow.up"

    private let locationManager = CLLocationManager()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpokenInstruction = ""

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    }

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func centerOnUser() {}

    func setDestination(_ coordinate: CLLocationCoordinate2D) {
        destination = coordinate
        fetchRoute()
    }

    func fetchRoute() {
        guard let dest = destination,
              let userLoc = locationManager.location?.coordinate else { return }

        let options = RouteOptions(coordinates: [userLoc, dest])
        options.profileIdentifier = .walking
        options.includesSteps = true

        Directions.shared.calculate(options) { [weak self] (session, result) in
            switch result {
            case .failure(let error):
                print("Route error: \(error)")
            case .success(let response):
                guard let route = response.routes?.first else { return }
                DispatchQueue.main.async {
                    self?.route = route
                    self?.updateInstruction(route: route)
                }
            }
        }
    }

    func startNavigation() {
        isNavigating.toggle()
        if isNavigating, let route = route {
            speak("ナビゲーションを開始します。\(Int(route.expectedTravelTime/60))分のルートです。")
        } else {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    func updateInstruction(route: Route) {
        guard let leg = route.legs.first, let step = leg.steps.first else { return }

        let distance = step.distance
        let instruction: String
        let icon: String

        switch step.maneuverType {
        case .depart:
            instruction = "まっすぐ進んでください"
            icon = "arrow.up"
        case .turnLeft:
            instruction = "左に曲がってください"
            icon = "arrow.turn.up.left"
        case .turnRight:
            instruction = "右に曲がってください"
            icon = "arrow.turn.up.right"
        case .straightAhead:
            instruction = "まっすぐ進んでください"
            icon = "arrow.up"
        default:
            instruction = step.instructions
            icon = "arrow.up"
        }

        currentInstruction = "\(instruction)"
        remainingDistance = "あと\(Int(distance))メートル"
        instructionIcon = icon
        progress = 1.0 - (distance / route.distance)

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
        guard isNavigating, let route = route else { return }
        updateInstruction(route: route)
    }
}
