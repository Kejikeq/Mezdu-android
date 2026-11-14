"""Copies the light part of a content pack (shaders, materials, small textures) into the APK assets.
Atlas and world are left to the updater so git does not grow by megabytes on every game commit.
    python3 tools/bundle_pack.py <full pack dir> [app/src/main/assets/pack]"""
import json, shutil, sys
from pathlib import Path

KINDS = {'shader', 'materials', 'tex'}
src = Path(sys.argv[1])
dst = Path(sys.argv[2] if len(sys.argv) > 2 else 'app/src/main/assets/pack')
m = json.loads((src / 'manifest.json').read_text())
m['files'] = [f for f in m['files'] if f.get('kind') in KINDS]
m['bundled'] = True
shutil.rmtree(dst, ignore_errors=True)
for f in m['files']:
    (dst / f['path']).parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src / f['path'], dst / f['path'])
(dst / 'manifest.json').write_text(json.dumps(m, ensure_ascii=False, indent=1))
print(f"{dst}: {len(m['files'])} files, {sum(f['size'] for f in m['files']) // 1024} KB, commit {m['commit'][:7]}")
