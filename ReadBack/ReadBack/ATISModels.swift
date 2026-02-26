import Foundation

struct ATISReport: Equatable {
    var raw: String

    var information: String?
    var timeZulu: String?
    var wind: String?
    var visibility: String?
    var ceiling: String?
    var temperatureDewpoint: String?
    var altimeter: String?

    var runways: [String] = []
    var approaches: [String] = []
    var remarks: [String] = []
}

struct ATISHistoryItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let time: Date
    let report: ATISReport

    var shortTitle: String { title }
    var shortTime: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: time)
    }
}
