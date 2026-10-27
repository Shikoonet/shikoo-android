"""Writes assets/data/shikoo-go-licenses.txt: the licence of every Go module linked into the core for Android and
Windows (mihomo, Xray, sing-box and their dependencies), in the NOTICES form `lib/shikoo/app/licenses.dart` reads.
Run it after tools/core-patches/apply.sh, whose copies hold the replaced modules, and after every go.mod change."""
import os, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'assets/data/shikoo-go-licenses.txt'
SEPARATOR = '-' * 80
NAMES = ('LICENSE', 'LICENCE', 'COPYING', 'NOTICE')
NONE = 'This module ships no licence file.'
TARGETS = (('android', 'arm64', '1'), ('android', 'arm', '1'), ('android', 'amd64', '1'), ('windows', 'amd64', '0'))
tags = next(l.split(':', 1)[1].strip() for l in (ROOT / 'build_config.yaml').read_text().splitlines() if l.startswith('tags:'))

modules = {}
for goos, goarch, cgo in TARGETS:
    listed = subprocess.run(
        ['go', 'list', '-deps', '-tags', tags, '-f', '{{with .Module}}{{if not .Main}}{{.Path}}\t{{.Dir}}{{end}}{{end}}', '.'],
        cwd=ROOT / 'core', check=True, capture_output=True, text=True,
        env={**os.environ, 'GOOS': goos, 'GOARCH': goarch, 'CGO_ENABLED': cgo},
    ).stdout
    for line in filter(None, listed.splitlines()):
        path, folder = line.split('\t')
        modules[path] = Path(folder)

groups, missing = {}, []
for path in sorted(modules):
    files = sorted(f for f in modules[path].iterdir() if f.is_file() and f.name.upper().startswith(NAMES))
    text = '\n\n'.join(f.read_text(encoding='utf-8', errors='replace').strip() for f in files) or NONE
    if not files:
        missing.append(path)
    assert SEPARATOR not in text.splitlines(), f'{path}: its licence holds the separator line'
    groups.setdefault(text, []).append(path)
if missing:
    print('no licence file at the root of: ' + ', '.join(missing), file=sys.stderr)

OUT.write_text(f'\n{SEPARATOR}\n'.join('\n'.join(paths) + '\n\n' + text for text, paths in groups.items()) + '\n',
               encoding='utf-8', newline='\n')
print(f'{len(modules)} modules, {len(groups)} licence texts, {OUT.stat().st_size} bytes')
