import Foundation
import Speech
import AVFoundation
import Combine
import CoreLocation

final class ATCLiveRecognizer: ObservableObject {

    // UI
    @Published var liveTranscript: String = ""
    @Published var transmissions: [Transmission] = []
    @Published var isListening: Bool = false
    /// When true, MAYDAY was just committed; listening is stopped and alert is playing. Tap ACKNOWLEDGE to resume.
    @Published var maydayAlertActive: Bool = false

    // Settings
    @Published var callsignFilterEnabled: Bool = true
    @Published var callsign: String = "N641CC"
    /// ATC tab: silence duration before committing a phrase. IFR tab uses Listen/Commit only (no auto-commit on pause).
    @Published var silenceThreshold: Double = 1.9
    /// When true, do not auto-commit on silence (IFR tab: commit only when user taps COMMIT). Set by IFR/ATC tab on appear.
    var commitOnlyOnTap: Bool = false

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    /// Set true before intentional cancel/restart so 301 is logged as expected, not as error.
    private var didRequestRestart: Bool = false

    private var silenceTimer: Timer?
    private var lastChangeTime = Date()

    // Running best transcript from Apple
    private var currentFullText: String = ""

    // Snapshot at last commit (used to compute deltas)
    private var lastCommittedSnapshot: String = ""

    // Baseline for current phrase window (delta since phrase started)
    private var phraseStartSnapshot: String = ""

    // Prevent exact repeat commits (key includes transcript + runway + validated + SIM + lat/lon)
    private var lastCommittedFinal: String = ""
    private var lastCommittedDedupeKey: String?
    private var lastCommittedNormText: String?
    private var lastCommittedRwy: String?
    private var lastCommittedVal: String?
    private var lastCommittedSim: Bool?
    private var lastCommittedLat: Double?
    private var lastCommittedLon: Double?

    init() {
        requestPermissions()
    }

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }

    // MARK: - Start/Stop

    /// Start listening. Commit mode (pause vs tap-only) is determined by which tab is visible (commitOnlyOnTap set in IFR/ATC onAppear).
    func startListening(useIFRThreshold: Bool = false) {
        guard !isListening else { return }

        isListening = true
        liveTranscript = ""
        currentFullText = ""
        lastCommittedSnapshot = ""
        phraseStartSnapshot = ""
        lastCommittedFinal = ""
        lastCommittedDedupeKey = nil
        lastCommittedNormText = nil
        lastCommittedRwy = nil
        lastCommittedVal = nil
        lastCommittedSim = nil
        lastCommittedLat = nil
        lastCommittedLon = nil
        lastChangeTime = Date()
        ReadbackDebugLog.log("txDedupeReset: reason=startListening")

        startAudioSession()
        startRecognition()
        startSilenceTimer()
    }

    func stopListening() {
        guard isListening else { return }

        isListening = false
        stopSilenceTimer()

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        didRequestRestart = true
        ReadbackDebugLog.log("speech: restart requested reason=manual")
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
    }

    // MARK: - Audio / Speech

    private func startAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    private func startRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            print("Audio engine start error: \(error)")
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            guard let self else { return }

            if let result = result {
                let newText = result.bestTranscription.formattedString
                if newText != self.currentFullText {
                    DispatchQueue.main.async {
                        self.currentFullText = newText
                        self.liveTranscript = newText
                        self.lastChangeTime = Date()
                    }
                }
            }

            if let err = error {
                let ns = err as NSError
                if ns.code == 301 && self.didRequestRestart {
                    ReadbackDebugLog.log("speech: canceled (expected restart)")
                    self.didRequestRestart = false
                } else {
                    print("Speech recognition error: \(String(describing: error))")
                    self.didRequestRestart = false
                }
            }
        }
    }

    // MARK: - Silence commit

    private func startSilenceTimer() {
        stopSilenceTimer()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.checkForSilenceCommit()
        }
    }

    private func stopSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    private func checkForSilenceCommit() {
        tryCommitCurrentPhrase(force: false)
    }

    /// Commit the current phrase now (e.g. user tapped COMMIT). Skips waiting for the pause threshold.
    func commitNow() {
        tryCommitCurrentPhrase(force: true)
    }

    private func tryCommitCurrentPhrase(force: Bool) {
        guard isListening else { return }

        if !force {
            // IFR tab: no auto-commit on pause; user taps COMMIT when done (avoids early commit on long clearances or fumbles).
            if commitOnlyOnTap { return }
            let silenceDuration = Date().timeIntervalSince(lastChangeTime)
            guard silenceDuration >= silenceThreshold else { return }
        }

        let full = currentFullText
        let cleanedFull = cleanup(full)
        guard cleanedFull.count >= 3 else { return }

        // Phrase window text (delta from phrase start)
        let phraseText = cleanup(
            computeDelta(fullText: cleanedFull, lastSnapshot: phraseStartSnapshot)
        ).uppercased()

        // If phrase window is empty/too short, consume + restart so it can't bleed
        guard phraseText.count >= 3 else {
            consumeAndRestartRecognition(reason: "restart")
            return
        }

        // Callsign filter evaluates ONLY phrase window (not the whole running transcript)
        // MAYDAY (distress) always passes. "LOAD KXXX" always passes (user can say it anytime to open that diagram).
        if callsignFilterEnabled {
            let normalizedPhrase = AviationNormalizer.normalize(phraseText, waypointIds: AviationDataManager.shared.waypointIds).uppercased()
            let isMayday = normalizedPhrase.contains("MAYDAY")
            let isLoadDiagramPhrase = AirportDiagramInfo.diagramFromLoadPhrase(normalizedPhrase) != nil
            if !isMayday && !isLoadDiagramPhrase {
                let phraseForMatch = CallsignFormatter.compressSpokenCallsigns(in: phraseText)
                let matched = CallsignFormatter.matchesTransmission(phraseForMatch, desiredUserInput: callsign)
                if !matched {
                    // Rejected phrase must be consumed and must not leak into next phrase
                    consumeAndRestartRecognition(reason: "restart")
                    return
                }
            }
        }

        // Commit delta since last committed baseline
        let delta = cleanup(
            computeDelta(fullText: cleanedFull, lastSnapshot: lastCommittedSnapshot)
        ).uppercased()

        guard delta.count >= 3 else {
            consumeAndRestartRecognition()
            return
        }

        // Commit: run engine first so we can build full dedupe key (transcript + runway + validated + SIM + location)
        let normalizedDelta = AviationNormalizer.normalize(delta, waypointIds: AviationDataManager.shared.waypointIds).uppercased()
        let isMayday = normalizedDelta.contains("MAYDAY")
        // Don't turn pilot initiator calls into cards ("Crystal Tower Cherokee 641CC requesting taxi")
        if !isMayday, PilotInitiatorDetector.isLikelyPilotInitiator(normalizedText: normalizedDelta, callsign: callsign) {
            consumeAndRestartRecognition()
            return
        }
        // Run ReadbackEngine on committed transcript (use real GPS for runway validation)
        let loc = LocationManager.shared.effectiveLocation
        let lat = loc?.coordinate.latitude ?? 0
        let lon = loc?.coordinate.longitude ?? 0
        if loc == nil && !LocationManager.shared.useTestPosition {
            ReadbackDebugLog.log("gps unavailable — using 0,0 for process")
        }
        let gps = GPSContext(
            lat: lat,
            lon: lon,
            altitudeFt: loc.map { $0.altitude * 3.28084 },
            trackDeg: nil,
            groundSpeedKt: nil,
            timestamp: loc?.timestamp
        )
        let store = ReadbackEngineProvider.sharedStore
        let tabName = force ? "IFR" : "ATC"
        ReadbackDebugLog.log("process start. tab=\(tabName) transcript=\"\(delta.prefix(80))\(delta.count > 80 ? "…" : "")\" gps=\(String(format: "%.2f", gps.lat)),\(String(format: "%.2f", gps.lon)) storeLoaded=\(store.isLoaded)")
        let result = ReadbackEngineProvider.sharedEngine.process(transcript: delta, gps: gps)
        let normPreview = result.normalizedText.prefix(120)
        ReadbackDebugLog.log("process done. conf=\(String(format: "%.2f", result.overallConfidence)) intents=\(result.intents.count) normalized=\"\(normPreview)\(result.normalizedText.count > 120 ? "…" : "")\"")
        for (i, intent) in result.intents.enumerated() {
            switch intent {
            case .frequencyChange(let f):
                ReadbackDebugLog.log("intent[\(i)]=frequencyChange \(f.frequencyMHz)")
            case .altitude(let a):
                ReadbackDebugLog.log("intent[\(i)]=altitude \(a.verb.rawValue) \(a.altitudeFt)")
            case .ifrClearance(let ifr):
                ReadbackDebugLog.log("intent[\(i)]=ifrClearance limit=\(ifr.clearanceLimit ?? "nil") squawk=\(ifr.squawk ?? "nil")")
            case .runwayOperation(let r):
                ReadbackDebugLog.log("intent[\(i)]=runwayOp \(r.operation.rawValue) runway=\(r.runway ?? "nil")")
            case .taxiToRunway(let t):
                ReadbackDebugLog.log("intent[\(i)]=taxiToRunway runway=\(t.runway ?? "nil")")
            case .crossRunway(let c):
                ReadbackDebugLog.log("intent[\(i)]=crossRunway runways=\(c.runways)")
            case .continueTaxi(let c):
                ReadbackDebugLog.log("intent[\(i)]=continueTaxi taxiway=\(c.taxiway ?? "nil")")
            case .viaTaxiway(let v):
                ReadbackDebugLog.log("intent[\(i)]=viaTaxiway taxiway=\(v.taxiway)")
            }
        }
        DispatchQueue.main.async {
            ReadbackDebugState.shared.lastConfidence = result.overallConfidence
        }

        // User tapped COMMIT (force) → IFR tab; treat as IFR so it shows with CRAFT. Silence commit → classify by text.
        let kind: TransmissionKind = force ? .ifr : TransmissionKind.classify(normalizedText: normalizedDelta)
        let runwayFromIntent = result.intents.compactMap { i -> String? in if case .runwayOperation(let r) = i { return r.runway }; return nil }.first
        let runwayValidated: Bool? = result.runwayValidated
        let crossRunwayValidated: [String: Bool?] = result.intents.compactMap { i -> [String: Bool?]? in
            if case .crossRunway(let c) = i { return c.runwayValidated }; return nil
        }.first ?? [:]
        let viaTaxiways: [String] = result.intents.compactMap { i -> String? in
            if case .viaTaxiway(let v) = i { return v.taxiway }; return nil
        }
        let firstTaxiIntent = result.intents.compactMap { i -> TaxiToRunwayIntent? in if case .taxiToRunway(let t) = i { return t }; return nil }.first
        let taxiToRunway: String? = firstTaxiIntent?.runway
        let taxiToRunwayValidated: Bool? = firstTaxiIntent?.validated
        let runwayValidatedLog = runwayValidated == true ? "true" : (runwayValidated == false ? "false" : "nil")
        let taxiValLog = taxiToRunwayValidated == true ? "true" : (taxiToRunwayValidated == false ? "false" : "nil")
        ReadbackDebugLog.log("txMap: transcript=\"\(delta.prefix(60))\(delta.count > 60 ? "…" : "")\" runwayFromIntent=\(runwayFromIntent ?? "nil") runwayValidated=\(runwayValidatedLog) taxiToRunway=\(taxiToRunway ?? "nil") taxiToRunwayValidated=\(taxiValLog)")

        // Dedupe: suppress only if transcript + runway + validated + SIM + location all match previous (check BEFORE insert)
        #if DEBUG
        let simActive = LocationManager.shared.isUsingSimulatedLocation
        #else
        let simActive = false
        #endif
        let decimals = simActive ? 3 : 2  // SIM: 3 decimals; REAL: 2 to resist GPS jitter
        let roundedLat = quantize(lat, decimals: decimals)
        let roundedLon = quantize(lon, decimals: decimals)
        let latStr = String(format: "%.\(decimals)f", roundedLat)
        let lonStr = String(format: "%.\(decimals)f", roundedLon)
        let valStr = runwayValidated == true ? "t" : (runwayValidated == false ? "f" : "n")
        let taxiValStr = taxiToRunwayValidated == true ? "t" : (taxiToRunwayValidated == false ? "f" : "n")
        let crossValStr = crossRunwayValidated.keys.sorted().map { k in
            let v = crossRunwayValidated[k] ?? nil
            return "\(k):\(v == true ? "t" : (v == false ? "f" : "n"))"
        }.joined(separator: ",")
        let currentDedupeKey = "\(normalizedDelta)|rwy:\(runwayFromIntent ?? "nil")|val:\(valStr)|cross:\(crossValStr)|taxi:\(taxiToRunway ?? "nil"):\(taxiValStr)|sim:\(simActive)|lat:\(latStr)|lon:\(lonStr)"
        let prevKey = lastCommittedDedupeKey
        let keysEqual = prevKey == currentDedupeKey

        ReadbackDebugLog.log("txDedupeFields: text=\(normalizedDelta) rwy=\(runwayFromIntent ?? "nil") val=\(valStr) sim=\(simActive) lat=\(latStr) lon=\(lonStr)")
        if let pt = lastCommittedNormText, let pr = lastCommittedRwy, let pv = lastCommittedVal, let ps = lastCommittedSim, let pla = lastCommittedLat, let plo = lastCommittedLon {
            ReadbackDebugLog.log("txDedupePrev:   text=\(pt) rwy=\(pr) val=\(pv) sim=\(ps) lat=\(pla) lon=\(plo)")
        }
        ReadbackDebugLog.log("txDedupeKey: current=\(currentDedupeKey) prev=\(prevKey ?? "nil") equal=\(keysEqual)")

        if let pk = prevKey, pk == currentDedupeKey {
            ReadbackDebugLog.log("txDedupe: suppressed=true key=\(currentDedupeKey) prevKey=\(pk)")
            consumeAndRestartRecognition(reason: "dedupeSuppress")
            return
        }

        DispatchQueue.main.async {
            self.transmissions.insert(Transmission(text: delta, kind: kind, runwayFromIntent: runwayFromIntent, runwayValidated: runwayValidated, crossRunwayValidated: crossRunwayValidated, viaTaxiways: viaTaxiways, taxiToRunway: taxiToRunway, taxiToRunwayValidated: taxiToRunwayValidated), at: 0)
            self.liveTranscript = ""
            if isMayday {
                self.stopListening()
                self.maydayAlertActive = true
                // Delay play so the session and input hardware are fully released (playback often fails until record path is fully torn down)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    MaydayAlertPlayer.play()
                }
            }
        }

        lastCommittedFinal = delta
        lastCommittedDedupeKey = currentDedupeKey
        lastCommittedNormText = normalizedDelta
        lastCommittedRwy = runwayFromIntent
        lastCommittedVal = valStr
        lastCommittedSim = simActive
        lastCommittedLat = roundedLat
        lastCommittedLon = roundedLon

        if isMayday {
            return
        }
        // After committing, consume and restart to prevent Apple from reusing prior tokens
        consumeAndRestartRecognition(reason: "commit")
    }

    /// Call when user acknowledges MAYDAY alert; resumes listening.
    func acknowledgeMayday() {
        maydayAlertActive = false
        startListening()
    }
    // MARK: - Delta (token-based)

    private func computeDelta(fullText: String, lastSnapshot: String) -> String {
        // Token-based common-prefix removal is much more stable than character-prefix
        // when the recognizer alternates between "641" vs "6 4 1", punctuation, etc.

        let fullTokens = canonicalTokens(fullText)
        let snapTokens = canonicalTokens(lastSnapshot)

        guard !fullTokens.isEmpty else { return "" }
        guard !snapTokens.isEmpty else { return fullTokens.joined(separator: " ") }

        var i = 0
        let n = min(fullTokens.count, snapTokens.count)
        while i < n, fullTokens[i] == snapTokens[i] {
            i += 1
        }

        if i >= fullTokens.count { return "" }
        return fullTokens[i...].joined(separator: " ")
    }

    private func canonicalTokens(_ s: String) -> [String] {
        if s.isEmpty { return [] }

        // Normalize aviation-y phrasing first (numbers, etc.)
        let normalized = AviationNormalizer.normalize(s, waypointIds: AviationDataManager.shared.waypointIds)

        // Stabilize spoken callsigns (e.g., "6 4 1 CHARLIE CHARLIE" -> "641CC" in many cases)
        let compressed = CallsignFormatter.compressSpokenCallsigns(in: normalized.uppercased())

        // Collapse whitespace and split
        let rawTokens = compressed
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { String($0) }
            .filter { !$0.isEmpty }

        // Merge consecutive single-digit tokens into one number token (e.g., "6 4 1" -> "641")
        var merged: [String] = []
        var digitBuffer: String = ""

        func flushDigitsIfNeeded() {
            if !digitBuffer.isEmpty {
                merged.append(digitBuffer)
                digitBuffer = ""
            }
        }

        for t in rawTokens {
            if t.count == 1, t.range(of: #"^\d$"#, options: .regularExpression) != nil {
                digitBuffer.append(t)
            } else {
                flushDigitsIfNeeded()
                merged.append(t)
            }
        }
        flushDigitsIfNeeded()

        return merged
    }

    // MARK: - Cleanup

    private func cleanup(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func restartRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest = nil

        startRecognition()
    }
    // MARK: - Recognition reset (prevents old words from bleeding into next phrase)

    /// Consume current recognition and restart pipeline; does NOT clear lastCommitted* (dedupe state persists so repeat phrases can be suppressed).
    private func consumeAndRestartRecognition(reason: String = "commit") {
        didRequestRestart = true
        ReadbackDebugLog.log("speech: restart requested reason=\(reason)")
        // Clear UI
        DispatchQueue.main.async { self.liveTranscript = "" }

        // Clear phrase/snapshot buffers only; keep lastCommitted* so dedupe can compare to previous commit
        currentFullText = ""
        phraseStartSnapshot = ""
        lastCommittedSnapshot = ""
        lastChangeTime = Date()

        // Hard reset just the speech recognition task/request (keep audio engine running)
        restartRecognitionPipeline()
    }

    /// Quantize for dedupe key: SIM = 3 decimals, REAL = 2 decimals (resists GPS jitter).
    private func quantize(_ value: Double, decimals: Int) -> Double {
        let factor = pow(10.0, Double(decimals))
        return (value * factor).rounded() / factor
    }

    private func restartRecognitionPipeline() {
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        // Start a fresh request/task using the same audio engine
        startRecognition()
    }
}
