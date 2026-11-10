#!/usr/bin/env python3
# Serve build/web/ em http://localhost:8060 com os cabeçalhos COOP/COEP que o Godot Web com threads exige. Uso: scripts/serve-web.py [porta]
import functools, http.server, os, sys
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
H.extensions_map[".wasm"] = "application/wasm"
d = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8060), functools.partial(H, directory=d)).serve_forever()
