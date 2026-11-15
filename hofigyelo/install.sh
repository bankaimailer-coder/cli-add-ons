#!/bin/sh
# Hőfigyelő telepítése az aktuális felhasználónak (root nem kell): systemd felhasználói szolgáltatás
# (hofigyelo.service, a hofigyelo.service.in sablonból) és három Claude Code horog a ~/.claude/settings.json-ban
# (PreToolUse/Bash, PostToolUse, UserPromptSubmit). Az útvonalakat a szkript helyéből számolja, a python -I
# kapcsolóval fut. Többször is futtatható: ami megvan, azt nem írja újra; a szolgáltatás csak akkor indul újra,
# ha az egysége változott. Ha a meglévő bejegyzés ugyanerre a mappára mutat más írásmóddal (szimlinken át),
# azt meghagyja; ha egy másik klónra mutat, átírja erre.
#
#   sh install.sh                    # telepítés (ha nincs ismert hőérzékelő: kihagyja, kilépési kód 3)
#   sh install.sh --erzekelo-nelkul  # akkor is telepít, ha nincs ismert hőérzékelő (figyelmeztetéssel)
#   sh install.sh --eltavolitas      # leállítás, egység törlése, a hőfigyelő horgainak kivétele (mentéssel)
#   sh install.sh --szaraz [...]     # csak kiírja, mit tenne; semmit nem ír, nem indít
#
# Kilépési kód: 0 kész (vagy már megvolt), 1 hiba, 2 ismeretlen kapcsoló, 3 kihagyva (hiányzó függőség).
# HOFIGYELO_HWMON: a hwmon-mappa helye (próbához; alapból /sys/class/hwmon).
# TELEPIT_EREDMENY: ha meg van adva, ebbe a fájlba írja a gyökér telepit.sh összesítőjének, hogy változott-e
# valami („valtozott”), illetve a kihagyás okát („kihagyva<TAB>ok”).
set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
UNIT_NAME=hofigyelo.service
UNIT_DST="$HOME/.config/systemd/user/$UNIT_NAME"
SETTINGS="$HOME/.claude/settings.json"
HWMON=${HOFIGYELO_HWMON:-/sys/class/hwmon}

MODE=telepit
SZARAZ=0
KENYSZER=0
for a in "$@"; do
    case "$a" in
        --eltavolitas) MODE=eltavolit ;;
        --szaraz) SZARAZ=1 ;;
        --erzekelo-nelkul) KENYSZER=1 ;;
        *) echo "HIBA: ismeretlen kapcsoló: $a (lehet: --eltavolitas, --erzekelo-nelkul, --szaraz)"; exit 2 ;;
    esac
done

ok() { echo "  kész: $1"; }
jelez() { [ -z "${TELEPIT_EREDMENY:-}" ] || printf '%s\n' "$1" >> "$TELEPIT_EREDMENY"; }
kihagy() { echo "  kihagyva: $1"; jelez "kihagyva	$1"; exit 3; }
# változás bejelentése; szárazon csak kiírja, és 1-et ad, hogy a hívó ne írjon
valtozas() {
    jelez valtozott
    if [ "$SZARAZ" = 1 ]; then echo "  tenné: $1"; return 1; fi
}

# a hofigyelo.py által ismert érzékelők: k10temp és acpitz (hwmon), nvidia-smi
erzekelo() {
    for n in "$HWMON"/hwmon*/name; do
        [ -r "$n" ] || continue
        case "$(cat "$n")" in k10temp|acpitz) return 0 ;; esac
    done
    command -v nvidia-smi >/dev/null
}

# python-seged: „unit” = a kitöltött egység; „horgok” = a settings.json horgainak beírása/kivétele
seged() {
    python3 - "$@" <<'PY'
import json, os, re, shlex, shutil, sys, time

SAFE = re.compile(r"[A-Za-z0-9/._+:@,=-]+")


def same(a, b):
    return os.path.realpath(a) == os.path.realpath(b)


def unit(tpl, python, script, existing):
    # ha a meglévő egység ugyanerre a fájlra mutat (más írásmóddal), annak írásmódja marad
    if os.path.exists(existing):
        with open(existing, encoding="utf-8") as f:
            for line in f:
                if line.startswith("ExecStart="):
                    try:
                        old = shlex.split(line[len("ExecStart="):].replace("%%", "%").replace("$$", "$"))[-1]
                    except (ValueError, IndexError):
                        continue
                    if old.endswith("/hofigyelo.py") and same(old, script):
                        script = old
                    try:
                        oldpy = shlex.split(line[len("ExecStart="):].replace("%%", "%").replace("$$", "$"))[0]
                    except (ValueError, IndexError):
                        continue
                    if same(oldpy, python):   # ugyanaz a python más írásmóddal (pl. /bin vagy /usr/bin): marad
                        python = oldpy

    def q(s):   # systemd-idézés, csak ha kell (így a meglévő, idézetlen egység változatlan marad)
        if SAFE.fullmatch(s):
            return s
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%").replace("$", "$$") + '"'

    with open(tpl, encoding="utf-8") as f:
        sys.stdout.write(f.read().replace("@PYTHON@", q(python)).replace("@SCRIPT@", q(script)))


EVENTS = [("PreToolUse", "Bash"), ("PostToolUse", "*"), ("UserPromptSubmit", None)]
SUFFIX = "/hofigyelo/hofigyelo_horog.py"


def script_of(cmd):
    """A horogparancsban a hőfigyelő horgának útvonala (bármelyik klónból), különben None."""
    try:
        parts = shlex.split(str(cmd))
    except ValueError:
        return None
    return next((p for p in parts if p.endswith(SUFFIX)), None)


def horgok(mode, szaraz, path, script, result):
    def jelez(s):
        if result:
            with open(result, "a", encoding="utf-8") as f:
                f.write(s + "\n")

    sq = script if SAFE.fullmatch(script) else '"' + re.sub(r'(["\\$`])', r"\\\1", script) + '"'
    cmd = "python3 -I " + sq
    data = {}
    if os.path.exists(path):
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except ValueError as e:
            print(f"HIBA: a {path} nem érvényes JSON ({e}); nem nyúlok hozzá")
            sys.exit(1)
    elif mode == "eltavolit":
        print("  kész: horgok (nincs settings.json, nincs mit kivenni)")
        return
    hooks = data.setdefault("hooks", {})
    notes = []
    for event, matcher in EVENTS:
        groups = hooks.get(event, [])
        seen = False
        for g in groups:
            keep = []
            for h in g.get("hooks", []):
                old = script_of(h.get("command", "")) if isinstance(h, dict) else None
                if old is None:
                    keep.append(h)
                elif mode == "eltavolit":
                    notes.append(f"{event}: kivéve")
                elif seen:
                    notes.append(f"{event}: kettőzött bejegyzés kivéve")
                else:
                    seen = True
                    if not same(old, script):
                        notes.append(f"{event}: útvonal átírva: {old} -> {script}")
                        h["command"] = cmd
                    keep.append(h)
            g["hooks"] = keep
        if mode == "telepit" and not seen:
            g = {"matcher": matcher} if matcher else {}
            g["hooks"] = [{"type": "command", "command": cmd, "timeout": 5}]
            groups.append(g)
            notes.append(f"{event}: bejegyezve")
        groups = [g for g in groups if g.get("hooks")]
        if groups:
            hooks[event] = groups
        else:
            hooks.pop(event, None)
    if not hooks:
        data.pop("hooks", None)
    if not notes:
        print("  kész: horgok (már megvolt)" if mode == "telepit" else "  kész: horgok (nem voltak bejegyezve)")
        return
    jelez("valtozott")
    if szaraz:
        for n in notes:
            print(f"  tenné: horog {n}")
        return
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
        print(f"  kész: horog {n}")


if sys.argv[1] == "unit":
    unit(*sys.argv[2:6])
else:
    horgok(sys.argv[2], sys.argv[3] == "1", sys.argv[4], sys.argv[5], os.environ.get("TELEPIT_EREDMENY", ""))
PY
}

if [ "$MODE" = eltavolit ]; then
    echo "Hőfigyelő eltávolítása"
    if [ -f "$UNIT_DST" ]; then
        if valtozas "szolgáltatás leállítása, kikapcsolása, törlése: $UNIT_DST"; then
            systemctl --user disable --now "$UNIT_NAME" || true
            rm -f "$UNIT_DST"
            systemctl --user daemon-reload || true
            ok "szolgáltatás leállítva, kikapcsolva, törölve: $UNIT_DST"
        fi
    else
        ok "szolgáltatás nincs telepítve (nincs mit törölni)"
    fi
    # az egység python nélkül is lebontható; a horgok kivételéhez python kell
    command -v python3 >/dev/null || kihagy "nincs python3: a szolgáltatás lebontva, a horgok kivétele kimaradt (pkexec apt install python3)"
    seged horgok eltavolit "$SZARAZ" "$SETTINGS" "$DIR/hofigyelo_horog.py"
    exit 0
fi

command -v python3 >/dev/null || kihagy "nincs python3 (pkexec apt install python3)"

echo "Hőfigyelő telepítése innen: $DIR"
command -v systemctl >/dev/null || kihagy "nincs systemctl (a hőfigyelő systemd felhasználói szolgáltatásként fut)"
if ! erzekelo; then
    [ "$KENYSZER" = 1 ] || kihagy "nincs ismert hőérzékelő (k10temp, ACPI-zóna, nvidia-smi)"
    echo "  figyelem: nincs ismert hőérzékelő (k10temp, ACPI-zóna, nvidia-smi); a hőfigyelő így nem mér hőmérsékletet"
fi

mkdir_p() { [ "$SZARAZ" = 1 ] || mkdir -p "$1"; }
mkdir_p "$(dirname "$UNIT_DST")"
NEW_UNIT=$(seged unit "$DIR/hofigyelo.service.in" "$(command -v python3)" "$DIR/hofigyelo.py" "$UNIT_DST")
CHANGED=0
if [ -f "$UNIT_DST" ] && [ "$(cat "$UNIT_DST")" = "$NEW_UNIT" ]; then
    ok "szolgáltatás-egység (már megvolt): $UNIT_DST"
else
    CHANGED=1
    if valtozas "szolgáltatás-egység: $UNIT_DST"; then
        printf '%s\n' "$NEW_UNIT" > "$UNIT_DST"
        ok "szolgáltatás-egység: $UNIT_DST"
    fi
fi

if [ "$SZARAZ" = 1 ]; then
    if [ "$CHANGED" = 1 ]; then echo "  tenné: systemctl --user daemon-reload, enable, restart $UNIT_NAME"
    else echo "  tenné: systemctl --user enable, start $UNIT_NAME (ha fut, nem indul újra)"; fi
elif systemctl --user daemon-reload; then
    systemctl --user enable "$UNIT_NAME"
    if [ "$CHANGED" = 1 ]; then
        systemctl --user restart "$UNIT_NAME"
    else
        systemctl --user start "$UNIT_NAME"
    fi
    ok "szolgáltatás bekapcsolva és fut (állapot: systemctl --user status $UNIT_NAME)"
else
    echo "  figyelem: a systemctl --user nem érhető el; a hőfigyelőt kézzel kell indítani:"
    echo "            python3 -I \"$DIR/hofigyelo.py\""
fi

seged horgok telepit "$SZARAZ" "$SETTINGS" "$DIR/hofigyelo_horog.py"
