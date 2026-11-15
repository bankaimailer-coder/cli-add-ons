#!/bin/sh
# Kontextus-horog telepítése az aktuális felhasználónak (root nem kell):
# PostToolUse hookként bekerül a ~/.claude/settings.json-ba, így minden Claude Code
# terminálban (és alügynökben) mér, 500k-nál soft stopot, 600k-nál erős stopot kér.
# Többször is futtatható; ha a horog egy másik klónból volt bejegyezve, átírja erre a helyre
# (ha ugyanerre a fájlra mutat más írásmóddal, pl. szimlinken át, meghagyja).
#
#   sh install.sh                 # bejegyzés
#   sh install.sh --eltavolitas   # a horog kivétele (mentéssel; más horoghoz nem nyúl)
#   sh install.sh --szaraz [...]  # csak kiírja, mit tenne; semmit nem ír
#
# Kilépési kód: 0 kész (vagy már megvolt), 1 hiba, 2 ismeretlen kapcsoló, 3 kihagyva (nincs claude vagy python3).
# TELEPIT_EREDMENY: ha meg van adva, ebbe a fájlba írja a gyökér telepit.sh összesítőjének, hogy változott-e
# valami („valtozott”), illetve a kihagyás okát („kihagyva<TAB>ok”).
set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
SETTINGS="$HOME/.claude/settings.json"
CMD="python3 \"$DIR/kontextus_horog.py\""

MODE=telepit
SZARAZ=0
for a in "$@"; do
    case "$a" in
        --eltavolitas) MODE=eltavolit ;;
        --szaraz) SZARAZ=1 ;;
        *) echo "HIBA: ismeretlen kapcsoló: $a (lehet: --eltavolitas, --szaraz)"; exit 2 ;;
    esac
done

kihagy() {
    echo "  kihagyva: $1"
    [ -z "${TELEPIT_EREDMENY:-}" ] || printf 'kihagyva\t%s\n' "$1" >> "$TELEPIT_EREDMENY"
    exit 3
}
command -v python3 >/dev/null || kihagy "nincs python3 (pkexec apt install python3)"
if [ "$MODE" = telepit ]; then
    command -v claude >/dev/null || kihagy "nincs claude (a Claude Code CLI; telepítés: https://claude.com/claude-code)"
fi

python3 - "$SETTINGS" "$CMD" "$DIR/kontextus_horog.py" "$MODE" "$SZARAZ" <<'PY'
import json, os, shlex, shutil, sys, time
path, cmd, script, mode, szaraz = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] == "1"
SUFFIX = "/kontextus-horog/kontextus_horog.py"


def script_of(c):
    try:
        parts = shlex.split(str(c))
    except ValueError:
        return None
    return next((p for p in parts if p.endswith(SUFFIX)), None)


data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except ValueError as e:
        print(f"HIBA: a {path} nem érvényes JSON ({e}); nem nyúlok hozzá")
        sys.exit(1)
elif mode == "eltavolit":
    print("  kész: horog (nincs settings.json, nincs mit kivenni)")
    sys.exit()
hooks = data.setdefault("hooks", {})
post = hooks.setdefault("PostToolUse", [])
found = False
notes = []
for group in post:
    keep = []
    for h in group.get("hooks", []):
        old = script_of(h.get("command", "")) if isinstance(h, dict) else None
        if old is None:
            keep.append(h)
        elif mode == "eltavolit":
            notes.append("kivéve")
        elif found:
            notes.append("kettőzött bejegyzés kivéve")
        else:
            found = True
            if os.path.realpath(old) != os.path.realpath(script):
                h["command"] = cmd
                notes.append(f"útvonal átírva: {old} -> {script}")
            keep.append(h)
    group["hooks"] = keep
if mode == "telepit" and not found:
    post.append({"matcher": "*", "hooks": [{"type": "command", "command": cmd, "timeout": 10}]})
    notes.append("bejegyezve: " + cmd)
post[:] = [g for g in post if g.get("hooks")]
if not post:
    hooks.pop("PostToolUse")
if not hooks:
    data.pop("hooks")
if not notes:
    print("  kész: horog (már be volt jegyezve)" if mode == "telepit" else "  kész: horog (nem volt bejegyezve)")
    sys.exit()
if os.environ.get("TELEPIT_EREDMENY"):
    with open(os.environ["TELEPIT_EREDMENY"], "a") as f:
        f.write("valtozott\n")
if szaraz:
    for n in notes:
        print("  tenné: horog", n)
    sys.exit()
path = os.path.realpath(path)   # szimlinknél a célfájlt írja, a szimlink megmarad
os.makedirs(os.path.dirname(path), exist_ok=True)
perm = os.stat(path).st_mode & 0o7777 if os.path.exists(path) else 0o600
if os.path.exists(path):
    backup = base = f"{path}.backup-{time.strftime('%Y%m%d-%H%M%S')}"
    n = 0
    while os.path.exists(backup):   # egy másodpercen belüli több írás se írja felül a korábbi mentést
        n += 1
        backup = f"{base}-{n}"
    shutil.copy2(path, backup)
    print("  mentés:", backup)
tmp = f"{path}.{os.getpid()}.tmp"
# az ideiglenes fájl 0600-zal jön létre (más nem olvashatja), az eredeti jogát csak a csere előtt kapja meg
with os.fdopen(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
    f.flush()
    os.fsync(f.fileno())
os.chmod(tmp, perm)
os.replace(tmp, path)
for n in notes:
    print("  kész: horog", n)
PY
if [ "$MODE" = telepit ] && [ "$SZARAZ" = 0 ]; then
    echo "Az új Claude Code munkamenetekben már fut; a nyitottakban a /hooks megnyitása vagy újraindítás után."
fi
