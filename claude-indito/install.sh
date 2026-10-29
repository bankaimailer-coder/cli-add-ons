#!/bin/sh
# Claude indító telepítése az aktuális felhasználónak (root nem kell),
# és kitűzése a dokkba. Többször is futtatható.
#
#   sh install.sh
set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
APP_ID=claude-indito.desktop
DST="$HOME/.local/share/applications/$APP_ID"

command -v zenity >/dev/null || { echo "HIBA: nincs zenity (sudo apt install zenity)"; exit 1; }
command -v ptyxis >/dev/null || { echo "HIBA: nincs ptyxis"; exit 1; }

mkdir -p "$(dirname "$DST")"
cat > "$DST" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Claude indító
Comment=Mappa kiválasztása és Claude Code indítása terminálban
Exec=sh $DIR/claude-indito.sh
Icon=$DIR/claude-figura.svg
Terminal=false
Categories=Development;
DESKTOP
echo "  kész: $DST"

# kitűzés a dokkba, ha még nincs ott
FAV=$(gsettings get org.gnome.shell favorite-apps)
case "$FAV" in
    *"'$APP_ID'"*) echo "  kész: dokk (már ki volt tűzve)" ;;
    *) gsettings set org.gnome.shell favorite-apps "$(printf '%s' "$FAV" | sed "s/]\$/, '$APP_ID']/")"
       echo "  kész: kitűzve a dokkba" ;;
esac
