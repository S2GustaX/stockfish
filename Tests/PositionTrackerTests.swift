import Foundation

@main
struct PositionTrackerTests {
    static func main() {
        let whiteStart = startingBoard(.whiteBottom)
        assert(whiteStart.count == 64)
        assert(whiteStart[0] == "r")
        var tracker = PositionTracker(orientation: .whiteBottom)
        assert(tracker.fen() == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        let afterE4 = update(tracker.state.position.board, orientation: .whiteBottom,
                             from: "e2", to: "e4")
        assert(!tracker.ingest(afterE4))
        assert(tracker.ingest(afterE4))
        assert(tracker.state.position.lastMoveUCI == "e2e4")
        assert(tracker.fen() == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
        let afterE5 = update(tracker.state.position.board, orientation: .whiteBottom,
                             from: "e7", to: "e5")
        assert(!tracker.ingest(afterE5))
        assert(tracker.ingest(afterE5))
        assert(tracker.state.position.lastMoveUCI == "e7e5")
        assert(tracker.fen() == "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2")
        var blackTracker = PositionTracker(orientation: .blackBottom)
        assert(blackTracker.fen() == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        let blackOrientationE4 = update(blackTracker.state.position.board,
                                        orientation: .blackBottom, from: "e2", to: "e4")
        assert(!blackTracker.ingest(blackOrientationE4))
        assert(blackTracker.ingest(blackOrientationE4))
        assert(blackTracker.state.position.lastMoveUCI == "e2e4")
        print("PASS: posição inicial, e2e4, e7e5, FEN e orientação invertida")
    }

    static func update(_ board: [String], orientation: BoardOrientation,
                       from: String, to: String) -> [String] {
        func index(_ square: String) -> Int {
            let chars = Array(square)
            let file = Array("abcdefgh").firstIndex(of: chars[0])!
            let rank = chars[1].wholeNumberValue!
            let row = orientation == .whiteBottom ? 8 - rank : rank - 1
            let col = orientation == .whiteBottom ? file : 7 - file
            return row * 8 + col
        }
        var next = board
        next[index(to)] = next[index(from)]
        next[index(from)] = "."
        return next
    }
}
