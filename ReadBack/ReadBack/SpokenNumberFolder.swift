import Foundation

enum SpokenNumberFolder {

    private static let digitMap: [String: String] = [
        "zero": "0",
        "one": "1",
        "two": "2",
        "three": "3",
        "tree": "3",
        "four": "4",
        "five": "5",
        "fife": "5",
        "six": "6",
        "seven": "7",
        "eight": "8",
        "nine": "9",
        "niner": "9"
    ]

    static func foldTokens(_ tokens: [String]) -> [String] {
        var result: [String] = []
        var i = 0

        while i < tokens.count {

            var numeric = ""
            var j = i
            var didAccumulate = false

            while j < tokens.count {
                let t = tokens[j].lowercased()

                if let digit = digitMap[t] {
                    numeric += digit
                    didAccumulate = true
                    j += 1
                } else if t.count == 1 && t.first?.isNumber == true {
                    numeric += t
                    didAccumulate = true
                    j += 1
                } else if t == "point" && didAccumulate {
                    numeric += "."
                    j += 1
                } else {
                    break
                }
            }

            if didAccumulate && numeric.count > 1 {
                result.append(numeric)
                i = j
            } else {
                result.append(tokens[i])
                i += 1
            }
        }

        return result
    }
}
