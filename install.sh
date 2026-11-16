#!/bin/sh
# Közös telepítő: sorban lefuttatja az összetevők saját telepítőit (root nem kell).
# Bárhonnan és többször is futtatható. Ha egy összetevő telepítése elbukik, a többi lefut,
# a végén összesítés jön.
#
#   sh install.sh                              minden összetevő
#   sh install.sh kontextus-ikon hofigyelo     csak a felsoroltak
#   sh install.sh --horog-nelkul               a hőfigyelő horgai nélkül (csak a szolgáltatás)
#
# Összetevők: kontextus-ikon, kontextus-horog, hofigyelo, claude-indito
set -u

DIR=$(cd "$(dirname "$0")" && pwd)
ALL="kontextus-ikon kontextus-horog hofigyelo claude-indito"
HOFIGYELO_ARG=""
PICKED=""

for arg in "$@"; do
    case "$arg" in
        --horog-nelkul) HOFIGYELO_ARG="--horog-nelkul" ;;
        kontextus-ikon|kontextus-horog|hofigyelo|claude-indito) PICKED="$PICKED $arg" ;;
        *) echo "Ismeretlen paraméter: $arg"; echo "Összetevők: $ALL; kapcsoló: --horog-nelkul"; exit 2 ;;
    esac
done
[ -n "$PICKED" ] || PICKED="$ALL"

DONE=""
FAILED=""
for comp in $PICKED; do
    echo
    echo "=== $comp ==="
    if [ "$comp" = hofigyelo ]; then
        sh "$DIR/$comp/install.sh" $HOFIGYELO_ARG
    else
        sh "$DIR/$comp/install.sh"
    fi
    if [ $? -eq 0 ]; then
        DONE="$DONE $comp"
    else
        FAILED="$FAILED $comp"
    fi
done

echo
echo "Telepítve:${DONE:- semmi}"
if [ -n "$FAILED" ]; then
    echo "Hibával leállt:$FAILED (a fenti kimenetben a HIBA sor mondja meg, mi hiányzik)"
    exit 1
fi
echo "A sáv mérői a következő ki- és bejelentkezés után jelennek meg."
