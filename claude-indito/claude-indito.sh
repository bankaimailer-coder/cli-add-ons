#!/bin/sh
# Claude indító: mappa kiválasztása, majd új Ptyxis ablak abban a mappában,
# benne a Claude Code-dal (új beszélgetés vagy a legutóbbi folytatása).
# A mappák listája a mellette lévő mappak.txt-ben van.
set -u

DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
LIST="$DIR/mappak.txt"
CLAUDE=$(command -v claude || echo "$HOME/.local/bin/claude")

# mappák beolvasása: ~ kibontása, nem létező mappák kihagyása
ROWS=""
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in
        *'|'*) name=$(printf '%s' "${line%%|*}" | sed 's/^ *//; s/ *$//')
               path=${line#*|} ;;
        *)     name=""; path=$line ;;
    esac
    path=$(printf '%s' "$path" | sed "s/^ *//; s/ *$//; s|^~|$HOME|")
    [ -d "$path" ] || continue
    [ -n "$name" ] || name=$(printf '%s' "$path" | sed "s|^$HOME/||")
    ROWS="$ROWS$name
$path
"
done < "$LIST"

if [ -z "$ROWS" ]; then
    zenity --error --title="Claude indító" --text="Nincs egy létező mappa sem itt: $LIST"
    exit 1
fi

TARGET=$(printf '%s' "$ROWS" | zenity --list --title="Claude indító" \
    --text="Melyik mappában dolgozol?" --column="Repó" --column="Útvonal" \
    --hide-column=2 --print-column=2 --width=420 --height=360) || exit 0
[ -n "$TARGET" ] || exit 0

MODE=$(zenity --list --title="Claude indító" --text="$(printf '%s' "$ROWS" | grep -x -B1 -F "$TARGET" | head -1 | sed "s/&/\&amp;/g")" \
    --column="Indítás" "Új beszélgetés" "Legutóbbi folytatása" \
    --width=320 --height=220) || exit 0

case "$MODE" in
    "Legutóbbi folytatása") ARGS="--continue" ;;
    *) ARGS="" ;;
esac

# a Claude kilépése után a terminál nyitva marad egy sima shellel
exec ptyxis --new-window -d "$TARGET" -T "Claude: $(basename "$TARGET")" \
    -- bash -lc "\"$CLAUDE\" $ARGS; exec bash"
