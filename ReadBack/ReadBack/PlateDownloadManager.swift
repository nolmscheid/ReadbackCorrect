import Foundation
import Combine
import PDFKit

/// Fetches airport diagram PDFs from the FAA d-TPP and saves them to app storage.
final class PlateDownloadManager: ObservableObject {
    static let shared = PlateDownloadManager()

    @Published private(set) var isDownloading = false
    @Published private(set) var lastError: String?
    @Published private(set) var downloadedIdentifiers: [String] = []

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private let downloadedKey = "PlateDownloadManager.downloadedIdentifiers"

    /// Current d-TPP cycle (28-day). Update when FAA cycle changes; can later be parsed from FAA page.
    private let currentCycle = "2602"

    private init() {
        loadDownloadedList()
    }

    private func loadDownloadedList() {
        downloadedIdentifiers = defaults.stringArray(forKey: downloadedKey) ?? []
    }

    private func saveDownloadedList() {
        defaults.set(downloadedIdentifiers, forKey: downloadedKey)
    }

    /// Application Support directory for plate PDFs: ReadBack/plates/
    func platesDirectory() -> URL? {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = support.appendingPathComponent("ReadBack", isDirectory: true).appendingPathComponent("plates", isDirectory: true)
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return nil
        }
    }

    /// URL for a downloaded plate PDF (e.g. KMIC.pdf). Returns nil if not downloaded.
    func localPDFURL(airportId: String) -> URL? {
        let id = airportId.uppercased()
        guard let dir = platesDirectory() else { return nil }
        let file = dir.appendingPathComponent("\(id).pdf")
        return fileManager.fileExists(atPath: file.path) ? file : nil
    }

    /// Download airport diagram PDF from FAA for the given identifier (e.g. KMIC). Saves to plates dir and adds to downloaded list.
    func downloadDiagram(airportId: String) async {
        let id = airportId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !id.isEmpty else { return }

        await MainActor.run { isDownloading = true; lastError = nil }
        defer { Task { @MainActor in isDownloading = false } }

        // 1) Fetch FAA search results HTML
        let resultsURLString = "https://www.faa.gov/air_traffic/flight_info/aeronav/digital_products/dtpp/search/results/?cycle=\(currentCycle)&ident=\(id)"
        guard let resultsURL = URL(string: resultsURLString),
              let (htmlData, _) = try? await URLSession.shared.data(from: resultsURL),
              let html = String(data: htmlData, encoding: .utf8) else {
            await MainActor.run { lastError = "Could not reach FAA. Check network." }
            return
        }

        // 2) Parse for Airport Diagram (APD) PDF link: href to .../xxxxxad.pdf
        guard let pdfURL = parseAirportDiagramPDFURL(from: html) else {
            await MainActor.run { lastError = "No airport diagram found for \(id)." }
            return
        }

        // 3) Download PDF
        guard let (pdfData, _) = try? await URLSession.shared.data(from: pdfURL),
              !pdfData.isEmpty,
              PDFDocument(data: pdfData) != nil else {
            await MainActor.run { lastError = "Download failed or invalid PDF." }
            return
        }

        // 4) Save to plates directory
        guard let dir = platesDirectory() else {
            await MainActor.run { lastError = "Could not create plates folder." }
            return
        }
        let dest = dir.appendingPathComponent("\(id).pdf")
        do {
            try pdfData.write(to: dest)
        } catch {
            await MainActor.run { lastError = "Could not save: \(error.localizedDescription)" }
            return
        }

        await MainActor.run {
            if !downloadedIdentifiers.contains(id) {
                downloadedIdentifiers.append(id)
                saveDownloadedList()
            }
            lastError = nil
        }
    }

    /// Extract the first airport diagram PDF URL from FAA search results HTML. Format: aeronav.faa.gov/d-tpp/CYCLE/xxxxxad.pdf
    private func parseAirportDiagramPDFURL(from html: String) -> URL? {
        // Match href="https://aeronav.faa.gov/d-tpp/2602/05158ad.pdf..." or href="/d-tpp/2602/05158ad.pdf..."
        let pattern = #"https?://aeronav\.faa\.gov/d-tpp/\d+/\d+ad\.pdf[^"]*"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range, in: html) {
            let urlString = String(html[range]).components(separatedBy: "#").first ?? String(html[range])
            return URL(string: urlString)
        }
        // Fallback: relative URL
        let relPattern = #"href=["'](/d-tpp/\d+/\d+ad\.pdf)[^"']*"#
        if let regex = try? NSRegularExpression(pattern: relPattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            let path = String(html[range])
            return URL(string: "https://aeronav.faa.gov\(path)")
        }
        return nil
    }

    /// Remove a downloaded plate (delete file and remove from list).
    func removeDownloaded(airportId: String) {
        let id = airportId.uppercased()
        if let url = localPDFURL(airportId: id) {
            try? fileManager.removeItem(at: url)
        }
        downloadedIdentifiers.removeAll { $0 == id }
        saveDownloadedList()
    }
}
