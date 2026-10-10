import CoreGraphics
import Foundation

// Detector baseado em modelos visuais colhidos de uma posição inicial padrão.
// Não depende de rede/ML, mas é sensível a tema, zoom, animações e sobreposições.
struct BoardRecognizer {
    static let tileSize = 24

    struct Features {
        var vector: [Float]
        var occupancy: Float
        var signedBrightness: Float
    }

    enum RecognizerError: LocalizedError {
        case invalidRectangle
        case screenshotFailed
        case insufficientPieces
        case screenChanged

        var errorDescription: String? {
            switch self {
            case .invalidRectangle: return "Selecione um quadrado inteiramente dentro da imagem."
            case .screenshotFailed: return "Não foi possível ler os pixels do tabuleiro."
            case .insufficientPieces: return "Comece pela posição inicial, com todas as peças visíveis."
            case .screenChanged: return "Formato de tela mudou desde a calibração."
            }
        }
    }

    static func enroll(image: CGImage, rect: NormalizedRect,
                       forcedOrientation: BoardOrientation? = nil) throws -> Calibration {
        guard rect.isValid(aspect: Double(image.width) / Double(image.height)) else { throw RecognizerError.invalidRectangle }
        let samples = try sampleBoard(image: image, rect: rect)
        let orientation = forcedOrientation ?? autoOrientation(samples)
        let board = startingBoard(orientation)
        let occupied = zip(samples, board).filter { $0.1 != "." }.map { $0.0.occupancy }
        let empty = zip(samples, board).filter { $0.1 == "." }.map { $0.0.occupancy }
        guard occupied.count == 32, empty.count == 32 else { throw RecognizerError.insufficientPieces }
        let occLow = occupied.sorted()[min(4, occupied.count - 1)]
        let emptyHigh = empty.sorted()[min(28, empty.count - 1)]
        guard occLow > emptyHigh + 0.012 else { throw RecognizerError.insufficientPieces }
        let templates = zip(samples, board).compactMap { sample, piece -> Template? in
            piece == "." ? nil : Template(piece: piece, vector: sample.vector)
        }
        return Calibration(rect: rect, orientation: orientation,
                           screenshotAspect: Double(image.width) / Double(image.height),
                           templates: templates, emptyThreshold: (occLow + emptyHigh) / 2,
                           initialBoard: board)
    }

    static func scan(image: CGImage, calibration: Calibration) throws -> ScanResult {
        let aspect = Double(image.width) / Double(image.height)
        guard abs(aspect - calibration.screenshotAspect) < 0.04 else {
            throw RecognizerError.screenChanged
        }
        let samples = try sampleBoard(image: image, rect: calibration.rect)
        var detected: [String] = []
        var totalConfidence = 0.0
        var unknownCount = 0
        for sample in samples {
            if sample.occupancy < calibration.emptyThreshold {
                detected.append(".")
                totalConfidence += 1.0
                continue
            }
            var best: (piece: String, score: Float) = ("?", -1)
            var second = -1 as Float
            for template in calibration.templates {
                let score = similarity(sample.vector, template.vector)
                if score > best.score {
                    if template.piece != best.piece { second = best.score }
                    best = (template.piece, score)
                } else if template.piece != best.piece {
                    second = max(second, score)
                }
            }
            // Evita transformar um quadro incerto em um lance inventado.
            // Uma peça só é aceita se sua semelhança ao exemplo inicial for razoável.
            let confident = best.score >= 0.60 && (best.score - second) >= 0.008
            if confident {
                detected.append(best.piece)
                totalConfidence += Double(max(0, best.score))
            } else {
                detected.append("?")
                unknownCount += 1
            }
        }
        return ScanResult(board: detected,
                          confidence: totalConfidence / 64.0,
                          unknownCount: unknownCount)
    }

    private static func autoOrientation(_ samples: [Features]) -> BoardOrientation {
        let top = (0..<16).reduce(Float(0)) { $0 + samples[$1].signedBrightness } / 16
        let bottom = (48..<64).reduce(Float(0)) { $0 + samples[$1].signedBrightness } / 16
        return bottom >= top ? .whiteBottom : .blackBottom
    }

    private static func sampleBoard(image: CGImage, rect: NormalizedRect) throws -> [Features] {
        var output: [Features] = []
        let boardWidthPixels = rect.size * Double(image.width)
        for row in 0..<8 {
            for col in 0..<8 {
                let square = CGRect(x: (rect.x + Double(col) * rect.size / 8) * Double(image.width),
                                    y: rect.y * Double(image.height) + Double(row) * boardWidthPixels / 8,
                                    width: boardWidthPixels / 8,
                                    height: boardWidthPixels / 8)
                guard let cropped = image.cropping(to: square.integral),
                      let feature = feature(from: cropped) else { throw RecognizerError.screenshotFailed }
                output.append(feature)
            }
        }
        return output
    }

    private static func feature(from tile: CGImage) -> Features? {
        let n = tileSize
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        guard let context = CGContext(data: &pixels, width: n, height: n,
                                      bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(tile, in: CGRect(x: 0, y: 0, width: n, height: n))

        // Plano de fundo aproximado pelos quatro cantos da casa. A subtração
        // diminui a dependência das cores do tema e do destaque do último lance.
        var bg = [Float](repeating: 0, count: 3)
        var count = Float(0)
        for y in 0..<n {
            for x in 0..<n where (x < 3 || x >= n - 3) && (y < 3 || y >= n - 3) {
                let i = (y * n + x) * 4
                for c in 0..<3 { bg[c] += Float(pixels[i + c]) / 255.0 }
                count += 1
            }
        }
        guard count > 0 else { return nil }
        for c in 0..<3 { bg[c] /= count }
        let bgLuminance = (0.2126 * bg[0] + 0.7152 * bg[1] + 0.0722 * bg[2])
        var mask: [Float] = []
        var signed: [Float] = []
        var magnitudeSum: Float = 0
        var brightnessSum: Float = 0
        for y in 0..<n {
            for x in 0..<n {
                let i = (y * n + x) * 4
                let r = Float(pixels[i]) / 255 - bg[0]
                let g = Float(pixels[i + 1]) / 255 - bg[1]
                let b = Float(pixels[i + 2]) / 255 - bg[2]
                let delta = min(1, (r * r + g * g + b * b).squareRoot())
                let lum = 0.2126 * Float(pixels[i]) / 255 +
                          0.7152 * Float(pixels[i + 1]) / 255 +
                          0.0722 * Float(pixels[i + 2]) / 255 - bgLuminance
                mask.append(delta)
                signed.append(lum)
                if x >= 3 && x < n - 3 && y >= 3 && y < n - 3 {
                    magnitudeSum += delta
                    brightnessSum += lum
                }
            }
        }
        return Features(vector: mask + signed, occupancy: magnitudeSum / Float((n - 6) * (n - 6)),
                        signedBrightness: brightnessSum / Float((n - 6) * (n - 6)))
    }

    private static func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return -1 }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0.001 && normB > 0.001 else { return -1 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }
}
