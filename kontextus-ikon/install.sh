#!/bin/sh
# Kontextus-ikon telepítése az aktuális felhasználónak (root nem kell).
# Bárhonnan futtatható; az útvonalakat a script saját helyéből számolja.
# Többször is futtatható: ami már be van állítva, azt nem módosítja. Ha egy meglévő bejegyzés ugyanerre a
# mappára mutat más írásmóddal (szimlinken át), annak írásmódja marad; ha egy másik klónra, átírja erre.
#
#   sh install.sh                          # minden, a keretfigyelő szolgáltatással együtt
#   sh install.sh --figyelo-nelkul         # minden, a keretfigyelő nélkül
#   sh install.sh --figyelo                # csak a keretfigyelő szolgáltatás (telepítés, bekapcsolás, indítás)
#   sh install.sh --figyelo-eltavolitas    # a keretfigyelő leállítása, kikapcsolása és törlése
#   sh install.sh --eltavolitas            # minden eltávolítása (--figyelo-nelkul: a keretfigyelő marad)
#   sh install.sh --szaraz [...]           # csak kiírja, mit tenne; semmit nem ír, nem indít
#
# Utána egyszer ki kell jelentkezni és vissza, hogy a GNOME-bővítmény betöltődjön.
# Kilépési kód: 0 kész (vagy már megvolt), 1 hiba, 2 ismeretlen kapcsoló, 3 kihagyva (hiányzó függőség).
# KONTEXTUS_SYSTEMCTL: a systemctl helyett ez a parancs fut (próbához; alapból: systemctl).
# TELEPIT_EREDMENY: ha meg van adva, ebbe a fájlba írja a gyökér telepit.sh összesítőjének, hogy változott-e
# valami („valtozott”), illetve a kihagyás okát („kihagyva<TAB>ok”).
set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
UNIT_NAME=kontextus-keretfigyelo.service
UNIT_DST="$HOME/.config/systemd/user/$UNIT_NAME"
SYSTEMCTL=${KONTEXTUS_SYSTEMCTL:-systemctl}
EXT_UUID=kontextus@kontextus-ikon
EXT_DST="$HOME/.local/share/gnome-shell/extensions/$EXT_UUID"
AUTOSTART="$HOME/.config/autostart/kontextus-ikon.desktop"
SETTINGS="$HOME/.claude/settings.json"

MODE=minden
SZARAZ=0
FIGYELO=1
for a in "$@"; do
    case "$a" in
        --figyelo) MODE=figyelo ;;
        --figyelo-nelkul) FIGYELO=0 ;;
        --eltavolitas) MODE=eltavolitas ;;
        --szaraz) SZARAZ=1 ;;
        --figyelo-eltavolitas) MODE=figyelo-eltavolitas ;;
        *) echo "HIBA: ismeretlen kapcsoló: $a (lehet: --figyelo, --figyelo-nelkul, --eltavolitas, --szaraz, --figyelo-eltavolitas)"; exit 2 ;;
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

# van-e gsettings a GNOME Shell sémájával (nem GNOME-os gépen a gsettings megvan, a séma nincs)
gnome_sema() { command -v gsettings >/dev/null && gsettings list-keys org.gnome.shell >/dev/null 2>&1; }

# ha egy meglévő bejegyzés ugyanerre a mappára mutat más írásmóddal (szimlinken át), annak írásmódja marad
adopt_dir() {
    [ -n "$1" ] && [ -d "$1" ] || return 1
    [ "$(cd "$1" && pwd -P)" = "$(cd "$DIR" && pwd -P)" ] || return 1
    DIR=$1
}
if [ -L "$EXT_DST" ] && adopt_dir "$(dirname "$(dirname "$(readlink "$EXT_DST")")")"; then :
elif [ -f "$UNIT_DST" ] && adopt_dir "$(sed -n 's/^ExecStart=.* "\(.*\)\/keretfigyelo\.py"$/\1/p' "$UNIT_DST")"; then :
elif [ -f "$AUTOSTART" ] && adopt_dir "$(sed -n 's/^Exec=python3 "\(.*\)\/kontextus_ikon\.py"$/\1/p' "$AUTOSTART")"; then :
fi
EXT_SRC="$DIR/gnome-extension/$EXT_UUID"
STATUS_CMD="python3 \"$DIR/statusline.py\""

# a keretfigyelő systemd felhasználói egysége: a sablonból kitöltve (keretfigyelo.py --unit), csak ha változott;
# bekapcsolva és (újra)indítva
install_figyelo() {
    command -v python3 >/dev/null || { echo "HIBA: nincs python3"; exit 1; }
    if ! command -v claude >/dev/null && ! command -v codex >/dev/null; then
        kihagy "nincs claude és codex sem (a keretfigyelő ezek keretét méri)"
    fi
    [ "$SZARAZ" = 1 ] || mkdir -p "$(dirname "$UNIT_DST")"
    NEW_UNIT=$(python3 "$DIR/keretfigyelo.py" --unit)
    if [ -f "$UNIT_DST" ] && [ "$(cat "$UNIT_DST")" = "$NEW_UNIT" ]; then
        ok "keretfigyelő-egység (már megvolt): $UNIT_DST"
        CHANGED=0
    else
        CHANGED=1
        if valtozas "keretfigyelő-egység: $UNIT_DST"; then
            printf '%s\n' "$NEW_UNIT" > "$UNIT_DST"
            ok "keretfigyelő-egység: $UNIT_DST"
        elif [ -f "$UNIT_DST" ]; then
            printf '%s\n' "$NEW_UNIT" | diff "$UNIT_DST" - | sed -n 's/^[<>] /          /p' || true
        fi
    fi
    if [ "$SZARAZ" = 1 ]; then
        if [ "$CHANGED" = 1 ]; then echo "  tenné: systemctl --user daemon-reload, enable, restart $UNIT_NAME"
        else echo "  tenné: systemctl --user enable, start $UNIT_NAME (ha fut, nem indul újra)"; fi
        return 0
    fi
    if ! "$SYSTEMCTL" --user daemon-reload; then
        echo "  figyelem: a systemctl --user nem érhető el; a keretfigyelőt kézzel kell indítani:"
        echo "            python3 \"$DIR/keretfigyelo.py\""
        return 0
    fi
    "$SYSTEMCTL" --user enable "$UNIT_NAME"
    if [ "$CHANGED" = 1 ]; then
        "$SYSTEMCTL" --user restart "$UNIT_NAME"
    else
        "$SYSTEMCTL" --user start "$UNIT_NAME"
    fi
    ok "keretfigyelő bekapcsolva és fut (állapot: systemctl --user status $UNIT_NAME)"
}

uninstall_figyelo() {
    if [ -f "$UNIT_DST" ]; then
        valtozas "keretfigyelő leállítása, kikapcsolása, törlése: $UNIT_DST" || return 0
        "$SYSTEMCTL" --user disable --now "$UNIT_NAME" || true
        rm -f "$UNIT_DST"
        "$SYSTEMCTL" --user daemon-reload || true
        ok "keretfigyelő leállítva, kikapcsolva, törölve: $UNIT_DST"
    else
        ok "keretfigyelő nincs telepítve (nincs mit törölni)"
    fi
    [ "$SZARAZ" = 1 ] && return 0   # szárazon semmit nem töröl
    rm -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/kontextus-ikon/keretfigyelo.json"
}

# a statusline beírása (telepit) vagy kivétele (eltavolit) a Claude Code beállításaiban, mentéssel, atomikusan
statusline() {
    python3 - "$SETTINGS" "$STATUS_CMD" "$DIR/statusline.py" "$1" "$SZARAZ" <<'EOF'
import json, os, shlex, shutil, sys, time
path, cmd, script, mode, szaraz = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] == "1"
want = {"type": "command", "command": cmd, "refreshInterval": 30}
data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except ValueError as e:
        print(f"HIBA: a {path} nem érvényes JSON ({e}); nem nyúlok hozzá")
        sys.exit(1)
cur = data.get("statusLine")
try:
    old = next((p for p in shlex.split(cur.get("command", "")) if p.endswith("/kontextus-ikon/statusline.py")), None)
except (AttributeError, ValueError):
    old = None
mine = old is not None and os.path.realpath(old) == os.path.realpath(script)
if mode == "eltavolit":
    if old is None:
        print("  kész: statusline (nem ez a repó állította be, nem nyúlok hozzá)" if cur else "  kész: statusline (nem volt beállítva)")
        sys.exit()
    del data["statusLine"]
    note = "statusline kivéve"
elif mine:
    print("  kész: statusline (már megvolt)")
    sys.exit()
elif old is not None:
    cur["command"] = cmd
    note = f"statusline útvonala átírva: {old} -> {script}"
elif cur:
    print("  figyelem: már van másik statusline a", path, "fájlban, nem írom felül:")
    print("           ", cur.get("command") if isinstance(cur, dict) else cur)
    print("            a keretsorhoz ezt kell beírni helyette:", cmd)
    sys.exit()
else:
    data["statusLine"] = want
    note = f"statusline a {path} fájlban"
if os.environ.get("TELEPIT_EREDMENY"):
    with open(os.environ["TELEPIT_EREDMENY"], "a") as f:
        f.write("valtozott\n")
if szaraz:
    print("  tenné:", note)
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
print("  kész:", note)
EOF
}

# a bővítmény hozzáadása (+) a bekapcsoltakhoz vagy kivétele (-), GVariant-szövegként
ext_list() {
    python3 - "$1" "$2" "$EXT_UUID" <<'EOF'
import ast, sys
cur, op, uuid = sys.argv[1], sys.argv[2], sys.argv[3]
cur = cur.replace("@as ", "")
lst = ast.literal_eval(cur) if cur.strip() else []
if op == "+" and uuid not in lst:
    lst.append(uuid)
if op == "-":
    lst = [x for x in lst if x != uuid]
print(repr(lst))
EOF
}

case "$MODE" in
    figyelo) echo "Keretfigyelő telepítése innen: $DIR"; install_figyelo; exit 0 ;;
    figyelo-eltavolitas) echo "Keretfigyelő eltávolítása"; uninstall_figyelo; exit 0 ;;
    eltavolitas)
        echo "Kontextus-ikon eltávolítása"
        if [ -L "$EXT_DST" ]; then
            if valtozas "bővítmény-symlink törlése: $EXT_DST"; then rm -f "$EXT_DST"; ok "bővítmény-symlink törölve"; fi
        else
            ok "bővítmény-symlink (nem volt)"
        fi
        if gnome_sema && command -v python3 >/dev/null; then
            CUR=$(gsettings get org.gnome.shell enabled-extensions)
            NEW=$(ext_list "$CUR" -)
            if [ "$CUR" != "$NEW" ]; then
                if valtozas "bővítmény kikapcsolása"; then
                    gsettings set org.gnome.shell enabled-extensions "$NEW"; ok "bővítmény kikapcsolva"
                fi
            else
                ok "bővítmény (nem volt bekapcsolva)"
            fi
        else
            ok "bővítmény bekapcsolása (nincs GNOME Shell-séma, nincs mit kikapcsolni)"
        fi
        if [ -f "$AUTOSTART" ]; then
            if valtozas "automatikus indítás törlése: $AUTOSTART"; then rm -f "$AUTOSTART"; ok "automatikus indítás törölve"; fi
        else
            ok "automatikus indítás (nem volt)"
        fi
        command -v python3 >/dev/null && statusline eltavolit
        [ "$FIGYELO" = 0 ] || uninstall_figyelo
        exit 0 ;;
esac

echo "Kontextus-ikon telepítése innen: $DIR"

# 1. függőségek (a hiányzó résznél a kilépési kód 3; a csomagból pótolhatóhoz a pkexec-parancsot javasolja)
command -v python3 >/dev/null || kihagy "nincs python3 (pkexec apt install python3)"
# GNOME nélkül a bővítmény, az automatikus indítás és a háttérfolyamat kimarad, a statusline (és a keretfigyelő)
# akkor is települ; a kilépési kód ilyenkor 3, az ok kiírva
GNOME_HIANY=""
command -v gnome-shell >/dev/null || GNOME_HIANY="nincs gnome-shell (a bővítmény csak GNOME alatt működik)"
if [ -z "$GNOME_HIANY" ] && ! python3 -c 'from gi.repository import Gio, GLib' 2>/dev/null; then
    GNOME_HIANY="hiányzik a python3-gi csomag (pkexec apt install python3-gi)"
fi

gnome_lepesek() {
SHELL_MAJOR=$(gnome-shell --version | sed 's/[^0-9]*\([0-9]*\).*/\1/')
grep -q "\"$SHELL_MAJOR\"" "$EXT_SRC/metadata.json" \
    || echo "  figyelem: a GNOME Shell $SHELL_MAJOR nincs a metadata.json shell-version listájában; a bővítmény nem fog betölteni, amíg fel nem veszed"

# 2. GNOME-bővítmény symlinkje
[ "$SZARAZ" = 1 ] || mkdir -p "$(dirname "$EXT_DST")"
if [ -L "$EXT_DST" ] && [ "$(readlink -f "$EXT_DST")" = "$(readlink -f "$EXT_SRC")" ]; then
    ok "bővítmény-symlink (már megvolt)"
else
    if [ -e "$EXT_DST" ] && [ ! -L "$EXT_DST" ]; then
        echo "HIBA: $EXT_DST létezik és nem symlink; nézd meg, és töröld kézzel"; exit 1
    fi
    if valtozas "bővítmény-symlink: $EXT_DST -> $EXT_SRC"; then
        ln -sfn "$EXT_SRC" "$EXT_DST"
        ok "bővítmény-symlink: $EXT_DST"
    fi
fi

# 3. a bővítmény bekapcsolása (a meglévő bekapcsolt bővítmények mellé)
if gnome_sema; then
    CUR=$(gsettings get org.gnome.shell enabled-extensions)
    NEW=$(ext_list "$CUR" +)
    if [ "$CUR" = "$NEW" ]; then
        ok "bővítmény bekapcsolva (már be volt)"
    elif valtozas "bővítmény bekapcsolása (enabled-extensions)"; then
        gsettings set org.gnome.shell enabled-extensions "$NEW"
        ok "bővítmény bekapcsolva"
    fi
    if [ "$(gsettings get org.gnome.shell disable-user-extensions)" = "true" ]; then
        if valtozas "felhasználói bővítmények engedélyezése"; then
            gsettings set org.gnome.shell disable-user-extensions false
            ok "felhasználói bővítmények engedélyezve"
        fi
    fi
else
    echo "  figyelem: nincs gsettings vagy GNOME Shell-séma; a bővítményt kézzel kell bekapcsolni"
fi

# 4. automatikus indítás bejelentkezéskor
DESKTOP="[Desktop Entry]
Type=Application
Name=Claude kontextus-ikon
Comment=Claude Code kontextusmérők és memória-chip a felső sávban
Exec=python3 \"$DIR/kontextus_ikon.py\"
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
NoDisplay=true"
if [ -f "$AUTOSTART" ] && [ "$(cat "$AUTOSTART")" = "$DESKTOP" ]; then
    ok "automatikus indítás (már megvolt)"
elif valtozas "automatikus indítás: $AUTOSTART"; then
    mkdir -p "$(dirname "$AUTOSTART")"
    printf '%s\n' "$DESKTOP" > "$AUTOSTART"
    ok "automatikus indítás: $AUTOSTART"
fi
}

if [ -z "$GNOME_HIANY" ]; then
    gnome_lepesek
else
    echo "  kimarad: bővítmény és automatikus indítás: $GNOME_HIANY"
fi

# 5. statusline a Claude Code beállításaiban (5 órás és heti keret minden CLI alján)
statusline telepit

# 6. háttérfolyamat indítása most (ha már fut, a második példány magától kilép)
if [ -z "$GNOME_HIANY" ] && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ "$SZARAZ" = 0 ]; then
    setsid python3 "$DIR/kontextus_ikon.py" >/dev/null 2>&1 &
    ok "háttérfolyamat elindítva (vagy már futott)"
fi

# 7. keretfigyelő: folyamatos Claude- és Codex-keretmérés, systemd felhasználói szolgáltatásként
[ "$FIGYELO" = 0 ] || install_figyelo

[ -z "$GNOME_HIANY" ] || kihagy "$GNOME_HIANY; a bővítmény és az automatikus indítás kimaradt, a statusline települt"

if [ "$SZARAZ" = 0 ]; then
    echo
    echo "Kész. A GNOME-bővítmény a következő ki- és bejelentkezés után töltődik be."
fi
