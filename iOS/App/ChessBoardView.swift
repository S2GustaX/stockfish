import SwiftUI

struct ChessBoardView: View {
    let board: [String]
    let orientation: BoardOrientation
    let suggestedMove: String?
    let showArrow: Bool

    private let symbols: [String: String] = [
        "K": "♔", "Q": "♕", "R": "♖", "B": "♗", "N": "♘", "P": "♙",
        "k": "♚", "q": "♛", "r": "♜", "b": "♝", "n": "♞", "p": "♟",
        ".": "", "?": "?"
    ]

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 8), spacing: 0) {
                    ForEach(0..<64, id: \.self) { index in
                        let row = index / 8
                        let col = index % 8
                        ZStack {
                            Rectangle().fill((row + col) % 2 == 0
                                ? Color(red: 0.93, green: 0.92, blue: 0.83)
                                : Color(red: 0.48, green: 0.62, blue: 0.37))
                            Text(board.indices.contains(index) ? (symbols[board[index]] ?? "?") : "")
                                .font(.system(size: side / 11.5))
                                .foregroundStyle(.black)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(width: side / 8, height: side / 8)
                    }
                }
                if showArrow, let uci = suggestedMove, let endpoints = endpointsFor(uci) {
                    ArrowLine(from: endpoints.0, to: endpoints.1)
                        .stroke(.orange.opacity(0.85), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func endpointsFor(_ move: String) -> (CGPoint, CGPoint)? {
        guard move.count >= 4 else { return nil }
        let chars = Array(move)
        func point(file: Character, rank: Character) -> CGPoint? {
            guard let index = Array("abcdefgh").firstIndex(of: file),
                  let rankNum = rank.wholeNumberValue, (1...8).contains(rankNum) else { return nil }
            let col = orientation == .whiteBottom ? index : 7 - index
            let row = orientation == .whiteBottom ? 8 - rankNum : rankNum - 1
            return CGPoint(x: CGFloat(col * 2 + 1) / 16, y: CGFloat(row * 2 + 1) / 16)
        }
        guard let a = point(file: chars[0], rank: chars[1]),
              let b = point(file: chars[2], rank: chars[3]) else { return nil }
        return (a, b)
    }
}

struct ArrowLine: Shape {
    let from: CGPoint
    let to: CGPoint
    func path(in rect: CGRect) -> Path {
        let start = CGPoint(x: from.x * rect.width, y: from.y * rect.height)
        let end = CGPoint(x: to.x * rect.width, y: to.y * rect.height)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 14
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        path.move(to: CGPoint(x: end.x - length * cos(angle - .pi / 6),
                              y: end.y - length * sin(angle - .pi / 6)))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: end.x - length * cos(angle + .pi / 6),
                                y: end.y - length * sin(angle + .pi / 6)))
        return path
    }
}
