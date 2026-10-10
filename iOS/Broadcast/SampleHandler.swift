import ReplayKit
import CoreImage
import AVFoundation
import Foundation

/// O processamento acontece na extensão (e não no app suspenso em segundo plano).
final class SampleHandler: RPBroadcastSampleHandler {
    private let queue = DispatchQueue(label: "com.example.chesstrainer.recognition", qos: .userInitiated)
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private var lastSampleTime = Date.distantPast
    private let sampleInterval: TimeInterval = 0.85

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        SharedStore.save(BroadcastStatus(active: true,
            message: "Captura iniciada. Aguardando tabuleiro…"), as: "broadcast.json")
    }

    override func broadcastPaused() {
        SharedStore.save(BroadcastStatus(active: false,
            message: "Captura pausada."), as: "broadcast.json")
    }

    override func broadcastResumed() {
        SharedStore.save(BroadcastStatus(active: true,
            message: "Captura retomada."), as: "broadcast.json")
    }

    override func broadcastFinished() {
        SharedStore.save(BroadcastStatus(active: false,
            message: "Captura encerrada."), as: "broadcast.json")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video,
              Date().timeIntervalSince(lastSampleTime) >= sampleInterval,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastSampleTime = Date()
        // A referência é retida pelo bloco capturado pelo ARC. Não use as
        // funções CVPixelBufferRetain/Release, indisponíveis em Swift moderno.
        queue.async { [weak self, pixelBuffer] in
            guard let self,
                  let calibration: Calibration = SharedStore.load("calibration.json") else { return }
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = self.context.createCGImage(image, from: image.extent) else { return }
            do {
                let scan = try BoardRecognizer.scan(image: cgImage, calibration: calibration)
                SharedStore.save(scan, as: "scan.json")
                var tracker = PositionTracker(orientation: calibration.orientation,
                    state: SharedStore.load("tracking.json"))
                let accepted = tracker.ingest(scan.board)
                SharedStore.save(tracker.state, as: "tracking.json")
                SharedStore.save(BroadcastStatus(active: true,
                    message: "Capturando · confiança \(Int(scan.confidence * 100))%"),
                    as: "broadcast.json")
                guard accepted else { return }
                let fen = tracker.fen()
                let settings = SharedStore.loadSettings()
                StockfishClient.analyze(fen: fen, settings: settings) { result in
                    switch result {
                    case .success(let value):
                        // Evita sobrescrever a análise mais nova com uma resposta antiga.
                        guard let latest: TrackingState = SharedStore.load("tracking.json"),
                              PositionTracker(orientation: calibration.orientation,
                                              state: latest).fen() == fen else { return }
                        SharedStore.save(value, as: "analysis.json")
                    case .failure(let error):
                        SharedStore.save(EngineResult(fen: fen, bestMove: nil,
                            bestMoveSAN: nil, evaluationCP: nil, mate: nil,
                            principalVariation: [], engineName: nil,
                            error: "Stockfish inacessível: \(error.localizedDescription)"),
                            as: "analysis.json")
                    }
                }
            } catch {
                SharedStore.save(BroadcastStatus(active: true,
                    message: "Leitura: \(error.localizedDescription)"), as: "broadcast.json")
            }
        }
    }
}
