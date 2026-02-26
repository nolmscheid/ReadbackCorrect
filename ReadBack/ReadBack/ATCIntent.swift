import Foundation

enum ATCIntent: Equatable {
    case taxi(destinationRunway: String?, via: [String])
    case holdShort(runway: String?)
    case crossRunway(runway: String?)
    case clearedForTakeoff(runway: String?)
    case clearedToLand(runway: String?)
    case lineUpAndWait(runway: String?)
    case climb(altitude: Int)
    case descend(altitude: Int)
    case maintain(altitude: Int)
    case heading(degrees: Int)
    case contact(facility: String?, frequency: String?)
    case squawk(code: String)
    case goAround
}
