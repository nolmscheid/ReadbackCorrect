// ReadbackEngine/GeoIndex.swift
// Lightweight geo grid index (1-degree tiles) for nearest-airport/fix/navaid queries.
// Deterministic; no network.

import Foundation

/// 1-degree tile key: "lat,lon" where lat/lon are integer degrees.
struct GridKey: Hashable, Sendable {
    let lat: Int
    let lon: Int
    var key: String { "\(lat),\(lon)" }
}

/// Point with optional altitude for distance sorting.
struct GeoPoint: Sendable {
    let lat: Double
    let lon: Double
    let altitudeFt: Double?

    func distanceNm(to other: GeoPoint) -> Double {
        GeoIndex.haversineNm(lat1: lat, lon1: lon, lat2: other.lat, lon2: other.lon)
    }
}

/// Haversine distance in nautical miles.
enum GeoIndex {
    static func haversineNm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 3440.065 // Earth radius in NM
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    static func gridKey(lat: Double, lon: Double) -> GridKey {
        GridKey(lat: Int(floor(lat)), lon: Int(floor(lon)))
    }

    /// All grid keys that overlap a circle of radiusNm around (lat, lon).
    static func gridKeysNear(lat: Double, lon: Double, radiusNm: Double) -> Set<GridKey> {
        // ~1 deg ≈ 60 NM; fetch tiles in a square that contains the circle
        let degPerNm = 1.0 / 60.0
        let delta = radiusNm * degPerNm
        var keys = Set<GridKey>()
        let latMin = Int(floor(lat - delta))
        let latMax = Int(floor(lat + delta))
        let lonMin = Int(floor(lon - delta))
        let lonMax = Int(floor(lon + delta))
        for la in latMin...latMax {
            for lo in lonMin...lonMax {
                keys.insert(GridKey(lat: la, lon: lo))
            }
        }
        return keys
    }
}

/// Generic geo-indexed list: items with lat/lon, bucketed by 1-deg grid.
struct GeoBucket<Item: Sendable>: Sendable {
    typealias Id = String
    typealias Position = (lat: Double, lon: Double)
    typealias ExtractId = (Item) -> Id
    typealias ExtractPosition = (Item) -> Position

    private var byKey: [String: [Item]] = [:]
    private let extractId: ExtractId
    private let extractPosition: ExtractPosition

    init(extractId: @escaping ExtractId, extractPosition: @escaping ExtractPosition) {
        self.extractId = extractId
        self.extractPosition = extractPosition
    }

    mutating func add(_ item: Item) {
        let pos = extractPosition(item)
        let key = GeoIndex.gridKey(lat: pos.lat, lon: pos.lon).key
        byKey[key, default: []].append(item)
    }

    mutating func load(_ items: [Item]) {
        for item in items {
            add(item)
        }
    }

    /// Items in tiles that overlap the circle; caller sorts by distance.
    func candidates(lat: Double, lon: Double, radiusNm: Double) -> [Item] {
        let keys = GeoIndex.gridKeysNear(lat: lat, lon: lon, radiusNm: radiusNm)
        var result: [Item] = []
        for k in keys {
            if let list = byKey[k.key] {
                result.append(contentsOf: list)
            }
        }
        return result
    }
}

/// Wrapper for distance-sorted result.
struct LocatedItem<Item: Sendable>: Sendable {
    let item: Item
    let distanceNm: Double
}
