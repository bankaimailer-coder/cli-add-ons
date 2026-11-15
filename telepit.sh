#!/bin/sh
# A repó minden eszköze egy paranccsal, az aktuális felhasználónak (root nem kell). Bárhonnan és bármilyen
# klónhelyről futtatható; a részek a saját telepítőjüket futtatják, ez a szkript csak a sorrendet, a kapcsolókat
# és az összesítést kezeli. Többször is futtatható: ami megvan, az „már megvolt”.
#
#   sh telepit.sh                          # minden rész, ami ezen a gépen működni tud
#   sh telepit.sh --csak hofigyelo,kontextus-horog
#   sh telepit.sh --kihagy claude-indito
#   sh telepit.sh --eltavolitas [--csak ...]
#   sh telepit.sh --szaraz [...]           # csak kiírja, mit tenne; semmit nem ír, nem indít
#
# Részek (ebben a sorrendben):
#   kontextus-ikon   GNOME-bővítmény (kontextus- és keretmérők, CPU/GPU-hőmérő), memória-chip, statusline
#   keretfigyelo     háttérszolgáltatás: folyamatos Claude- és Codex-keretmérés
#   kontextus-horog  Claude Code horog: kontextusmérés, 500k/600k-s stop
#   hofigyelo        hőfigyelő szolgáltatás és a horgai (ha nincs ismert hőérzékelő, csak --csak hofigyelo-val)
#   claude-indito    dokkba tűzött indító és repónkénti Ptyxis-színprofilok (terminálszínek)
#
# Kilépési kód: 0 minden kért rész kész (vagy már megvolt); 1 hiba (egy rész hibával állt le, vagy hibás
# kapcsoló / ismeretlen rész: ekkor semmi nem fut); 3 nem volt hiba, de valamelyik rész kimaradt (hiányzó függőség).
set -uf

ROOT=$(cd "$(dirname "$0")" && pwd)
RESZEK="kontextus-ikon keretfigyelo kontextus-horog hofigyelo claude-indito"

hasznalat() {
    echo "Használat: sh telepit.sh [--szaraz] [--eltavolitas] [--csak RÉSZ,...] [--kihagy RÉSZ,...]"
    echo "Részek: $(echo $RESZEK | sed 's/ /, /g')"
}
hiba() { echo "HIBA: $1"; hasznalat; exit 1; }

SZARAZ=0
ELTAVOLITAS=0
CSAK=""
KIHAGY=""
CSAK_VOLT=0
KIHAGY_VOLT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --szaraz) SZARAZ=1 ;;
        --eltavolitas) ELTAVOLITAS=1 ;;
        --csak|--kihagy)
            [ $# -ge 2 ] || hiba "a $1 után meg kell adni a részeket"
            if [ "$1" = --csak ]; then CSAK="$CSAK,$2"; CSAK_VOLT=1; else KIHAGY="$KIHAGY,$2"; KIHAGY_VOLT=1; fi
            shift ;;
        --csak=*) CSAK="$CSAK,${1#--csak=}"; CSAK_VOLT=1 ;;
        --kihagy=*) KIHAGY="$KIHAGY,${1#--kihagy=}"; KIHAGY_VOLT=1 ;;
        -h|--help) hasznalat; exit 0 ;;
        *) hiba "ismeretlen kapcsoló: $1" ;;
    esac
    shift
done

# a felsorolt nevek ellenőrzése: ismeretlen névnél semmi nem fut
benne() {   # $1: név, $2: vesszős lista
    case ",$2," in *",$1,"*) return 0 ;; esac
    return 1
}
# a megadott, de üres vagy csak vesszős lista hiba (különben csendben semmi nem futna)
if [ "$CSAK_VOLT" = 1 ] && [ -z "$(printf '%s' "$CSAK" | tr -d ', ')" ]; then hiba "a --csak listája üres"; fi
if [ "$KIHAGY_VOLT" = 1 ] && [ -z "$(printf '%s' "$KIHAGY" | tr -d ', ')" ]; then hiba "a --kihagy listája üres"; fi
for n in $(echo "$CSAK,$KIHAGY" | tr ',' ' '); do
    benne "$n" "$(echo $RESZEK | tr ' ' ',')" || hiba "ismeretlen rész: $n (lehetséges: $(echo $RESZEK | sed 's/ /, /g'))"
done

SORREND=$RESZEK
if [ "$ELTAVOLITAS" = 1 ]; then
    SORREND=""
    for r in $RESZEK; do SORREND="$r $SORREND"; done
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TABLA=""
HIBA=0
KIMARADT=0
VALTOZOTT_IKON=0
sor() { TABLA="$TABLA$(printf '%-16s %-14s %s' "$1" "$2" "$3")
"; }

if [ "$SZARAZ" = 1 ]; then echo "Szárazfutás: semmit nem ír, nem indít, csak kiírja, mit tenne. Klón: $ROOT"
else echo "Telepítés innen: $ROOT"; fi

for r in $SORREND; do
    if [ -n "$CSAK" ] && ! benne "$r" "$CSAK"; then sor "$r" "nem futott" "nincs a --csak listában"; continue; fi
    if benne "$r" "$KIHAGY"; then sor "$r" "nem futott" "--kihagy"; continue; fi
    case "$r" in
        kontextus-ikon) set -- "$ROOT/kontextus-ikon/install.sh" --figyelo-nelkul
                        [ "$ELTAVOLITAS" = 0 ] || set -- "$@" --eltavolitas ;;
        keretfigyelo)   if [ "$ELTAVOLITAS" = 1 ]; then set -- "$ROOT/kontextus-ikon/install.sh" --figyelo-eltavolitas
                        else set -- "$ROOT/kontextus-ikon/install.sh" --figyelo; fi ;;
        hofigyelo)      set -- "$ROOT/hofigyelo/install.sh"
                        [ "$ELTAVOLITAS" = 0 ] || set -- "$@" --eltavolitas
                        # kifejezett kérésre ismert hőérzékelő nélkül is (figyelmeztetéssel)
                        if [ "$ELTAVOLITAS" = 0 ] && benne hofigyelo "$CSAK"; then set -- "$@" --erzekelo-nelkul; fi ;;
        *)              set -- "$ROOT/$r/install.sh"
                        [ "$ELTAVOLITAS" = 0 ] || set -- "$@" --eltavolitas ;;
    esac
    [ "$SZARAZ" = 0 ] || set -- "$@" --szaraz
    echo
    echo "== $r"
    res="$TMP/$r"
    : > "$res"
    TELEPIT_EREDMENY="$res" sh "$@"
    code=$?
    if [ "$code" = 0 ]; then
        if grep -qx valtozott "$res"; then
            if [ "$ELTAVOLITAS" = 1 ]; then e=eltávolítva; else e=települt; fi
            [ "$SZARAZ" = 0 ] || { if [ "$ELTAVOLITAS" = 1 ]; then e=eltávolítaná; else e=települne; fi; }
            [ "$r" != kontextus-ikon ] || [ "$ELTAVOLITAS" = 1 ] || VALTOZOTT_IKON=1
            sor "$r" "$e" ""
        elif [ "$ELTAVOLITAS" = 1 ]; then
            sor "$r" "nem volt" "nincs mit eltávolítani"
        else
            sor "$r" "már megvolt" ""
        fi
    elif [ "$code" = 3 ]; then
        KIMARADT=1
        sor "$r" "kihagyva" "$(sed -n 's/^kihagyva	//p' "$res" | head -n 1)"
    else
        HIBA=1
        sor "$r" "HIBA" "kilépési kód $code (a fenti kimenet szerint)"
    fi
done

echo
echo "Összesítés$([ "$SZARAZ" = 0 ] || echo ' (szárazfutás, semmi nem változott)'):"
printf '%-16s %-14s %s\n' "rész" "eredmény" "ok"
printf '%s' "$TABLA"
if [ "$VALTOZOTT_IKON" = 1 ] && [ "$SZARAZ" = 0 ]; then
    echo
    echo "Teendő: ki- és bejelentkezés; a GNOME-bővítmény csak utána töltődik be."
fi
[ "$HIBA" = 0 ] || exit 1
[ "$KIMARADT" = 0 ] || exit 3
exit 0
