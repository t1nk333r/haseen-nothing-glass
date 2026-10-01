# The cover server tests/cover-art.sh points the Now Playing art at. Stdlib only.
#
#   python3 cover-art-server.py <scratch> <cert> <key>
#
# Serves HTTPS (the scheme the tile accepts) and plain HTTP (the one it must
# refuse) on two ephemeral ports, writes "<https port> <http port>" to
# <scratch>/ports, and appends every request line it sees to
# <scratch>/hits-https and <scratch>/hits-http, so the test can count what the
# shell asked for.
import os, ssl, struct, sys, threading, time, zlib
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

scratch, cert, key = sys.argv[1:4]


def png(w, h, rgb):
    row = b"\x00" + bytes(rgb) * w
    raw = zlib.compress(row * h, 9)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", raw) + chunk(b"IEND", b""))


GOOD = png(200, 200, (204, 34, 34))
_covers = {}
_lock = threading.Lock()


def cover(n):
    # 2000x2000, a different colour each: decoded at full size that is 16 MB
    # apiece, which is what the sampling check measures.
    with _lock:
        if n not in _covers:
            _covers[n] = png(2000, 2000, ((n * 53) % 256, (n * 97) % 256, (n * 151) % 256))
        return _covers[n]


def make_handler(log, https_port_ref, http_port_ref):
    class H(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *a):
            pass

        def send_body(self, body, ctype="image/png"):
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            with open(log, "a") as f:
                f.write(self.path + "\n")
            path = self.path.split("?")[0]
            try:
                if path == "/good.png":
                    self.send_body(GOOD)
                elif path.startswith("/cover/"):
                    self.send_body(cover(int(path[len("/cover/"):].split(".")[0])))
                elif path == "/stall":
                    time.sleep(120)
                elif path == "/endless":
                    # An image/png body that never ends, chunked so no
                    # Content-Length announces it.
                    self.send_response(200)
                    self.send_header("Content-Type", "image/png")
                    self.send_header("Transfer-Encoding", "chunked")
                    self.end_headers()
                    block = GOOD[:8] + b"\x00" * 65528
                    while True:
                        self.wfile.write(b"%x\r\n%s\r\n" % (len(block), block))
                elif path == "/oversize":
                    # Announced: 6 MiB with a Content-Length.
                    self.send_body(b"\x00" * (6 * 1024 * 1024))
                elif path == "/oversize-chunked":
                    # Not announced: 6 MiB, chunked, then a proper end.
                    self.send_response(200)
                    self.send_header("Content-Type", "image/png")
                    self.send_header("Transfer-Encoding", "chunked")
                    self.end_headers()
                    block = b"\x00" * 65536
                    for _ in range(96):
                        self.wfile.write(b"%x\r\n%s\r\n" % (len(block), block))
                    self.wfile.write(b"0\r\n\r\n")
                elif path == "/redirect-http":
                    self.redirect("http://127.0.0.1:%d/good.png" % http_port_ref[0])
                elif path == "/redirect-https":
                    self.redirect("https://127.0.0.1:%d/good.png" % https_port_ref[0])
                else:
                    self.send_error(404)
            except (BrokenPipeError, ConnectionResetError, ssl.SSLError, OSError):
                pass

        def redirect(self, where):
            self.send_response(302)
            self.send_header("Location", where)
            self.send_header("Content-Length", "0")
            self.end_headers()

    return H


class Server(ThreadingHTTPServer):
    daemon_threads = True

    # A client hanging up mid-body - curl at its cap, a fetch killed - is the
    # point of most cases here, not an error worth a traceback.
    def handle_error(self, request, client_address):
        pass


https_port, http_port = [0], [0]
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert, key)

secure = Server(("127.0.0.1", 0), make_handler(os.path.join(scratch, "hits-https"), https_port, http_port))
# The handshake runs in the request thread, not in accept(): a client that
# never finishes one must not stall the whole server.
secure.socket = ctx.wrap_socket(secure.socket, server_side=True, do_handshake_on_connect=False)
plain = Server(("127.0.0.1", 0), make_handler(os.path.join(scratch, "hits-http"), https_port, http_port))
https_port[0] = secure.server_address[1]
http_port[0] = plain.server_address[1]

threading.Thread(target=plain.serve_forever, daemon=True).start()
with open(os.path.join(scratch, "ports.tmp"), "w") as f:
    f.write("%d %d\n" % (https_port[0], http_port[0]))
os.rename(os.path.join(scratch, "ports.tmp"), os.path.join(scratch, "ports"))
secure.serve_forever()
