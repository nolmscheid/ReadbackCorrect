import CoreLocation
import SwiftUI

struct SettingsView: View {
    @AppStorage("showCardBodyText") private var showCardBodyText = true
    @AppStorage("ReadbackDebug.loggingEnabled") private var readbackDebugLoggingEnabled = true
    @ObservedObject var atcRecognizer: ATCLiveRecognizer
    @ObservedObject var aviationData = AviationDataManager.shared
    @ObservedObject var plateDownloader = PlateDownloadManager.shared
    @State private var plateSearchID: String = ""
    @State private var diagramToShow: AirportDiagramInfo?
    @State private var cardsExpanded = false
    @State private var atcExpanded = false
    @State private var referenceDataExpanded = false
    @State private var airportPlatesExpanded = false
    #if DEBUG
    @State private var simulatedLocationError: String?
    @State private var phraseBankPreviewResults: [PhraseBankPreviewResult]?
    @State private var phraseBankPreviewSelected: PhraseBankPreviewResult?

    private var simulatedLocationSection: some View {
        Group {
            Toggle("Simulated GPS", isOn: $locationManager.useSimulatedLocation)
            TextField("Airport (ICAO or ID)", text: $locationManager.simulatedAirportId)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(.subheadline, design: .monospaced))
            Button("Apply") {
                simulatedLocationError = nil
                let store = ReadbackEngineProvider.sharedStore
                guard store.isLoaded else {
                    simulatedLocationError = "NASR not loaded yet"
                    return
                }
                if !locationManager.updateSimulatedLocationFromAirport(store: store) {
                    simulatedLocationError = "Airport not found in NASR"
                }
            }
            .buttonStyle(.borderedProminent)
            if let loc = locationManager.effectiveLocation {
                Text("Effective GPS: \(String(format: "%.4f", loc.coordinate.latitude)),\(String(format: "%.4f", loc.coordinate.longitude)) \(locationManager.isUsingSimulatedLocation ? "(SIM)" : "(REAL)")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let err = simulatedLocationError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("Use an airport identifier (e.g. KMIC, MIC) to simulate being at that airport for runway validation. Overlay shows (SIM) when active.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
    #endif

    var body: some View {
        NavigationStack {
            List {
            // Cards
            DisclosureGroup(isExpanded: $cardsExpanded) {
                Toggle("Show full text on cards", isOn: $showCardBodyText)
                (Text("When off, ") + Text("MONOSPACE").font(.system(.footnote, design: .monospaced)) + Text(" is removed from card."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } label: {
                Text("Cards")
                    .font(.headline)
            }

            // ATC pause threshold (IFR uses Listen/Commit only)
            DisclosureGroup(isExpanded: $atcExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Silence before commit")
                        Spacer()
                        Text("\(String(format: "%.1f", atcRecognizer.silenceThreshold))s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    Slider(value: $atcRecognizer.silenceThreshold, in: 0.6...2.6, step: 0.1)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                Text("Seconds of silence before auto-committing a phrase on the ATC tab. IFR uses Tap COMMIT when done.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } label: {
                Text("ATC")
                    .font(.headline)
            }

            // Aviation reference data
            DisclosureGroup(isExpanded: $referenceDataExpanded) {
                if let date = aviationData.lastUpdatedDate, let cycle = aviationData.nasrEffectiveDate {
                    HStack {
                        Label("Data", systemImage: "doc.text")
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                            Text("Cycle \(cycle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let size = aviationData.downloadedDataSizeFormatted {
                                Text(size)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                VStack(spacing: 10) {
                    Button {
                        Task { await aviationData.checkForUpdates() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("CHECK FOR UPDATES")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(aviationData.isUpdating)

                    if aviationData.updateAvailable {
                        Button {
                            Task { await aviationData.downloadUpdates() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle")
                                Text("DOWNLOAD")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(aviationData.isUpdating)
                    }
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                if aviationData.nasrEffectiveDate != nil {
                    Button(role: .destructive) {
                        aviationData.clearDownloadedData()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("CLEAR DATA")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                if let msg = aviationData.statusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                }
                Text("Airports, Victor airways, waypoints. The app checks the server's cycle and build date; tap Download to refresh. Clear downloaded data to force re-download (e.g. if the server was updated but the app still says current).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } label: {
                Text("Reference data")
                    .font(.headline)
            }
            .onAppear {
                aviationData.refreshDownloadedDataSize()
            }

            #if DEBUG
            DisclosureGroup {
                Toggle("Readback debug logging", isOn: $readbackDebugLoggingEnabled)
                Text("When on, [READBACK_DEBUG] lines appear in the Xcode console (NASR load, process, intents).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                simulatedLocationSection
                Button("Run PhraseBank (Preview)") {
                    runPhraseBankPreview()
                }
                .sheet(isPresented: Binding(
                    get: { phraseBankPreviewResults != nil },
                    set: { if !$0 { phraseBankPreviewResults = nil; phraseBankPreviewSelected = nil } }
                )) {
                    if let results = phraseBankPreviewResults {
                        PhraseBankPreviewSheet(results: results, selected: $phraseBankPreviewSelected)
                    }
                }
            } label: {
                Text("Developer")
                    .font(.headline)
            }
            #endif

            // Airport diagram plates — search by ID, add diagrams
            airportPlatesDisclosure
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    dismissKeyboard()
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { diagramToShow != nil },
            set: { if !$0 { diagramToShow = nil } }
        )) {
            if let d = diagramToShow {
                AirportDiagramView(diagram: d)
            }
        }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Display name for known diagram IDs when not in reference data (expand as needed).
    private static let diagramDisplayNames: [String: String] = [
        "KMIC": "Crystal",
        "KSTC": "St. Cloud",
        "KMSP": "Minneapolis–St. Paul",
        "KDLH": "Duluth",
        "KANE": "Anoka County–Blaine",
        "KBRD": "Brainerd Lakes Regional",
        "KPRC": "Ernest A. Love Field (Prescott)",
    ]

    @ObservedObject private var locationManager = LocationManager.shared

    private var airportPlatesDisclosure: some View {
        DisclosureGroup(isExpanded: $airportPlatesExpanded) {
            Toggle("Use test position (tap diagram to set)", isOn: $locationManager.useTestPosition)
                .onChange(of: locationManager.useTestPosition) { _, useTest in
                    if !useTest {
                        locationManager.startUpdatingLocation()
                    } else {
                        locationManager.stopUpdatingLocation()
                    }
                }

            TextField("Search by airport ID", text: $plateSearchID)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(.subheadline, design: .monospaced))
                .onAppear {
                    LocationManager.shared.requestWhenInUseAuthorization()
                }

            let search = plateSearchID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let known = AirportDiagramInfo.known
            let matching = search.isEmpty
                ? known
                : known.filter { $0.airportId.contains(search) }

            ForEach(matching, id: \.airportId) { info in
                Button {
                    diagramToShow = info
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.airportId)
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.medium)
                            if let name = aviationData.airportDisplayName(forIdentifier: info.airportId) ?? Self.diagramDisplayNames[info.airportId] {
                                Text(name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(info.localPDFURL != nil ? "On device" : "Available")
                            .font(.caption)
                            .foregroundStyle(info.localPDFURL != nil ? .green : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if info.localPDFURL != nil {
                        Button("Remove", role: .destructive) {
                            plateDownloader.removeDownloaded(airportId: info.airportId)
                        }
                    }
                }
            }

            if !search.isEmpty && matching.isEmpty && plateDownloader.localPDFURL(airportId: search) == nil {
                HStack {
                    Text("No diagram for \(search)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if !search.isEmpty {
                let alreadyDownloaded = plateDownloader.localPDFURL(airportId: search) != nil
                if alreadyDownloaded {
                    HStack {
                        Label("On device", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Remove", role: .destructive) {
                            plateDownloader.removeDownloaded(airportId: search)
                        }
                        .font(.caption)
                    }
                } else {
                    Button {
                        Task { await plateDownloader.downloadDiagram(airportId: search) }
                    } label: {
                        HStack(spacing: 6) {
                            if plateDownloader.isDownloading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.down.circle")
                            }
                            Text(plateDownloader.isDownloading ? "Downloading…" : "Download diagram from FAA")
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(plateDownloader.isDownloading)
                }
            }

            if let err = plateDownloader.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("Search by airport ID (e.g. KMIC, KSTC). Download saves the FAA diagram PDF on your device. Turn \"Use test position\" off to show your real GPS location on the diagram when at the airport; turn it on and tap the diagram to pin the dot for testing off-site.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } label: {
            Text("Airport Diagram Plates")
                .font(.headline)
        }
    }

    #if DEBUG
    private func runPhraseBankPreview() {
        guard let cases = try? PhraseBankLoader.loadFromBundle(.main), !cases.isEmpty else {
            phraseBankPreviewResults = []
            return
        }
        let engine = ReadbackEngineProvider.sharedEngine
        let defaultGPS = PhraseGPS(lat: 44.88, lon: -93.22)
        var results: [PhraseBankPreviewResult] = []
        for phraseCase in cases {
            let gps = phraseCase.gps.map { GPSContext(lat: $0.lat, lon: $0.lon) }
                ?? GPSContext(lat: defaultGPS.lat, lon: defaultGPS.lon)
            let result = engine.process(transcript: phraseCase.transcript, gps: gps)
            let normalizedUpper = result.normalizedText.uppercased()
            var pass = true
            if let contains = phraseCase.expectedNormalizedContains {
                for sub in contains where !normalizedUpper.contains(sub.uppercased()) { pass = false; break }
            }
            if phraseCase.expectedIntents.isEmpty {
                let hasRunwayOp = result.intents.contains { if case .runwayOperation = $0 { return true }; return false }
                if hasRunwayOp { pass = false }
            } else {
                for expected in phraseCase.expectedIntents {
                    let match = phraseBankIntentMatches(expected: expected, intents: result.intents)
                    if !match { pass = false; break }
                }
            }
            let intentsDesc = result.intents.map { i -> String in
                switch i {
                case .runwayOperation(let r): return "runwayOp(\(r.operation.rawValue),\(r.runway ?? "nil"))"
                case .taxiToRunway(let t): return "taxiToRunway(\(t.runway ?? "nil"))"
                case .crossRunway(let c): return "crossRunway(\(c.runways))"
                case .continueTaxi(let c): return "continueTaxi(\(c.taxiway ?? "nil"))"
                case .viaTaxiway(let v): return "viaTaxiway(\(v.taxiway))"
                case .frequencyChange(let f): return "freq(\(f.frequencyMHz))"
                case .altitude(let a): return "alt(\(a.verb.rawValue),\(a.altitudeFt))"
                case .ifrClearance: return "ifr"
                }
            }.joined(separator: ", ")
            results.append(PhraseBankPreviewResult(
                id: phraseCase.id,
                title: phraseCase.title,
                passed: pass,
                transcript: phraseCase.transcript,
                normalizedText: result.normalizedText,
                intentsDescription: intentsDesc,
                runwayValidated: result.runwayValidated
            ))
        }
        phraseBankPreviewResults = results
    }

    private func phraseBankIntentMatches(expected: ExpectedIntent, intents: [ParsedIntent]) -> Bool {
        intents.contains { intent in
            switch (expected.kind, intent) {
            case ("runwayOp", .runwayOperation(let r)):
                return (expected.operation == nil || r.operation.rawValue == expected.operation)
                    && (expected.runway == nil || r.runway == expected.runway)
            case ("taxiToRunway", .taxiToRunway(let t)):
                let rwyMatch = expected.runway == nil || t.runway == expected.runway
                let valMatch = expected.validated == nil || t.validated == expected.validated
                return rwyMatch && valMatch
            case ("crossRunway", .crossRunway(let c)):
                guard let expRunways = expected.runways else { return true }
                return Set(c.runways) == Set(expRunways)
            case ("continueTaxi", .continueTaxi(let c)):
                return (expected.extra?["taxiway"]).map { c.taxiway == $0 } ?? (c.taxiway != nil)
            case ("viaTaxiway", .viaTaxiway(let v)):
                return (expected.extra?["taxiway"]).map { v.taxiway == $0 } ?? true
            default: return false
            }
        }
    }
    #endif
}

#if DEBUG
struct PhraseBankPreviewResult: Identifiable {
    let id: String
    let title: String
    let passed: Bool
    let transcript: String
    let normalizedText: String
    let intentsDescription: String
    let runwayValidated: Bool?
}

struct PhraseBankPreviewSheet: View {
    let results: [PhraseBankPreviewResult]
    @Binding var selected: PhraseBankPreviewResult?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let passed = results.filter(\.passed).count
                Section {
                    Text("Passed: \(passed) / \(results.count)")
                        .font(.headline)
                }
                ForEach(results) { r in
                    Button {
                        selected = r
                    } label: {
                        HStack {
                            Image(systemName: r.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(r.passed ? .green : .red)
                            Text(r.title)
                                .font(.subheadline)
                        }
                    }
                }
            }
            .navigationTitle("PhraseBank Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selected) { r in
                VStack(alignment: .leading, spacing: 12) {
                    Text(r.title).font(.headline)
                    Text("Transcript: \(r.transcript)").font(.caption)
                    Text("Normalized: \(r.normalizedText)").font(.caption)
                    Text("Intents: \(r.intentsDescription)").font(.caption)
                    Text("Runway validated: \(r.runwayValidated.map { $0 ? "true" : "false" } ?? "nil")").font(.caption)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding()
                .presentationDetents([.medium])
            }
        }
    }
}
#endif
