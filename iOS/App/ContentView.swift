import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var settings = SharedStore.loadSettings()
    @State private var photo: PhotosPickerItem?
    @State private var screenshot: UIImage?
    @State private var boardRect = NormalizedRect()
    @State private var orientationChoice = "auto"
    @State private var calibration: Calibration? = SharedStore.load("calibration.json")
    @State private var scan: ScanResult?
    @State private var tracking: TrackingState?
    @State private var analysis: EngineResult?
    @State private var broadcast: BroadcastStatus?
    @State private var feedback: String = ""
    @State private var requesting = false

    private let refreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Análise de treino com reconhecimento automático do tabuleiro. Para estudar posições e partidas de treino, não para auxílio em partidas online contra outras pessoas.")
                        .font(.subheadline).foregroundStyle(.secondary)

                    GroupBox("1. Calibrar no início de uma partida") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tire uma captura com as 32 peças na posição inicial, sem setas ou menus sobre o tabuleiro.")
                                .font(.footnote)
                            PhotosPicker(selection: $photo, matching: .images) {
                                Label("Escolher captura de tela", systemImage: "photo")
                                    .frame(maxWidth: .infinity)
                            }.buttonStyle(.borderedProminent)
                            if let image = screenshot {
                                CalibrationPreview(image: image, rect: boardRect)
                                    .frame(height: 360)
                                Text("Ajuste a moldura até coincidir exatamente com as 64 casas.")
                                    .font(.footnote)
                                sliderField("Posição horizontal", value: $boardRect.x,
                                            upper: max(0, 1 - boardRect.size))
                                let aspect = image.size.width / max(image.size.height, 1)
                                sliderField("Posição vertical", value: $boardRect.y,
                                            upper: max(0, 1 - boardRect.size * aspect))
                                sliderField("Tamanho", value: $boardRect.size,
                                            lower: 0.2,
                                            upper: max(0.2, min(1 - boardRect.x,
                                                (1 - boardRect.y) / aspect)))
                                Picker("Peças na parte de baixo", selection: $orientationChoice) {
                                    Text("Auto").tag("auto")
                                    Text("Brancas").tag("white")
                                    Text("Pretas").tag("black")
                                }.pickerStyle(.segmented)
                                Button("Calibrar e salvar") { calibrate(image) }
                                    .buttonStyle(.borderedProminent)
                            }
                            if let calibration {
                                Label("Calibrado — \(calibration.orientation.label)", systemImage: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("2. Stockfish no Windows") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Inicie WindowsServer/server.py no PC. O iPhone e o Windows precisam estar na mesma rede.")
                                .font(.footnote)
                            TextField("http://IP-DO-PC:8765", text: $settings.serverURL)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            SecureField("Token do servidor", text: $settings.apiToken)
                                .textFieldStyle(.roundedBorder)
                            HStack {
                                Text("Força: \(settings.elo) ELO aprox.")
                                Spacer()
                                Text("Profundidade: \(settings.depth)")
                            }.font(.subheadline)
                            Slider(value: Binding(get: { Double(settings.elo) },
                                set: { settings.elo = Int($0) }), in: 1400...3000, step: 100)
                            Stepper("Profundidade: \(settings.depth)", value: $settings.depth,
                                    in: 8...22)
                            Toggle("Detectar cor automaticamente", isOn: $settings.automaticSide)
                            Toggle("Mostrar setas", isOn: $settings.showArrows)
                            Toggle("Mostrar avaliação", isOn: $settings.showEvaluation)
                            Button("Salvar configurações") {
                                SharedStore.saveSettings(settings)
                                feedback = "Configurações salvas."
                            }.buttonStyle(.bordered)
                        }
                    }

                    GroupBox("3. Compartilhar a tela para reconhecimento") {
                        HStack(spacing: 15) {
                            BroadcastPicker().frame(width: 60, height: 60)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Toque no botão circular e selecione Chess Trainer Capture.")
                                Text(broadcast?.message ?? "Transmissão não iniciada")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("A extensão reconhece lances enquanto recebe a transmissão. No iOS, o app principal pode ficar suspenso ao trocar de aplicativo; esta versão não oferece janela PiP sobre o Chess.com.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    GroupBox("4. Última análise") {
                        VStack(alignment: .leading, spacing: 12) {
                            let activeBoard = tracking?.position.board ?? calibration?.initialBoard
                            if let activeBoard, let calibration {
                                ChessBoardView(board: activeBoard,
                                               orientation: calibration.orientation,
                                               suggestedMove: analysis?.bestMove,
                                               showArrow: settings.showArrows)
                                    .frame(maxWidth: 340)
                            }
                            if let tracking, let calibration {
                                let tracker = PositionTracker(orientation: calibration.orientation, state: tracking)
                                Text("FEN: \(tracker.fen())")
                                    .font(.caption.monospaced()).textSelection(.enabled)
                                if let move = tracking.position.lastMoveUCI {
                                    Text("Último lance reconhecido: \(move)")
                                }
                                if let error = tracking.lastError {
                                    Text(error).foregroundStyle(.orange).font(.footnote)
                                }
                                Button(requesting ? "Analisando…" : "Analisar posição agora") {
                                    analyzeNow(fen: tracker.fen())
                                }.disabled(requesting)
                            }
                            if let scan {
                                Text("Leitura: \(Int(scan.confidence * 100))% de similaridade média · \(scan.unknownCount) casas incertas")
                                    .font(.footnote)
                            }
                            if let analysis {
                                if let error = analysis.error {
                                    Text(error).foregroundStyle(.orange)
                                } else {
                                    Text("Sugestão: \(analysis.bestMoveSAN ?? analysis.bestMove ?? "—")")
                                        .font(.headline)
                                    if settings.showEvaluation {
                                        if let cp = analysis.evaluationCP {
                                            Text(String(format: "Avaliação: %+.2f (ponto de vista das brancas)", Double(cp) / 100))
                                        } else if let mate = analysis.mate {
                                            Text("Mate em \(mate)")
                                        }
                                    }
                                    if !analysis.principalVariation.isEmpty {
                                        Text("Linha: \(analysis.principalVariation.joined(separator: " "))")
                                            .font(.caption.monospaced())
                                    }
                                }
                            } else {
                                Text("Aguardando uma análise do Stockfish…")
                                    .foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !feedback.isEmpty {
                        Text(feedback).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Chess Trainer")
            .onAppear { refresh() }
            .onReceive(refreshTimer) { _ in refresh() }
            .onChange(of: photo) { _, newValue in
                Task {
                    guard let data = try? await newValue?.loadTransferable(type: Data.self),
                          let raw = UIImage(data: data) else { return }
                    let format = UIGraphicsImageRendererFormat.default()
                    format.scale = 1
                    let normalized = UIGraphicsImageRenderer(size: raw.size, format: format)
                        .image { _ in raw.draw(in: CGRect(origin: .zero, size: raw.size)) }
                    await MainActor.run {
                        screenshot = normalized
                        boardRect = NormalizedRect()
                        feedback = "Ajuste a moldura e toque em Calibrar."
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sliderField(_ title: String, value: Binding<Double>,
                             lower: Double = 0, upper: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption)
            Slider(value: value, in: lower...max(lower + 0.0001, upper))
        }
    }

    private func calibrate(_ image: UIImage) {
        guard SharedStore.directory != nil else {
            feedback = "App Group não está configurado na assinatura dos dois targets."
            return
        }
        guard let cgImage = image.cgImage else { feedback = "Imagem inválida."; return }
        let forced: BoardOrientation?
        switch orientationChoice {
        case "white": forced = .whiteBottom
        case "black": forced = .blackBottom
        default: forced = nil
        }
        do {
            let value = try BoardRecognizer.enroll(image: cgImage, rect: boardRect,
                                                    forcedOrientation: forced)
            calibration = value
            SharedStore.save(value, as: "calibration.json")
            SharedStore.clearSession()
            SharedStore.save(TrackingState(position: TrainingPosition(
                board: value.initialBoard, sideToMove: "w")), as: "tracking.json")
            SharedStore.saveSettings(settings)
            feedback = "Calibrado! Agora inicie a transmissão e abra o tabuleiro de treino."
        } catch { feedback = error.localizedDescription }
    }

    private func refresh() {
        scan = SharedStore.load("scan.json")
        tracking = SharedStore.load("tracking.json")
        analysis = SharedStore.load("analysis.json")
        broadcast = SharedStore.load("broadcast.json")
    }

    private func analyzeNow(fen: String) {
        SharedStore.saveSettings(settings)
        requesting = true
        StockfishClient.analyze(fen: fen, settings: settings) { result in
            DispatchQueue.main.async {
                requesting = false
                switch result {
                case .success(let value):
                    SharedStore.save(value, as: "analysis.json")
                    analysis = value
                case .failure(let error): feedback = "Erro Stockfish: \(error.localizedDescription)"
                }
            }
        }
    }
}

private struct CalibrationPreview: View {
    let image: UIImage
    let rect: NormalizedRect
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / image.size.width,
                            geometry.size.height / image.size.height)
            let width = image.size.width * scale
            let height = image.size.height * scale
            let ox = (geometry.size.width - width) / 2
            let oy = (geometry.size.height - height) / 2
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: width, height: height)
                    .position(x: ox + width / 2, y: oy + height / 2)
                Rectangle()
                    .stroke(.yellow, lineWidth: 3)
                    .background(.yellow.opacity(0.1))
                    .frame(width: width * CGFloat(rect.size), height: width * CGFloat(rect.size))
                    .position(x: ox + width * CGFloat(rect.x + rect.size / 2),
                              y: oy + height * CGFloat(rect.y) + width * CGFloat(rect.size) / 2)
            }
        }
    }
}
