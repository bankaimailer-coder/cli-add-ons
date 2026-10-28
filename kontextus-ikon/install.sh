#!/bin/sh
# Kontextus-ikon telepítése az aktuális felhasználónak (root nem kell).
# Bárhonnan futtatható; az útvonalakat a script saját helyéből számolja.
# Többször is futtatható: ami már be van állítva, azt nem módosítja.
#
#   sh install.sh
#
# Utána egyszer ki kell jelentkezni és vissza, hogy a GNOME-bővítmény betöltődjön.
set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
EXT_UUID=kontextus@kontextus-ikon
EXT_SRC="$DIR/gnome-extension/$EXT_UUID"
EXT_DST="$HOME/.local/share/gnome-shell/extensions/$EXT_UUID"
AUTOSTART="$HOME/.config/autostart/kontextus-ikon.desktop"
SETTINGS="$HOME/.claude/settings.json"
STATUS_CMD="python3 $DIR/statusline.py"

ok() { echo "  kész: $1"; }

echo "Kontextus-ikon telepítése innen: $DIR"

# 1. függőségek
command -v python3 >/dev/null || { echo "HIBA: nincs python3"; exit 1; }
python3 -c 'from gi.repository import Gio, GLib' 2>/dev/null \
    || { echo "HIBA: hiányzik a python3-gi csomag (sudo apt install python3-gi)"; exit 1; }
command -v gnome-shell >/dev/null || echo "  figyelem: nem találom a gnome-shell-t; a bővítmény csak GNOME alatt működik"
if command -v gnome-shell >/dev/null; then
    SHELL_MAJOR=$(gnome-shell --version | sed 's/[^0-9]*\([0-9]*\).*/\1/')
    grep -q "\"$SHELL_MAJOR\"" "$EXT_SRC/metadata.json" \
        || echo "  figyelem: a GNOME Shell $SHELL_MAJOR nincs a metadata.json shell-version listájában; a bővítmény nem fog betölteni, amíg fel nem veszed"
fi

# 2. GNOME-bővítmény symlinkje
mkdir -p "$(dirname "$EXT_DST")"
if [ -L "$EXT_DST" ] && [ "$(readlink "$EXT_DST")" = "$EXT_SRC" ]; then
    ok "bővítmény-symlink (már megvolt)"
else
    if [ -e "$EXT_DST" ] && [ ! -L "$EXT_DST" ]; then
        echo "HIBA: $EXT_DST létezik és nem symlink; nézd meg, és töröld kézzel"; exit 1
    fi
    ln -sfn "$EXT_SRC" "$EXT_DST"
    ok "bővítmény-symlink: $EXT_DST"
fi

# 3. a bővítmény bekapcsolása (a meglévő bekapcsolt bővítmények mellé)
if command -v gsettings >/dev/null; then
    CUR=$(gsettings get org.gnome.shell enabled-extensions)
    NEW=$(python3 - "$CUR" "$EXT_UUID" <<'EOF'
import ast, sys
cur, uuid = sys.argv[1], sys.argv[2]
cur = cur.replace("@as ", "")
lst = ast.literal_eval(cur) if cur.strip() else []
if uuid not in lst:
    lst.append(uuid)
print(repr(lst))
EOF
)
    if [ "$CUR" = "$NEW" ]; then
        ok "bővítmény bekapcsolva (már be volt)"
    else
        gsettings set org.gnome.shell enabled-extensions "$NEW"
        ok "bővítmény bekapcsolva"
    fi
    if [ "$(gsettings get org.gnome.shell disable-user-extensions)" = "true" ]; then
        gsettings set org.gnome.shell disable-user-extensions false
        ok "felhasználói bővítmények engedélyezve"
    fi
else
    echo "  figyelem: nincs gsettings; a bővítményt kézzel kell bekapcsolni"
fi

# 4. automatikus indítás bejelentkezéskor
mkdir -p "$(dirname "$AUTOSTART")"
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
else
    printf '%s\n' "$DESKTOP" > "$AUTOSTART"
    ok "automatikus indítás: $AUTOSTART"
fi

# 5. statusline a Claude Code beállításaiban (5 órás és heti keret minden CLI alján)
python3 - "$SETTINGS" "$STATUS_CMD" <<'EOF'
import json, os, shutil, sys, time
path, cmd = sys.argv[1], sys.argv[2]
want = {"type": "command", "command": cmd}
data = {}
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
cur = data.get("statusLine")
if cur == want or (isinstance(cur, dict) and cur.get("command") == cmd):
    print("  kész: statusline (már megvolt)")
elif cur:
    print("  figyelem: már van másik statusline a", path, "fájlban, nem írom felül:")
    print("           ", cur.get("command") if isinstance(cur, dict) else cur)
    print("            a keretsorhoz ezt kell beírni helyette:", cmd)
else:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        backup = f"{path}.backup-{time.strftime('%Y%m%d-%H%M%S')}"
        shutil.copy2(path, backup)
        print("  mentés:", backup)
    data["statusLine"] = want
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)
    print("  kész: statusline a", path, "fájlban")
EOF

# 6. háttérfolyamat indítása most (ha már fut, a második példány magától kilép)
if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    setsid python3 "$DIR/kontextus_ikon.py" >/dev/null 2>&1 &
    ok "háttérfolyamat elindítva (vagy már futott)"
fi

echo
echo "Kész. A GNOME-bővítmény a következő ki- és bejelentkezés után töltődik be."
