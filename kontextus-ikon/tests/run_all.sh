#!/usr/bin/env bash
# Minden teszt egy paranccsal: a bővítmény adatfeldolgozása (gjs), a keretfigyelő és a statusline közös
# fiók-lekérdezése (python unittest), a keretfigyelő telepítése/eltávolítása (ideiglenes HOME, systemctl-utánzat).
#   bash kontextus-ikon/tests/run_all.sh
# Kilépési kód: 0, ha mind a három rész zöld; különben 1. Valódi hálózatot, tokent, Codexet, systemd-t nem ér el.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
bad=0
echo "== gjs -m tests/run.js"
gjs -m "$HERE/run.js" || bad=1
echo "== python3 -m unittest (tests/test_*.py)"
python3 -m unittest discover -s "$HERE" -p 'test_*.py' -v 2>&1 | grep -v '^ResourceWarning\|Enable tracemalloc' ; [ "${PIPESTATUS[0]}" -eq 0 ] || bad=1
echo "== tests/install_figyelo.sh"
bash "$HERE/install_figyelo.sh" || bad=1
echo
[ "$bad" = 0 ] && echo "MIND ZÖLD" || echo "VAN PIROS"
exit $bad
