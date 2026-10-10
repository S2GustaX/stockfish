import Foundation

// Cliente HTTP opcional: a engine Stockfish roda no Windows na mesma rede.
// Uma versão posterior pode substituir por engine incorporada ao app.
enum StockfishClient {
    static func analyze(fen: String, settings: AppSettings,
                        completion: @escaping (Result<EngineResult, Error>) -> Void) {
        guard let url = URL(string: settings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
            + "/analyze"), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            completion(.failure(NSError(domain: "ChessTrainer", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Endereço do servidor inválido."])))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(AnalyzeRequest(fen: fen,
            elo: settings.elo, depth: settings.depth))
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else {
                completion(.failure(NSError(domain: "ChessTrainer", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Servidor não enviou resposta."])))
                return
            }
            do {
                let result = try JSONDecoder().decode(EngineResult.self, from: data)
                completion(.success(result))
            } catch {
                let explanation = String(data: data, encoding: .utf8) ?? error.localizedDescription
                completion(.failure(NSError(domain: "ChessTrainer", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: explanation])))
            }
        }.resume()
    }
}
