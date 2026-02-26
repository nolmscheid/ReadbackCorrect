import Foundation
import Combine
import Speech
import AVFoundation

final class ATISLiveRecognizer: ObservableObject {

    @Published var isListening: Bool = false
    @Published var liveTranscript: String = ""
    @Published var history: [ATISHistoryItem] = []
    @Published var currentReport: ATISReport? = nil

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer()

    func startListening() {
        guard !isListening else { return }

        liveTranscript = ""
        currentReport = nil

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            isListening = false
            return
        }

        isListening = true

        task = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
            guard let self else { return }
            if let result {
                DispatchQueue.main.async {
                    self.liveTranscript = result.bestTranscription.formattedString
                }
            }
            if error != nil {
                DispatchQueue.main.async {
                    self.stopListeningInternal()
                }
            }
        }
    }

    func stopListening() {
        guard isListening else { return }
        stopListeningInternal()

        let raw = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count >= 3 else { return }

        let report = ATISParser.parse(raw: raw)

        DispatchQueue.main.async {
            self.currentReport = report

            let title: String
            if let info = report.information, !info.isEmpty {
                title = "INFO \(info)"
            } else {
                title = "ATIS"
            }

            self.history.insert(
                ATISHistoryItem(title: title, time: Date(), report: report),
                at: 0
            )

            // small history
            if self.history.count > 12 {
                self.history = Array(self.history.prefix(12))
            }
        }
    }

    func selectHistory(id: UUID) {
        guard let item = history.first(where: { $0.id == id }) else { return }
        currentReport = item.report
    }

    private func stopListeningInternal() {
        isListening = false

        task?.cancel()
        task = nil

        request?.endAudio()
        request = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}
