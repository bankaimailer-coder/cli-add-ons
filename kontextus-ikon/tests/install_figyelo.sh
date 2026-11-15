#!/usr/bin/env bash
# A keretfigyelő telepítésének és eltávolításának próbája (6. feltétel), a valódi systemd és a valódi HOME
# érintése nélkül: a kontextus-ikon mappa egy szóközös és ékezetes útvonalú másolatából fut, ideiglenes HOME-mal,
# a systemctl helyén egy naplózó utánzattal (KONTEXTUS_SYSTEMCTL). Ha van systemd-analyze, az egységet ellenőrzi.
#   bash kontextus-ikon/tests/install_figyelo.sh
# KERETFIGYELO_SRC: a tesztelt forrásmappa (alapból a repóbeli kontextus-ikon; a mutants.sh a hibás másolatra).
# Kilépési kód: 0 = minden ellenőrzés rendben; 1 = valamelyik elbukott (a sor „FAIL”).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${KERETFIGYELO_SRC:-$HERE/..}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CLONE="$TMP/klón szóközzel/kontextus-ikon"
mkdir -p "$CLONE"
cp "$SRC/install.sh" "$SRC/keretfigyelo.py" "$SRC/keretfigyelo.service.in" "$SRC/statusline.py" "$CLONE/"
export HOME="$TMP/home"
export XDG_RUNTIME_DIR="$TMP/run"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR/kontextus-ikon"
LOG="$TMP/systemctl.log"
printf '#!/bin/sh\necho "$*" >> "%s"\n' "$LOG" > "$TMP/systemctl"
chmod +x "$TMP/systemctl"
export KONTEXTUS_SYSTEMCTL="$TMP/systemctl"
UNIT="$HOME/.config/systemd/user/kontextus-keretfigyelo.service"

failed=0
check() {   # név, parancs...
    local name=$1; shift
    if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failed=1; fi
}

out1=$(sh "$CLONE/install.sh" --figyelo 2>&1); code1=$?
check "install_figyelo: első telepítés exit 0" test "$code1" -eq 0
check "install_figyelo: az egység létrejött" test -f "$UNIT"
check "install_figyelo: ExecStart a szóközös útvonallal, idézve" \
    grep -qF "ExecStart=\"$(command -v python3)\" \"$CLONE/keretfigyelo.py\"" "$UNIT"
check "install_figyelo: daemon-reload, enable, restart" \
    test "$(cat "$LOG")" = "$(printf -- '--user daemon-reload\n--user enable kontextus-keretfigyelo.service\n--user restart kontextus-keretfigyelo.service')"
if command -v systemd-analyze >/dev/null; then
    # a verify a kulcs-hibákra is 0-val lép ki, csak figyelmeztet: az egységről szóló sor is hiba
    verify_unit() { local o; o=$(systemd-analyze --user verify "$1" 2>&1) && ! printf '%s' "$o" | grep -qF "$1"; }
    check "install_figyelo: systemd-analyze verify, figyelmeztetés nélkül" verify_unit "$UNIT"
fi
before=$(stat -c %y "$UNIT")
: > "$LOG"
out2=$(sh "$CLONE/install.sh" --figyelo 2>&1); code2=$?
check "install_figyelo: második futás exit 0, „már megvolt”" sh -c "[ $code2 -eq 0 ] && printf '%s' \"\$1\" | grep -q 'már megvolt'" _ "$out2"
check "install_figyelo: második futás az egységet nem írja újra" test "$(stat -c %y "$UNIT")" = "$before"
check "install_figyelo: második futás start (nem restart)" grep -qx -- '--user start kontextus-keretfigyelo.service' "$LOG"
check "install_figyelo: a valódi ~/.claude és ~/.codex alá nem ír" test ! -e "$HOME/.claude" -a ! -e "$HOME/.codex"

echo '{"ts": 1}' > "$XDG_RUNTIME_DIR/kontextus-ikon/keretfigyelo.json"
: > "$LOG"
out3=$(sh "$CLONE/install.sh" --figyelo-eltavolitas 2>&1); code3=$?
check "install_figyelo: eltávolítás exit 0" test "$code3" -eq 0
check "install_figyelo: az egység törölve" test ! -e "$UNIT"
check "install_figyelo: az állapotfájl törölve" test ! -e "$XDG_RUNTIME_DIR/kontextus-ikon/keretfigyelo.json"
check "install_figyelo: disable --now és daemon-reload" \
    test "$(cat "$LOG")" = "$(printf -- '--user disable --now kontextus-keretfigyelo.service\n--user daemon-reload')"
out4=$(sh "$CLONE/install.sh" --figyelo-eltavolitas 2>&1); code4=$?
check "install_figyelo: második eltávolítás exit 0, nincs mit törölni" \
    sh -c "[ $code4 -eq 0 ] && printf '%s' \"\$1\" | grep -q 'nincs mit törölni'" _ "$out4"
out5=$(sh "$CLONE/install.sh" --ismeretlen 2>&1); code5=$?
check "install_figyelo: ismeretlen kapcsoló exit 2" test "$code5" -eq 2
[ "$failed" = 0 ] || printf '%s\n' "--- kimenetek:" "$out1" "$out2" "$out3" "$out4"
exit $failed
