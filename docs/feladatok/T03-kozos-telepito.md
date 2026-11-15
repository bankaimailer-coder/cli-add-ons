# T03 Közös telepítő: a repó minden eszköze egy paranccsal, bármelyik gépre

- Forrás: a user kérése (2026-11-15): az eszközöket (keretmérők, keretfigyelő, CPU/GPU-hőmérő, terminálszínek, hőfigyelő) a többi gépre is a repóból akarja telepíteni. Előzmény: T02 (kész, `eeb78bf`); a keretfigyelő ezen a gépen fut (`kontextus-keretfigyelo.service`).
- Besorolás: kényes (a `~/.claude/settings.json`-t, systemd-egységeket és GNOME-beállítást ír).
- Cél: egy új gépen a repó klónozása után egyetlen parancs (`sh telepit.sh`) mindent feltesz, ami azon a gépen működni tud, és a végén röviden kiírja, mi települt, mi maradt ki és miért. Ugyanez a parancs ezen a gépen semmit nem ront el (idempotens), és az eltávolítás is egy parancs.
- Mostani állapot, amire épül:
  - `kontextus-ikon/install.sh` (bővítmény, statusline, keretfigyelő; `--figyelo`, `--figyelo-eltavolitas`);
  - `kontextus-horog/install.sh` (PostToolUse horog);
  - `claude-indito/install.sh` (indító, dokk, Ptyxis-színprofilok; zenity és ptyxis nélkül hibával kilép);
  - a `hofigyelo/`-nek **nincs telepítője**: ezen a gépen kézzel írt `~/.config/systemd/user/hofigyelo.service` (`ExecStart=/usr/bin/python3 -I /data/cli-add-ons/hofigyelo/hofigyelo.py`) és három horogbejegyzés a `~/.claude/settings.json`-ban (`python3 -I /data/cli-add-ons/hofigyelo/hofigyelo_horog.py`; PreToolUse/Bash, PostToolUse, UserPromptSubmit). A pontos szerkezetet a mostani settings.json-ból olvasd ki (csak olvasd).
- Lefedett esetek:
  - E1: teljes telepítés egy GNOME-os gépen, ahol minden függőség megvan → mind az öt rész települ, a végén összesítő tábla (rész, eredmény, ok).
  - E2: hiányzó függőség egy résznél (pl. nincs ptyxis/zenity, nincs gnome-shell, nincs python3-gi, nincs `claude` vagy `codex`) → az a rész „kihagyva: <ok>”, a többi települ, a kilépési kód ezt megkülönböztethetően jelzi (0: minden kész, 1: hiba, 3: volt kihagyott rész).
  - E3: nincs olyan hőérzékelő, amit a `hofigyelo.py` ismer (k10temp, ACPI-zóna, nvidia-smi) → a hőfigyelő „kihagyva: nincs ismert hőérzékelő”, hacsak a user nem kéri kifejezetten (`--csak hofigyelo`), akkor figyelmeztetéssel települ.
  - E4: részleges telepítés: `--csak <rész,...>` és `--kihagy <rész,...>`; ismeretlen rész neve → hiba, a lehetséges nevek felsorolásával, semmi nem fut.
  - E5: ismételt futtatás → semmi nem duplikálódik (horgok, dokk, egységek), a már kész rész „már megvolt”; a futó szolgáltatás csak akkor indul újra, ha az egysége változott.
  - E6: más klónhelyről futtatva (pl. egy régi klón után innen) → a horgok és az egységek útvonala az új helyre íródik át, régi bejegyzés nem marad.
  - E7: eltávolítás: `sh telepit.sh --eltavolitas [--csak ...]` → a szolgáltatások leállnak és törlődnek, a repóhoz tartozó horgok kikerülnek a settings.json-ból (mentéssel), a dokkból az indító kikerül, a Ptyxis-profilok a `szinprofil.py eltavolit`-tal; más bejegyzéshez nem nyúl.
  - E8: szóközös klónútvonal (`~/AI PROJECTS/cli-add-ons`) → minden rész működik.
- Elfogadási feltételek:
  1. A `hofigyelo/` kap saját `install.sh`-t (egység sablonból, útvonal a szkript helyéből, `-I` kapcsolóval; horgok a mostani szerkezettel), a többi rész a meglévő telepítőjét használja; a gyökér `telepit.sh` csak sorrendet, kapcsolókat és összesítést kezel.
  2. E1-E8 mindegyikére automatikus teszt, ideiglenes `HOME`-mal és álparancsokkal (systemctl, gsettings, ptyxis, zenity, gnome-shell, nvidia-smi); a valódi `~/.claude`, `~/.config` és gsettings nem változhat a tesztektől. Egy paranccsal fut, kilépési kód 0.
  3. Minden új tesztnek van szándékosan hibás változata, amelyre piros; a T01/T02 tesztjei és hibás változatai (`kontextus-ikon/tests/run_all.sh`, `mutants.sh`) továbbra is zöldek, illetve pirosak.
  4. A settings.json írása mindig mentéssel és atomikusan történik, és a repón kívüli horgokat érintetlenül hagyja (teszt igazolja egy idegen horoggal).
  5. Root nem kell; ha egy függőség csak csomagtelepítéssel pótolható, a kimenet a `pkexec apt install ...` parancsot javasolja, de nem futtatja.
  6. Valódi próba ezen a gépen **csak szárazon**: `sh telepit.sh --szaraz` kiírja, mit csinálna, és semmit nem ír; a zárójelentés idézi a kimenetet. Éles futtatás ezen a gépen nincs (a hőfigyelő egysége a mostani `/data/cli-add-ons` útvonalra mutat, a szkript helye `~/AI PROJECTS/cli-add-ons` szimlinken át ugyanaz; ezt a zárójelentés kezelje: az E6 ne írja át feleslegesen).
  7. A gyökér `README.md` „Telepítés másik gépre” szakasza: klónozás, egy parancs, a részek listája, a kilépési kódok, az eltávolítás, és hogy utána ki- és bejelentkezés kell (GNOME-bővítmény).
- Érinthető fájlok: új `telepit.sh` (gyökér); új `hofigyelo/install.sh` és egységsablon; `kontextus-ikon/install.sh`, `kontextus-horog/install.sh`, `claude-indito/install.sh` (csak ha a közös kezeléshez kell: kilépési kód kihagyásnál, eltávolító kapcsoló, `--szaraz`); `README.md`, `hofigyelo/README.md`; új tesztek a `tests/` (gyökér) alatt; máshoz nem nyúlhat.
- Útvonal-megkötés: a `hofigyelo.py`, `hofigyelo_horog.py`, `keretfigyelo.py`, `statusline.py` és a GNOME-bővítmény kódja nem változhat. A `~/.codex` alá nem írhat, az `auth.json`-t nem olvashatja. A globális `~/.claude/CLAUDE.md` gépspecifikus szabályait (Chrome-korlát, hőfigyelő) nem telepíti.
- Nincs benne: a `mappak.txt` gépenkénti tartalma (a nem létező mappákat az indító már most kihagyja); csomagok telepítése; a GNOME Shell újraindítása; commit és push; éles futtatás ezen a gépen.
- Szükséges kapuk: tesztek zöldek, hibás változatok pirosak, `sh -n` és `shellcheck` (ha telepítve van) minden új shell-fájlon, `python3 -m py_compile` a python-részeken.
- Függ: T02 · Méret: egy kontextusba fér.
- Nyitott kérdés, amely érinti: nincs.
