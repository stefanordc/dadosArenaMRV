"""Servidor local Arena MRV. Exibe apenas o HTML público do portal.

Uso:
    python servidor.py --porta 8001

Por padrão, utiliza 8001 para preservar a porta 8000 de outros projetos.
"""
from argparse import ArgumentParser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
HTML = (ROOT / "index.html").read_bytes()
ROUTES = {
    "/", "/inicio", "/jogos", "/desempenho", "/estatisticas",
    "/artilheiros", "/assistencias", "/tecnicos", "/disciplina",
    "/publico", "/bordero", "/admin", "/cadastro", "/inserir-jogos",
    "/cadastro/jogadores", "/cadastro/tecnicos", "/cadastro/arbitros",
    "/cadastro/assistentes", "/cadastro/var",
    "/cadastro/adversarios", "/cadastro/campeonatos",
}


class SiteHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path).path.rstrip("/") or "/"
        if path not in ROUTES:
            self.send_error(404, "Página não encontrada")
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(HTML)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "strict-origin-when-cross-origin")
        self.end_headers()
        self.wfile.write(HTML)


def main():
    parser = ArgumentParser(description="Servidor local do site Arena MRV")
    parser.add_argument("--porta", type=int, default=8001,
                        help="Porta para o servidor HTTP (padrão: 8001)")
    args = parser.parse_args()
    if not (1 <= args.porta <= 65535):
        parser.error("A porta deve estar entre 1 e 65535")
    address = f"http://127.0.0.1:{args.porta}"
    print(f"Arena MRV: {address}/  |  Administração: {address}/admin", flush=True)
    print("Arquivos privados (banco.sql e código de instalação) NÃO são servidos.", flush=True)
    try:
        with ThreadingHTTPServer(("127.0.0.1", args.porta), SiteHandler) as server:
            server.serve_forever()
    except OSError as exc:
        raise SystemExit(f"Não foi possível iniciar na porta {args.porta}: {exc}") from exc
    except KeyboardInterrupt:
        print("Servidor interrompido.")


if __name__ == "__main__":
    main()
