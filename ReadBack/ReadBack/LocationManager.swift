import Foundation
import CoreLocation
import Combine

/// Provides current location for airport diagram and ReadbackEngine (runway validation). Requests When In Use, publishes lastKnown lat/lon.
final class LocationManager: NSObject, ObservableObject {

    static let shared = LocationManager()

    @Published private(set) var currentLocation: CLLocation?
    /// Last known latitude from real GPS (nil if using test position or no fix yet).
    @Published private(set) var lastKnownLat: Double?
    /// Last known longitude from real GPS (nil if using test position or no fix yet).
    @Published private(set) var lastKnownLon: Double?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private var hasLoggedFirstFix = false

    /// When true, use testCoordinate instead of real GPS (for testing diagram off-airport).
    @Published var useTestPosition: Bool {
        didSet { UserDefaults.standard.set(useTestPosition, forKey: Self.useTestPositionKey) }
    }
    /// Test latitude when useTestPosition is true (e.g. 45.061 for KMIC).
    @Published var testLat: Double {
        didSet { UserDefaults.standard.set(testLat, forKey: Self.testLatKey) }
    }
    /// Test longitude when useTestPosition is true (e.g. -93.352 for KMIC).
    @Published var testLon: Double {
        didSet { UserDefaults.standard.set(testLon, forKey: Self.testLonKey) }
    }
    /// Test position as coordinate (derived from testLat/testLon).
    var testCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: testLat, longitude: testLon)
    }

    private static let useTestPositionKey = "LocationManager.useTestPosition"
    private static let testLatKey = "LocationManager.testLat"
    private static let testLonKey = "LocationManager.testLon"

    #if DEBUG
    private static let useSimulatedLocationKey = "LocationManager.useSimulatedLocation"
    private static let simulatedAirportIdKey = "LocationManager.simulatedAirportId"
    /// When true (DEBUG only), effectiveLocation returns simulated airport coords for engine/overlay.
    @Published var useSimulatedLocation: Bool = false {
        didSet { UserDefaults.standard.set(useSimulatedLocation, forKey: Self.useSimulatedLocationKey) }
    }
    /// Airport identifier or ICAO (e.g. KMIC, MIC). UserDefaults backed.
    @Published var simulatedAirportId: String = "" {
        didSet { UserDefaults.standard.set(simulatedAirportId, forKey: Self.simulatedAirportIdKey) }
    }
    /// Set by updateSimulatedLocationFromAirport; nil until Apply with valid airport.
    @Published var simulatedLat: Double?
    @Published var simulatedLon: Double?
    /// True when simulated GPS is active (DEBUG only).
    var isUsingSimulatedLocation: Bool { useSimulatedLocation && simulatedLat != nil && simulatedLon != nil }
    #endif

    private let manager = CLLocationManager()

    private override init() {
        self.useTestPosition = UserDefaults.standard.object(forKey: Self.useTestPositionKey) as? Bool ?? false
        let lat = UserDefaults.standard.double(forKey: Self.testLatKey)
        let lon = UserDefaults.standard.double(forKey: Self.testLonKey)
        self.testLat = (lat != 0 || lon != 0) ? lat : 45.061
        self.testLon = (lat != 0 || lon != 0) ? lon : -93.352
        super.init()
        #if DEBUG
        self.useSimulatedLocation = UserDefaults.standard.object(forKey: Self.useSimulatedLocationKey) as? Bool ?? false
        self.simulatedAirportId = UserDefaults.standard.string(forKey: Self.simulatedAirportIdKey) ?? ""
        // simulatedLat/Lon not persisted; if toggle was left on, we have no coords at launch so show toggle off
        if useSimulatedLocation && simulatedLat == nil && simulatedLon == nil {
            useSimulatedLocation = false
        }
        #endif
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        authorizationStatus = manager.authorizationStatus
        #if DEBUG
        ReadbackDebugLog.log("location auth status=\(authStatusString(manager.authorizationStatus))")
        #endif
    }

    private func authStatusString(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    /// Effective location to use (simulated in DEBUG, then test position, then real).
    var effectiveLocation: CLLocation? {
        #if DEBUG
        if useSimulatedLocation, let lat = simulatedLat, let lon = simulatedLon {
            return CLLocation(latitude: lat, longitude: lon)
        }
        #endif
        if useTestPosition {
            return CLLocation(latitude: testLat, longitude: testLon)
        }
        return currentLocation
    }

    /// Accuracy in meters for runway validation. When simulated (DEBUG), returns 10 so gate/radius logic works.
    var effectiveHorizontalAccuracy: Double? {
        #if DEBUG
        if isUsingSimulatedLocation { return 10 }
        #endif
        return currentLocation?.horizontalAccuracy
    }

    #if DEBUG
    /// Look up airport by ICAO then identifier and set simulated lat/lon. Call from Settings after Apply. Returns true if found.
    func updateSimulatedLocationFromAirport(store: NASRStore) -> Bool {
        let id = simulatedAirportId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !id.isEmpty else { simulatedLat = nil; simulatedLon = nil; return false }
        let airport = store.airport(byIcao: id) ?? store.airport(byIdentifier: id)
        guard let ap = airport else {
            simulatedLat = nil
            simulatedLon = nil
            return false
        }
        simulatedLat = ap.latitude
        simulatedLon = ap.longitude
        ReadbackDebugLog.log("simLocation set airport=\(ap.identifier) lat=\(ap.latitude) lon=\(ap.longitude)")
        return true
    }
    #endif

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        if !useTestPosition {
            manager.startUpdatingLocation()
        }
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        #if DEBUG
        ReadbackDebugLog.log("location auth status=\(authStatusString(manager.authorizationStatus))")
        #endif
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        currentLocation = loc
        lastKnownLat = loc.coordinate.latitude
        lastKnownLon = loc.coordinate.longitude
        let acc = loc.horizontalAccuracy
        ReadbackDebugLog.log("location update lat=\(String(format: "%.4f", loc.coordinate.latitude)) lon=\(String(format: "%.4f", loc.coordinate.longitude)) accuracy=\(String(format: "%.0f", acc))m")
        #if DEBUG
        if !hasLoggedFirstFix {
            hasLoggedFirstFix = true
            ReadbackDebugLog.log("location first fix lat=\(String(format: "%.4f", loc.coordinate.latitude)) lon=\(String(format: "%.4f", loc.coordinate.longitude)) acc=\(String(format: "%.0f", acc))m")
        }
        #endif
    }
}
