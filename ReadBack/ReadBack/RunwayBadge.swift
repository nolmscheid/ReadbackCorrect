import SwiftUI

struct RunwayBadge: View {

    enum BadgeType {
        case hold
        case taxi
        case taxiTo
        case takeoff
        case land
        case cross
    }

    let runway: String
    let type: BadgeType
    /// nil = unknown (yellow icon), true = valid (green check), false = invalid (red X).
    var validated: Bool? = nil

    private var validatedLogValue: String {
        switch validated {
        case true: return "true"
        case false: return "false"
        case .none: return "nil"
        }
    }

    var body: some View {
        let _ = ReadbackDebugLog.log("uiBadge: runway=\(runway) validated=\(validatedLogValue)")
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(runway)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                validationIcon
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(runwaySignBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            #if DEBUG
            validationStateLabel
            #endif
        }
    }

    /// VALID: green check. INVALID: red X (octagon, prominent). UNKNOWN: yellow question (no red/green).
    @ViewBuilder
    private var validationIcon: some View {
        if validated == true {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        } else if validated == false {
            Image(systemName: "xmark.octagon.fill")
                .font(.body)
                .foregroundStyle(.white)
        } else {
            Image(systemName: "questionmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.yellow)
        }
    }

    #if DEBUG
    @ViewBuilder
    private var validationStateLabel: some View {
        let label: String = switch validated {
        case true: "Valid"
        case false: "Invalid"
        case .none: "Unknown"
        }
        Text(label)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
    #endif

    private var runwaySignBackground: Color {
        if validated == false { return .red }
        switch type {
        case .hold: return .red
        case .taxi: return .red
        case .taxiTo: return .red
        case .takeoff: return .red
        case .land: return .red
        case .cross: return .red
        }
    }
}
