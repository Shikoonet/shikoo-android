"""A fake Shikoo panel for emulator tests: no real link, no real server.

Serves on 127.0.0.1:18089 (10.0.2.2:18089 from an emulator) the Clash subscription the panel
gives FlClash, with the panel's headers. Its servers carry the names of the design frames.
All but «انگلیس» are one local mihomo on :17899 that exits through this machine's proxy
(127.0.0.1:10808), so an emulator's outside IP changes country only when the app's tunnel
really carries its traffic; «انگلیس» points at a closed port, a server that does not answer.
mihomo prints one line per connection.

Run: python fake-panel.py   Ctrl-C stops mihomo too. A hard kill (Stop-Process, a stopped
background task) does not run `finally`, so kill both PIDs from the first line it prints.
"""
import base64, http.server, os, subprocess, tempfile, time
from pathlib import Path

MIHOMO = r"D:\dev\shikoo-spike\mihomo\mihomo-windows-amd64-compatible.exe"
GB = 1024 ** 3
SUB = """proxies:
  - {name: "آلمان ۲", type: http, server: 10.0.2.2, port: 17899}
  - {name: "فنلاند ۲", type: http, server: 10.0.2.2, port: 17899}
  - {name: "هلند ۱", type: http, server: 10.0.2.2, port: 17899}
  - {name: "آمریکا ۲", type: http, server: 10.0.2.2, port: 17899}
  - {name: "انگلیس", type: http, server: 10.0.2.2, port: 1}
proxy-groups:
  - {name: PROXY, type: select, proxies: ["آلمان ۲", "فنلاند ۲", "هلند ۱", "آمریکا ۲", "انگلیس", DIRECT]}
rules:
  - MATCH,PROXY
"""
EXIT_PROXY = """mixed-port: 17899
allow-lan: false
log-level: info
mode: global
proxies:
  - {name: exit, type: socks5, server: 127.0.0.1, port: 10808}
proxy-groups:
  - {name: GLOBAL, type: select, proxies: [exit]}
"""

def b64(s): return base64.b64encode(s.encode()).decode()

class Panel(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        for k, v in {
            "profile-title": "base64:" + b64("user123 · الماس"),
            "subscription-userinfo": f"upload={2*GB}; download={31*GB}; total={100*GB}; expire={int(time.time()) + 23*86400}",
            "profile-update-interval": "1",
            "support-url": "https://t.me/telegram",
            "announce": "base64:" + b64("امشب ۲ تا ۳ بامداد سرور آمریکا به‌روز می‌شود"),
            "Content-Type": "text/yaml; charset=utf-8",
        }.items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(SUB.encode())

with tempfile.TemporaryDirectory(prefix="fake-panel-") as d:
    (Path(d) / "config.yaml").write_text(EXIT_PROXY, encoding="utf-8")
    proxy = subprocess.Popen([MIHOMO, "-d", d, "-f", str(Path(d) / "config.yaml")])
    print(f"panel pid {os.getpid()} proxy pid {proxy.pid}", flush=True)
    try:
        http.server.HTTPServer(("127.0.0.1", 18089), Panel).serve_forever()
    finally:
        proxy.terminate()
        proxy.wait()
