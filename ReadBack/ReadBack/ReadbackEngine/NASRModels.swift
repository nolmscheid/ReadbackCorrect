// ReadbackEngine/NASRModels.swift
// Codable structs matching aviation_data_v2/*.json produced by scripts_v2 builders.
// Do not invent fields; use only what the pipeline outputs.

import Foundation

// MARK: - LosslessInt (Int/Double/String or optional) for tolerant decoding

/// Decodes an Int from JSON that may be Int, Double, or String. Use when the pipeline sometimes emits numbers and sometimes strings.
struct LosslessInt: Codable, Sendable {
    let value: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i; return }
        if let d = try? c.decode(Double.self) { value = Int(d); return }
        if let s = try? c.decode(String.self), let i = Int(s) { value = i; return }
        throw DecodingError.typeMismatch(Int.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Int, Double, or String convertible to Int"))
    }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(value) }
}

/// Same as LosslessInt but accepts null/missing and decodes to Int?.
struct OptionalLosslessInt: Codable, Sendable {
    let value: Int?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if try c.decodeNil() { value = nil; return }
        if let i = try? c.decode(Int.self) { value = i; return }
        if let d = try? c.decode(Double.self) { value = Int(d); return }
        if let s = try? c.decode(String.self), let i = Int(s) { value = i; return }
        throw DecodingError.typeMismatch(Int.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Int, Double, String, or null"))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let v = value { try c.encode(v) } else { try c.encodeNil() }
    }
}

// MARK: - Airport (airports.json)
struct NASRAirport: Codable, Sendable {
    let identifier: String
    let icaoId: String?
    let name: String
    let city: String
    let state: String
    let latitude: Double
    let longitude: Double
    let elevationFt: Int?
    let runways: [String]
    let frequencies: [String: [String]]?

    enum CodingKeys: String, CodingKey {
        case identifier
        case icaoId = "icao_id"
        case name, city, state
        case latitude, longitude
        case elevationFt = "elevation_ft"
        case runways, frequencies
    }
}

// MARK: - Runway (runways.json)
struct NASRRunwayEnd: Codable, Sendable {
    let endId: String
    let latitude: Double?
    let longitude: Double?
    let elevationFt: Double?
    let trueAlignment: String?
    let ilsType: String?
    let displacedThresholdFt: Int?
    let tdzElevFt: Double?

    enum CodingKeys: String, CodingKey {
        case endId = "end_id"
        case latitude, longitude
        case elevationFt = "elevation_ft"
        case trueAlignment = "true_alignment"
        case ilsType = "ils_type"
        case displacedThresholdFt = "displaced_threshold_ft"
        case tdzElevFt = "tdz_elev_ft"
    }
}

struct NASRRunway: Codable, Sendable {
    let airportIdentifier: String
    let runwayId: String
    let lengthFt: Int?
    let widthFt: Int?
    let surface: String?
    let lighting: String?
    let ends: [NASRRunwayEnd]

    enum CodingKeys: String, CodingKey {
        case airportIdentifier = "airport_identifier"
        case runwayId = "runway_id"
        case lengthFt = "length_ft"
        case widthFt = "width_ft"
        case surface, lighting
        case ends
    }
}

// MARK: - Frequency (frequencies.json)
struct NASRFrequency: Codable, Sendable {
    let facilityId: String
    let facilityType: String?
    let freqType: String?
    let frequency: String
    let units: String?
    let service: String?
    let callsign: String?
    let sectorName: String?
    let commLocation: String?
    let remarks: String?

    enum CodingKeys: String, CodingKey {
        case facilityId = "facility_id"
        case facilityType = "facility_type"
        case freqType = "freq_type"
        case frequency, units, service
        case callsign
        case sectorName = "sector_name"
        case commLocation = "comm_location"
        case remarks
    }
}

// MARK: - Navaid (navaids.json)
struct NASRNavaid: Codable, Sendable {
    let identifier: String
    let type: String
    let name: String
    let state: String?
    let country: String?
    let icaoRegion: String?
    let latitude: Double
    let longitude: Double
    let elevationFt: Int?
    let frequencyKhzOrMhz: String?
    let channel: String?
    let status: String?
    let tacan: [String: String?]?
    let flags: [String: String?]?

    enum CodingKeys: String, CodingKey {
        case identifier, type, name
        case state, country
        case icaoRegion = "icao_region"
        case latitude, longitude
        case elevationFt = "elevation_ft"
        case frequencyKhzOrMhz = "frequency_khz_or_mhz"
        case channel, status
        case tacan, flags
    }
}

// MARK: - Fix (fixes.json)
struct NASRFix: Codable, Sendable {
    let identifier: String
    let latitude: Double
    let longitude: Double
}

// MARK: - Comm (comms.json)
struct NASRComm: Codable, Sendable {
    let outletId: String
    let name: String?
    let type: String?
    let state: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?
    let artccId: String?

    enum CodingKeys: String, CodingKey {
        case outletId = "outlet_id"
        case name, type, state, country
        case latitude, longitude
        case artccId = "artcc_id"
    }
}

// MARK: - ILS (ils.json) — minimal for validation
struct NASRILS: Codable, Sendable {
    let airportIdentifier: String
    let runwayId: String
    let ident: String
    let frequency: String?
    let latitude: Double?
    let longitude: Double?
    let components: [String: [[String: String]]]?

    enum CodingKeys: String, CodingKey {
        case airportIdentifier = "airport_identifier"
        case runwayId = "runway_id"
        case ident
        case frequency
        case latitude, longitude
        case components
    }
}

// MARK: - Procedure (departures/arrivals) — minimal for clearance

/// One route segment; pipeline may emit seq as Int or (legacy) String. Other fields are optional strings.
struct NASRProcedureRouteSegment: Codable, Sendable {
    /// Sequence number; decoded from Int, Double, or String in JSON (and null/missing → nil).
    let seq: OptionalLosslessInt?
    let fixId: String?
    let fixType: String?
    let navId: String?
    let navType: String?
    let pathTerm: String?
    let altDesc: String?
    let speed: String?
    let speedAlt: String?
    let rnvLeg: String?
    let transition: String?
    let point: String?
    let pointType: String?
    let nextPoint: String?
    let routeName: String?
    /// Pipeline may emit as number; decode flexibly.
    let bodySeq: OptionalLosslessInt?
    let arptRwyAssoc: String?

    enum CodingKeys: String, CodingKey {
        case seq
        case fixId = "fix_id"
        case fixType = "fix_type"
        case navId = "nav_id"
        case navType = "nav_type"
        case pathTerm = "path_term"
        case altDesc = "alt_desc"
        case speed
        case speedAlt = "speed_alt"
        case rnvLeg = "rnv_leg"
        case transition
        case point
        case pointType = "point_type"
        case nextPoint = "next_point"
        case routeName = "route_name"
        case bodySeq = "body_seq"
        case arptRwyAssoc = "arpt_rwy_assoc"
    }
}

struct NASRProcedureAirport: Codable, Sendable {
    let airportIdentifier: String
    let runway: String?

    enum CodingKeys: String, CodingKey {
        case airportIdentifier = "airport_identifier"
        case runway
    }
}

struct NASRProcedure: Codable, Sendable {
    let id: String
    let name: String
    let type: String?
    let status: String?
    let airports: [NASRProcedureAirport]
    let route: [NASRProcedureRouteSegment]?
}
