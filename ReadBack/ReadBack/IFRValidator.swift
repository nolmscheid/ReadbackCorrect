import Foundation

/// Rule-based validation and confidence scoring for IFR clearances. Mutates clearance slots in place.
final class IFRValidator {

    private static let confidenceValidatedBonus: Double = 0.2
    private static let confidenceNumericCleanBonus: Double = 0.1
    private static let confidenceAmbiguousPenalty: Double = -0.3
    private static let confidenceValidationFailPenalty: Double = -0.4

    private static let weightClearanceLimit: Double = 0.15
    private static let weightRoute: Double = 0.25
    private static let weightAltitude: Double = 0.25
    private static let weightFrequency: Double = 0.20
    private static let weightSquawk: Double = 0.15

    /// Validate clearance and apply rule-based confidence (validation result, ambiguity only). Modifies clearance in place.
    static func validate(clearance: inout IFRClearance, context: ParsingContext, dataProvider: AviationDataProvider? = nil) {
        validateAndScoreSquawk(clearance: &clearance)
        validateAndScoreFrequency(clearance: &clearance)
        validateAndScoreAltitude(clearance: &clearance)
        validateAndScoreClearanceLimit(clearance: &clearance, dataProvider: dataProvider)
        computeOverallConfidence(clearance: &clearance)
    }

    // MARK: - Squawk: 4 digits, 0–7 only

    private static func validateAndScoreSquawk(clearance: inout IFRClearance) {
        var conf = clearance.squawk.confidence
        let valid: Bool
        if let s = clearance.squawk.value, s.count == 4, s.allSatisfy({ $0.isNumber }) {
            let digits = s.compactMap { Int(String($0)) }
            valid = digits.allSatisfy { (0...7).contains($0) }
        } else {
            valid = false
        }
        if valid {
            clearance.squawk.validated = true
            conf += confidenceValidatedBonus
            conf += confidenceNumericCleanBonus
        } else if clearance.squawk.value != nil {
            conf += confidenceValidationFailPenalty
        }
        clearance.squawk.confidence = clamp(conf)
    }

    // MARK: - Frequency: 118.000–136.975

    private static func validateAndScoreFrequency(clearance: inout IFRClearance) {
        var conf = clearance.frequency.confidence
        var valid = false
        var numericClean = false
        if let f = clearance.frequency.value, let val = Double(f) {
            numericClean = true
            valid = (118.000...136.975).contains(val)
        }
        if valid {
            clearance.frequency.validated = true
            conf += confidenceValidatedBonus
            conf += confidenceNumericCleanBonus
        } else if clearance.frequency.value != nil && !valid {
            conf += confidenceValidationFailPenalty
        } else if numericClean {
            conf += confidenceNumericCleanBonus
        }
        clearance.frequency.confidence = clamp(conf)
    }

    // MARK: - Initial altitude > 0 and < 60000; expect kept as-is; expect < initial → validated false, confidence penalty

    private static func validateAndScoreAltitude(clearance: inout IFRClearance) {
        var conf = clearance.altitude.confidence
        let initialFt = clearance.altitude.value?.initialFeet
        let expectFt = clearance.altitude.value?.expectFeet
        var valid = false
        var numericClean = false
        if let initAlt = initialFt, initAlt > 0, initAlt < 60000 {
            numericClean = true
            if let expAlt = expectFt {
                if expAlt < initAlt {
                    valid = false
                    conf += confidenceValidationFailPenalty
                } else {
                    valid = true
                }
            } else {
                valid = true
            }
        }
        if valid {
            clearance.altitude.validated = true
            conf += confidenceValidatedBonus
            if initialFt != nil { conf += confidenceNumericCleanBonus }
        } else if clearance.altitude.value != nil && initialFt != nil && (initialFt! <= 0 || initialFt! >= 60000) {
            conf += confidenceValidationFailPenalty
        } else if numericClean {
            conf += confidenceNumericCleanBonus
        }
        clearance.altitude.confidence = clamp(conf)
    }

    // MARK: - Clearance limit exists in provider (stub). If dataProvider is nil, validated remains false.

    private static func validateAndScoreClearanceLimit(clearance: inout IFRClearance, dataProvider: AviationDataProvider?) {
        var conf = clearance.clearanceLimit.confidence
        var valid = false
        if let name = clearance.clearanceLimit.value, !name.isEmpty, let provider = dataProvider {
            valid = provider.hasClearanceLimit(name)
        }
        if valid && clearance.clearanceLimit.value != nil {
            clearance.clearanceLimit.validated = true
            conf += confidenceValidatedBonus
        }
        clearance.clearanceLimit.confidence = clamp(conf)
    }

    // MARK: - Overall confidence (sum of weighted slot contributions; no renormalization)

    private static func computeOverallConfidence(clearance: inout IFRClearance) {
        let clearanceLimitContribution = clearance.clearanceLimit.value != nil
            ? weightClearanceLimit * clearance.clearanceLimit.confidence : 0
        let routeContribution = clearance.route.value != nil
            ? weightRoute * clearance.route.confidence : 0
        let altitudeContribution = clearance.altitude.value != nil
            ? weightAltitude * clearance.altitude.confidence : 0
        let frequencyContribution = clearance.frequency.value != nil
            ? weightFrequency * clearance.frequency.confidence : 0
        let squawkContribution = clearance.squawk.value != nil
            ? weightSquawk * clearance.squawk.confidence : 0

        clearance.overallConfidence = clamp(
            clearanceLimitContribution +
            routeContribution +
            altitudeContribution +
            frequencyContribution +
            squawkContribution
        )
    }

    private static func clamp(_ v: Double) -> Double {
        min(1.0, max(0.0, v))
    }
}
