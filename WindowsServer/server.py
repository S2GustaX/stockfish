"""Servidor local HTTP de treino com Stockfish, executável no Windows.

Instalar: py -m pip install -r requirements.txt
Rodar: py server.py --engine "C:\\Stockfish\\stockfish.exe" --token "troque-este-token"
"""
import argparse
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

import chess
import chess.engine


class StockfishService:
    def __init__(self, engine_path: str):
        self.engine = chess.engine.SimpleEngine.popen_uci(engine_path, timeout=15)
        self.lock = threading.Lock()
        self.options = self.engine.options

    def analyze(self, fen: str, elo: int, depth: int) -> dict[str, Any]:
        board = chess.Board(fen)
        if not board.is_valid():
            raise ValueError("FEN de posição inválida; verifique a calibração e a sequência de lances.")
        elo = max(1400, min(3000, elo))
        depth = max(8, min(22, depth))
        with self.lock:
            if "UCI_LimitStrength" in self.options and "UCI_Elo" in self.options:
                option = self.options["UCI_Elo"]
                min_elo = option.min or elo
                max_elo = option.max or elo
                self.engine.configure({"UCI_LimitStrength": True,
                    "UCI_Elo": max(min_elo, min(max_elo, elo))})
            else:
                # Engine sem suporte a UCI_Elo: avaliação em força máxima.
                if "UCI_LimitStrength" in self.options:
                    self.engine.configure({"UCI_LimitStrength": False})
            info = self.engine.analyse(board, chess.engine.Limit(depth=depth))
        score = info.get("score")
        relative_white = score.white() if score else None
        pv = info.get("pv", [])
        board_copy = board.copy()
        line = []
        for move in pv[:8]:
            if not board_copy.is_legal(move):
                break
            line.append(board_copy.san(move))
            board_copy.push(move)
        return {
            "fen": fen,
            "bestMove": pv[0].uci() if pv else None,
            "bestMoveSAN": board.san(pv[0]) if pv and board.is_legal(pv[0]) else None,
            "evaluationCP": relative_white.score() if relative_white else None,
            "mate": relative_white.mate() if relative_white else None,
            "principalVariation": line,
            "engineName": self.engine.id.get("name", "Stockfish"),
            "error": None,
        }


def make_handler(service: StockfishService, token: str):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/health":
                self.send_error(404)
                return
            self.reply(200, {"status": "ok", "engine": service.engine.id.get("name", "Stockfish")})

        def do_POST(self):
            if self.path != "/analyze":
                self.send_error(404)
                return
            if self.headers.get("Authorization") != f"Bearer {token}":
                self.reply(401, {"error": "Token incorreto."})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not (0 < length <= 4096):
                    raise ValueError("Tamanho de requisição inválido.")
                request = json.loads(self.rfile.read(length))
                fen = str(request["fen"])
                result = service.analyze(fen, int(request.get("elo", 2500)),
                                         int(request.get("depth", 16)))
                self.reply(200, result)
            except (ValueError, KeyError, TypeError, chess.InvalidMoveError) as exc:
                self.reply(422, {"error": str(exc)})
            except Exception as exc:
                self.reply(500, {"error": f"Erro de análise: {exc}"})

        def reply(self, status: int, body: dict):
            encoded = json.dumps(body, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

    return Handler


def main():
    parser = argparse.ArgumentParser(description="Stockfish local para Chess Trainer iOS")
    parser.add_argument("--engine", required=True, help="Caminho do executável Stockfish")
    parser.add_argument("--token", required=True, help="Token longo compartilhado com o app")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    if len(args.token) < 12:
        parser.error("Use um token com pelo menos 12 caracteres.")
    service = StockfishService(args.engine)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(service, args.token))
    print(f"Servidor ativo em http://{args.host}:{args.port}, motor: {service.engine.id.get('name')}")
    print("Atenção: HTTP sem criptografia. Use apenas uma rede Wi-Fi confiável.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        service.engine.quit()


if __name__ == "__main__":
    main()
