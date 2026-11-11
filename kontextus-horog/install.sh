#!/bin/sh
# Kontextus-horog telepítése az aktuális felhasználónak (root nem kell):
# PostToolUse hookként bekerül a ~/.claude/settings.json-ba, így minden Claude Code
# terminálban (és alügynökben) mér, 500k-nál soft stopot, 600k-nál erős stopot kér.
# Többször is futtatható; ha a horog máshonnan volt bejegyezve, átírja erre a helyre.
#
#   sh install.sh
set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
SETTINGS="$HOME/.claude/settings.json"
CMD="python3 \"$DIR/kontextus_horog.py\""

command -v python3 >/dev/null || { echo "HIBA: nincs python3"; exit 1; }

python3 - "$SETTINGS" "$CMD" <<'PY'
import json, os, shutil, sys, time
path, cmd = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
post = data.setdefault("hooks", {}).setdefault("PostToolUse", [])
found = changed = False
for group in post:
    for h in group.get("hooks", []):
        if str(h.get("command", "")).rstrip("\"").endswith("kontextus_horog.py"):
            found = True
            if h["command"] != cmd:
                h["command"] = cmd
                changed = True
if not found:
    post.append({"matcher": "*", "hooks": [{"type": "command", "command": cmd, "timeout": 10}]})
    changed = True
if not changed:
    print("  kész: horog (már be volt jegyezve)")
    sys.exit()
os.makedirs(os.path.dirname(path), exist_ok=True)
if os.path.exists(path):
    backup = f"{path}.backup-{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(path, backup)
    print("  mentés:", backup)
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, path)
print("  kész: horog bejegyezve:", cmd)
PY
echo "Az új Claude Code munkamenetekben már fut; a nyitottakban a /hooks megnyitása vagy újraindítás után."
