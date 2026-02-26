import SwiftUI

/// IFR tab: same transmissions as ATC but cards show CRAFT notepad when the transmission is an IFR clearance.
/// Use this tab when receiving an IFR clearance (e.g. "Cleared to Denver Airport via...") so the CRAFT layout appears.
struct IFRView: View {

    @ObservedObject var atcRecognizer: ATCLiveRecognizer

    var body: some View {
        VStack(spacing: 12) {

            Text("IFR — CRAFT Clearances")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Tap LISTEN, then COMMIT when the clearance is complete.")
                .font(.caption)
                .foregroundStyle(.tertiary)

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
                if atcRecognizer.isListening {
                    HStack(spacing: 12) {
                        Button(action: {
                            // Delay so the recognizer can flush final tokens; main thread stays responsive so recognition updates aren't starved
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                                atcRecognizer.commitNow()
                            }
                        }) {
                            Text("COMMIT")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.blue.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        Button(action: { atcRecognizer.stopListening() }) {
                            Text("STOP")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(.horizontal)
                } else {
                    Button(action: { atcRecognizer.startListening(useIFRThreshold: true) }) {
                        Text("LISTEN")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal)
                }
            }

            if !atcRecognizer.liveTranscript.isEmpty {
                Text(atcRecognizer.liveTranscript.uppercased())
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(atcRecognizer.transmissions.filter { $0.kind == .ifr }) { t in
                        TransmissionCard(transmission: t, recognizer: atcRecognizer, showCRAFT: true)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.top, 8)
        .onAppear {
            atcRecognizer.commitOnlyOnTap = true
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
}
