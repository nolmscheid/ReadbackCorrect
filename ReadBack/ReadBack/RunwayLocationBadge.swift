import SwiftUI

struct RunwayLocationBadge: View {
    let runway: String  // e.g. "32", "27L", "04"

    /// Runway signage: red background, white text, thin black border (consistent with hold position / runway signs).
    var body: some View {
        Text(runway.uppercased())
            .font(.system(.headline, design: .monospaced))
            .bold()
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.red)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.black, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel("Runway \(runway)")
    }
}
