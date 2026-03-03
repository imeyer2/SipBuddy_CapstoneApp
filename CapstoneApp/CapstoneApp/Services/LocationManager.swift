
// LocationManager.swift
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let mgr = CLLocationManager()
    @Published var lastLocation: CLLocation?
    @Published var hasFullAccuracy: Bool = true   // NEW

    // NEW: reverse-geocode support
    private let geocoder = CLGeocoder()
    private var cache: [String: String] = [:] // lat/lon-rounded → name

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyHundredMeters
        mgr.distanceFilter = 50
        mgr.requestWhenInUseAuthorization()
        mgr.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }

    // NEW: Resolve a friendly place name from coordinates
    func resolvePlaceName(for loc: CLLocation, completion: @escaping (String?) -> Void) {
        let key = String(format: "%.4f,%.4f", loc.coordinate.latitude, loc.coordinate.longitude)
        if let cached = cache[key] { completion(cached); return }

        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            guard let self = self else { return }
            var best: String?

            if let p = placemarks?.first {
                // Prefer points of interest (business, park, venue)
                if let poi = p.areasOfInterest?.first, !poi.isEmpty {
                    best = poi
                } else if let name = p.name, !name.isEmpty {
                    best = name
                } else {
                    let street = [p.subThoroughfare, p.thoroughfare].compactMap{$0}.joined(separator: " ")
                    let city   = [p.locality, p.administrativeArea].compactMap{$0}.joined(separator: ", ")
                    best = [street, city].filter{ !$0.isEmpty }.joined(separator: ", ")
                }
            }

            if let best, !best.isEmpty { self.cache[key] = best }
            completion(best)
        }
    }
    
    
    
    // NEW: ask for temporary precise location on demand (SipMap screen)
    func ensurePreciseLocation(completion: (() -> Void)? = nil) {
        guard #available(iOS 14.0, *) else { completion?(); return }
        var hasFullAccuracy = false
        hasFullAccuracy = (mgr.accuracyAuthorization == .fullAccuracy)
        guard !hasFullAccuracy else { completion?(); return }

        mgr.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "SipMapPrecision") { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.hasFullAccuracy = (self.mgr.accuracyAuthorization == .fullAccuracy)
                completion?()
            }
        }
    }
    
    
    
}
