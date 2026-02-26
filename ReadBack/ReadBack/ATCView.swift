import SwiftUI

struct ATCView: View {

    @ObservedObject var atcRecognizer: ATCLiveRecognizer
    @State private var callsignSectionExpanded = false

    var body: some View {
        VStack(spacing: 12) {

            Text(statusLabel)
                .font(.headline)
                .foregroundStyle(statusColor)

            if atcRecognizer.maydayAlertActive {
                Button(action: { atcRecognizer.acknowledgeMayday() }) {
                    Text("ACKNOWLEDGE")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal)
            } else {
                Button(action: {
                    if atcRecognizer.isListening {
                        atcRecognizer.stopListening()
                    } else {
                        atcRecognizer.startListening(useIFRThreshold: false)
                    }
                }) {
                    Text(atcRecognizer.isListening ? "STOP" : "LISTEN")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(atcRecognizer.isListening ? Color.red : Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal)
            }

            // Live transcript
            if !atcRecognizer.liveTranscript.isEmpty {
                Text(atcRecognizer.liveTranscript.uppercased())
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            Divider()

            // Callsign — collapsible to save space; collapsed shows current callsign + filter badge
            DisclosureGroup(isExpanded: $callsignSectionExpanded) {
                HStack {
                    Text("Filter")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: $atcRecognizer.callsignFilterEnabled)
                        .labelsHidden()
                }
                .padding(.vertical, 4)
                .padding(.trailing, 12)

                TextField("Callsign (e.g. N641CC)", text: $atcRecognizer.callsign)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "airplane.circle.fill")
                        .foregroundStyle(.secondary)
                    Text(atcRecognizer.callsign.isEmpty ? "Callsign" : atcRecognizer.callsign)
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundStyle(atcRecognizer.callsign.isEmpty ? .secondary : .primary)
                    if atcRecognizer.callsignFilterEnabled {
                        Text("FILTER ON")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .padding(.horizontal)

            Divider()

            // Cards (ATC only — hold short, taxi, cleared to land, etc.; IFR clearances/readbacks show on IFR tab)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(atcRecognizer.transmissions.filter { $0.kind == .atc }) { t in
                        TransmissionCard(transmission: t, recognizer: atcRecognizer, showCRAFT: false)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.top, 8)
        .onAppear {
            atcRecognizer.commitOnlyOnTap = false
            LocationManager.shared.requestWhenInUseAuthorization()
            LocationManager.shared.startUpdatingLocation()
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            ReadbackDebugOverlay()
                .padding(12)
        }
        #endif
    }

    private var statusLabel: String {
        if atcRecognizer.maydayAlertActive { return "MAYDAY — Tap ACKNOWLEDGE to resume" }
        return atcRecognizer.isListening ? "LISTENING..." : "IDLE"
    }

    private var statusColor: Color {
        if atcRecognizer.maydayAlertActive { return .orange }
        return atcRecognizer.isListening ? .green : .gray
    }
}
