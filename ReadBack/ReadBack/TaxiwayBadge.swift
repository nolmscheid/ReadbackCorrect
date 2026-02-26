import SwiftUI

struct TaxiwayBadge: View {
    let taxiway: String

    var body: some View {
        Text(taxiway.uppercased())
            .font(.system(.headline, design: .monospaced))
            .foregroundStyle(.yellow)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.yellow, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
