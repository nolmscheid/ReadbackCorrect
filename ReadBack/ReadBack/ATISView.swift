import SwiftUI

struct ATISView: View {

    @ObservedObject var recognizer: ATISLiveRecognizer

    var body: some View {
        VStack(spacing: 16) {

            // Top controls
            HStack(spacing: 14) {
                Button(action: { recognizer.startListening() }) {
                    Text("LISTEN")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(recognizer.isListening ? Color.gray.opacity(0.35) : Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .disabled(recognizer.isListening)

                Button(action: { recognizer.stopListening() }) {
                    Text("STOP")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(recognizer.isListening ? Color.red : Color.gray.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .disabled(!recognizer.isListening)
            }
            .padding(.horizontal)

            // Live box
            VStack(alignment: .leading, spacing: 8) {
                Text("LIVE")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))

                    Text(recognizer.liveTranscript.uppercased())
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(12)
                }
                .frame(height: 120)
            }
            .padding(.horizontal)

            // History chips
            if !recognizer.history.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("HISTORY")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(recognizer.history) { item in
                                Button(action: { recognizer.selectHistory(id: item.id) }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.shortTitle)
                                            .font(.headline)
                                        Text(item.shortTime)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }

            // Card
            ScrollView {
                VStack(spacing: 12) {
                    if let report = recognizer.currentReport {
                        ATISCard(report: report)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.top, 8)
    }
}

private struct ATISCard: View {
    let report: ATISReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ATIS SUMMARY")
                .font(.headline)

            field("INFO", report.information)
            field("TIME", report.timeZulu)
            field("WIND", report.wind)
            field("VIS", report.visibility)
            field("CEILING", report.ceiling)
            field("TEMP/DEW", report.temperatureDewpoint)
            field("ALT", report.altimeter)

            if !report.runways.isEmpty {
                field("RWY", report.runways.joined(separator: ", "))
            }
            if !report.approaches.isEmpty {
                field("APCH", report.approaches.joined(separator: ", "))
            }
            if !report.remarks.isEmpty {
                field("RMKS", report.remarks.joined(separator: " • "))
            }

            Divider()

            Text("RAW")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(report.raw)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func field(_ label: String, _ value: String?) -> some View {
        if let v = value, !v.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)

                Text(v)
                    .font(.headline)
            }
        }
    }
}
