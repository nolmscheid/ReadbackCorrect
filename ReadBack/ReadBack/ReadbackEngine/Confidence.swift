// ReadbackEngine/Confidence.swift
// Deterministic scoring: base 0.5, bonuses for validation, penalties for conflicts/uncertainty.

import Foundation

public struct ConfidenceModel {
    public static let baseScore = 0.5
    public static let bonusValidNumeric = 0.15
    public static let bonusSnappedValid = 0.20
    public static let bonusIntentValid = 0.15
    public static let bonusRunwayOp = 0.12
    public static let bonusRunwayValidated = 0.10
    public static let penaltyRunwayImpossible = 0.15
    public static let penaltyUncertainField = 0.10
    public static let penaltyConflict = 0.20
    public static let cap = 0.99

    /// Compute overall confidence and per-field confidences.
    public static func compute(
        hasValidNumericTokens: Bool,
        hasValidSnaps: Bool,
        hasValidatedIntent: Bool,
        uncertainFields: [String],
        hasConflict: Bool,
        hasRunwayOp: Bool = false,
        runwayValidated: Bool? = nil
    ) -> (overall: Double, fieldConfidences: [String: Double]) {
        var score = baseScore
        if hasValidNumericTokens { score += bonusValidNumeric }
        if hasValidSnaps { score += bonusSnappedValid }
        if hasValidatedIntent { score += bonusIntentValid }
        if hasRunwayOp { score += bonusRunwayOp }
        if runwayValidated == true { score += bonusRunwayValidated }
        if runwayValidated == false { score -= penaltyRunwayImpossible }
        for _ in uncertainFields { score -= penaltyUncertainField }
        if hasConflict { score -= penaltyConflict }
        score = min(cap, max(0.0, score))
        var fieldConfidences: [String: Double] = [:]
        for f in uncertainFields { fieldConfidences[f] = max(0, 0.5 - penaltyUncertainField) }
        return (score, fieldConfidences)
    }
}
