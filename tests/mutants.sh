#!/usr/bin/env bash
# Szándékosan hibás változatok a közös telepítő tesztjeihez (T03, MUNKAREND 2.5): mindegyik a repó részeinek
# egy ideiglenes másolatán egy perl-helyettesítés, utána lefut a tests/telepit_teszt.sh a másolatra
# (TELEPIT_SRC). Elvárás: minden változatra piros, és minden teszt legalább egy változatra elbukik.
#   bash tests/mutants.sh
# Kilépési kód: 0, ha minden változat piros és minden teszt elbukott legalább egyszer; különben 1.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT="$HERE/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# név | fájl (a repó gyökeréhez képest) | perl -0 helyettesítés (s~minta~csere~)
MUTANTS=(
'T1 kihagyásnál exit 0|telepit.sh|s~\[ "\$KIMARADT" = 0 \] \|\| exit 3~[ "\$KIMARADT" = 0 ] || exit 0~'
'T2 hibánál exit 0|telepit.sh|s~\[ "\$HIBA" = 0 \] \|\| exit 1~[ "\$HIBA" = 0 ] || exit 0~'
'T3 ismeretlen rész csak figyelmeztetés|telepit.sh|s~\|\| hiba "ismeretlen rész: \$n~|| echo "ismeretlen rész: \$n~'
'T4 a lehetséges nevek nincsenek felsorolva|telepit.sh|s~\(lehetséges: \$\(echo \$RESZEK \| sed .s/ /, /g.\)\)~(lehetséges: lásd a súgót)~; s~hiba\(\) \{ echo "HIBA: \$1"; hasznalat; exit 1; \}~hiba() { echo "HIBA: \$1"; exit 1; }~'
'T5 a --csak hatástalan|telepit.sh|s~if \[ -n "\$CSAK" \] && ! benne "\$r" "\$CSAK"; then~if false; then~'
'T6 a --kihagy hatástalan|telepit.sh|s~if benne "\$r" "\$KIHAGY"; then~if false; then~'
'T7 --csak hofigyelo nem kényszerít|telepit.sh|s~then set -- "\$@" --erzekelo-nelkul; fi~then :; fi~'
'T8 a --szaraz nem jut el a részekig|telepit.sh|s~    \[ "\$SZARAZ" = 0 \] \|\| set -- "\$@" --szaraz\n~~'
'T9 az --eltavolitas nem jut el a horoghoz és az indítóhoz|telepit.sh|s~(\*\)              set -- "\$ROOT/\$r/install.sh"\n)\s*\[ "\$ELTAVOLITAS" = 0 \] \|\| set -- "\$@" --eltavolitas ;;~$1 ;;~'
'T10 a „már megvolt” nincs felismerve|telepit.sh|s~if grep -qx valtozott "\$res"; then~if true; then~'
'T11 a kihagyás oka elvész|telepit.sh|s~"\$\(sed -n .s/\^kihagyva\t//p. "\$res" \| head -n 1\)"~""~'
'T12 nincs fejléc|telepit.sh|s~printf .%-16s %-14s %s\\n. "rész" "eredmény" "ok"\n~~'
'T13 nincs bejelentkezés-teendő|telepit.sh|s~    echo "Teendő: ki- és bejelentkezés[^\n]*\n~~'
'T14 a keretfigyelő eltávolítása telepít|telepit.sh|s~install.sh" --figyelo-eltavolitas~install.sh" --figyelo~'
'H1 az egységben nincs -I|hofigyelo/hofigyelo.service.in|s~@PYTHON@ -I @SCRIPT@~@PYTHON@ @SCRIPT@~'
'H2 a horogban nincs -I|hofigyelo/install.sh|s~cmd = "python3 -I " \+ sq~cmd = "python3 " + sq~'
'H3 nincs idézés az egységben|hofigyelo/install.sh|s~        if SAFE.fullmatch\(s\):\n            return s\n~        return s\n~'
'H4 nincs idézés a horogban|hofigyelo/install.sh|s~sq = script if SAFE.fullmatch\(script\) else~sq = script if True else~'
'H5 az érzékelő hiánya nem számít|hofigyelo/install.sh|s~\[ "\$KENYSZER" = 1 \] \|\| kihagy~true || kihagy~'
'H6 a kényszerítés hatástalan|hofigyelo/install.sh|s~--erzekelo-nelkul\) KENYSZER=1 ;;~--erzekelo-nelkul) KENYSZER=0 ;;~'
'H7 az ACPI-zóna nem érzékelő|hofigyelo/install.sh|s~k10temp\|acpitz\)~k10temp)~'
'H8 az nvidia-smi nem érzékelő|hofigyelo/install.sh|s~    command -v nvidia-smi >/dev/null\n\}~    false\n}~'
'H9 mindig restart|hofigyelo/install.sh|s~systemctl --user start "\$UNIT_NAME"~systemctl --user restart "\$UNIT_NAME"~'
'H10 mindig újraírja az egységet|hofigyelo/install.sh|s~if \[ -f "\$UNIT_DST" \] && \[ "\$\(cat "\$UNIT_DST"\)" = "\$NEW_UNIT" \]; then~if false; then~'
'H11 az egység írásmódja nem marad|hofigyelo/install.sh|s~                        script = old\n~                        pass\n~'
'H12 a horog írásmódja nem marad|hofigyelo/install.sh|s~if not same\(old, script\):~if old != script:~'
'H13 a kettőzött horog marad|hofigyelo/install.sh|s~elif seen:~elif False:~'
'H14 az eltávolítás nem veszi ki a horgot|hofigyelo/install.sh|s~elif mode == "eltavolit":\n(\s*)notes.append\(f"\{event\}: kivéve"\)~elif False:\n$1pass~'
'H15 az idegen horog elvész|hofigyelo/install.sh|s~if old is None:\n(\s*)keep.append\(h\)~if old is None:\n$1pass~'
'H16 nincs mentés|hofigyelo/install.sh|s~        shutil.copy2\(path, backup\)\n~~'
'H17 ideiglenes fájl marad|hofigyelo/install.sh|s~    os.replace\(tmp, path\)~    shutil.copy(tmp, path)~'
'H18 az eltávolítás nem állítja le|hofigyelo/install.sh|s~            systemctl --user disable --now "\$UNIT_NAME" \|\| true\n~~'
'H19 az eltávolítás nem törli az egységet|hofigyelo/install.sh|s~            rm -f "\$UNIT_DST"\n~~'
'H20 szárazon is ír|hofigyelo/install.sh|s~echo "  tenné: \$1"; return 1; fi~echo "  tenné: \$1"; return 0; fi~'
'H21 a változás nincs jelezve|hofigyelo/install.sh|s~(valtozas\(\) \{\n)    jelez valtozott\n~$1~'
'H22 hibás sablon|hofigyelo/hofigyelo.service.in|s~Restart=always~Restart=no~'
'H23 rossz matcher|hofigyelo/install.sh|s~\("PreToolUse", "Bash"\)~("PreToolUse", "*")~'
'H24 matcher a UserPromptSubmit-ben|hofigyelo/install.sh|s~g = \{"matcher": matcher\} if matcher else \{\}~g = {"matcher": matcher or "*"}~'
'H25 a régi klón horga marad|hofigyelo/install.sh|s~                        h\["command"\] = cmd\n~~'
'K1 a horog írásmódja nem marad|kontextus-horog/install.sh|s~if os.path.realpath\(old\) != os.path.realpath\(script\):~if old != script:~'
'K2 a kettőzött horog marad|kontextus-horog/install.sh|s~elif found:~elif False:~'
'K3 az eltávolítás nem veszi ki|kontextus-horog/install.sh|s~elif mode == "eltavolit":\n(\s*)notes.append\("kivéve"\)~elif False:\n$1pass~'
'K4 az idegen horog elvész|kontextus-horog/install.sh|s~if old is None:\n(\s*)keep.append\(h\)~if old is None:\n$1pass~'
'K5 a claude hiánya nem számít|kontextus-horog/install.sh|s~command -v claude >/dev/null \|\| kihagy~true || kihagy~'
'K6 nincs mentés|kontextus-horog/install.sh|s~    shutil.copy2\(path, backup\)\n~~'
'K7 a régi klón horga marad|kontextus-horog/install.sh|s~                h\["command"\] = cmd\n~~'
'K8 a hibás JSON felülíródik|kontextus-horog/install.sh|s~        print\(f"HIBA: a \{path\} nem érvényes JSON \(\{e\}\); nem nyúlok hozzá"\)\n        sys.exit\(1\)~        data = {}~'
'C1 a ptyxis hiánya nem számít|claude-indito/install.sh|s~for c in zenity ptyxis gsettings python3 claude; do~for c in gsettings python3 claude; do~'
'C2 nincs pkexec-javaslat|claude-indito/install.sh|s~    \[ -z "\$pkgs" \] \|\| why="\$why; pótlás: pkexec apt install\$pkgs"\n~~'
'C3 a dokkból nem veszi ki|claude-indito/install.sh|s~favorite-apps "\$\(fav_list "\$FAV" -\)"~favorite-apps "\$FAV"~'
'C4 mindig újraírja az indítót|claude-indito/install.sh|s~if \[ -f "\$DST" \] && \[ "\$\(cat "\$DST"\)" = "\$DESKTOP" \]; then~if false; then~'
'C5 az indító írásmódja nem marad|claude-indito/install.sh|s~        DIR=\$OLD\n~~'
'C6 a színprofilok maradnak|claude-indito/install.sh|s~python3 "\$DIR/szinprofil.py" eltavolit~true~'
'C7 kettőzött dokk-bejegyzés|claude-indito/install.sh|s~\*"\x27\$APP_ID\x27"\*\) echo "  kész: dokk \(már ki volt tűzve\)" ;;~*"NINCS"*) echo "  kész: dokk (már ki volt tűzve)" ;;~'
'C8 szárazon is ír|claude-indito/install.sh|s~echo "  tenné: \$1"; return 1; fi~echo "  tenné: \$1"; return 0; fi~'
'C9 a meglévő kedvencek elvesznek|claude-indito/install.sh|s~lst = ast.literal_eval\(cur\) if cur else \[\]~lst = []~'
'C10 az indító nem törlődik|claude-indito/install.sh|s~then rm -f "\$DST"; echo~then echo~'
'KI1 a gnome-shell hiánya nem számít|kontextus-ikon/install.sh|s~command -v gnome-shell >/dev/null \|\| GNOME_HIANY=~true || GNOME_HIANY=~'
'KI2 a python3-gi hiánya nem számít|kontextus-ikon/install.sh|s~then\n    GNOME_HIANY="hiányzik a python3-gi~then\n    : "hiányzik a python3-gi~'
'KI3 nincs írásmód-átvétel|kontextus-ikon/install.sh|s~    DIR=\$1\n\}~    return 0\n}~'
'KI4 a régi klón statusline-ja marad|kontextus-ikon/install.sh|s~    cur\["command"\] = cmd\n~~'
'KI5 a statusline nem kerül ki|kontextus-ikon/install.sh|s~    del data\["statusLine"\]\n~    pass\n~'
'KI6 a symlink nem törlődik|kontextus-ikon/install.sh|s~then rm -f "\$EXT_DST"; ok~then ok~'
'KI7 a bővítmény bekapcsolva marad|kontextus-ikon/install.sh|s~gsettings set org.gnome.shell enabled-extensions "\$NEW"; ok "bővítmény kikapcsolva"~ok "bővítmény kikapcsolva"~'
'KI8 az automatikus indítás marad|kontextus-ikon/install.sh|s~then rm -f "\$AUTOSTART"; ok~then ok~'
'KI9 a keretfigyelő claude és codex nélkül is|kontextus-ikon/install.sh|s~if ! command -v claude >/dev/null && ! command -v codex >/dev/null; then~if false; then~'
'KI10 a --figyelo-nelkul hatástalan|kontextus-ikon/install.sh|s~--figyelo-nelkul\) FIGYELO=0 ;;~--figyelo-nelkul) FIGYELO=1 ;;~'
'KI11 szárazon is ír|kontextus-ikon/install.sh|s~echo "  tenné: \$1"; return 1; fi~echo "  tenné: \$1"; return 0; fi~'
'KI12 nincs mentés|kontextus-ikon/install.sh|s~    shutil.copy2\(path, backup\)\n~~'
'KI13 az idegen kulcsok elvesznek|kontextus-ikon/install.sh|s~    data\["statusLine"\] = want\n~    data = {"statusLine": want}\n~'
'KI14 a mentés felülírja a korábbit|kontextus-ikon/install.sh|s~while os.path.exists\(backup\):~while False:~'
'KI15 a symlink ide mutatása nem számít|kontextus-ikon/install.sh|s~if \[ -L "\$EXT_DST" \] && \[ "\$\(readlink -f "\$EXT_DST"\)" = "\$\(readlink -f "\$EXT_SRC"\)" \]; then~if [ -L "\$EXT_DST" ]; then~'
'T15 a --csak fordítva|telepit.sh|s~if \[ -n "\$CSAK" \] && ! benne~if [ -n "\$CSAK" ] && benne~'
'T16 az eltávolítás „települt”-ként jelenik meg|telepit.sh|s~then e=eltávolítva; else~then e=települt; else~'
'T17 a keretfigyelő helyett eltávolítás|telepit.sh|s~else set -- "\$ROOT/kontextus-ikon/install.sh" --figyelo; fi~else set -- "\$ROOT/kontextus-ikon/install.sh" --figyelo-eltavolitas; fi~'
'H26 hibás szakasznév a sablonban|hofigyelo/hofigyelo.service.in|s~\[Service\]~[Servize]~'
'H27 minden futás új horgot ír|hofigyelo/install.sh|s~if mode == "telepit" and not seen:~if mode == "telepit":~'
'H28 az egység változása nem számít|hofigyelo/install.sh|s~if \[ -f "\$UNIT_DST" \] && \[ "\$\(cat "\$UNIT_DST"\)" = "\$NEW_UNIT" \]; then~if [ -f "\$UNIT_DST" ]; then~'
'C11 a kihagyáskor pkexec-et futtat|claude-indito/install.sh|s~    echo "  kihagyva: \$why"~    pkexec apt install\$pkgs; echo "  kihagyva: \$why"~'
'KI16 rossz statusline-útvonal|kontextus-ikon/install.sh|s~STATUS_CMD="python3 \\"\$DIR/statusline.py\\""~STATUS_CMD="python3 \\"\$DIR/../statusline.py\\""~'
'KI17 a symlink rossz helyre mutat|kontextus-ikon/install.sh|s~ln -sfn "\$EXT_SRC" "\$EXT_DST"~ln -sfn "\$DIR" "\$EXT_DST"~'
'KI18 az automatikus indítás útvonal nélkül|kontextus-ikon/install.sh|s~Exec=python3 \\"\$DIR/kontextus_ikon.py\\"~Exec=python3 kontextus_ikon.py~'
'T18 rossz kényszerítő kapcsoló|telepit.sh|s~set -- "\$@" --erzekelo-nelkul; fi~set -- "\$@" --erzekelo; fi~'
'H29 a mentés felülírja a korábbit|hofigyelo/install.sh|s~while os.path.exists\(backup\):~while False:~'
'K9 a mentés felülírja a korábbit|kontextus-horog/install.sh|s~while os.path.exists\(backup\):~while False:~'
'C12 az eltávolítás hibával lép ki|claude-indito/install.sh|s~    exit 0\nfi\n\n# függőségek~    exit 1\nfi\n\n# függőségek~'
'T19 az üres --csak nem hiba|telepit.sh|s~if \[ "\$CSAK_VOLT" = 1 \][^\n]*\n~~'
'T20 az üres --kihagy nem hiba|telepit.sh|s~if \[ "\$KIHAGY_VOLT" = 1 \][^\n]*\n~~'
'KI21 GNOME nélkül a statusline is kimarad|kontextus-ikon/install.sh|s~(if \[ -z "\$GNOME_HIANY" \]; then\n    gnome_lepesek)~[ -z "\$GNOME_HIANY" ] || kihagy "\$GNOME_HIANY"\n$1~'
'KI22 GNOME nélkül is a GNOME-lépések|kontextus-ikon/install.sh|s~if \[ -z "\$GNOME_HIANY" \]; then\n    gnome_lepesek~if true; then\n    gnome_lepesek~'
'KI23 eltávolításkor nincs sémaellenőrzés|kontextus-ikon/install.sh|s~if gnome_sema && command -v python3 >/dev/null; then\n            CUR=~if command -v gsettings >/dev/null; then\n            CUR=~'
'KI24 szárazon is törli a keretfigyelo.json-t|kontextus-ikon/install.sh|s~    \[ "\$SZARAZ" = 1 \] && return 0   # szárazon semmit nem töröl\n~~'
'KI25 nincs refreshInterval|kontextus-ikon/install.sh|s~, "refreshInterval": 30\}~}~'
'KI20 a meglévő statusline-beállítás felülíródik|kontextus-ikon/install.sh|s~    cur\["command"\] = cmd\n~    data["statusLine"] = dict(want)\n~'
'KI26 a szimlink helyére sima fájl|kontextus-ikon/install.sh|s~path = os.path.realpath\(path\)   # szimlinknél~pass   # szimlinknél~'
'KI27 közvetlen írás|kontextus-ikon/install.sh|s~os.replace\(tmp, path\)~open(path, "w").write(open(tmp).read()); os.remove(tmp)~'
'K10 a szimlink helyére sima fájl|kontextus-horog/install.sh|s~path = os.path.realpath\(path\)   # szimlinknél~pass   # szimlinknél~'
'K11 közvetlen írás|kontextus-horog/install.sh|s~os.replace\(tmp, path\)~open(path, "w").write(open(tmp).read()); os.remove(tmp)~'
'H30 az egység python-írásmódja nem marad|hofigyelo/install.sh|s~                        python = oldpy\n~                        pass\n~'
'H31 python3 nélkül az eltávolítás semmit nem bont|hofigyelo/install.sh|s~(if \[ "\$MODE" = eltavolit \]; then\n)~$1    command -v python3 >/dev/null \|\| kihagy "nincs python3"\n~'
'H32 a szimlink helyére sima fájl|hofigyelo/install.sh|s~path = os.path.realpath\(path\)   # szimlinknél~pass   # szimlinknél~'
'H33 közvetlen írás|hofigyelo/install.sh|s~os.replace\(tmp, path\)~open(path, "w").write(open(tmp).read()); os.remove(tmp)~'
'H34 az eredeti jog elvész|hofigyelo/install.sh|s~    os.chmod\(tmp, perm\)\n~~'
'C13 séma nélkül nincs kihagyás|claude-indito/install.sh|s~if \[ -z "\$missing" \] && ! gnome_sema; then~if false; then~'
'C14 séma nélkül a színprofilok maradnak|claude-indito/install.sh|s~elif ! python3 "\$DIR/szinprofil.py" eltavolit; then~elif gnome_sema && ! python3 "\$DIR/szinprofil.py" eltavolit; then~'
'KI19 a keretfigyelő nincs bekapcsolva|kontextus-ikon/install.sh|s~    "\$SYSTEMCTL" --user enable "\$UNIT_NAME"\n~~'
)

# őrző ellenőrzések: a valódi gép változatlanságát nézik; hibás telepítő-változat ezeket csak a valódi HOME
# írásával buktatná el, ezért szándékosan nincs rájuk változat (a sima futás igazolja őket)
GUARDS=$'a valódi ~/.claude, ~/.config egységei és a gsettings nem változtak\na valódi ~/.codex alá nem írt (nincs ilyen az ideiglenes HOME-okban sem)'

ALL=$(bash "$HERE/telepit_teszt.sh" 2>&1 | sed -n 's/^ok   //p')
killed=""
bad=0
for m in "${MUTANTS[@]}"; do
    IFS='|' read -r name file expr <<<"$m"
    dir="$TMP/src"
    rm -rf "$dir"; mkdir -p "$dir"
    cp "$ROOT/telepit.sh" "$dir/"
    cp -r "$ROOT/kontextus-ikon" "$ROOT/kontextus-horog" "$ROOT/hofigyelo" "$ROOT/claude-indito" "$dir/"
    perl -0pi -e "$expr" "$dir/$file"
    if cmp -s "$ROOT/$file" "$dir/$file"; then
        echo "HIBA  $name: a helyettesítés nem talált (a változat nem jött létre)"
        bad=1; continue
    fi
    out=$(TELEPIT_SRC="$dir" timeout 300 bash "$HERE/telepit_teszt.sh" 2>&1); code=$?
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

echo
while IFS= read -r t; do
    [ -z "$t" ] && continue
    grep -qxF "$t" <<<"$GUARDS" && continue
    if ! grep -qxF "$t" <<<"$killed"; then
        echo "NEM BUKOTT EGY VÁLTOZATRA SEM: $t"; bad=1
    fi
done <<<"$ALL"
echo "tesztek: $(grep -c . <<<"$ALL"); változatok: ${#MUTANTS[@]}"
exit $bad
