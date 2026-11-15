#!/usr/bin/env bash
# Szándékosan hibás változatok (MUNKAREND 2.5): mindegyik egy ideiglenes másolaton egy perl-helyettesítés,
# utána lefutnak a tesztek. M1-M15 (T01) és J1-J15 (T02): a bővítmény másolata, tests/run.js. P1-P37 (T02):
# a kontextus-ikon Python-fájljainak és az egységsablonnak a másolata, tests/test_*.py. I1-I10 (T02): az
# install.sh (és a sablon) másolata, tests/install_figyelo.sh. Elvárás: minden változatra piros, és minden
# teszt legalább egy változatra elbukik. Futtatás: bash kontextus-ikon/tests/mutants.sh
# Kilépési kód: 0, ha minden változat piros és minden teszt elbukott legalább egyszer; különben 1.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/../gnome-extension/kontextus@kontextus-ikon"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# név | fájl | perl -0 helyettesítés (s~minta~csere~)
MUTANTS=(
'M1 küszöb megfordítva|limits.js|s~t - ts > STALE_AFTER~t - ts < STALE_AFTER~'
'M2 visszaállás-ellenőrzés kivéve|limits.js|s~if \(resetsAt && resetsAt <= t\)~if (false)~'
'M3 a mérő nem nézi a régiséget|meter.js|s~export function limitStyle\(left, stale, tag, rgb\) \{~export function limitStyle(left, _s, tag, rgb) { const stale = false;~'
'M4 üres Codex-mappa ága kivéve|limits.js|s~    if \(!files.length\)\n        return both\([^\n]*\n~~'
'M5 null rate_limits nincs ellenőrizve|limits.js|s~if \(rl && \(rl.limit_id~if ((rl.limit_id~'
'M6 csonka sornál megáll|limits.js|s~bad\+\+;\n            continue;~bad++;\n            break;~'
'M7 csonka sor nem számít|limits.js|s~            bad\+\+;\n~~'
'M8 Codex olvasási hiba elnyelve|limits.js|s~why \?\?= reportOnce\(f.path, [^\n]*\n~\n~'
'M9 listázási hiba elnyelve|limits.js|s~throw e;~return out;~'
'M10 naplózás minden frissítéskor|limits.js|s~if \(reported.get\(key\) !== msg\)~if (true)~'
'M11 hiányzó fájl nem várt eset|limits.js|s~        if \(isNotFound\(e\)\)\n            return \{why: `nincs \$\{label\}`\};\n~~'
'M12 hiányzó ablak helyett az első|limits.js|s~const w = wins.find\(x => test\(x.window_minutes\)\);~const w = wins.find(x => test(x.window_minutes)) ?? wins[0];~'
'M13 hiányzó Claude-ablak helyett az 5 órás|limits.js|s~const v = c\[key\];~const v = c[key] ?? c.five_hour;~'
'M14 Claude: fájlszintű idő az ablakidő helyett|limits.js|s~v.ts \?\? data.ts~data.ts ?? v.ts~'
'M15 idegen limit_id is elfogadva|limits.js|s~\(rl.limit_id \?\? .codex.\) === .codex. && ~~'
'J1 elavult szívverés is fut|limits.js|s~if \(t - data.ts > FIGYELO_MAX_AGE\)~if (false)~'
'J2 ts nélküli állapotfájl is fut|limits.js|s~if \(typeof data.ts !== .number.\)~if (false)~'
'J3 a frissesség nem számít, a helyi nyer|limits.js|s~return \(b.ts \?\? 0\) > \(a.ts \?\? 0\) \? b : a;~return a;~'
'J4 mindig a figyelő nyer|limits.js|s~if \(has\(a\) && has\(b\)\)\n        return \(b.ts \?\? 0\) > \(a.ts \?\? 0\) \? b : a;~if (true)\n        return b;~'
'J5 nem futó figyelő adata is beolvad|limits.js|s~    if \(!figyelo.running\)\n        return \{claude, codex, figyelo\};\n~~'
'J6 a figyelő oka elvész|limits.js|s~noData\(block\?.why \?\? (.ez az ablak hiányzik a keretfigyelő adatából.)\)~noData($1)~'
'J7 a figyelő megjegyzése elvész|limits.js|s~note: block.why \?\? null~note: null~'
'J8 nincs régiség-jel|meter.js|s~mark: Boolean\(stale\),~mark: false,~'
'J9 a régi felirat takarja a jelet|meter.js|s~        tag,\n        mark~        tag: stale ? "régi" : tag,\n        mark~'
'J10 adat nélkül a helyi ok nyer|limits.js|s~    return b \?\? a;~    return a;~'
'J11 nincs inkrementális olvasás|limits.js|s~\} else if \(c\?.inc && c.inc.path === top.path && top.size >= c.inc.end\) \{~} else if (false) {~'
'J12 a félig írt sor után folytat|limits.js|s~return \{text, end: from \+ last \+ 1\};~return {text, end: size};~'
'J13 csak a napi mappa figyelt|limits.js|s~for \(let i = 0; i < 3 &&~for (let i = 0; i < 1 \&\&~'
'J15 a félig írt sor levágva|limits.js|s~let text = new TextDecoder\(\).decode\(bytes\);~let text = new TextDecoder().decode(bytes.subarray(0, last + 1));~'
'J14 a figyelő menüsora fordítva|limits.js|s~    if \(!fig.running\)\n        return `Keretfigyelő: NEM FUT~    if (fig.running)\n        return `Keretfigyelő: NEM FUT~'
)

ALL=$(gjs -m "$HERE/run.js" | sed -n 's/^ok   //p')
killed=""
bad=0
for m in "${MUTANTS[@]}"; do
    IFS='|' read -r name file expr <<<"$m"
    dir="$TMP/ext"
    rm -rf "$dir"; cp -r "$SRC" "$dir"
    perl -0pi -e "$expr" "$dir/$file"
    if cmp -s "$SRC/$file" "$dir/$file"; then
        echo "HIBA  $name: a helyettesítés nem talált (a változat nem jött létre)"
        bad=1; continue
    fi
    out=$(KONTEXTUS_EXT_DIR="$dir" gjs -m "$HERE/run.js" 2>&1); code=$?
    fails=$(sed -n 's/^FAIL //p' <<<"$out")
    n=$(grep -c . <<<"$fails")
    if [ "$code" -eq 0 ]; then
        echo "ZÖLD  $name: exit 0 (a tesztek nem vették észre)"; bad=1
    else
        echo "piros $name: exit $code, $n bukott teszt"
        sed 's/^/        /' <<<"$fails"
    fi
    killed+="$fails"$'\n'
done

# ---- Python (keretfigyelő, statusline) és telepítő ------------------------------------
PYSRC="$HERE/.."
pytests() {   # $1: forrásmappa; kimenet: a bukott tesztek nevei, kilépési kód: a tesztek kódja
    local out code
    out=$(KERETFIGYELO_SRC="$1" timeout 120 python3 -m unittest discover -s "$HERE" -p 'test_*.py' -v 2>&1); code=$?
    sed -n 's/^\(test_[A-Za-z0-9_]*\) .* \.\.\. \(FAIL\|ERROR\)$/\1/p' <<<"$out"
    grep -q '^FAIL: \|^ERROR: ' <<<"$out" && [ "$code" -eq 0 ] && code=1
    return $code
}
insttests() {
    local out code
    out=$(KERETFIGYELO_SRC="$1" timeout 120 bash "$HERE/install_figyelo.sh" 2>&1); code=$?
    sed -n 's/^FAIL //p' <<<"$out"
    return $code
}
ALL_PY=$(python3 -m unittest discover -s "$HERE" -p 'test_*.py' -v 2>&1 | sed -n 's/^\(test_[A-Za-z0-9_]*\) .* \.\.\. ok$/\1/p')
ALL_INST=$(bash "$HERE/install_figyelo.sh" 2>&1 | sed -n 's/^ok   //p')

# név | fájl | perl -0 helyettesítés | melyik tesztsor (py vagy inst)
PY_MUTANTS=(
'P1 nincs gyorsítótár|statusline.py|s~USAGE_EVERY = 120~USAGE_EVERY = 0~|py'
'P2 a statusline a zár mellett is kérdez|statusline.py|s~            return c or \{~            c = c or {~|py'
'P3 az 5 órás sor kimarad|statusline.py|s~USAGE_KINDS = \{"session": "five_hour", ~USAGE_KINDS = {~|py'
'P4 a Fable-sor kimarad a figyelőből|keretfigyelo.py|s~    if fable is not None:\n        out\["fable"\]~    if False:\n        out["fable"]~|py'
'P5 a 401 nincs megkülönböztetve|statusline.py|s~if e.code == 401:~if e.code == 999:~|py'
'P6 hibánál elvész az utolsó jó adat|statusline.py|s~"windows": c.get\("windows"\) or \{\},~"windows": {},~|py'
'P7 a lejárati idő nem számít|statusline.py|s~expires / 1000 <= now~expires / 1000 <= 0~|py'
'P8 hiányzó fájl nem külön eset|statusline.py|s~    except FileNotFoundError:\n        raise UsageError\("nincs Claude-bejelentkezés"\) from None\n~~|py'
'P9 a fejléc a naplóba kerül|statusline.py|s~(\n    try:\n        with opener\(req)~\n    print(dict(req.header_items()), file=sys.stderr)$1~|py'
'P10 a hitelesítő fájlhoz ír|statusline.py|s~\n    return token\n~\n    os.utime(cred_path)\n    return token\n~|py'
'P11 nem atomikus írás|keretfigyelo.py|s~    tmp = f"\{path\}.\{os.getpid\(\)\}.tmp"\n    with open\(tmp~    tmp = path\n    with open(tmp~|py'
'P12 nincs initialized|keretfigyelo.py|s~            self._send\("initialized", None, now, notify=True\)\n~~|py'
'P13 lekérés minden körben|keretfigyelo.py|s~self.next_read = now \+ self.every~self.next_read = now~|py'
'P14 az értesítés nincs kezelve|keretfigyelo.py|s~if msg.get\("method"\) == "account/rateLimits/updated":~if msg.get("method") == "x":~|py'
'P15 idegen limitId is elfogadva|keretfigyelo.py|s~    if \(snap.get\("limitId"\) or "codex"\) != "codex":\n        return None\n~~|py'
'P16 ablak fordítva|keretfigyelo.py|s~mins <= DAY_MINUTES~mins >= DAY_MINUTES~|py'
'P17 a ritka értesítés törli a másik ablakot|keretfigyelo.py|s~self.data = \{\*\*self.data, \*\*new\}~self.data = new~|py'
'P18 nincs-bejelentkezés oka elvész|keretfigyelo.py|s~"codex account authentication required" in msg~"xyz" in msg~|py'
'P19 API-kulcs oka elvész|keretfigyelo.py|s~"chatgpt authentication required" in msg~"xyz" in msg~|py'
'P20 nem növekvő várakozás|keretfigyelo.py|s~return BACKOFF\[min\(max\(failures, 1\), len\(BACKOFF\)\) - 1\]~return BACKOFF[0]~|py'
'P21 a kilépés nincs kezelve|keretfigyelo.py|s~if kind == "exit":~if kind == "nope":~|py'
'P22 nincs időkorlát|keretfigyelo.py|s~if any\(now - sent > self.timeout~if False and any(now - sent > self.timeout~|py'
'P23 a hiányzó codex nincs felismerve|keretfigyelo.py|s~return \(os.environ.get\("KERETFIGYELO_CODEX"\) or shutil.which\("codex"\)~return ("codex"~|py'
'P24 nem JSON sor megállítja az olvasót|keretfigyelo.py|s~            except ValueError:\n                msg = None~            except ValueError:\n                break~|py'
'P25 leállításkor megmarad az állapotfájl|keretfigyelo.py|s~os.remove\(path\)   #~pass   #~|py'
'P26 nincs idézés az egységben|keretfigyelo.py|s~    return .". \+ s \+ .".\n~    return s\n~|py'
'P27 a % nincs escape-elve|keretfigyelo.py|s~.replace\("%", "%%"\)~~|py'
'P28 a statusline sorai elvesznek|statusline.py|s~return c.get\("rows"\), c.get\("resets"\) or \{\}, c.get\("ok_at"\)~return None, {}, None~|py'
'P29 a hálózati hiba nincs elkapva|statusline.py|s~except \(urllib.error.URLError, OSError, http.client.HTTPException\) as e:~except KeyError as e:~|py'
'P30 a saját leállítás késő kilépése második hiba|keretfigyelo.py|s~        self.gen \+= 1   # a saját leállítás[^\n]*\n~~|py'
'P31 a csonka törzs nincs elkapva|statusline.py|s~except \(urllib.error.URLError, OSError, http.client.HTTPException\) as e:~except (urllib.error.URLError, OSError) as e:~|py'
'P32 a sémahiba nincs elkapva|statusline.py|s~    try:\n        return parse_usage\(data\)\n    except[^\n]*\n[^\n]*\n~    return parse_usage(data)\n~|py'
'P33 nem egész id nincs kiszűrve|keretfigyelo.py|s~        if not isinstance\(mid, int\) or isinstance\(mid, bool\):\n            return False[^\n]*\n~~|py'
'P34 nem objektum result nincs kiszűrve|keretfigyelo.py|s~    if not isinstance\(result, dict\):\n        return None\n~~|py'
'P35 nem szám százalék elfogadva|keretfigyelo.py|s~not isinstance\(w.get\("usedPercent"\), \(int, float\)\)~w.get("usedPercent") is None~|py'
'P37 nem objektum error nincs kezelve|keretfigyelo.py|s~    if not isinstance\(err, dict\):[^\n]*\n[^\n]*\n~~|py'
'P36 a --once a közös gyorsítótárat használja|keretfigyelo.py|s~cache_path=os.path.join\(tmp, "usage.json"\), ~~|py'
'I1 mindig újraírja az egységet|install.sh|s~if \[ -f "\$UNIT_DST" \] && \[ "\$\(cat "\$UNIT_DST"\)" = "\$NEW_UNIT" \]; then~if false; then~|inst'
'I2 az állapotfájl megmarad|install.sh|s~    rm -f "\$\{XDG_RUNTIME_DIR[^\n]*\n~~|inst'
'I3 a második eltávolítás hibát ad|install.sh|s~ok "keretfigyelő nincs telepítve \(nincs mit törölni\)"~exit 1~|inst'
'I4 ismeretlen kapcsoló exit 0|install.sh|s~--figyelo-eltavolitas\)"; exit 2 ;;~--figyelo-eltavolitas)"; exit 0 ;;~|inst'
'I5 nincs enable|install.sh|s~    "\$SYSTEMCTL" --user enable "\$UNIT_NAME"\n~~|inst'
'I6 nincs disable|install.sh|s~        "\$SYSTEMCTL" --user disable --now "\$UNIT_NAME" .. true\n~~|inst'
'I7 hibás egységsablon|keretfigyelo.service.in|s~Type=simple~Type=nemletezo~|inst'
'I8 az egység kitöltése elbukik|install.sh|s~NEW_UNIT=\$\(python3 "\$DIR/keretfigyelo.py" --unit\)~NEW_UNIT=\$(false)~|inst'
'I9 a ~/.claude alá ír|install.sh|s~(install_figyelo\(\) \{\n)~$1    mkdir -p "\$HOME/.claude"\n~|inst'
'I10 az egység törlése elbukik|install.sh|s~        rm -f "\$UNIT_DST"\n~        false\n~|inst'
)

killed_py=""
killed_inst=""
for m in "${PY_MUTANTS[@]}"; do
    IFS='|' read -r name file expr kind <<<"$m"
    dir="$TMP/py"
    rm -rf "$dir"; mkdir -p "$dir"
    cp "$PYSRC"/*.py "$PYSRC/keretfigyelo.service.in" "$PYSRC/install.sh" "$dir/"
    perl -0pi -e "$expr" "$dir/$file"
    if cmp -s "$PYSRC/$file" "$dir/$file"; then
        echo "HIBA  $name: a helyettesítés nem talált (a változat nem jött létre)"
        bad=1; continue
    fi
    if [ "$kind" = py ]; then fails=$(pytests "$dir"); code=$?; else fails=$(insttests "$dir"); code=$?; fi
    n=$(grep -c . <<<"$fails")
    if [ "$code" -eq 0 ]; then
        echo "ZÖLD  $name: exit 0 (a tesztek nem vették észre)"; bad=1
    else
        echo "piros $name: exit $code, $n bukott teszt"
        sed 's/^/        /' <<<"$fails"
    fi
    if [ "$kind" = py ]; then killed_py+="$fails"$'\n'; else killed_inst+="$fails"$'\n'; fi
done

echo
not_killed() {   # $1: összes teszt, $2: bukott tesztek
    while IFS= read -r t; do
        [ -z "$t" ] && continue
        if ! grep -qxF "$t" <<<"$2"; then
            echo "NEM BUKOTT EGY VÁLTOZATRA SEM: $t"; bad=1
        fi
    done <<<"$1"
}
not_killed "$ALL" "$killed"
not_killed "$ALL_PY" "$killed_py"
not_killed "$ALL_INST" "$killed_inst"
echo "tesztek: gjs $(grep -c . <<<"$ALL"), python $(grep -c . <<<"$ALL_PY"), telepítő $(grep -c . <<<"$ALL_INST");" \
     "változatok: bővítmény ${#MUTANTS[@]}, python+telepítő ${#PY_MUTANTS[@]}"
exit $bad
