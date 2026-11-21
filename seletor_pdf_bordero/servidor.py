from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from pathlib import Path
import ipaddress, socket, json

ROOT = Path(__file__).resolve().parent
PORT = 8765
class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)
    def do_GET(self):
        parsed = urlsplit(self.path)
        if parsed.path != '/api/pdf':
            return super().do_GET()
        url = parse_qs(parsed.query).get('url', [''])[0].strip()
        u = urlsplit(url)
        if u.scheme not in ('http', 'https') or not u.hostname or u.username or u.password:
            return self.fail(400, 'Informe uma URL HTTP(S) válida.')
        # Only allow publicly routed hosts to avoid proxying private resources.
        try:
            addresses = socket.getaddrinfo(u.hostname, u.port or (443 if u.scheme == 'https' else 80))
            if any(not ipaddress.ip_address(item[4][0]).is_global for item in addresses):
                return self.fail(400, 'Endereços locais ou privados não são permitidos.')
        except OSError:
            return self.fail(400, 'Não foi possível resolver o domínio.')
        try:
            req = Request(url, headers={'User-Agent': 'Mozilla/5.0 (compatible; PDFViewer/1.0)', 'Accept': 'application/pdf,*/*'})
            with urlopen(req, timeout=30) as res:
                size = int(res.headers.get('Content-Length', '0'))
                if size > 40 * 1024 * 1024:
                    return self.fail(413, 'Arquivo excede o limite de 40 MB.')
                data = res.read(40 * 1024 * 1024 + 1)
                if len(data) > 40 * 1024 * 1024:
                    return self.fail(413, 'Arquivo excede o limite de 40 MB.')
                if not data.lstrip().startswith(b'%PDF-'):
                    return self.fail(415, 'O endereço não retornou um PDF válido.')
                self.send_response(200)
                self.send_header('Content-Type', 'application/pdf')
                self.send_header('Content-Length', str(len(data)))
                self.send_header('Cache-Control', 'no-store')
                self.end_headers()
                self.wfile.write(data)
        except (HTTPError, URLError, TimeoutError, ValueError) as e:
            self.fail(502, f'Falha ao baixar PDF: {e}')
    def fail(self, status, detail):
        body = json.dumps({'erro': detail}, ensure_ascii=False).encode('utf8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

if __name__ == '__main__':
    print(f'Abra no navegador: http://127.0.0.1:{PORT}')
    ThreadingHTTPServer(('127.0.0.1', PORT), Handler).serve_forever()
