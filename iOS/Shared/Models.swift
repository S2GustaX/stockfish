import Foundation

// Os identificadores devem coincidir nos targets e nos profiles de assinatura.
enum AppIdentity {
    static let appGroup = "group.com.example.chesstrainer"
    static let broadcastBundle = "com.example.chesstrainer.broadcast"
}

struct AppSettings: Codable {
    var elo: Int = 2500
    var depth: Int = 16
    var automaticSide: Bool = true
    var showArrows: Bool = true
    var showEvaluation: Bool = true
    var serverURL: String = "http://192.168.1.10:8765"
    var apiToken: String = ""
}

enum BoardOrientation: String, Codable, CaseIterable {
    case whiteBottom
    case blackBottom

    var label: String { self == .whiteBottom ? "Brancas embaixo" : "Pretas embaixo" }
}

struct NormalizedRect: Codable {
    var x: Double = 0.0
    var y: Double = 0.24
    // size é a fração da LARGURA da imagem. O tabuleiro é quadrado em pixels.
    var size: Double = 0.98

    func isValid(aspect: Double) -> Bool {
        x >= 0 && y >= 0 && size > 0.05 && x + size <= 1.001 && y + size * aspect <= 1.001
    }
}

struct Template: Codable {
    var piece: String
    var vector: [Float]
}

struct Calibration: Codable {
    var rect: NormalizedRect
    var orientation: BoardOrientation
    var screenshotAspect: Double
    var templates: [Template]
    var emptyThreshold: Float
    var initialBoard: [String]
}

struct ScanResult: Codable {
    var board: [String]
    var confidence: Double
    var unknownCount: Int
    var timestamp: Date = Date()
}

struct TrainingPosition: Codable {
    var board: [String]
    var sideToMove: String // "w" or "b"
    var castling: String = "KQkq"
    var enPassant: String = "-"
    var halfmoveClock: Int = 0
    var fullmoveNumber: Int = 1
    var lastMoveUCI: String? = nil
    var updatedAt: Date = Date()
}

struct TrackingState: Codable {
    var position: TrainingPosition
    var candidate: [String]? = nil
    var count: Int = 0
    var lastError: String? = nil
}

struct EngineResult: Codable {
    var fen: String
    var bestMove: String?
    var bestMoveSAN: String?
    var evaluationCP: Int?
    var mate: Int?
    var principalVariation: [String]
    var engineName: String?
    var error: String?
    var timestamp: Date? = nil // opcional: resposta JSON do servidor não precisa enviá-lo
}

struct AnalyzeRequest: Encodable {
    let fen: String
    let elo: Int
    let depth: Int
}

func startingBoard(_ orientation: BoardOrientation) -> [String] {
    let whiteBottom = [
        "rnbqkbnr", "pppppppp", "........", "........",
        "........", "........", "PPPPPPPP", "RNBQKBNR"
    ]
    let rows = orientation == .whiteBottom
        ? whiteBottom : whiteBottom.reversed().map { String($0.reversed()) }
    return rows.flatMap { $0.map { String($0) } }
}

func squareName(row: Int, col: Int, orientation: BoardOrientation) -> String {
    let fileIndex = orientation == .whiteBottom ? col : 7 - col
    let rank = orientation == .whiteBottom ? 8 - row : row + 1
    return "\(Array("abcdefgh")[fileIndex])\(rank)"
}

func pieceIsWhite(_ piece: String) -> Bool {
    guard let ch = piece.first, piece != ".", piece != "?" else { return false }
    return ch.isUppercase
}

func pieceIsBlack(_ piece: String) -> Bool {
    guard let ch = piece.first, piece != ".", piece != "?" else { return false }
    return ch.isLowercase
}
