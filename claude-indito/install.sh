#!/bin/sh
# Claude indító telepítése az aktuális felhasználónak (root nem kell),
# és kitűzése a dokkba. Többször is futtatható: ami megvan, azt nem írja újra.
#
#   sh install.sh                 # indító, dokk, Ptyxis-színprofilok
#   sh install.sh --eltavolitas   # indító törlése, kivétel a dokkból, színprofilok törlése (szinprofil.py eltavolit)
#   sh install.sh --szaraz [...]  # csak kiírja, mit tenne; semmit nem ír
#
# Kilépési kód: 0 kész (vagy már megvolt), 1 hiba, 2 ismeretlen kapcsoló, 3 kihagyva (hiányzó függőség).
# TELEPIT_EREDMENY: ha meg van adva, ebbe a fájlba írja a gyökér telepit.sh összesítőjének, hogy változott-e
# valami („valtozott”), illetve a kihagyás okát („kihagyva<TAB>ok”).
set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
APP_ID=claude-indito.desktop
DST="$HOME/.local/share/applications/$APP_ID"

MODE=telepit
SZARAZ=0
for a in "$@"; do
    case "$a" in
        --eltavolitas) MODE=eltavolit ;;
        --szaraz) SZARAZ=1 ;;
        *) echo "HIBA: ismeretlen kapcsoló: $a (lehet: --eltavolitas, --szaraz)"; exit 2 ;;
    esac
done

jelez() { [ -z "${TELEPIT_EREDMENY:-}" ] || printf '%s\n' "$1" >> "$TELEPIT_EREDMENY"; }
# változás bejelentése; szárazon csak kiírja, és 1-et ad, hogy a hívó ne írjon
valtozas() {
    jelez valtozott
    if [ "$SZARAZ" = 1 ]; then echo "  tenné: $1"; return 1; fi
}
# van-e gsettings a GNOME Shell sémájával (nem GNOME-os gépen a gsettings megvan, a séma nincs)
gnome_sema() { command -v gsettings >/dev/null && gsettings list-keys org.gnome.shell >/dev/null 2>&1; }
# a kedvencek listája az alkalmazással (+) vagy nélküle (-), GVariant-szövegként
fav_list() {
    python3 - "$1" "$2" "$APP_ID" <<'PY'
import ast, sys
cur, op, app = sys.argv[1], sys.argv[2], sys.argv[3]
cur = cur.replace("@as ", "").strip()
lst = ast.literal_eval(cur) if cur else []
if op == "+" and app not in lst:
    lst.append(app)
if op == "-":
    lst = [x for x in lst if x != app]
print(repr(lst))
PY
}

if [ "$MODE" = eltavolit ]; then
    echo "Claude indító eltávolítása"
    if [ -f "$DST" ]; then
        if valtozas "indító törlése: $DST"; then rm -f "$DST"; echo "  kész: indító törölve: $DST"; fi
    else
        echo "  kész: indító nincs telepítve (nincs mit törölni)"
    fi
    if gnome_sema && command -v python3 >/dev/null; then
        FAV=$(gsettings get org.gnome.shell favorite-apps)
        case "$FAV" in
            *"'$APP_ID'"*)
                if valtozas "kivétel a dokkból"; then
                    gsettings set org.gnome.shell favorite-apps "$(fav_list "$FAV" -)"
                    echo "  kész: kivéve a dokkból"
                fi ;;
            *) echo "  kész: dokk (nem volt kitűzve)" ;;
        esac
    else
        echo "  kész: dokk (nincs GNOME Shell-séma, nincs mit kivenni)"
    fi
    # a színprofilok törlése a GNOME Shell-sémától függetlenül (a Ptyxis saját sémáját használja)
    if [ "$SZARAZ" = 1 ]; then
        echo "  tenné: színprofilok törlése (python3 szinprofil.py eltavolit)"
    elif ! command -v python3 >/dev/null || ! command -v gsettings >/dev/null; then
        echo "  figyelem: nincs python3 vagy gsettings; a színprofilok törlése kimaradt"
    elif ! python3 "$DIR/szinprofil.py" eltavolit; then
        echo "  figyelem: a színprofilok törlése nem sikerült (python3 szinprofil.py eltavolit); a többi kész"
    fi
    exit 0
fi

# függőségek: a hiányzókat egyszerre jelzi; a csomagból pótolhatókhoz a pkexec-parancsot javasolja
missing=""
pkgs=""
for c in zenity ptyxis gsettings python3 claude; do
    command -v "$c" >/dev/null && continue
    missing="$missing${missing:+, }$c"
    case "$c" in
        gsettings) pkgs="$pkgs libglib2.0-bin" ;;
        claude) ;;
        *) pkgs="$pkgs $c" ;;
    esac
done
if [ -z "$missing" ] && ! gnome_sema; then
    missing="GNOME Shell-séma (org.gnome.shell)"
fi
if [ -n "$missing" ]; then
    why="nincs $missing"
    [ -z "$pkgs" ] || why="$why; pótlás: pkexec apt install$pkgs"
    case "$missing" in *claude*) why="$why; a Claude Code CLI: https://claude.com/claude-code" ;; esac
    echo "  kihagyva: $why"
    jelez "kihagyva	$why"
    exit 3
fi

echo "Claude indító telepítése innen: $DIR"
# ha a meglévő indító ugyanerre a mappára mutat más írásmóddal (szimlinken át), annak írásmódja marad
if [ -f "$DST" ]; then
    OLD=$(sed -n 's/^Exec=sh "\(.*\)\/claude-indito\.sh"$/\1/p' "$DST")
    if [ -n "$OLD" ] && [ -d "$OLD" ] && [ "$(cd "$OLD" && pwd -P)" = "$(cd "$DIR" && pwd -P)" ]; then
        DIR=$OLD
    fi
fi
DESKTOP="[Desktop Entry]
Type=Application
Name=Claude indító
Comment=Mappa kiválasztása és Claude Code indítása terminálban
Exec=sh \"$DIR/claude-indito.sh\"
Icon=$DIR/claude-figura.svg
Terminal=false
Categories=Development;"
if [ -f "$DST" ] && [ "$(cat "$DST")" = "$DESKTOP" ]; then
    echo "  kész: $DST (már megvolt)"
elif valtozas "$DST"; then
    mkdir -p "$(dirname "$DST")"
    printf '%s\n' "$DESKTOP" > "$DST"
    echo "  kész: $DST"
fi

# kitűzés a dokkba, ha még nincs ott
FAV=$(gsettings get org.gnome.shell favorite-apps)
case "$FAV" in
    *"'$APP_ID'"*) echo "  kész: dokk (már ki volt tűzve)" ;;
    *) if valtozas "kitűzés a dokkba"; then
           gsettings set org.gnome.shell favorite-apps "$(fav_list "$FAV" +)"
           echo "  kész: kitűzve a dokkba"
       fi ;;
esac

# repónkénti színprofilok a Ptyxisben (mappak.txt 3. oszlopa); eltávolítás:
#   python3 szinprofil.py eltavolit
if [ "$SZARAZ" = 1 ]; then
    echo "  tenné: színprofilok frissítése (python3 szinprofil.py telepit); a mappak.txt ezen a gépen létező repói:"
    python3 "$DIR/szinprofil.py" lista | grep -v '(nincs ezen a gépen)' | sed 's/^/          /' || true
else
    python3 "$DIR/szinprofil.py" telepit
fi
