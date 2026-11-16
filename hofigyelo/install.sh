#!/bin/sh
# Hőfigyelő telepítése az aktuális felhasználónak (root nem kell):
# felhasználói szolgáltatásként elindítja a hofigyelo.py-t (bejelentkezéskor magától indul),
# és Claude Code horogként bejegyzi a hofigyelo_horog.py-t a ~/.claude/settings.json-ba.
# Bárhonnan és többször is futtatható; ami már be van állítva, azt nem módosítja.
#
#   sh install.sh                 szolgáltatás és horgok
#   sh install.sh --horog-nelkul  csak a szolgáltatás (a sáv hőmérőihez ennyi elég)
set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
UNIT="$HOME/.config/systemd/user/hofigyelo.service"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
HOOK_CMD="python3 \"$DIR/hofigyelo_horog.py\""
HOOKS=1
[ "${1:-}" = "--horog-nelkul" ] && HOOKS=0

ok() { echo "  kész: $1"; }

echo "Hőfigyelő telepítése innen: $DIR"

# 1. függőségek és érzékelők
command -v python3 >/dev/null || { echo "HIBA: nincs python3"; exit 1; }
command -v systemctl >/dev/null || { echo "HIBA: nincs systemctl; a szolgáltatás nem telepíthető"; exit 1; }
command -v notify-send >/dev/null || echo "  figyelem: nincs notify-send; asztali értesítés nem lesz"
command -v powerprofilesctl >/dev/null || echo "  figyelem: nincs powerprofilesctl; az energiamód-váltás kimarad"
command -v nvidia-smi >/dev/null || echo "  figyelem: nincs nvidia-smi; GPU-hőmérséklet nem lesz"
if ! grep -qsx -e k10temp -e coretemp /sys/class/hwmon/hwmon*/name; then
    echo "  figyelem: nincs k10temp vagy coretemp érzékelő; CPU-hőmérséklet nem lesz"
fi

# 2. felhasználói szolgáltatás
mkdir -p "$(dirname "$UNIT")"
WANT="[Unit]
Description=Hőfigyelő: CPU- és GPU-hőmérséklet figyelése

[Service]
ExecStart=/usr/bin/env python3 \"$DIR/hofigyelo.py\"
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target"
if [ -f "$UNIT" ] && [ "$(cat "$UNIT")" = "$WANT" ]; then
    ok "szolgáltatásfájl (már megvolt)"
    CHANGED=0
else
    printf '%s\n' "$WANT" > "$UNIT"
    ok "szolgáltatásfájl: $UNIT"
    CHANGED=1
fi
systemctl --user daemon-reload
systemctl --user enable hofigyelo.service >/dev/null 2>&1
if [ "$CHANGED" = 1 ]; then
    systemctl --user restart hofigyelo.service
else
    systemctl --user start hofigyelo.service
fi
ok "szolgáltatás: $(systemctl --user is-enabled hofigyelo.service), $(systemctl --user is-active hofigyelo.service)"

# 3. Claude Code horgok
if [ "$HOOKS" = 0 ]; then
    echo "  kihagyva: horgok (--horog-nelkul)"
else
    python3 - "$SETTINGS" "$HOOK_CMD" <<'PY'
import json, os, shutil, sys, time
path, cmd = sys.argv[1], sys.argv[2]
# event -> matcher (None: the event takes no matcher)
EVENTS = {"PreToolUse": "Bash", "PostToolUse": "*", "UserPromptSubmit": None}
data = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
hooks = data.setdefault("hooks", {})
changed = False
for event, matcher in EVENTS.items():
    groups = hooks.setdefault(event, [])
    found = False
    for group in groups:
        for h in group.get("hooks", []):
            if str(h.get("command", "")).rstrip('"').endswith("hofigyelo_horog.py"):
                found = True
                if h["command"] != cmd:
                    h["command"] = cmd
                    changed = True
    if not found:
        group = {"hooks": [{"type": "command", "command": cmd, "timeout": 5}]}
        if matcher:
            group = {"matcher": matcher, **group}
        groups.append(group)
        changed = True
if not changed:
    print("  kész: horgok (már be voltak jegyezve)")
    sys.exit()
os.makedirs(os.path.dirname(path), exist_ok=True)
if os.path.exists(path):
    backup = f"{path}.backup-{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(path, backup)
    print("  mentés:", backup)
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, path)
print("  kész: horgok bejegyezve (PreToolUse/Bash, PostToolUse, UserPromptSubmit):", cmd)
PY
fi

echo "Állapot: systemctl --user status hofigyelo"
