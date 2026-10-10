import Foundation

/// Não é um validador completo de lances: acompanha transições prováveis do tabuleiro.
/// Ignora quadros transitórios e exige duas leituras sucessivas idênticas.
struct PositionTracker {
    var orientation: BoardOrientation
    var state: TrackingState

    init(orientation: BoardOrientation, state: TrackingState? = nil) {
        self.orientation = orientation
        self.state = state ?? TrackingState(position: TrainingPosition(
            board: startingBoard(orientation), sideToMove: "w"
        ))
    }

    mutating func ingest(_ candidate: [String]) -> Bool {
        guard candidate.count == 64, !candidate.contains("?") else {
            state.lastError = "Uma ou mais casas não puderam ser reconhecidas."
            return false
        }
        if candidate == state.position.board {
            state.candidate = nil
            state.count = 0
            return false
        }
        if state.candidate == candidate { state.count += 1 }
        else { state.candidate = candidate; state.count = 1 }
        guard state.count >= 2 else { return false }

        guard let move = inferMove(from: state.position.board, to: candidate) else {
            state.lastError = "Mudança ambígua. Recalibre no início de uma nova partida."
            return false
        }

        let oldBoard = state.position.board
        let movingPiece = oldBoard[move.from]
        guard (state.position.sideToMove == "w" && pieceIsWhite(movingPiece)) ||
              (state.position.sideToMove == "b" && pieceIsBlack(movingPiece)) else {
            state.lastError = "Ordem dos lances inconsistente; aguardando uma posição válida."
            return false
        }
        let destination = oldBoard[move.to]
        var position = state.position
        let fromName = name(move.from)
        let toName = name(move.to)
        position.lastMoveUCI = fromName + toName + (move.promotion ?? "")
        position.board = candidate
        position.updatedAt = Date()
        position.enPassant = "-"
        position.halfmoveClock = movingPiece.lowercased() == "p" || destination != "."
            ? 0 : position.halfmoveClock + 1
        var rights = position.castling == "-" ? "" : position.castling
        if movingPiece == "K" { rights.removeAll(where: { "KQ".contains($0) }) }
        if movingPiece == "k" { rights.removeAll(where: { "kq".contains($0) }) }
        for (square, letter) in [("h1", "K"), ("a1", "Q"), ("h8", "k"), ("a8", "q")] {
            if fromName == square || (toName == square && destination.lowercased() == "r") {
                rights.removeAll(where: { String($0) == letter })
            }
        }
        position.castling = rights.isEmpty ? "-" : rights
        if movingPiece.lowercased() == "p" {
            let delta = abs(Int(fromName.last!.wholeNumberValue!) - Int(toName.last!.wholeNumberValue!))
            if delta == 2 {
                let middleRank = (fromName.last!.wholeNumberValue! + toName.last!.wholeNumberValue!) / 2
                position.enPassant = String(fromName.first!) + String(middleRank)
            }
        }
        if position.sideToMove == "b" { position.fullmoveNumber += 1 }
        position.sideToMove = position.sideToMove == "w" ? "b" : "w"
        state.position = position
        state.candidate = nil
        state.count = 0
        state.lastError = nil
        return true
    }

    func fen() -> String {
        let board = state.position.board
        var ranks: [String] = []
        for rank in stride(from: 8, through: 1, by: -1) {
            var line = ""
            var empty = 0
            for file in "abcdefgh" {
                guard let idx = index(for: "\(file)\(rank)") else { continue }
                let piece = board[idx]
                if piece == "." { empty += 1 }
                else {
                    if empty > 0 { line += String(empty); empty = 0 }
                    line += piece
                }
            }
            if empty > 0 { line += String(empty) }
            ranks.append(line)
        }
        let p = state.position
        return "\(ranks.joined(separator: "/")) \(p.sideToMove) \(p.castling) \(p.enPassant) \(p.halfmoveClock) \(p.fullmoveNumber)"
    }

    private func name(_ index: Int) -> String {
        squareName(row: index / 8, col: index % 8, orientation: orientation)
    }
    private func index(for square: String) -> Int? {
        guard square.count == 2,
              let file = square.first, let c = Array("abcdefgh").firstIndex(of: file),
              let rank = square.last?.wholeNumberValue, (1...8).contains(rank) else { return nil }
        let row = orientation == .whiteBottom ? 8 - rank : rank - 1
        let col = orientation == .whiteBottom ? c : 7 - c
        return row * 8 + col
    }

    private func inferMove(from old: [String], to new: [String]) -> (from: Int, to: Int, promotion: String?)? {
        let diffs = (0..<64).filter { old[$0] != new[$0] }
        guard [2, 3, 4].contains(diffs.count) else { return nil }
        let sources = diffs.filter { old[$0] != "." && new[$0] == "." }
        let arrivals = diffs.filter { new[$0] != "." &&
            (old[$0] == "." || pieceIsWhite(old[$0]) != pieceIsWhite(new[$0])) }
        for source in sources {
            for dest in arrivals {
                let srcPiece = old[source]
                let dstPiece = new[dest]
                let sameColor = pieceIsWhite(srcPiece) == pieceIsWhite(dstPiece)
                let sameType = srcPiece.lowercased() == dstPiece.lowercased()
                let promotion = srcPiece.lowercased() == "p" &&
                    ["q", "r", "b", "n"].contains(dstPiece.lowercased())
                if sameColor && (sameType || promotion) {
                    // Castling: rook also moves, but the king uniquely identifies the move.
                    if diffs.count == 4 && srcPiece.lowercased() != "k" { continue }
                    return (source, dest, promotion ? dstPiece.lowercased() : nil)
                }
            }
        }
        // En passant: três casas mudam, sendo uma o peão capturado.
        return nil
    }
}
