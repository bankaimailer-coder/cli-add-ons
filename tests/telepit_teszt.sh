#!/usr/bin/env bash
# A közös telepítő (telepit.sh) és a részek telepítőinek próbája (T03, E1-E8), a valódi gép érintése nélkül:
# minden eset saját ideiglenes HOME-mal fut, a PATH csak egy ideiglenes bin-mappa (a szükséges valódi
# alapeszközök szimlinkjei és álparancsok: systemctl, gsettings, dconf, gnome-shell, zenity, ptyxis, claude,
# codex, nvidia-smi, pkexec), a hwmon-mappa álmappa (HOFIGYELO_HWMON), a klón szóközös és ékezetes útvonalon áll.
# A végén ellenőrzi, hogy a valódi ~/.claude/settings.json, a ~/.config egységei és a gsettings nem változtak.
#   bash tests/telepit_teszt.sh
# TELEPIT_SRC: a tesztelt repó gyökere (alapból ez a repó; a tests/mutants.sh a hibás másolatra állítja).
# Kilépési kód: 0 = minden ellenőrzés rendben; 1 = valamelyik elbukott (a sor „FAIL”).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${TELEPIT_SRC:-$HERE/..}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REAL_HOME=$HOME
UUID=kontextus@kontextus-ikon
APP=claude-indito.desktop

failed=0
check() {   # név, parancs...
    local name=$1; shift
    if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failed=1; fi
}

# ---- a valódi gép állapota (csak olvasás) -------------------------------------------------------------
real_state() {
    local f
    for f in "$REAL_HOME/.claude/settings.json" "$REAL_HOME"/.config/systemd/user/*.service \
             "$REAL_HOME/.config/autostart/kontextus-ikon.desktop" "$REAL_HOME/.local/share/applications/$APP"; do
        [ -e "$f" ] && sha256sum "$f"
    done
    readlink "$REAL_HOME/.local/share/gnome-shell/extensions/$UUID"
    if [ -x /usr/bin/gsettings ] && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
        /usr/bin/gsettings get org.gnome.shell enabled-extensions
        /usr/bin/gsettings get org.gnome.shell favorite-apps
        /usr/bin/gsettings get org.gnome.Ptyxis profile-uuids
    fi
} 2>/dev/null
REAL_BEFORE=$(real_state)

# ---- környezet ------------------------------------------------------------------------------------------
# kornyezet NÉV: új eset-mappa ($E) home-mal, bin-nel, naplóval, álparancsokkal, hwmon-nal, mappak.txt-vel
kornyezet() {
    E="$TMP/$1"
    EXTRA=()
    mkdir -p "$E/home/repo-a" "$E/bin" "$E/log" "$E/gs" "$E/run" "$E/hwmon/hwmon0" "$E/hwmon/hwmon1"
    local t p
    for t in sh bash python3 cat mkdir ln readlink dirname basename rm cp mv sed grep id mktemp diff stat head \
             tr env sort touch chmod ls setsid date; do
        p=$(type -P "$t") && ln -s "$p" "$E/bin/$t"
    done
    printf '#!/bin/sh\necho "$*" >> "%s/log/systemctl"\n' "$E" > "$E/bin/systemctl"
    printf '#!/bin/sh\necho "$*" >> "%s/log/dconf"\n' "$E" > "$E/bin/dconf"
    printf '#!/bin/sh\necho "$*" >> "%s/log/pkexec"\n' "$E" > "$E/bin/pkexec"
    printf '#!/bin/sh\necho "GNOME Shell 50.0"\n' > "$E/bin/gnome-shell"
    for t in zenity ptyxis claude codex nvidia-smi; do printf '#!/bin/sh\nexit 0\n' > "$E/bin/$t"; done
    cat > "$E/bin/gsettings" <<EOF
#!/bin/sh
f="$E/gs/\$(printf '%s %s' "\$2" "\$3" | tr '/' '_')"
# a „nosema” jelzőfájl: nem GNOME-os gép, az org.gnome.shell séma hiányzik (a Ptyxis-é megvan)
if [ -f "$E/nosema" ] && [ "\$2" = org.gnome.shell ]; then echo "No such schema “org.gnome.shell”" >&2; exit 1; fi
case "\$1" in
    list-keys) exit 0 ;;
    get) if [ -f "\$f" ]; then cat "\$f"; else
             case "\$3" in
                 enabled-extensions|profile-uuids) echo "@as []" ;;
                 disable-user-extensions) echo false ;;
                 favorite-apps) echo "['org.gnome.Nautilus.desktop']" ;;
                 *) echo "''" ;;
             esac
         fi ;;
    set) printf '%s\n' "\$4" > "\$f"; echo "\$*" >> "$E/log/gsettings" ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$E/bin/"{systemctl,dconf,pkexec,gnome-shell,zenity,ptyxis,claude,codex,nvidia-smi,gsettings}
    echo k10temp > "$E/hwmon/hwmon0/name"
    echo BAT0 > "$E/hwmon/hwmon1/name"
    printf 'REPO A | ~/repo-a | #1a3a7a\nNINCS | ~/nincs-ilyen | #7a1a1a\n' > "$E/mappak.txt"
    valtozok
    klon "$K"
}
valtozok() {   # az eset ($E) útvonalai
    K="$E/klón szóközzel/cli-add-ons"
    S="$E/home/.claude/settings.json"
    HU="$E/home/.config/systemd/user/hofigyelo.service"
    KU="$E/home/.config/systemd/user/kontextus-keretfigyelo.service"
    DESK="$E/home/.local/share/applications/$APP"
    EXT="$E/home/.local/share/gnome-shell/extensions/$UUID"
    AUTO="$E/home/.config/autostart/kontextus-ikon.desktop"
}
klon() {   # $1: célmappa; a tesztelt forrás részeinek másolata
    mkdir -p "$1"
    cp "$SRC/telepit.sh" "$1/"
    local d
    for d in kontextus-ikon kontextus-horog hofigyelo claude-indito; do cp -r "$SRC/$d" "$1/"; done
}
nincs() { local t; for t in "$@"; do rm -f "$E/bin/$t"; done; }
# futtat KLÓN KAPCSOLÓK...: a telepit.sh tiszta környezetben; kimenet: $E/out, kód: $CODE
futtat() {
    local c=$1; shift
    : > "$E/log/systemctl"
    env -i HOME="$E/home" PATH="$E/bin" XDG_RUNTIME_DIR="$E/run" LANG=C.UTF-8 HOFIGYELO_HWMON="$E/hwmon" \
        CLAUDE_INDITO_LIST="$E/mappak.txt" "${EXTRA[@]}" sh "$c/telepit.sh" "$@" > "$E/out" 2>&1
    CODE=$?
}
kod() { [ "$CODE" = "$1" ]; }
van() { grep -qF -- "$1" "$E/out"; }
sor() { grep -qE "^$1 +$2( |\$)" "$E/out"; }   # összesítő sor: rész, eredmény
sorok() { local e=$1 r; shift; for r in "$@"; do sor "$r" "$e" || return 1; done; }
MIND=(kontextus-ikon keretfigyelo kontextus-horog hofigyelo claude-indito)
syslog() { grep -qx -- "$1" "$E/log/systemctl"; }
nincs_syslog() { ! grep -qx -- "$1" "$E/log/systemctl"; }
gs() { cat "$E/gs/org.gnome.shell $1" 2>/dev/null; }
# py KIFEJEZÉS: python-kifejezés a settings.json-on (d), a klónon (k) és a horogszámlálón (n)
py() {
    python3 - "$S" "$K" "$1" <<'EOF'
import json, os, shlex, sys
d = json.load(open(sys.argv[1])) if os.path.exists(sys.argv[1]) else {}
k = sys.argv[2]
def cmds(ev=None):
    return [h.get("command", "") for e, gs in d.get("hooks", {}).items() if ev in (None, e)
            for g in gs for h in g.get("hooks", [])]
def n(sub, ev=None):
    return sum(sub in c for c in cmds(ev))
sys.exit(0 if eval("(" + sys.argv[3] + "\n)") else 1)
EOF
}
uj_mentes() { [ "$(ls "$E/home/.claude/" | grep -c 'settings.json.backup-')" = "$1" ]; }

HOROG='python3 -I "'   # a hőfigyelő horgának eleje szóközös útvonalnál

# ---- E1: teljes telepítés, minden függőséggel ------------------------------------------------------------
kornyezet e1
futtat "$K"
check "E1 teljes telepítés: exit 0" kod 0
check "E1 összesítő: mind az öt rész „települt”" sorok települt "${MIND[@]}"
check "E1 összesítő fejléce (rész, eredmény, ok)" grep -qE '^rész +eredmény +ok$' "$E/out"
check "E1 hőfigyelő-egység: python -I, a klón útvonala idézve" \
    grep -qxF "ExecStart=$E/bin/python3 -I \"$K/hofigyelo/hofigyelo.py\"" "$HU"
check "E1 hőfigyelő-egység: a sablon többi sora" \
    sh -c 'grep -qx "Restart=always" "$1" && grep -qx "WantedBy=default.target" "$1"' _ "$HU"
check "E1 hőfigyelő horgai a mostani szerkezettel (PreToolUse/Bash, PostToolUse/*, UserPromptSubmit)" py '
sorted(((e, g.get("matcher"), json.dumps(h)) for e, gs in d["hooks"].items() for g in gs for h in g["hooks"] if "hofigyelo_horog" in h["command"]), key=str)
== sorted(((e, m, json.dumps({"type": "command", "command": "python3 -I \"%s/hofigyelo/hofigyelo_horog.py\"" % k, "timeout": 5}))
     for e, m in [("PreToolUse", "Bash"), ("PostToolUse", "*"), ("UserPromptSubmit", None)]), key=str)
and all("matcher" not in g for g in d["hooks"]["UserPromptSubmit"])'
check "E1 kontextus-horog bejegyezve" py 'n(k + "/kontextus-horog/kontextus_horog.py", "PostToolUse") == 1'
check "E1 statusline beállítva, refreshInterval 30-cal" py 'd["statusLine"] == {"type": "command", "command": "python3 \"%s/kontextus-ikon/statusline.py\"" % k, "refreshInterval": 30}'
check "E1 bővítmény: symlink és bekapcsolva" \
    sh -c '[ "$(readlink "$1")" = "$2" ] && grep -qF "$3" "$4"' _ "$EXT" "$K/kontextus-ikon/gnome-extension/$UUID" "'$UUID'" "$E/gs/org.gnome.shell enabled-extensions"
check "E1 automatikus indítás a klónból" grep -qxF "Exec=python3 \"$K/kontextus-ikon/kontextus_ikon.py\"" "$AUTO"
check "E1 keretfigyelő-egység a klónból" grep -qF "\"$K/kontextus-ikon/keretfigyelo.py\"" "$KU"
check "E1 indító és dokk" sh -c 'grep -qxF "Exec=sh \"$1/claude-indito/claude-indito.sh\"" "$2" && grep -qF "$3" "$4"' _ "$K" "$DESK" "'$APP'" "$E/gs/org.gnome.shell favorite-apps"
check "E1 dokk: a meglévő kedvenc megmarad" grep -qF "'org.gnome.Nautilus.desktop'" "$E/gs/org.gnome.shell favorite-apps"
check "E1 Ptyxis-színprofil a létező repónak" grep -q "	REPO A	" "$E/home/.local/share/claude-indito/profilok.tsv"
check "E1 systemctl: mindkét szolgáltatás enable és restart" sh -c '
    for u in hofigyelo.service kontextus-keretfigyelo.service; do
        grep -qx -- "--user enable $u" "$1" && grep -qx -- "--user restart $u" "$1" || exit 1
    done' _ "$E/log/systemctl"
check "E1 a végén: ki- és bejelentkezés kell" van "Teendő: ki- és bejelentkezés"
if command -v systemd-analyze >/dev/null; then
    verify_unit() { local o; o=$(systemd-analyze --user verify "$1" 2>&1) && ! printf '%s' "$o" | grep -qF "$1"; }
    check "E1 hőfigyelő-egység: systemd-analyze verify, figyelmeztetés nélkül" verify_unit "$HU"
fi
# E8: szóközös klónútvonal: a bejegyzett parancsok egy argumentumként a létező fájlra mutatnak
check "E8 szóközös útvonal: a horgok és a statusline parancsa létező fájlra bomlik" py '
all(os.path.isfile(shlex.split(c)[-1]) for c in cmds() + [d["statusLine"]["command"]]) and " " in k'
check "E8 szóközös útvonal: a hőfigyelő-egység ExecStart-ja létező fájlra bomlik" python3 -c '
import os, shlex, sys
line = [l for l in open(sys.argv[1]) if l.startswith("ExecStart=")][0]
a = shlex.split(line[len("ExecStart="):])
sys.exit(0 if a[1] == "-I" and os.path.isfile(a[2]) and os.path.isfile(a[0]) else 1)' "$HU"
check "E8 szóközös útvonal: az indító Exec-je létező fájlra bomlik" python3 -c '
import os, shlex, sys
line = [l for l in open(sys.argv[1]) if l.startswith("Exec=")][0]
sys.exit(0 if os.path.isfile(shlex.split(line[5:])[1]) else 1)' "$DESK"

# ---- E5: ismételt futtatás --------------------------------------------------------------------------------
cp "$S" "$E/s1"
mt=$(stat -c %y "$HU" "$KU" "$DESK" "$AUTO")
nb=$(ls "$E/home/.claude/" | grep -c 'settings.json.backup-')
futtat "$K"
check "E5 második futás: exit 0" sh -c '[ "$1" = 0 ]' _ "$CODE"
check "E5 második futás: összesítő „már megvolt”" sorok "már megvolt" "${MIND[@]}"
check "E5 a settings.json nem változott, nincs új mentés" sh -c 'cmp -s "$1" "$2"' _ "$S" "$E/s1"
check "E5 nincs új mentés" uj_mentes "$nb"
check "E5 az egységek és az indítófájlok nem íródtak újra" test "$(stat -c %y "$HU" "$KU" "$DESK" "$AUTO")" = "$mt"
check "E5 nincs kettőzött horog" py 'all(n("hofigyelo_horog.py", e) == 1 for e in ("PreToolUse", "PostToolUse", "UserPromptSubmit")) and n("kontextus_horog.py") == 1'
check "E5 a dokkban és a bővítmények közt egyszer" sh -c '[ "$(grep -o "$1" "$2" | wc -l)" = 1 ] && [ "$(grep -o "$3" "$4" | wc -l)" = 1 ]' _ \
    "'$APP'" "$E/gs/org.gnome.shell favorite-apps" "'$UUID'" "$E/gs/org.gnome.shell enabled-extensions"
check "E5 változatlan egységnél start, nem restart" sh -c '
    for u in hofigyelo.service kontextus-keretfigyelo.service; do
        grep -qx -- "--user start $u" "$1" && ! grep -qx -- "--user restart $u" "$1" || exit 1
    done' _ "$E/log/systemctl"
echo "# kézi módosítás" >> "$HU"
futtat "$K"
check "E5 megváltozott egység: újraírja és restart" sh -c '! grep -q "kézi módosítás" "$1"' _ "$HU"
check "E5 megváltozott egység: restart, a másik szolgáltatás csak start" \
    sh -c 'grep -qx -- "--user restart hofigyelo.service" "$1" && grep -qx -- "--user start kontextus-keretfigyelo.service" "$1"' _ "$E/log/systemctl"
check "E5 megváltozott egység: hofigyelo „települt”, a többi „már megvolt”" \
    sh -c 'grep -qE "^hofigyelo +települt" "$1" && grep -qE "^kontextus-horog +már megvolt" "$1"' _ "$E/out"
python3 - "$S" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
for ev in ("PostToolUse", "PreToolUse"):
    d["hooks"][ev].append(json.loads(json.dumps([g for g in d["hooks"][ev] if any("horog.py" in h["command"] for h in g["hooks"])][0])))
json.dump(d, open(sys.argv[1], "w"), indent=2)
EOF
futtat "$K"
check "E5 kézzel kettőzött horog: a fölösleg kikerül" py 'all(n("hofigyelo_horog.py", e) == 1 for e in ("PreToolUse", "PostToolUse", "UserPromptSubmit")) and n("kontextus_horog.py") == 1'

# ---- E6: más klónhelyről --------------------------------------------------------------------------------
OLD=$K
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["statusLine"]["refreshInterval"] = 10; json.dump(d, open(sys.argv[1], "w"))' "$S"
K="$E/új klón/cli-add-ons"
klon "$K"
futtat "$K"
check "R1-10 új klónhely: a statusline útvonala átíródik, a meglévő refreshInterval (10) marad" py 'd["statusLine"] == {"type": "command", "command": "python3 \"%s/kontextus-ikon/statusline.py\"" % k, "refreshInterval": 10}'
check "E6 új klónhely: exit 0" kod 0
check "E6 új klónhely: a régi útvonal sehol nem marad" sh -c '! grep -rqF "$1" "$2/.claude/settings.json" "$2/.config" "$2/.local/share/applications" && [ "$(readlink "$3")" = "$4" ]' _ \
    "$OLD" "$E/home" "$EXT" "$K/kontextus-ikon/gnome-extension/$UUID"
check "E6 új klónhely: a horgok az új helyre mutatnak, egyszer" py '
all(n(k + "/hofigyelo/hofigyelo_horog.py", e) == 1 for e in ("PreToolUse", "PostToolUse", "UserPromptSubmit")) and n(k + "/kontextus-horog/kontextus_horog.py") == 1 and k in d["statusLine"]["command"]'
check "E6 új klónhely: az egységek az új helyre mutatnak, restart" sh -c 'grep -qF "$1/hofigyelo/hofigyelo.py" "$2" && grep -qF "$1/kontextus-ikon/keretfigyelo.py" "$3" && grep -qx -- "--user restart hofigyelo.service" "$4"' _ \
    "$K" "$HU" "$KU" "$E/log/systemctl"

# E6 szimlinkes írásmód (mint ezen a gépen): a meglévő bejegyzés a valódi útvonalra mutat, idézőjel nélkül;
# a szimlinken át futtatva sem írja át, és fordítva sem
kornyezet e6s
D="$E/data/cli-add-ons"
klon "$D"
mkdir -p "$E/AI PROJECTS" "$(dirname "$HU")" "$E/home/.claude"
ln -s "$D" "$E/AI PROJECTS/cli-add-ons"
L="$E/AI PROJECTS/cli-add-ons"
mkdir -p "$E/alt"
ln -s "$E/bin/python3" "$E/alt/python3"   # R1-7: ugyanaz a python más írásmóddal
sed -e "s|@PYTHON@|$E/alt/python3|" -e "s|@SCRIPT@|$D/hofigyelo/hofigyelo.py|" "$D/hofigyelo/hofigyelo.service.in" > "$HU"
python3 - "$S" "$D" <<'EOF'
import json, sys
c = "python3 -I %s/hofigyelo/hofigyelo_horog.py" % sys.argv[2]
h = lambda: [{"type": "command", "command": c, "timeout": 5}]
json.dump({"hooks": {"PostToolUse": [{"matcher": "*", "hooks": h()}], "UserPromptSubmit": [{"hooks": h()}],
                     "PreToolUse": [{"matcher": "Bash", "hooks": h()}]}}, open(sys.argv[1], "w"), indent=1)
EOF
cp "$HU" "$E/hu0"
K=$L
futtat "$L"
check "E6 szimlinken át: a hőfigyelő „már megvolt”, a többi települ" sh -c '[ "$1" = 0 ] && grep -qE "^hofigyelo +már megvolt" "$2" && grep -qE "^kontextus-horog +települt" "$2"' _ "$CODE" "$E/out"
check "E6 szimlinken át: a hőfigyelő egysége és horgai érintetlenek" sh -c 'cmp -s "$1" "$2"' _ "$HU" "$E/hu0"
check "E6 szimlinken át: a horgok a valódi írásmóddal maradnak" py 'n("python3 -I %s/hofigyelo/hofigyelo_horog.py" % os.path.realpath(k)) == 3'
futtat "$D"
check "E6 a valódi útvonalról: mind az öt „már megvolt”" sh -c '[ "$1" = 0 ]' _ "$CODE"
check "E6 a valódi útvonalról: összesítő" sorok "már megvolt" "${MIND[@]}"
cp "$S" "$E/s1"
futtat "$D" --szaraz
check "E6 szárazon: mind „már megvolt”, semmi nem változik" sh -c '[ "$1" = 0 ] && cmp -s "$2" "$3"' _ "$CODE" "$S" "$E/s1"
check "E6 szárazon: összesítő" sorok "már megvolt" "${MIND[@]}"

# ---- E2: hiányzó függőségek ------------------------------------------------------------------------------
kornyezet e2a
nincs zenity ptyxis
futtat "$K"
check "E2 nincs zenity/ptyxis: exit 3" kod 3
check "E2 nincs zenity/ptyxis: claude-indito kihagyva, pkexec-javaslattal" sh -c 'grep -qE "^claude-indito +kihagyva +nincs zenity, ptyxis; pótlás: pkexec apt install zenity ptyxis" "$1"' _ "$E/out"
check "E2 nincs zenity/ptyxis: a többi települt" sorok települt kontextus-ikon keretfigyelo kontextus-horog hofigyelo
check "E2 nincs zenity/ptyxis: nincs indító" test ! -e "$DESK"
check "E2 a pkexec-et nem futtatja" test ! -e "$E/log/pkexec"

kornyezet e2b
nincs gnome-shell
futtat "$K"
check "E2 nincs gnome-shell: exit 3, kontextus-ikon kihagyva" sh -c '[ "$1" = 3 ] && grep -qE "^kontextus-ikon +kihagyva +nincs gnome-shell" "$2"' _ "$CODE" "$E/out"
check "E2 nincs gnome-shell: nincs bővítmény-symlink, a többi települt" sh -c '[ ! -e "$1" ]' _ "$EXT"
check "E2 nincs gnome-shell: a többi rész települt" sorok települt keretfigyelo kontextus-horog hofigyelo claude-indito
check "R1-1 nincs gnome-shell: a statusline települ, az automatikus indítás kimarad" sh -c '[ ! -e "$1" ] && grep -qE "^kontextus-ikon +kihagyva +nincs gnome-shell.*a statusline települt" "$2"' _ "$AUTO" "$E/out"
check "R1-1 nincs gnome-shell: a statusLine a settings.json-ban" py 'd["statusLine"]["command"] == "python3 \"%s/kontextus-ikon/statusline.py\"" % k'
check "R1-1 nincs gnome-shell: a bővítményt nem kapcsolja be" sh -c '! grep -q "enabled-extensions" "$1"' _ "$E/log/gsettings"

kornyezet e2s
nincs gnome-shell
touch "$E/nosema"
futtat "$K"
check "R1-8 gsettings van, GNOME Shell-séma nincs: exit 3, nincs HIBA" sh -c '[ "$1" = 3 ] && ! grep -qE "^[a-z-]+ +HIBA" "$2"' _ "$CODE" "$E/out"
check "R1-8 séma nélkül: az indító kihagyva, okkal" sh -c 'grep -qE "^claude-indito +kihagyva +nincs GNOME Shell-séma" "$1"' _ "$E/out"
kornyezet e2t
futtat "$K"
touch "$E/nosema"
nincs gnome-shell
futtat "$K" --eltavolitas
check "R1-8 séma nélküli eltávolítás: exit 0, nincs HIBA" sh -c '[ "$1" = 0 ] && ! grep -qE "^[a-z-]+ +HIBA" "$2"' _ "$CODE" "$E/out"
check "R1-8 séma nélküli eltávolítás: az indító és a színprofilok törölve" sh -c '[ ! -e "$1" ] && [ ! -e "$2/.local/share/claude-indito/profilok.tsv" ] && grep -q "^reset -f /org/gnome/Ptyxis/Profiles/" "$3"' _ "$DESK" "$E/home" "$E/log/dconf"

kornyezet e2c
mkdir -p "$E/nogi/gi"
echo 'raise ImportError("teszt: nincs gi")' > "$E/nogi/gi/__init__.py"
EXTRA=(PYTHONPATH="$E/nogi")
futtat "$K"
check "E2 nincs python3-gi: kontextus-ikon kihagyva, pkexec-javaslattal" sh -c '[ "$1" = 3 ] && grep -qE "^kontextus-ikon +kihagyva .*pkexec apt install python3-gi" "$2"' _ "$CODE" "$E/out"

kornyezet e2d
nincs claude codex
futtat "$K"
check "E2 nincs claude és codex: exit 3" kod 3
check "E2 nincs claude és codex: keretfigyelő, horog, indító kihagyva" sorok kihagyva keretfigyelo kontextus-horog claude-indito
check "E2 nincs claude és codex: a kihagyás oka" sh -c 'grep -qE "^kontextus-horog +kihagyva +nincs claude" "$1" && grep -qE "^keretfigyelo +kihagyva +nincs claude és codex" "$1"' _ "$E/out"
check "E2 nincs claude és codex: kontextus-ikon és hőfigyelő települt" sorok települt kontextus-ikon hofigyelo
check "E2 nincs claude és codex: nincs keretfigyelő-egység" test ! -e "$KU"

kornyezet e2e
mkdir -p "$E/home/.claude"
echo '{ hibás json' > "$S"
futtat "$K"
check "E2 hibás settings.json: exit 1 (hiba)" kod 1
check "E2 hibás settings.json: a hibás rész „HIBA”, a fájl érintetlen" sh -c 'grep -qE "^kontextus-horog +HIBA" "$1" && [ "$(cat "$2")" = "{ hibás json" ]' _ "$E/out" "$S"

# ---- E3: nincs ismert hőérzékelő ---------------------------------------------------------------------------
kornyezet e3
nincs nvidia-smi
echo BAT1 > "$E/hwmon/hwmon0/name"
futtat "$K"
check "E3 nincs hőérzékelő: hofigyelo kihagyva, exit 3" sh -c '[ "$1" = 3 ] && grep -qE "^hofigyelo +kihagyva +nincs ismert hőérzékelő" "$2"' _ "$CODE" "$E/out"
check "E3 nincs hőérzékelő: nincs egység, nincs horog" sh -c '[ ! -e "$1" ] && ! grep -q hofigyelo_horog "$2"' _ "$HU" "$S"
futtat "$K" --csak hofigyelo
check "E3 --csak hofigyelo: figyelmeztetéssel települ, exit 0" sh -c '[ "$1" = 0 ] && grep -q "figyelem: nincs ismert hőérzékelő" "$2" && [ -f "$3" ]' _ "$CODE" "$E/out" "$HU"
kornyezet e3b
echo BAT1 > "$E/hwmon/hwmon0/name"
futtat "$K" --csak hofigyelo,kontextus-horog
check "E3 csak nvidia-smi: a hőfigyelő települ figyelmeztetés nélkül" sh -c '[ "$1" = 0 ] && ! grep -q "figyelem: nincs ismert" "$2" && [ -f "$3" ]' _ "$CODE" "$E/out" "$HU"
kornyezet e3c
nincs nvidia-smi
echo acpitz > "$E/hwmon/hwmon0/name"
futtat "$K"
check "E3 csak ACPI-zóna: a hőfigyelő települ" sh -c '[ "$1" = 0 ] && [ -f "$2" ]' _ "$CODE" "$HU"

# ---- E4: részleges telepítés ---------------------------------------------------------------------------------
kornyezet e4a
futtat "$K" --csak hofigyelo,kontextus-horog
check "E4 --csak: exit 0, a két rész települt" sh -c '[ "$1" = 0 ]' _ "$CODE"
check "E4 --csak: a két rész települt" sorok települt hofigyelo kontextus-horog
check "E4 --csak: a többi „nem futott”, nincs nyoma" sh -c 'for r in kontextus-ikon keretfigyelo claude-indito; do grep -qE "^$r +nem futott" "$1" || exit 1; done; [ ! -e "$2" ] && [ ! -e "$3" ] && [ ! -e "$4" ]' _ "$E/out" "$EXT" "$KU" "$DESK"
kornyezet e4b
futtat "$K" --kihagy claude-indito
check "E4 --kihagy: az indító nem futott, nincs indítófájl" sh -c '[ "$1" = 0 ] && grep -qE "^claude-indito +nem futott" "$2" && [ ! -e "$3" ]' _ "$CODE" "$E/out" "$DESK"
check "E4 --kihagy: a többi települt" sorok települt kontextus-ikon keretfigyelo kontextus-horog hofigyelo
kornyezet e4c
futtat "$K" --csak hofigyelo,nemletezo
check "E4 ismeretlen rész: exit 1, a lehetséges nevek felsorolva" sh -c '[ "$1" = 1 ] && grep -qF "ismeretlen rész: nemletezo" "$2" && grep -qF "kontextus-ikon, keretfigyelo, kontextus-horog, hofigyelo, claude-indito" "$2"' _ "$CODE" "$E/out"
check "E4 ismeretlen rész: semmi nem fut" sh -c '[ -z "$(ls -A "$1/home" | grep -v repo-a)" ] && [ ! -s "$1/log/systemctl" ] && ! grep -q "^== " "$2"' _ "$E" "$E/out"
futtat "$K" --kihagy nemletezo
check "E4 ismeretlen rész a --kihagy-ban is hiba" sh -c '[ "$1" = 1 ] && [ -z "$(ls -A "$2/home" | grep -v repo-a)" ]' _ "$CODE" "$E"
for a in "--csak ," "--csak=" "--kihagy=,,"; do
    futtat "$K" $a
    check "R1-3 üres részlista ($a): exit 1, semmi nem fut" sh -c '[ "$1" = 1 ] && grep -qF "listája üres" "$3" && [ -z "$(ls -A "$2/home" | grep -v repo-a)" ]' _ "$CODE" "$E" "$E/out"
done
futtat "$K" --kihagy ""
check "R1-3 üres részlista (--kihagy \"\"): exit 1, semmi nem fut" sh -c '[ "$1" = 1 ] && [ -z "$(ls -A "$2/home" | grep -v repo-a)" ]' _ "$CODE" "$E"
futtat "$K" --ismeretlen-kapcsolo
check "E4 ismeretlen kapcsoló: exit 1, semmi nem fut" sh -c '[ "$1" = 1 ] && [ -z "$(ls -A "$2/home" | grep -v repo-a)" ]' _ "$CODE" "$E"

# ---- szárazfutás (6. feltétel) -----------------------------------------------------------------------------
kornyezet sz
futtat "$K" --szaraz
check "szárazfutás: exit 0, mind „települne”" sh -c '[ "$1" = 0 ]' _ "$CODE"
check "szárazfutás: összesítő „települne”" sorok települne "${MIND[@]}"
mkdir -p "$E/run/kontextus-ikon"
echo '{"ts": 1}' > "$E/run/kontextus-ikon/keretfigyelo.json"
futtat "$K" --eltavolitas --szaraz
check "R1-9 szárazon eltávolítva sem törli a keretfigyelo.json-t" sh -c '[ "$1" = 0 ] && [ -f "$2" ]' _ "$CODE" "$E/run/kontextus-ikon/keretfigyelo.json"
rm -f "$E/run/kontextus-ikon/keretfigyelo.json"
check "szárazfutás: semmit nem ír, nem indít" sh -c '[ -z "$(ls -A "$1/home" | grep -v repo-a)" ] && [ ! -s "$1/log/systemctl" ] && [ ! -e "$1/log/gsettings" ] && [ ! -e "$1/log/dconf" ]' _ "$E"

# ---- E7: eltávolítás, idegen bejegyzésekkel (4. feltétel) ------------------------------------------------
kornyezet e7
mkdir -p "$E/home/.claude"
cat > "$S" <<'EOF'
{
  "model": "idegen-beállítás",
  "hooks": {
    "PostToolUse": [{"matcher": "Edit", "hooks": [{"type": "command", "command": "echo idegen-horog", "timeout": 3}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "echo idegen-stop"}]}]
  }
}
EOF
cp "$S" "$E/s0"
FOREIGN='[g for g in d["hooks"]["PostToolUse"] if g == {"matcher": "Edit", "hooks": [{"type": "command", "command": "echo idegen-horog", "timeout": 3}]}] and d["hooks"]["Stop"] == [{"hooks": [{"type": "command", "command": "echo idegen-stop"}]}] and d["model"] == "idegen-beállítás"'
futtat "$K"
check "4. feltétel: telepítés után az idegen horgok és kulcsok érintetlenek" py "$FOREIGN"
check "4. feltétel: az eredeti settings.json mentése megvan" sh -c 'for b in "$1"/.claude/settings.json.backup-*; do cmp -s "$b" "$2" && exit 0; done; exit 1' _ "$E/home" "$E/s0"
check "4. feltétel: nem marad ideiglenes fájl" sh -c '! ls "$1/.claude" | grep -q "\.tmp$"' _ "$E/home"
nb=$(ls "$E/home/.claude/" | grep -c 'settings.json.backup-')
E7=$E
idegen_ok() { py "$FOREIGN" && ! ls "$E/home/.claude" "$E/dot" 2>/dev/null | grep -q '\.tmp$'; }
# részenként külön is: mindhárom settings.json-író rész ment és az idegen bejegyzést meghagyja
for r in kontextus-ikon kontextus-horog hofigyelo; do
    kornyezet "4-$r"
    # R1-2: a settings.json szimlink egy „dotfile” célfájlra; a mentés és az írás a célfájl mellett történik
    mkdir -p "$E/home/.claude" "$E/dot"
    SR="$E/dot/settings.json"
    cp "$E7/s0" "$SR"
    chmod 640 "$SR"
    ln -s "$SR" "$S"
    # a következő fél perc másodperceire szóló korábbi mentések: egyiket sem írhatja felül
    now=$(date +%s)
    for i in $(seq 0 30); do echo "régi mentés" > "$SR.backup-$(date -d "@$((now + i))" +%Y%m%d-%H%M%S)"; done
    ino=$(stat -c %i "$SR")
    futtat "$K" --csak "$r"
    check "R1-2 $r egyedül: a szimlink megmarad, a célfájl kapja a bejegyzést" sh -c '[ -L "$1" ] && [ "$(readlink "$1")" = "$2" ] && grep -q "$3" "$2"' _ "$S" "$SR" \
        "$(case $r in kontextus-ikon) echo statusline.py ;; kontextus-horog) echo kontextus_horog.py ;; *) echo hofigyelo_horog.py ;; esac)"
    check "R1-5/R1-6 $r egyedül: atomikus csere (új inode), az eredeti jog (0640) megmarad" \
        sh -c '[ "$(stat -c %i "$1")" != "$2" ] && [ "$(stat -c %a "$1")" = 640 ]' _ "$SR" "$ino"
    check "4. feltétel, $r egyedül: a korábbi mentést nem írja felül" sh -c '[ "$(cat "$1".backup-* | grep -cx "régi mentés")" = 31 ]' _ "$SR"
    check "4. feltétel, $r egyedül: az eredeti mentése megvan" sh -c 'for b in "$1".backup-*; do cmp -s "$b" "$2" && exit 0; done; exit 1' _ "$SR" "$E7/s0"
    check "4. feltétel, $r egyedül: az idegen horgok és kulcsok érintetlenek, nincs ideiglenes fájl" \
        idegen_ok
    futtat "$K" --csak "$r" --eltavolitas
    check "4. feltétel, $r egyedül: eltávolítás után is érintetlenek, a szimlink marad" sh -c '[ -L "$1" ]' _ "$S"
    check "4. feltétel, $r egyedül: eltávolítás után az idegenek érintetlenek" py "$FOREIGN"
done
E=$E7
valtozok
futtat "$K" --eltavolitas --szaraz
check "E7 szárazon: „eltávolítaná”, semmi nem tűnik el" sh -c '[ "$1" = 0 ] && [ -f "$2" ] && [ -f "$3" ] && [ ! -s "$4" ]' _ "$CODE" "$HU" "$DESK" "$E/log/systemctl"
check "E7 szárazon: összesítő" sorok eltávolítaná "${MIND[@]}"
futtat "$K" --eltavolitas
check "E7 eltávolítás: exit 0" sh -c '[ "$1" = 0 ]' _ "$CODE"
check "E7 eltávolítás: összesítő" sorok eltávolítva "${MIND[@]}"
check "E7 a szolgáltatások leállnak és törlődnek" sh -c '[ ! -e "$1" ] && [ ! -e "$2" ] && grep -qx -- "--user disable --now hofigyelo.service" "$3" && grep -qx -- "--user disable --now kontextus-keretfigyelo.service" "$3"' _ "$HU" "$KU" "$E/log/systemctl"
check "E7 a repó horgai és statusline-ja kikerül" py 'not any(k in c for c in cmds()) and "statusLine" not in d'
check "E7 az idegen horgok és kulcsok megmaradnak" py "$FOREIGN"
check "E7 az eltávolítás is ment (mindhárom író rész külön mentéssel)" sh -c '[ "$(ls "$1/.claude/" | grep -c "settings.json.backup-")" -eq "$(($2 + 3))" ]' _ "$E/home" "$nb"
check "E7 dokk: az indító kikerül, a többi kedvenc marad" sh -c '[ "$(cat "$1")" = "$3" ] && [ ! -e "$2" ]' _ "$E/gs/org.gnome.shell favorite-apps" "$DESK" "['org.gnome.Nautilus.desktop']"
check "E7 Ptyxis-profilok törölve (szinprofil.py eltavolit)" sh -c '[ ! -e "$1/.local/share/claude-indito/profilok.tsv" ] && grep -q "^reset -f /org/gnome/Ptyxis/Profiles/" "$2"' _ "$E/home" "$E/log/dconf"
check "E7 bővítmény: symlink, bekapcsolás, automatikus indítás eltűnt" sh -c '[ ! -e "$1" ] && [ ! -L "$1" ] && [ ! -e "$2" ] && ! grep -q "$3" "$4"' _ "$EXT" "$AUTO" "$UUID" "$E/gs/org.gnome.shell enabled-extensions"
futtat "$K" --eltavolitas
check "E7 második eltávolítás: exit 0" sh -c '[ "$1" = 0 ]' _ "$CODE"
check "E7 második eltávolítás: összesítő" sorok "nem volt" "${MIND[@]}"
futtat "$K"
futtat "$K" --eltavolitas --csak hofigyelo
check "E7 --eltavolitas --csak hofigyelo: csak a hőfigyelő tűnik el" sh -c '[ "$1" = 0 ] && [ ! -e "$2" ] && [ -f "$3" ]' _ "$CODE" "$HU" "$KU"
check "E7 --csak hofigyelo: a többi horog marad" py 'n("hofigyelo_horog") == 0 and n("kontextus_horog.py") == 1 and "statusLine" in d'

# ---- R1-11: python3 nélkül a hőfigyelő eltávolítása legalább az egységet lebontja ----------------------
kornyezet e11
futtat "$K" --csak hofigyelo
nincs python3
futtat "$K" --eltavolitas --csak hofigyelo
check "R1-11 python3 nélkül: az egység leállítva és törölve" sh -c '[ ! -e "$1" ] && grep -qx -- "--user disable --now hofigyelo.service" "$2"' _ "$HU" "$E/log/systemctl"
check "R1-11 python3 nélkül: kihagyva, okkal (a horgok maradtak), exit 3" sh -c '[ "$1" = 3 ] && grep -qE "^hofigyelo +kihagyva +nincs python3: a szolgáltatás lebontva" "$2"' _ "$CODE" "$E/out"

# ---- a valódi gép nem változott --------------------------------------------------------------------------
check "a valódi ~/.claude, ~/.config egységei és a gsettings nem változtak" test "$(real_state)" = "$REAL_BEFORE"
check "a valódi ~/.codex alá nem írt (nincs ilyen az ideiglenes HOME-okban sem)" sh -c '! ls -d "$1"/*/home/.codex 2>/dev/null | grep -q .' _ "$TMP"

[ "$failed" = 0 ] && echo "MIND ZÖLD" || echo "VAN PIROS"
exit $failed
