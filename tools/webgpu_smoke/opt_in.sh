#!/usr/bin/env bash
#
# Opts the workspace into WGSL sidecars for flutter_scene and the smoke app,
# merged into the workspace pubspec's hooks: user_defines: section (added when
# missing). The hook downloads the released flutter_scene_tint; pass TINT to
# use a local build instead. CI only: it edits the workspace pubspec in place.
#
#   tools/webgpu_smoke/opt_in.sh [TINT]
set -euo pipefail

TINT="${1:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT/pubspec.yaml" "$TINT" <<'EOF'
import sys

path, tint = sys.argv[1], sys.argv[2]
defines = ['flutter_scene_webgpu: true']
if tint:
    defines.append(f'flutter_scene_tint: {tint}')
lines = open(path).read().splitlines()

if 'hooks:' not in lines:
    lines += ['', 'hooks:']
hooks = lines.index('hooks:')
section = hooks + 1
while section < len(lines) and lines[section].startswith('  '):
    section += 1
if '  user_defines:' not in lines[hooks:section]:
    lines.insert(section, '  user_defines:')
    section += 1
start = lines.index('  user_defines:', hooks) + 1
end = start
while end < len(lines) and lines[end].startswith('    '):
    end += 1

for package in ['flutter_scene', 'smoke_render']:
    key = f'    {package}:'
    if key in lines[start:end]:
        at = lines.index(key, start) + 1
    else:
        lines.insert(end, key)
        at = end + 1
    for define in defines:
        lines.insert(at, f'      {define}')
        at += 1
    end = start
    while end < len(lines) and lines[end].startswith('    '):
        end += 1

open(path, 'w').write('\n'.join(lines) + '\n')
EOF
