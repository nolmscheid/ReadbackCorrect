import SwiftUI
import AVFoundation

struct TransmissionCard: View {

    let transmission: Transmission
    let recognizer: ATCLiveRecognizer
    /// When true (IFR tab), show CRAFT notepad for IFR clearances. When false (ATC tab), never show CRAFT so "cleared to land" stays a simple land row.
    var showCRAFT: Bool = false
    @AppStorage("showCardBodyText") private var showCardBodyText = true
    @State private var hasPlayedMaydayAlert = false
    @State private var maydayFlashPhase = false
    @State private var showDiagramSheet = false
    @State private var diagramToShowInSheet: AirportDiagramInfo?
    /// Cache so we don't re-run buildRows/extractCRAFT when only liveTranscript (or other unrelated @Published) changed.
    @State private var cardCache: (key: String, normalized: String, rows: [Row], isMatch: Bool, isMayday: Bool)?

    var body: some View {
        let crossValKey = transmission.crossRunwayValidated.keys.sorted().map { k in
            let v = transmission.crossRunwayValidated[k] ?? nil
            return "\(k):\(v == true ? "t" : (v == false ? "f" : "n"))"
        }.joined(separator: ",")
        let viaKey = transmission.viaTaxiways.joined(separator: ",")
        let taxiValKey = transmission.taxiToRunwayValidated == true ? "t" : (transmission.taxiToRunwayValidated == false ? "f" : "n")
        let cacheKey = "\(transmission.text)|\(recognizer.callsign)|\(showCRAFT)|rwy:\(transmission.runwayFromIntent ?? "nil")|val:\(transmission.runwayValidated.map { $0 ? "t" : "f" } ?? "n")|cross:\(crossValKey)|via:\(viaKey)|taxi:\(transmission.taxiToRunway ?? "nil"):\(taxiValKey)"
        let (normalizedUpper, rows, isMatch, isMayday): (String, [Row], Bool, Bool) = {
            if let cache = cardCache, cache.key == cacheKey {
                return (cache.normalized, cache.rows, cache.isMatch, cache.isMayday)
            }
            let rawUpper = transmission.text.uppercased()
            let compressedUpper = CallsignFormatter.compressSpokenCallsigns(in: rawUpper)
            let normalized = AviationNormalizer.normalize(compressedUpper, waypointIds: AviationDataManager.shared.waypointIds).uppercased()
            let mayday = normalized.contains("MAYDAY")
            let match = CallsignFormatter.matchesTransmission(compressedUpper, desiredUserInput: recognizer.callsign)
            let builtRows = Self.buildRows(
                from: normalized,
                isMatch: match,
                isMayday: mayday,
                showCRAFT: showCRAFT,
                runwayFromIntent: transmission.runwayFromIntent,
                runwayValidated: transmission.runwayValidated,
                crossRunwayValidated: transmission.crossRunwayValidated,
                viaTaxiways: transmission.viaTaxiways,
                taxiToRunway: transmission.taxiToRunway,
                taxiToRunwayValidated: transmission.taxiToRunwayValidated
            )
            // Defer cache write to avoid "Modifying state during view update"
            let key = cacheKey
            DispatchQueue.main.async { cardCache = (key, normalized, builtRows, match, mayday) }
            if transmission.runwayFromIntent != nil || transmission.taxiToRunway != nil || normalized.contains("RUNWAY") {
                let badge: String
                if let opRunway = transmission.runwayFromIntent {
                    badge = opRunway
                } else if let taxiRwy = transmission.taxiToRunway {
                    badge = "taxi:\(taxiRwy)"
                } else if normalized.contains("RUNWAY") {
                    badge = "parsed"
                } else {
                    badge = "none"
                }
                let op = Self.runwayOperationFromNormalized(normalized)
                let valStr = transmission.runwayValidated.map { $0 ? "true" : "false" } ?? "nil"
                let taxiValStr = transmission.taxiToRunwayValidated.map { $0 ? "true" : "false" } ?? "nil"
                ReadbackDebugLog.log("uiCard: op=\(op) runwayBadge=\(badge) fromIntent=\(transmission.runwayFromIntent != nil) runwayValidated=\(valStr) taxiToRunway=\(transmission.taxiToRunway ?? "nil") taxiValidated=\(taxiValStr) transcript=\"\(transmission.text.prefix(80))\(transmission.text.count > 80 ? "…" : "")\"")
            }
            return (normalized, builtRows, match, mayday)
        }()

        // 6) Display body text (remove callsign from body if matched)
        let bodyText = buildDisplayBodyText(from: normalizedUpper, isMatch: isMatch)

        // 7) "LOAD KANE" / "LOAD KXXX" – special phrase (no callsign); picks which diagram to show. LOAD also sets default for future taxi cards. No bundle fallback; only downloaded diagrams or saved default.
        let loadDiagram = AirportDiagramInfo.diagramFromLoadPhrase(normalizedUpper)
        let diagramForSheet = loadDiagram
            ?? AirportDiagramInfo.diagramFromTransmission(transmission.text)
            ?? AirportDiagramInfo.defaultDiagram
        let showDiagramButton = (normalizedUpper.contains("TAXI") || loadDiagram != nil) && diagramForSheet != nil

        VStack(alignment: .leading, spacing: 10) {

            // Callsign line (only if matched)
            if isMatch {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                    Text(CallsignFormatter.normalizeUserCallsign(recognizer.callsign))
                        .font(.system(.title3, design: .monospaced))
                        .bold()
                }
            }

            // Intent rows (MAYDAY first when present, then taxi, hold short, climb, heading, etc.)
            ForEach(rows) { row in
                row.view
            }

            // "LOAD KXXX" recognized – show which diagram will open
            if let diagram = loadDiagram {
                HStack(spacing: 6) {
                    Image(systemName: "map.fill")
                        .foregroundStyle(.blue)
                    Text("Load diagram: \(diagram.airportId)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }

            // Show on diagram (when card has taxi instructions or "LOAD KXXX")
            if showDiagramButton, let diagram = diagramForSheet {
                Button(action: {
                    if let loadD = loadDiagram {
                        AirportDiagramInfo.setDefaultDiagram(airportId: loadD.airportId)
                    }
                    diagramToShowInSheet = diagram
                    showDiagramSheet = true
                }) {
                    Label("Show on diagram", systemImage: "map")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
            }

            // Full transmission text (monospace) — hidden when Settings → "Show full text on cards" is off
            if showCardBodyText && !bodyText.isEmpty {
                Text(bodyText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)   // full width, consistent size
        .background(cardBackground(isMayday: isMayday))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
        .sheet(isPresented: $showDiagramSheet) {
            if let d = diagramToShowInSheet {
                AirportDiagramView(diagram: d, transmission: transmission, recognizer: recognizer)
            }
        }
        .onAppear {
            if isMayday {
                hasPlayedMaydayAlert = true
                maydayFlashPhase = true
            }
        }
    }

    private func cardBackground(isMayday: Bool) -> some View {
        Group {
            if isMayday {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.red.opacity(maydayFlashPhase ? 0.95 : 0.72))
                    .animation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true), value: maydayFlashPhase)
            } else {
                Color(.systemGray6)
            }
        }
    }

    // MARK: - Row model

    private struct Row: Identifiable {
        let id = UUID()
        let index: Int
        let view: AnyView
    }

    /// Words to drop from VIA so we show [A] [E] not [A] [AND] [E] or [E] [ON] [B] when transcription says "Echo proceed on Bravo".
    private static let viaConjunctions: Set<String> = ["AND", "OR", "TO", "IN", "ON"]

    /// IFR CRAFT extraction (clearance limit, route, altitude, frequency, transponder, void time).
    private struct CRAFTData {
        var c: String?
        var r: String?
        var a: String?   // main altitude + optional "Expect ... after departure"
        var f: String?
        var t: String?
        var v: String?
    }

    // MARK: - Build rows in spoken order (static so diagram overlay can reuse)

    /// Derives runway operation name from normalized text for debug logging (holdShort, lineUpAndWait, clearedTakeoff, clearedLand).
    private static func runwayOperationFromNormalized(_ normalized: String) -> String {
        if normalized.contains("CLEARED TO LAND") || normalized.contains("CLEAR TO LAND") { return "clearedLand" }
        if normalized.contains("CLEARED FOR TAKEOFF") || normalized.contains("CLEARED TAKEOFF") { return "clearedTakeoff" }
        if normalized.contains("LINE UP AND WAIT") || normalized.contains("LINE UP & WAIT") { return "lineUpAndWait" }
        if normalized.contains("HOLD SHORT") { return "holdShort" }
        if normalized.contains("HOLD RUNWAY") { return "holdShort" }
        return "runway"
    }

    private static func buildRows(
        from text: String,
        isMatch: Bool,
        isMayday: Bool = false,
        showCRAFT: Bool = false,
        runwayFromIntent: String? = nil,
        runwayValidated: Bool? = nil,
        crossRunwayValidated: [String: Bool?] = [:],
        viaTaxiways: [String] = [],
        taxiToRunway: String? = nil,
        taxiToRunwayValidated: Bool? = nil
    ) -> [Row] {

        var rows: [Row] = []

        // MAYDAY (distress): highest priority row; card also flashes and plays alert sound
        if isMayday {
            rows.append(Row(index: -1, view: AnyView(maydayRow())))
        }

        // IFR CRAFT only when showCRAFT (IFR tab) and not a landing clearance ("cleared to land runway 32")
        let isLandClearance = text.contains("CLEARED TO LAND") || text.contains("CLEAR TO LAND")
        if showCRAFT, !isLandClearance, text.contains("CLEARED TO"), let craft = extractCRAFT(from: text), craftHasContent(craft) {
            rows.append(Row(index: 0, view: AnyView(craftCardView(data: craft))))
        }

        // TAXI (T3: skip main taxi row when no runway and only one VIA – that single VIA shows as progressive row instead). Use intent runway + validation when present.
        if let taxiIndex = firstIndex(ofAny: ["TAXI"], in: text) {
            let taxiRunway = taxiToRunway ?? extractTaxiRunway(from: text)
            let viaFromIntent = viaTaxiways
            let viaFromText = viaFromIntent.isEmpty ? extractTaxiwaysVia(from: text) : viaFromIntent
            let showMainTaxiRow = taxiRunway != nil || viaFromText.count > 1
            if showMainTaxiRow {
                rows.append(Row(index: taxiIndex, view: AnyView(
                    taxiRow(
                        runway: taxiRunway,
                        via: viaFromText,
                        hasTaxiIntent: taxiToRunway != nil,
                        taxiToValidated: taxiToRunwayValidated
                    )
                )))
            }
        }

        // CROSS RUNWAY (all occurrences, in order; per-runway validation from intent)
        for (idx, runway) in extractAllCrossRunways(from: text) {
            let validated = crossRunwayValidated[runway] ?? nil
            rows.append(Row(index: idx, view: AnyView(
                crossRunwayRow(runway: runway, validated: validated)
            )))
        }

        // HOLD SHORT (all occurrences, in order; validation state from single runway op intent)
        for (idx, runway) in extractAllHoldShortRunways(from: text) {
            rows.append(Row(index: idx, view: AnyView(
                holdShortRow(runway: runway, validated: runwayValidated)
            )))
        }

        // CONTINUE ON / PROCEED ON / TAXI VIA [taxiway] (7110.65: progressive taxi; "taxi," "proceed," or step-wise)
        for (idx, taxiway, label) in extractProgressiveTaxiwayRows(from: text) {
            rows.append(Row(index: idx, view: AnyView(
                progressiveTaxiwayRow(taxiway: taxiway, label: label)
            )))
        }

        // CLIMB / DESCEND / MAINTAIN ALTITUDE (T5: separate icons – up / down / level)
        if let alt = extractAltitudeWithType(from: text) {
            rows.append(Row(index: alt.index, view: AnyView(
                altitudeRow(altitude: alt.altitude, type: alt.type)
            )))
        }

        // HEADING (T6: HEADING TO; T19: turn left/right; FAA: maintain heading 180)
        if let headingResult = extractHeadingWithTurn(from: text) {
            rows.append(Row(index: headingResult.index, view: AnyView(
                headingRow(heading: headingResult.heading, turn: headingResult.turnDirection, isMaintain: headingResult.isMaintain)
            )))
        }

        // CLEARED FOR TAKEOFF (badge from intent when present, else parsed)
        if let toIndex = firstIndex(ofAny: ["CLEARED FOR TAKEOFF"], in: text) {
            let runway = runwayFromIntent ?? extractRunwayAfter(keyword: "RUNWAY", in: text)
            rows.append(Row(index: toIndex, view: AnyView(
                takeoffRow(runway: runway, validated: runwayValidated)
            )))
        }

        // CLEARED TO LAND (badge from intent when present, else parsed)
        if let landIndex = firstIndex(ofAny: ["CLEARED TO LAND", "CLEAR TO LAND"], in: text) {
            let runway = runwayFromIntent ?? extractRunwayAfter(keyword: "RUNWAY", in: text)
            rows.append(Row(index: landIndex, view: AnyView(
                landRow(runway: runway, validated: runwayValidated)
            )))
        }

        // CONTACT / MONITOR [facility] [frequency]; or "[facility] frequency [value]" (e.g. "departure frequency 124.7")
        if let radioIndex = firstIndex(ofAny: ["CONTACT", "MONITOR", "FREQUENCY"], in: text),
           let (facility, frequency, isMonitor) = extractContactOrMonitor(from: text),
           facility != nil || frequency != nil {
            rows.append(Row(index: radioIndex, view: AnyView(
                contactOrMonitorRow(facility: facility, frequency: frequency, isMonitor: isMonitor)
            )))
        }

        // SQUAWK [code] (T10: normalizer fixes "quack" → "squawk")
        if let squawkIndex = firstIndex(ofAny: ["SQUAWK"], in: text),
           let code = extractSquawk(from: text) {
            rows.append(Row(index: squawkIndex, view: AnyView(
                squawkRow(code: code)
            )))
        }

        // GO AROUND (T13; normalizer fixes "go round" → "go around")
        if let goAroundIndex = firstIndex(ofAny: ["GO AROUND"], in: text) {
            rows.append(Row(index: goAroundIndex, view: AnyView(
                goAroundRow()
            )))
        }

        // LINE UP AND WAIT (T16: badge from intent when present, else parsed)
        if let luawIndex = firstIndex(ofAny: ["LINE UP AND WAIT"], in: text) {
            let runway = runwayFromIntent ?? extractLineUpAndWaitRunway(from: text)
            rows.append(Row(index: luawIndex, view: AnyView(
                lineUpAndWaitRow(runway: runway, validated: runwayValidated)
            )))
        }

        // MAINTAIN VFR (visual flight rules; normalizer fixes bfr/gfr/fr → vfr; eye = visual)
        if let vfrIndex = firstIndex(ofAny: ["MAINTAIN VFR"], in: text) {
            rows.append(Row(index: vfrIndex, view: AnyView(
                maintainVFRRow()
            )))
        }

        // Sort by spoken order
        rows.sort { $0.index < $1.index }

        return rows
    }

    /// Intent rows only (same icons/format as card), for diagram overlay. Use when opening diagram from a taxi card.
    static func intentRowsView(transmission: Transmission, recognizer: ATCLiveRecognizer, showCRAFT: Bool = false) -> some View {
        let rawUpper = transmission.text.uppercased()
        let compressedUpper = CallsignFormatter.compressSpokenCallsigns(in: rawUpper)
        let normalizedUpper = AviationNormalizer.normalize(compressedUpper, waypointIds: AviationDataManager.shared.waypointIds).uppercased()
        let isMayday = normalizedUpper.contains("MAYDAY")
        let isMatch = CallsignFormatter.matchesTransmission(compressedUpper, desiredUserInput: recognizer.callsign)
        let rows = buildRows(from: normalizedUpper, isMatch: isMatch, isMayday: isMayday, showCRAFT: showCRAFT, runwayFromIntent: transmission.runwayFromIntent, runwayValidated: transmission.runwayValidated, crossRunwayValidated: transmission.crossRunwayValidated, viaTaxiways: transmission.viaTaxiways, taxiToRunway: transmission.taxiToRunway, taxiToRunwayValidated: transmission.taxiToRunwayValidated)
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { row in
                row.view
            }
        }
    }

    // MARK: - Display body text (remove callsign from body if matched)

    private func buildDisplayBodyText(from text: String, isMatch: Bool) -> String {

        var t = text

        // If matched, remove the desired callsign (with and without N) from the body text so it does not repeat
        if isMatch {
            let desired = CallsignFormatter.normalizeUserCallsign(recognizer.callsign).uppercased()
            let desiredNoN = desired.hasPrefix("N") ? String(desired.dropFirst()) : desired

            t = t.replacingOccurrences(of: desired, with: " ")
            t = t.replacingOccurrences(of: desiredNoN, with: " ")
        }

        // cleanup spacing
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return t
    }

    // MARK: - Row Views

    private static func taxiRow(
        runway: String?,
        via: [String],
        hasTaxiIntent: Bool,
        taxiToValidated: Bool? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .foregroundStyle(.yellow)
                Text("TAXI")
                    .font(.headline)
                    .foregroundStyle(.yellow)
                if let r = runway {
                    Text("TO")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if hasTaxiIntent {
                        RunwayBadge(runway: r, type: .taxiTo, validated: taxiToValidated)
                    } else {
                        RunwayLocationBadge(runway: r)
                    }
                }
            }

            if !via.isEmpty {
                HStack(alignment: .center, spacing: 8) {
                    Text("VIA")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(via, id: \.self) { tw in
                        TaxiwayBadge(taxiway: tw)
                    }
                }
                .padding(.leading, 34)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func crossRunwayRow(runway: String, validated: Bool? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.left.and.right")
                .foregroundStyle(.green)
            Text("CROSS")
                .font(.headline)
                .foregroundStyle(.green)
            RunwayBadge(runway: runway, type: .cross, validated: validated)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func holdShortRow(runway: String?, validated: Bool? = nil) -> some View {
        HStack(spacing: 10) {
            Text("HOLD SHORT")
                .font(.headline)
                .foregroundStyle(.red)

            if let r = runway {
                RunwayBadge(runway: r, type: .hold, validated: validated)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Label is "CONTINUE ON", "PROCEED ON", or "TAXI VIA" per 7110.65.
    private static func progressiveTaxiwayRow(taxiway: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.forward.circle")
                .foregroundStyle(.yellow)
            Text(label)
                .font(.headline)
                .foregroundStyle(.yellow)
            TaxiwayBadge(taxiway: taxiway)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum AltitudeType { case climb, descend, maintain }

    private static func altitudeRow(altitude: String, type: AltitudeType) -> some View {
        // FAA 7110.65: full label in text (consistent with MAINTAIN HEADING 270); graphics + label.
        let color: Color = .blue
        return HStack(spacing: 10) {
            switch type {
            case .climb:
                Image(systemName: "arrow.up")
                    .foregroundStyle(color)
                Image(systemName: "line.horizontal.3")
                    .foregroundStyle(color)
                Text("CLIMB AND MAINTAIN \(altitude)")
                    .font(.headline)
                    .foregroundStyle(color)
            case .descend:
                Image(systemName: "arrow.down")
                    .foregroundStyle(color)
                Image(systemName: "line.horizontal.3")
                    .foregroundStyle(color)
                Text("DESCEND AND MAINTAIN \(altitude)")
                    .font(.headline)
                    .foregroundStyle(color)
            case .maintain:
                Image(systemName: "line.horizontal.3")
                    .foregroundStyle(color)
                Text("MAINTAIN \(altitude)")
                    .font(.headline)
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func headingRow(heading: String, turn: String? = nil, isMaintain: Bool = false) -> some View {
        let label = isMaintain ? "MAINTAIN HEADING \(heading)" : "HEADING \(heading)"
        return HStack(spacing: 10) {
            // Modifier icon (maintain = level, or turn left/right) when applicable
            if turn == "left" {
                Image(systemName: "arrow.turn.up.left")
                    .foregroundStyle(.blue)
            } else if turn == "right" {
                Image(systemName: "arrow.turn.up.right")
                    .foregroundStyle(.blue)
            } else if isMaintain {
                Image(systemName: "line.horizontal.3")
                    .foregroundStyle(.blue)
            }
            // Heading icon always shown for every heading row
            Image(systemName: "location.north.fill")
                .foregroundStyle(.blue)
            Text(label)
                .font(.headline)
                .foregroundStyle(.blue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func maydayRow() -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.white)
            Text("MAYDAY — DISTRESS")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private static func goAroundRow() -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.up")
                .foregroundStyle(.red)
            Text("GO AROUND")
                .font(.headline)
                .foregroundStyle(.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func lineUpAndWaitRow(runway: String?, validated: Bool? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "stopwatch")
                .foregroundStyle(.orange)
            Text("LINE UP AND WAIT")
                .font(.headline)
                .foregroundStyle(.orange)
            if let r = runway {
                RunwayBadge(runway: r, type: .taxi, validated: validated)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func maintainVFRRow() -> some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.fill")
                .foregroundStyle(.teal)
            Text("MAINTAIN VFR")
                .font(.headline)
                .foregroundStyle(.teal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - IFR CRAFT notepad-style card

    private static func craftCardView(data: CRAFTData) -> some View {
        let letterFont = Font.system(size: 28, weight: .bold, design: .rounded)
        let letterColor = Color.primary.opacity(0.9)
        let columnBg = Color(.systemGray5).opacity(0.6)

        func craftRow(letter: String, content: String?, lineLimit: Int? = 2) -> some View {
            HStack(alignment: .top, spacing: 12) {
                Text(letter)
                    .font(letterFont)
                    .foregroundStyle(letterColor)
                    .frame(width: 32, height: 32, alignment: .center)
                    .background(columnBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(content ?? "—")
                    .font(.system(.subheadline, design: .default))
                    .foregroundStyle(content != nil ? .primary : .secondary)
                    .lineLimit(lineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        }

        func craftCRow(content: String?) -> some View {
            let identifier = content.flatMap { AviationDataManager.shared.airportIdentifier(forClearanceName: $0) }
            let displayName = content.flatMap { AviationDataManager.shared.airportDisplayName(forClearanceName: $0) }
            let primaryText = displayName ?? content ?? "—"
            return HStack(alignment: .top, spacing: 12) {
                Text("C")
                    .font(letterFont)
                    .foregroundStyle(letterColor)
                    .frame(width: 32, height: 32, alignment: .center)
                    .background(columnBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(primaryText)
                        .font(.system(.subheadline, design: .default))
                        .foregroundStyle(content != nil ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let id = identifier, !id.isEmpty {
                        Text(id)
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        }

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("CRAFT")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.bottom, 6)

            craftCRow(content: data.c)
            craftRow(letter: "R", content: data.r, lineLimit: 4)
            craftRow(letter: "A", content: data.a)
            craftRow(letter: "F", content: data.f)
            craftRow(letter: "T", content: data.t)
            craftRow(letter: "V", content: data.v)
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func takeoffRow(runway: String?, validated: Bool? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "airplane.departure")
                .foregroundStyle(.green)

            Text("CLEARED FOR TAKEOFF")
                .font(.headline)
                .foregroundStyle(.green)

            if let r = runway {
                RunwayBadge(runway: r, type: .taxi, validated: validated)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func landRow(runway: String?, validated: Bool? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "airplane.arrival")
                .foregroundStyle(.green)

            Text("CLEARED TO LAND")
                .font(.headline)
                .foregroundStyle(.green)

            if let r = runway {
                RunwayBadge(runway: r, type: .taxi, validated: validated)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func contactOrMonitorRow(facility: String?, frequency: String?, isMonitor: Bool) -> some View {
        let label = isMonitor ? "MONITOR" : "CONTACT"
        return HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.headline)
                    .foregroundStyle(.blue)
                HStack(spacing: 8) {
                    if let f = facility, !f.isEmpty {
                        Text(f)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    if let fr = frequency, !fr.isEmpty {
                        Text(fr)
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func squawkRow(code: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "number")
                .foregroundStyle(.orange)
            Text("SQUAWK")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(code)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers (indexes)

    private static func firstIndex(ofAny needles: [String], in text: String) -> Int? {
        var best: Int?
        for n in needles {
            if let r = text.range(of: n) {
                let idx = text.distance(from: text.startIndex, to: r.lowerBound)
                if best == nil || idx < best! { best = idx }
            }
        }
        return best
    }

    // MARK: - Helpers (regex)

    /// Collapse spaces in ASR output like "11 9 .1" → "119.1"; return nil if result isn't a valid xxx.x frequency.
    private static func normalizeFrequencyCapture(_ raw: String) -> String? {
        let collapsed = raw.replacingOccurrences(of: " ", with: "")
        guard collapsed.range(of: #"^\d{3}\.\d{1,3}$"#, options: .regularExpression) != nil else { return nil }
        return collapsed
    }

    private static func firstRegexGroup(pattern: String, in text: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        guard match.numberOfRanges > group else { return nil }
        guard let r = Range(match.range(at: group), in: text) else { return nil }
        return String(text[r])
    }

    private static func firstRegexGroups(pattern: String, in text: String, g1: Int, g2: Int) -> (String?, String?) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (nil, nil) }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return (nil, nil) }

        var s1: String?
        var s2: String?

        if match.numberOfRanges > g1, let r1 = Range(match.range(at: g1), in: text) {
            s1 = String(text[r1])
        }
        if match.numberOfRanges > g2, let r2 = Range(match.range(at: g2), in: text) {
            s2 = String(text[r2])
        }
        return (s1, s2)
    }

    // MARK: - Extractors

    private static func extractRunwayAfter(keyword: String, in text: String) -> String? {
        // e.g. "RUNWAY 32", "RUNWAY 27L"
        let pattern = #"\#(keyword)\s+(\d{1,2})([LRC])?"#
        let (n, suf) = firstRegexGroups(pattern: pattern, in: text, g1: 1, g2: 2)
        guard let num = n else { return nil }
        let suffix = suf ?? ""
        return num.count == 1 ? "0\(num)\(suffix)" : "\(num)\(suffix)"
    }

    private static func extractHoldShortRunway(from text: String) -> String? {
        extractAllHoldShortRunways(from: text).first?.runway
    }

    /// All "HOLD SHORT RUNWAY XX" / "HOLD SHORT 22R" / "HOLD RUNWAY XX" in spoken order.
    private static func extractAllHoldShortRunways(from text: String) -> [(index: Int, runway: String)] {
        // Match: HOLD SHORT RUNWAY nn, HOLD SHORT nn (e.g. "hold short 22R"), HOLD RUNWAY nn
        let pattern = #"(?:HOLD\s+SHORT(?:\s+OF)?\s+RUNWAY|HOLD\s+SHORT|HOLD\s+(?:OF\s+)?RUNWAY)\s+(\d{1,2})([LRC])?"#
        return allRunwayMatches(pattern: pattern, in: text) { num, suf in
            let s = suf.uppercased()
            return num.count == 1 ? "0\(num)\(s)" : "\(num)\(s)"
        }
    }

    /// All "CROSS RUNWAY XX" / "CROSS 22L 22R" in spoken order (T2: support "cross 22 left 22 right" without saying "runway").
    private static func extractAllCrossRunways(from text: String) -> [(index: Int, runway: String)] {
        guard let crossRange = text.range(of: "CROSS ", options: .caseInsensitive) else { return [] }
        let fromCross = String(text[crossRange.lowerBound...])
        let segment: String
        if let hold = fromCross.range(of: "HOLD SHORT", options: .caseInsensitive) {
            segment = String(fromCross[..<hold.lowerBound])
        } else if let hold2 = fromCross.range(of: "HOLD ", options: .caseInsensitive) {
            segment = String(fromCross[..<hold2.lowerBound])
        } else if let cont = fromCross.range(of: "CONTINUE", options: .caseInsensitive) {
            segment = String(fromCross[..<cont.lowerBound])
        } else if let taxi = fromCross.range(of: "TAXI TO", options: .caseInsensitive) {
            segment = String(fromCross[..<taxi.lowerBound])
        } else {
            segment = fromCross
        }
        // "CROSS RUNWAY 24L", "CROSS 22L" (no runway word), "24L 24R", "AND RUNWAY 24R", etc.
        let pattern = #"(?:CROSS\s+RUNWAY\s+|CROSS\s+|AND\s+RUNWAY\s+|IN\s+RUNWAY\s+|AND\s+|IN\s+|,\s*|(?<!RUNWAY\s)\s+)(\d{1,2})([LRC])?"#
        let runs = allRunwayMatches(pattern: pattern, in: segment) { num, suf in
            num.count == 1 ? "0\(num)\(suf.uppercased())" : "\(num)\(suf.uppercased())"
        }
        let baseIdx = text.distance(from: text.startIndex, to: crossRange.lowerBound)
        return runs.map { (baseIdx + $0.0, $0.1) }
    }

    private static func allRunwayMatches(pattern: String, in text: String, format: (String, String) -> String) -> [(index: Int, runway: String)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        var results: [(Int, String)] = []
        regex.enumerateMatches(in: text, options: [], range: nsRange) { match, _, _ in
            guard let m = match,
                  m.numberOfRanges >= 2,
                  let matchRange = Range(m.range, in: text),
                  let r1 = Range(m.range(at: 1), in: text) else { return }
            let num = String(text[r1])
            var suf = ""
            if m.numberOfRanges > 2, let r2 = Range(m.range(at: 2), in: text) { suf = String(text[r2]) }
            let runway = format(num, suf)
            let idx = text.distance(from: text.startIndex, to: matchRange.lowerBound)
            results.append((idx, runway))
        }
        return results
    }

    /// 7110.65: "continue on," "proceed on," or "taxi via" [taxiway] for progressive taxi. Returns (index, taxiway, label).
    private static func extractProgressiveTaxiwayRows(from text: String) -> [(index: Int, taxiway: String, label: String)] {
        let phonetic: [String: String] = [
            "ALPHA":"A","ALFA":"A", "BRAVO":"B", "CHARLIE":"C", "DELTA":"D", "ECHO":"E",
            "FOXTROT":"F", "GOLF":"G", "HOTEL":"H", "INDIA":"I", "JULIET":"J", "JULIETT":"J",
            "KILO":"K", "LIMA":"L", "MIKE":"M", "NOVEMBER":"N", "OSCAR":"O", "PAPA":"P",
            "QUEBEC":"Q", "ROMEO":"R", "SIERRA":"S", "TANGO":"T", "UNIFORM":"U", "VICTOR":"V",
            "WHISKEY":"W", "XRAY":"X", "X-RAY":"X", "YANKEE":"Y", "ZULU":"Z"
        ]
        func toTaxiway(_ chunk: String) -> String? {
            let c = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if let letter = phonetic[c] { return letter }
            if c.count == 1, c.first!.isLetter { return c }
            if c.count == 2, c.first!.isLetter { return String(c.prefix(1)) }
            return nil
        }

        var results: [(Int, String, String)] = []

        for phrase in ["CONTINUE ON", "PROCEED ON"] {
            let pattern = #"\#(phrase)\s+([A-Z]{1,2}|[A-Z]+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let m = match, m.numberOfRanges >= 2,
                      let fullRange = Range(m.range, in: text),
                      let r1 = Range(m.range(at: 1), in: text),
                      let tw = toTaxiway(String(text[r1])) else { return }
                let idx = text.distance(from: text.startIndex, to: fullRange.lowerBound)
                results.append((idx, tw, phrase))
            }
        }

        // "TAXI VIA [single taxiway]" (progressive); skip "TAXI TO RUNWAY ... VIA A B" by requiring single token after VIA
        let taxiViaPattern = #"TAXI\s+VIA\s+([A-Z]|[A-Z]{2,})(?=\s|,|\.|$)"#
        guard let taxiViaRegex = try? NSRegularExpression(pattern: taxiViaPattern) else { return results }
        let nsRange = NSRange(text.startIndex..., in: text)
        taxiViaRegex.enumerateMatches(in: text, options: [], range: nsRange) { match, _, _ in
            guard let m = match, m.numberOfRanges >= 2,
                  let fullRange = Range(m.range, in: text),
                  let r1 = Range(m.range(at: 1), in: text),
                  let tw = toTaxiway(String(text[r1])) else { return }
            let idx = text.distance(from: text.startIndex, to: fullRange.lowerBound)
            results.append((idx, tw, "TAXI VIA"))
        }

        return results
    }

    /// CONTACT = switch and talk; MONITOR = listen only. Facility: tower, departure, approach, center, ground, etc.
    /// Also matches "[facility] frequency [value]" (e.g. "departure frequency 124.7", "approach frequency 124.9").
    private static func extractContactOrMonitor(from text: String) -> (facility: String?, frequency: String?, isMonitor: Bool)? {
        // Try "CONTACT/MONITOR facility [frequency]" first (facility required so "MONITOR TOWER" captures TOWER)
        let withFacility = #"(CONTACT|MONITOR)\s+([A-Z]+)(?:\s+([0-9]{3}\.[0-9]{1,3}))?"#
        if let r = try? NSRegularExpression(pattern: withFacility),
           let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           m.numberOfRanges >= 3,
           let r1 = Range(m.range(at: 1), in: text),
           let r2 = Range(m.range(at: 2), in: text) {
            let isMonitor = String(text[r1]) == "MONITOR"
            let facility = String(text[r2])
            var frequency: String?
            if m.numberOfRanges > 3, let r3 = Range(m.range(at: 3), in: text) { frequency = String(text[r3]) }
            return (facility, frequency, isMonitor)
        }
        // Then "CONTACT/MONITOR frequency" only (e.g. "CONTACT 124.8")
        let freqOnly = #"(CONTACT|MONITOR)\s+([0-9]{3}\.[0-9]{1,3})"#
        if let r = try? NSRegularExpression(pattern: freqOnly),
           let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           m.numberOfRanges >= 3,
           let r1 = Range(m.range(at: 1), in: text),
           let r2 = Range(m.range(at: 2), in: text) {
            let isMonitor = String(text[r1]) == "MONITOR"
            return (nil, String(text[r2]), isMonitor)
        }
        // "[facility] frequency [value]" (e.g. "departure frequency 124.7" or ASR "11 9 .1") — implies contact
        let facilityFreqPattern = #"(DEPARTURE|APPROACH|TOWER|CENTER|GROUND)\s+FREQUENCY\s+([\d\s.]+?)(?=\s+SQUAWK|\s+[A-Z]{2,}|\s*$)"#
        if let facility = firstRegexGroup(pattern: facilityFreqPattern, in: text, group: 1),
           let rawFreq = firstRegexGroup(pattern: facilityFreqPattern, in: text, group: 2),
           let freq = normalizeFrequencyCapture(rawFreq) {
            return (facility, freq, false)
        }
        // "clearance delivery frequency [value]"
        let clearanceFreq = #"CLEARANCE\s+DELIVERY\s+FREQUENCY\s+([0-9]{3}\.[0-9]{1,3})"#
        if let r = try? NSRegularExpression(pattern: clearanceFreq),
           let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           m.numberOfRanges >= 2,
           let r1 = Range(m.range(at: 1), in: text) {
            return ("CLEARANCE DELIVERY", String(text[r1]), false)
        }
        return nil
    }

    private static func extractSquawk(from text: String) -> String? {
        // "SQUAWK 4621" (also matches after normalizer fixes "squak")
        if let s = firstRegexGroup(pattern: #"SQUAWK\s+(\d{4})"#, in: text, group: 1) { return s }
        // ASR merged "frequency 119.1. Squawk 4463" → normalizer split to "119.1 4463"; 4 digits after frequency = squawk
        return firstRegexGroup(pattern: #"FREQUENCY\s+\d{3}\.\d{1,3}\s+(\d{4})\b"#, in: text, group: 1)
    }

    // MARK: - IFR CRAFT extraction

    /// Formats route string for display: space after V+digits before waypoint (V23OCN → V23 OCN), comma spacing, segment separators.
    private static func formatRouteForDisplay(_ route: String) -> String {
        var r = route
        // V23OCN → V23 OCN (airway + waypoint); V123AB → V123 AB
        if let regex = try? NSRegularExpression(pattern: #"(V\d+)([A-Z]{2,})"#) {
            let range = NSRange(r.startIndex..., in: r)
            r = regex.stringByReplacingMatches(in: r, range: range, withTemplate: "$1 $2")
        }
        // Comma without trailing space: "V23,OCN" → "V23, OCN"
        r = r.replacingOccurrences(of: ",", with: ", ")
        // Collapse multiple spaces
        r = r.split(separator: " ").filter { !$0.isEmpty }.joined(separator: " ")
        // Segment separators for readability: "FLY HEADING 175 VECTORS" → "FLY HEADING 175 • VECTORS"
        for prefix in [" VECTORS ", " DIRECT ", " THEN "] {
            if r.uppercased().contains(prefix.uppercased()) {
                r = r.replacingOccurrences(of: prefix, with: " •\(prefix)", options: .caseInsensitive)
            }
        }
        return r.trimmingCharacters(in: .whitespaces)
    }

    private static func craftHasContent(_ craft: CRAFTData) -> Bool {
        craft.c != nil || craft.r != nil || craft.a != nil || craft.f != nil || craft.t != nil || craft.v != nil
    }

    private static func extractCRAFT(from text: String) -> CRAFTData? {
        var craft = CRAFTData()

        // C — "Cleared to the Denver Airport" / "Cleared to Appleton" (stop before route so "Appleton Fly direct..." → C = Appleton)
        // Don't end at period when it's "St." (abbreviation): use (?<!st)\. so "St. Cloud" is captured fully.
        // Also stop at " Fly " / " Fly direct " / " Fly heading " so C doesn't eat the route when there's no "via".
        if let r = try? NSRegularExpression(pattern: #"CLEARED\s+TO\s+(?:THE\s+)?(.+?)(?=\s+VIA\s+|\s+FLY\s+|\s+MAINTAIN\s+|\s+DEPARTURE\s+|\s+SQUAWK\s+|(?<!st)\.|$)"#, options: .caseInsensitive),
           let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           m.numberOfRanges >= 2, let range = Range(m.range(at: 1), in: text) {
            var c = String(text[range]).trimmingCharacters(in: .whitespaces)
            // Trim at " after " or suffix " after" (capture can end with "ROCHESTER AFTER" when regex stops at " FLY ")
            if let afterRange = c.range(of: " after ", options: .caseInsensitive) {
                c = String(c[..<afterRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            } else if c.uppercased().hasSuffix(" AFTER") {
                c = String(c.dropLast(6)).trimmingCharacters(in: .whitespaces)
            }
            // End C at first sentence boundary (". ") — preserve "St. Cloud"
            if let periodRange = c.range(of: ". ") {
                let beforePeriod = String(c[..<periodRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let lastWord = beforePeriod.split(separator: " ").last.map(String.init) ?? ""
                let isAbbrev = (lastWord.uppercased() == "ST" || (lastWord.count <= 3 && lastWord.allSatisfy { $0.isLetter }))
                if !isAbbrev { c = beforePeriod }
            }
            c = c.replacingOccurrences(of: " AIRPORT", with: "", options: .caseInsensitive)
            c = c.replacingOccurrences(of: "^THE ", with: "", options: .caseInsensitive)
            craft.c = c.isEmpty ? nil : c
        }

        // R — After " VIA " or " FLY DIRECT " / " FLY " (phraseology: "via X" or "fly direct X, then...")
        let endMarkers = [" MAINTAIN ", " EXPECT ", " DEPARTURE ", " SQUAWK ", " CONTACT "]
        func routeFrom(afterStart startRange: Range<String.Index>) -> String? {
            let after = String(text[startRange.upperBound...])
            var endIndex = after.endIndex
            for marker in endMarkers {
                if let r = after.range(of: marker, options: .caseInsensitive) {
                    if r.lowerBound < endIndex { endIndex = r.lowerBound }
                }
            }
            var route = String(after[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Don’t truncate at ". " when it’s an abbreviation (e.g. "ST. CLOUD") — only when the word before the period is long (sentence boundary)
            if let periodRange = route.range(of: ". ") {
                let beforePeriod = String(route[..<periodRange.lowerBound])
                let lastWord = beforePeriod.split(separator: " ").last.map(String.init) ?? ""
                let isAbbrev = lastWord.count <= 3 && lastWord.allSatisfy { $0.isLetter }
                if !isAbbrev {
                    route = beforePeriod.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            let routeEndTrims = [" CLIMB AND", " DESCEND AND", " EXPECT "]
            for suffix in routeEndTrims {
                if route.uppercased().hasSuffix(suffix.uppercased()) {
                    route = String(route.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
            return route.isEmpty ? nil : route
        }
        /// Strip altitude instruction that leaked into route (e.g. "DIRECT MAINTAIN 3000" → "DIRECT", "MAINTAIN 3000" → "")
        func trimAltitudeFromRoute(_ s: String) -> String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            // Route that is only an altitude (e.g. "MAINTAIN 3000" when nothing after "FLY DIRECT") → empty so caller shows "DIRECT"
            if t.uppercased().hasPrefix("MAINTAIN ") {
                return ""
            }
            if let range = s.range(of: " MAINTAIN ", options: .caseInsensitive) {
                return String(s[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return s
        }
        if let viaRange = text.range(of: " VIA ", options: .caseInsensitive), let route = routeFrom(afterStart: viaRange) {
            craft.r = formatRouteForDisplay(trimAltitudeFromRoute(route))
        } else if let flyDirectRange = text.range(of: " FLY DIRECT ", options: .caseInsensitive) {
            let afterDirect = routeFrom(afterStart: flyDirectRange)
            // "Fly direct" with nothing after (e.g. "… FLY DIRECT MAINTAIN 3000") → show "DIRECT"
            var routeText = afterDirect.flatMap { $0.isEmpty ? nil : $0 } ?? "DIRECT"
            routeText = trimAltitudeFromRoute(routeText)
            if routeText.isEmpty { routeText = "DIRECT" }
            craft.r = formatRouteForDisplay(routeText)
        } else if let flyRange = text.range(of: " FLY ", options: .caseInsensitive), let route = routeFrom(afterStart: flyRange) {
            var r = trimAltitudeFromRoute(route)
            if r.isEmpty, text.range(of: " FLY DIRECT ", options: .caseInsensitive) != nil { r = "DIRECT" }
            if !r.isEmpty { craft.r = formatRouteForDisplay(r) }
        }

        // A — "Maintain 5000" / "Maintain FL350" / "Maintain flight level 350" / "expect 7000 5 minutes after departure"
        let mantPattern = #"MAINTAIN\s+(?:(FL)(\d+)|FLIGHT\s+LEVEL\s+(\d+)|(\d+))"#
        if let mant = try? NSRegularExpression(pattern: mantPattern),
           let mm = mant.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            var altNum: String?
            var isFL = false
            if mm.numberOfRanges > 2, let r2 = Range(mm.range(at: 2), in: text) {
                altNum = String(text[r2])
                isFL = mm.range(at: 1).location != NSNotFound
            }
            if altNum == nil, mm.numberOfRanges > 3, let r3 = Range(mm.range(at: 3), in: text) {
                altNum = String(text[r3])
                isFL = true
            }
            if altNum == nil, mm.numberOfRanges > 4, let r4 = Range(mm.range(at: 4), in: text) {
                altNum = String(text[r4])
            }
            if let num = altNum {
            // Only show FL when value is in real flight level range (≥180). ASR often turns "nine thousand" into "FL 900" → show 9000 ft, not FL900 (90,000 ft).
            let flVal = Int(num)
            let useFL = isFL && (flVal ?? 0) >= 180
            var aLine = useFL ? "FL\(num)" : (isFL && (flVal ?? 0) < 180 ? "\((flVal ?? 0) * 100)" : num)
            // "Expect 7000 5 min after dep" / "Expect 7000 in 5 minutes..." / "Expect FL350 10 min..."
            let expPattern = #"EXPECT\s+(?:FL|FLIGHT\s+LEVEL)?\s*(\d+)\s+(?:FEET?\s+)?(?:IN\s+)?(\d+)\s+MIN(?:UTE)?S?\s+AFTER\s+DEP(?:ARTURE)?"#
            var gotExpect = false
            if let exp = try? NSRegularExpression(pattern: expPattern, options: .caseInsensitive),
               let em = exp.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               em.numberOfRanges >= 3,
               let er1 = Range(em.range(at: 1), in: text),
               let er2 = Range(em.range(at: 2), in: text) {
                let expectAlt = String(text[er1])
                let expectMin = String(text[er2])
                // Only use FL when phrase says "flight level" or "FL" — 10,000 ft is not FL10000
                let expIsFL = text.uppercased().contains("FLIGHT LEVEL") || text.contains("FL\(expectAlt)")
                aLine += "  •  Exp \(expIsFL ? "FL" : "")\(expectAlt) \(expectMin)' a.d."
                gotExpect = true
            }
            // ASR merges "flight level 350" + "10" → "FLIGHT LEVEL 35010MINUTES" (no space before MINUTES)
            if !gotExpect, let flExp = try? NSRegularExpression(pattern: #"EXPECT\s+FLIGHT\s+LEVEL\s+(\d{4,5})\s*MIN(?:UTE)?S?\s+AFTER\s+DEP(?:ARTURE)?"#, options: .caseInsensitive),
               let fm = flExp.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               fm.numberOfRanges >= 2, let fr = Range(fm.range(at: 1), in: text),
               let merged = Int(text[fr]), (1...59).contains(merged % 100) {
                let expectAltVal = merged / 100   // 35010 → FL350
                let expectMinVal = merged % 100   // 35010 → 10
                aLine += "  •  Exp FL\(expectAltVal) \(expectMinVal)' a.d."
                gotExpect = true
            }
            // ASR often merges "7000" and "5" → "7005" (expect 7005 minutes...); \s* allows "7005MINUTES" with no space
            if !gotExpect, let singleExp = try? NSRegularExpression(pattern: #"EXPECT\s+(\d{4,5})\s*MIN(?:UTE)?S?\s+AFTER\s+DEP(?:ARTURE)?"#, options: .caseInsensitive),
               let sm = singleExp.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               sm.numberOfRanges >= 2, let sr = Range(sm.range(at: 1), in: text),
               let merged = Int(text[sr]), (1...59).contains(merged % 100) {
                let expectAltVal: Int
                let expectMinVal = merged % 100
                let expIsFL: Bool
                if merged >= 18000 {
                    // 35012 → FL350, 12 min; 18010 → FL180, 10 min (actual flight levels)
                    expectAltVal = merged / 100
                    expIsFL = true
                } else {
                    // 7005 → 7000, 5 min; 10010 → 10000, 10 min (altitude in feet, not FL)
                    // ASR can merge "8000" and "10" into "80010" → treat as 8000 ft, 10 min (not 80000)
                    let candidate = (merged % 100 == 10) ? (merged - 10) / 10 : -1
                    if candidate >= 5000, candidate <= 11000, candidate % 1000 == 0 {
                        expectAltVal = candidate
                    } else {
                        expectAltVal = (merged / 100) * 100
                    }
                    expIsFL = false
                }
                aLine += "  •  Exp \(expIsFL ? "FL" : "")\(expectAltVal) \(expectMinVal)' a.d."
            }
            craft.a = aLine
            }
        }

        // F — "Departure frequency 124.7" or ASR "11 9 .1" (spaces); normalize to "119.1"
        if let raw = firstRegexGroup(pattern: #"DEPARTURE\s+FREQUENCY\s+([\d\s.]+?)(?=\s+SQUAWK|\s+[A-Z]{2,}|\s*$)"#, in: text, group: 1),
           let freq = normalizeFrequencyCapture(raw) {
            craft.f = freq
        } else if let raw = firstRegexGroup(pattern: #"CONTACT\s+DEPARTURE\s+([\d\s.]+?)(?=\s+SQUAWK|\s+[A-Z]{2,}|\s*$)"#, in: text, group: 1),
                  let freq = normalizeFrequencyCapture(raw) {
            craft.f = freq
        } else if let freq = firstRegexGroup(pattern: #"OF\s+FREQUENCY\s+(\d{3}\.\d{1,3})"#, in: text, group: 1) {
            craft.f = freq
        } else if let raw = firstRegexGroup(pattern: #"FREQUENCY\s+([\d\s.]+?)(?=\s+SQUAWK|\s+[A-Z]{2,}|\s*$)"#, in: text, group: 1),
                  let freq = normalizeFrequencyCapture(raw) {
            craft.f = freq
        }

        // T — "Squawk 4721"
        craft.t = extractSquawk(from: text)

        // V — "Void if not off by 1430" / "Clearance void ... 1430"
        if let v = firstRegexGroup(pattern: #"VOID\s+IF\s+NOT\s+OFF\s+BY\s+(\d{4})"#, in: text, group: 1) {
            craft.v = v + " Z"
        } else if let v = firstRegexGroup(pattern: #"CLEARANCE\s+VOID[^\d]*(\d{4})"#, in: text, group: 1) {
            craft.v = v + " Z"
        }

        return craft
    }

    private static func extractTaxiRunway(from text: String) -> String? {
        // "TAXI TO RUNWAY 32" or "TAXI RUNWAY 22" (T2: without "TO")
        let patterns = [
            #"TAXI\s+TO\s+RUNWAY\s+(\d{1,2})([LRC])?"#,
            #"TAXI\s+RUNWAY\s+(\d{1,2})([LRC])?"#
        ]
        for pattern in patterns {
            let (n, suf) = firstRegexGroups(pattern: pattern, in: text, g1: 1, g2: 2)
            if let num = n {
                let suffix = suf ?? ""
                return num.count == 1 ? "0\(num)\(suffix)" : "\(num)\(suffix)"
            }
        }
        return nil
    }

    private static func extractTaxiwaysVia(from text: String) -> [String] {
        // "VIA ALPHA", "VIA ALPHA ECHO" — stop at CROSS / HOLD SHORT / RUNWAY so runways (e.g. 22L) don't appear in VIA
        let pattern = #"VIA\s+([A-Z0-9\s\-]+?)(?:,|CROSS|HOLD\s+SHORT|RUNWAY|$)"#
        guard let chunk = firstRegexGroup(pattern: pattern, in: text, group: 1)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: " ")
        else { return [] }

        let tokens = chunk
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).uppercased() }
            .filter { !Self.viaConjunctions.contains($0) }

        // Exclude runway designators (e.g. 22L, 9R) and the word CROSS from VIA list
        func isRunwayDesignator(_ s: String) -> Bool {
            guard let first = s.first else { return false }
            if s == "CROSS" { return true }
            if first.isNumber { return s.count <= 3 && (s.count == 1 || s.dropFirst().allSatisfy { $0.isNumber || "LRC".contains($0) }) }
            return false
        }

        let phonetic: [String: String] = [
            "ALPHA":"A","ALFA":"A",
            "BRAVO":"B",
            "CHARLIE":"C",
            "DELTA":"D",
            "ECHO":"E",
            "FOXTROT":"F",
            "GOLF":"G",
            "HOTEL":"H",
            "INDIA":"I",
            "JULIET":"J","JULIETT":"J",
            "KILO":"K",
            "LIMA":"L",
            "MIKE":"M",
            "NOVEMBER":"N",
            "OSCAR":"O",
            "PAPA":"P",
            "QUEBEC":"Q",
            "ROMEO":"R",
            "SIERRA":"S",
            "TANGO":"T",
            "UNIFORM":"U",
            "VICTOR":"V",
            "WHISKEY":"W",
            "XRAY":"X","X-RAY":"X",
            "YANKEE":"Y",
            "ZULU":"Z"
        ]

        var out: [String] = []
        for t in tokens {
            if isRunwayDesignator(t) { continue }
            if let mapped = phonetic[t] {
                out.append(mapped)
            } else if t.count <= 4 && t.allSatisfy({ $0.isLetter }) {
                out.append(t)
            }
        }

        // Dedup but keep order
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    private static func extractAltitude(from text: String) -> String? {
        extractAltitudeWithType(from: text)?.altitude
    }

    /// Returns (index, altitude, type) for CLIMB / DESCEND / MAINTAIN. Supports feet (e.g. 5000) and flight level (e.g. FL350).
    private static func extractAltitudeWithType(from text: String) -> (index: Int, altitude: String, type: AltitudeType)? {
        let phrases: [(String, AltitudeType)] = [
            ("CLIMB AND MAINTAIN", .climb),
            ("DESCEND AND MAINTAIN", .descend),
            ("MAINTAIN", .maintain)
        ]
        for (phrase, type) in phrases {
            guard let idx = firstIndex(of: phrase, in: text) else { continue }
            // Flight level: "maintain flight level 350" or "maintain FL 350". Only use FL when value ≥ 180 (ASR may say "FL 900" for "nine thousand" → return 9000 ft).
            let flPattern = #"\#(phrase)\s+(?:FLIGHT\s+LEVEL|FL)\s+(\d{2,3})"#
            if let flNum = firstRegexGroup(pattern: flPattern, in: text, group: 1),
               let flVal = Int(flNum) {
                if flVal >= 180 {
                    return (idx, "FL\(flNum)", type)
                }
                return (idx, "\(flVal * 100)", type)  // 90 → 9000, 100 → 10000
            }
            // Altitude in feet: 3–5 digits (e.g. 5000, 9000)
            if let alt = firstRegexGroup(pattern: #"\#(phrase)\s+(\d{3,5})"#, in: text, group: 1) {
                return (idx, alt, type)
            }
        }
        return nil
    }

    private static func firstIndex(of needle: String, in text: String) -> Int? {
        guard let r = text.range(of: needle) else { return nil }
        return text.distance(from: text.startIndex, to: r.lowerBound)
    }

    /// Returns (index, heading, turnDirection, isMaintain). FAA: "maintain heading (of) 180" / "heading 180" / "heading to 180".
    private static func extractHeadingWithTurn(from text: String) -> (index: Int, heading: String, turnDirection: String?, isMaintain: Bool)? {
        // MAINTAIN HEADING [OF] nnn | HEADING TO nnn | HEADING nnn
        let pattern = #"(?:MAINTAIN\s+HEADING\s+(?:OF\s+)?|HEADING\s+TO\s+|HEADING\s+)(\d{1,3})"#
        guard let h = firstRegexGroup(pattern: pattern, in: text, group: 1) else { return nil }
        let heading: String
        if h.count == 1 { heading = "00\(h)" }
        else if h.count == 2 { heading = "0\(h)" }
        else { heading = h }
        let isMaintain = text.range(of: "MAINTAIN HEADING", options: .caseInsensitive) != nil
        let idx = firstIndex(ofAny: ["MAINTAIN HEADING", "HEADING TO", "HEADING"], in: text) ?? 0
        var turn: String? = nil
        if let leftRange = text.range(of: "TURN LEFT", options: .caseInsensitive),
           let headRange = text.range(of: "HEADING", options: .caseInsensitive),
           leftRange.upperBound <= headRange.lowerBound { turn = "left" }
        else if let rightRange = text.range(of: "TURN RIGHT", options: .caseInsensitive),
                let headRange = text.range(of: "HEADING", options: .caseInsensitive),
                rightRange.upperBound <= headRange.lowerBound { turn = "right" }
        return (idx, heading, turn, isMaintain)
    }

    private static func extractHeading(from text: String) -> String? {
        extractHeadingWithTurn(from: text)?.heading
    }

    private static func extractLineUpAndWaitRunway(from text: String) -> String? {
        // "Line up and wait runway 14" / "Line up and wait 14L"
        let afterPhrase = #"LINE\s+UP\s+AND\s+WAIT(?:\s+RUNWAY)?\s+(\d{1,2})([LRC])?"#
        if let (n, suf) = firstRegexGroupsOptional(pattern: afterPhrase, in: text, g1: 1, g2: 2), let num = n {
            let suffix = suf ?? ""
            return num.count == 1 ? "0\(num)\(suffix)" : "\(num)\(suffix)"
        }
        // "Runway 14 line up and wait" / "Runway 14L line up and wait"
        let beforePhrase = #"RUNWAY\s+(\d{1,2})([LRC])?\s+LINE\s+UP\s+AND\s+WAIT"#
        guard let (n, suf) = firstRegexGroupsOptional(pattern: beforePhrase, in: text, g1: 1, g2: 2),
              let num = n else { return nil }
        let suffix = suf ?? ""
        return num.count == 1 ? "0\(num)\(suffix)" : "\(num)\(suffix)"
    }

    private static func firstRegexGroupsOptional(pattern: String, in text: String, g1: Int, g2: Int) -> (String?, String?)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        var s1: String?, s2: String?
        if m.numberOfRanges > g1, let r1 = Range(m.range(at: g1), in: text) { s1 = String(text[r1]) }
        if m.numberOfRanges > g2, let r2 = Range(m.range(at: g2), in: text) { s2 = String(text[r2]) }
        return (s1, s2)
    }
}

// MARK: - MAYDAY alert sound (generated tone so it’s audible even when app uses .record for speech)
enum MaydayAlertPlayer {
    private static let sampleRate: Int = 44100
    private static let durationSeconds: Double = 0.6
    private static let toneHz: Double = 700
    private static var playerKeepAlive: AVAudioPlayer?

    /// Call from main queue. Deactivates record session, waits for teardown, then switches to playback and plays tone.
    /// - Parameter isRetry: Pass true when this is the second attempt (avoids infinite retry).
    static func play(isRetry: Bool = false) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch { }

        // Give the system time to fully release the record path before reconfiguring for playback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            do {
                try session.setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                if !isRetry { retryLater() }
                return
            }

            guard let url = writeMaydayToneWAV() else {
                if !isRetry { retryLater() }
                return
            }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                playerKeepAlive = player
                player.play()
                DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds + 0.2) {
                    playerKeepAlive = nil
                    try? FileManager.default.removeItem(at: url)
                    try? session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
                    try? session.setActive(true, options: .notifyOthersOnDeactivation)
                }
            } catch {
                if !isRetry { retryLater() }
            }
        }
    }

    /// One retry after a longer delay in case first attempt was too soon after engine stop
    private static func retryLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                play(isRetry: true)
            }
        }
    }

    private static func writeMaydayToneWAV() -> URL? {
        let numSamples = Int(Double(sampleRate) * durationSeconds)
        let numBytes = 44 + numSamples * 2
        var data = Data(capacity: numBytes)
        func appendU16(_ v: UInt16) { data.append(contentsOf: [UInt8(v & 0xff), UInt8(v >> 8)]) }
        func appendU32(_ v: UInt32) {
            data.append(UInt8(v & 0xff)); data.append(UInt8((v >> 8) & 0xff))
            data.append(UInt8((v >> 16) & 0xff)); data.append(UInt8((v >> 24) & 0xff))
        }
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        appendU32(UInt32(numBytes - 8))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45, 0x66, 0x6d, 0x74, 0x20])
        appendU32(16)
        appendU16(1)
        appendU16(1)
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(sampleRate * 2))
        appendU16(2)
        appendU16(16)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        appendU32(UInt32(numSamples * 2))
        for i in 0..<numSamples {
            let t = Double(i) / Double(sampleRate)
            let sample = 0.5 * sin(2 * .pi * toneHz * t)
            let s16 = Int16(max(-32768, min(32767, sample * 32767)))
            appendU16(UInt16(bitPattern: s16))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mayday_alert_\(UUID().uuidString).wav")
        do {
            try data.write(to: url)
            return url
        } catch { return nil }
    }
}
