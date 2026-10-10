"""Build the standalone HTML review from local source, with no external assets."""
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def build():
    icons = (ROOT / "icons.js").read_text()
    fragment = (ROOT / "menu-bar.fragment.html").read_text()
    html = """<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'">
<title>SleepGuard · 新功能交互原型</title>
<style>
:root { color-scheme: light dark; background: light-dark(#fff, #19191b); }
body { margin: 0; padding: 22px; }
html { scrollbar-width: none; }
::-webkit-scrollbar { display: none; }
@media(max-width: 600px) { body { padding: 12px; } }
</style>
</head>
<body>
<script>""" + icons + "</script>\n" + fragment + "\n</body>\n</html>\n"
    (ROOT / "index.html").write_text(html)
    print("Built prototypes/index.html with local icons and no network dependencies")


if __name__ == "__main__":
    build()
