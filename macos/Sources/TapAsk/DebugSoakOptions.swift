#if DEBUG
import Foundation

struct DebugSoakOptions {
    let rounds: Int
    let dwell: Double

    init?(arguments: [String]) throws {
        guard let index = arguments.firstIndex(of: "-TapAskSoak") else { return nil }
        guard arguments.indices.contains(index + 1),
              let rounds = Int(arguments[index + 1]), rounds > 0 else {
            throw InvalidArgument.rounds
        }
        self.rounds = rounds
        if let dwellIndex = arguments.firstIndex(of: "-TapAskSoakDwell") {
            guard arguments.indices.contains(dwellIndex + 1),
                  let dwell = Double(arguments[dwellIndex + 1]), dwell.isFinite,
                  dwell > 0, dwell < Double(Int64.max) else {
                throw InvalidArgument.dwell
            }
            self.dwell = dwell
        } else {
            dwell = 8
        }
    }

    private enum InvalidArgument: LocalizedError {
        case rounds, dwell

        var errorDescription: String? {
            switch self {
            case .rounds: return "-TapAskSoak requires a positive integer round count"
            case .dwell: return "-TapAskSoakDwell requires positive finite seconds below Int64.max"
            }
        }
    }
}
#endif
