# Átadó (2026-11-15): T03 Közös telepítő, kódoló (a kapuig zárva, review előtt)
- Feladatlap: docs/feladatok/T03-kozos-telepito.md · Ág: feat/keretmerok · Alap-commit: eeb78bf (a T03 változásai commit nélkül) · Review: még nincs

## Mi készült
- `telepit.sh` (új, gyökér): csak a sorrendet, a kapcsolókat és az összesítést kezeli. Öt rész ebben a sorrendben: `kontextus-ikon`, `keretfigyelo`, `kontextus-horog`, `hofigyelo`, `claude-indito` (eltávolításkor fordított a sorrend). Kapcsolók: `--szaraz`, `--eltavolitas`, `--csak a,b`, `--kihagy a,b` (`=`-s alakban is). Ismeretlen részre vagy kapcsolóra exit 1, kiírja a lehetséges neveket, és semmi nem fut. A végén tábla: rész, eredmény (települt / települne / már megvolt / kihagyva / nem futott / eltávolítva / eltávolítaná / nem volt / HIBA), ok. Kilépési kód: 0, 1 vagy 3. A részek a `TELEPIT_EREDMENY` fájlba jelzik, hogy változott-e valami (`valtozott`), vagy mi miatt maradtak ki (`kihagyva<TAB>ok`). `--csak hofigyelo` esetén a hőfigyelő `--erzekelo-nelkul` kapcsolót kap.
- `hofigyelo/install.sh` és `hofigyelo/hofigyelo.service.in` (új). Az egység a sablonból készül: `ExecStart=<command -v python3> -I <klón>/hofigyelo/hofigyelo.py`. Idézés csak akkor kerül bele, ha kell, így a gépen kézzel írt egység szövegre is egyezik. A három horog a mostani szerkezettel kerül be: PreToolUse/`Bash`, PostToolUse/`*`, UserPromptSubmit matcher nélkül, mindegyik `python3 -I …/hofigyelo_horog.py`, timeout 5. A kettőzött bejegyzést kiveszi. Más klón útvonalát átírja. Ha a meglévő bejegyzés ugyanarra a fájlra mutat (realpath), az írásmódot meghagyja. Érzékelő: hwmon `k10temp`/`acpitz` vagy `nvidia-smi`; ha egyik sincs, kihagyja (exit 3), `--erzekelo-nelkul` mellett figyelmeztetéssel telepít. További kapcsolók: `--eltavolitas`, `--szaraz`.
- `kontextus-ikon/install.sh`: új kapcsolók: `--figyelo-nelkul`, `--eltavolitas` (symlink, bekapcsolás, autostart, statusline, és `--figyelo-nelkul` nélkül a keretfigyelő), `--szaraz`. A kapcsolók feldolgozása ciklusba került. A gnome-shell hiánya mostantól kihagyás (exit 3); eddig csak figyelmeztetett. A python3-gi hiánya is kihagyás, `pkexec apt install python3-gi` javaslattal (eddig `exit 1` és `sudo`-javaslat volt). A keretfigyelő kimarad, ha nincs se `claude`, se `codex`. Írásmód-átvétel: ha a symlink, az egység vagy az autostart ugyanarra a mappára mutat, annak az írásmódja marad. A symlinket és a statusline-t realpath alapján veti össze; régi klónból jövő statusline-útvonalat átír, idegen statusline-hoz nem nyúl. A T02 mutánsainak mintái változatlanul illeszkednek.
- `kontextus-horog/install.sh`: új kapcsolók: `--eltavolitas`, `--szaraz`. Realpath-összevetés, a kettőzött bejegyzés kivétele, `claude` nélkül kihagyás (exit 3). Hibás JSON-nál exit 1, és nem írja felül a fájlt. A horgot most a `/kontextus-horog/kontextus_horog.py` végződés azonosítja (eddig csak a fájlnév).
- `claude-indito/install.sh`: új kapcsolók: `--eltavolitas` (az indító törlése, kivétel a dokkból, `szinprofil.py eltavolit`) és `--szaraz` (a színprofiloknál csak a `szinprofil.py lista`-t futtatja). A függőségek (zenity, ptyxis, gsettings, python3, claude) hiányát egyszerre jelzi, kihagyással (exit 3) és `pkexec apt install …` javaslattal. Az indítófájlt csak változás esetén írja újra, írásmód-átvétellel. A dokk listáját Pythonban szerkeszti; ez az üres listát is helyesen kezeli, a korábbi sed `[, '…']`-t adott.
- A settings.json-t mindhárom író rész ugyanúgy írja: mentés (`settings.json.backup-<idő>`, és ha ilyen nevű már van, `-1`, `-2` … utótag), majd ideiglenes fájl, fsync, copymode, `os.replace`.
- `README.md`: „Telepítés másik gépre” szakasz (klónozás, egy parancs, a részek táblája, kilépési kódok, eltávolítás, ki- és bejelentkezés, tesztparancsok), valamint a hőfigyelő a listában. `hofigyelo/README.md`: Telepítés szakasz; a Kezelés szakasz az `--eltavolitas`-ra hivatkozik.
- `tests/telepit_teszt.sh` (új): 108 ellenőrzés. Minden eset saját ideiglenes HOME-mal fut, `env -i`-vel. A PATH egyetlen ideiglenes bin-mappa: valódi alapeszközök szimlinkjei, mellettük álparancsok (systemctl, gsettings, dconf, gnome-shell, zenity, ptyxis, claude, codex, nvidia-smi, pkexec). A hwmon is álmappa. A klón szóközös, ékezetes útvonalon áll.
- `tests/mutants.sh` (új): 87 hibás változat.

## Lefedett esetek → teszt
- E1: „E1 teljes telepítés…”, „E1 összesítő…”, „E1 hőfigyelő-egység…” (python -I, idézés, sablonsorok, systemd-analyze verify), „E1 hőfigyelő horgai a mostani szerkezettel…”, „E1 kontextus-horog…”, „E1 statusline…”, „E1 bővítmény…”, „E1 automatikus indítás…”, „E1 keretfigyelő-egység…”, „E1 indító és dokk”, „E1 Ptyxis-színprofil…”, „E1 systemctl…”, „E1 a végén: ki- és bejelentkezés kell”.
- E2: „E2 nincs zenity/ptyxis…” (5 teszt, köztük a pkexec-javaslat és az, hogy a pkexec nem fut), „E2 nincs gnome-shell…” (3), „E2 nincs python3-gi…” (a gi-t egy PYTHONPATH-on elhelyezett ál-csomag takarja), „E2 nincs claude és codex…” (5), „E2 hibás settings.json…” (exit 1, a fájl érintetlen).
- E3: „E3 nincs hőérzékelő…” (2), „E3 --csak hofigyelo: figyelmeztetéssel települ…”, „E3 csak nvidia-smi…”, „E3 csak ACPI-zóna…”.
- E4: „E4 --csak…” (3), „E4 --kihagy…” (2), „E4 ismeretlen rész…” (2), „E4 ismeretlen rész a --kihagy-ban is hiba”, „E4 ismeretlen kapcsoló…”.
- E5: „E5 második futás…”, „E5 a settings.json nem változott…”, „E5 nincs új mentés”, „E5 az egységek és az indítófájlok nem íródtak újra”, „E5 nincs kettőzött horog”, „E5 a dokkban és a bővítmények közt egyszer”, „E5 változatlan egységnél start, nem restart”, „E5 megváltozott egység…” (3), „E5 kézzel kettőzött horog: a fölösleg kikerül”.
- E6: „E6 új klónhely…” (4: a régi útvonal sehol nem marad, a horgok és az egységek az új helyre mutatnak, restart). „E6 szimlinken át…” és „E6 a valódi útvonalról…”, „E6 szárazon…” (7): a gép mostani helyzetét másolja le. A hőfigyelő egysége és horgai idézőjel nélkül, a valódi útvonallal vannak bejegyezve. Szimlinken át futtatva sem írja át őket, a valódi útvonalról futtatva mind az öt rész „már megvolt”.
- E7: „E7 szárazon…” (2), „E7 eltávolítás…”, „E7 a szolgáltatások leállnak és törlődnek”, „E7 a repó horgai és statusline-ja kikerül”, „E7 az idegen horgok és kulcsok megmaradnak”, „E7 az eltávolítás is ment…”, „E7 dokk…”, „E7 Ptyxis-profilok törölve…”, „E7 bővítmény…”, „E7 második eltávolítás…” (2), „E7 --eltavolitas --csak hofigyelo…” (2).
- E8: „E8 szóközös útvonal…” (3). Ezen felül minden eset szóközös, ékezetes klónból fut.
- 4. feltétel: „4. feltétel: …” (3 a teljes telepítésre). Részenként külön is, kontextus-ikon, kontextus-horog és hofigyelo mindegyikére 4 teszt: az eredeti mentése megvan; a korábbi mentést nem írja felül (31 előre létrehozott „régi mentés”); az idegen horgok és kulcsok érintetlenek, nincs ideiglenes fájl; eltávolítás után is érintetlenek.
- 6. feltétel, szárazfutás: „szárazfutás: …” (3: exit 0, „települne”, semmit nem ír, nem indít).
- Őrző ellenőrzések: „a valódi ~/.claude, ~/.config egységei és a gsettings nem változtak” (sha256 és `gsettings get`, csak olvasás), „a valódi ~/.codex alá nem írt”.

## Ellenőrzések ebben a munkamenetben
- `bash tests/telepit_teszt.sh`: kilépési kód 0, 108 ok, „MIND ZÖLD”, kb. 10 mp.
- `bash tests/mutants.sh`: kilépési kód 0. 87 változat, mind piros. A 108 tesztből 106 legalább egy változatra elbukik; a 2 őrző ellenőrzés szándékosan kivétel (lásd „Eltérések”).
- `bash kontextus-ikon/tests/run_all.sh`: kilépési kód 0 (gjs 30, python 29, telepítő 15; „MIND ZÖLD”).
- `bash kontextus-ikon/tests/mutants.sh`: kilépési kód 0 (bővítmény 30, python+telepítő 47 változat, mind piros, minden teszt elbukik legalább egyre). A T02 I1–I10 változatai a módosított `kontextus-ikon/install.sh`-n is létrejöttek és pirosak.
- `sh -n` a telepit.sh, hofigyelo/install.sh, kontextus-ikon/install.sh, kontextus-horog/install.sh és claude-indito/install.sh fájlon: mind 0. `bash -n tests/telepit_teszt.sh`, `bash -n tests/mutants.sh`: 0.
- `shellcheck`: nincs telepítve, nem futott.
- `python3 -m py_compile` a négy telepítőből kimásolt öt beágyazott Python-blokkon (scratchpad): mind 0.
- `sh telepit.sh --szaraz` ezen a gépen: kilépési kód 0. Előtte és utána összevetettem a sha256-ot (settings.json, a ~/.config egységei, autostart, indító), a `gsettings get` favorite-apps és enabled-extensions értékét és a mentések számát: változatlan (`cmp` 0). A `/home/bfuzzee/AI PROJECTS/cli-add-ons` és a `/data/cli-add-ons` útvonalról futtatva is ugyanez az összesítő:
  ```
  rész            eredmény      ok
  kontextus-ikon   már megvolt
  keretfigyelo     már megvolt
  kontextus-horog  már megvolt
  hofigyelo        már megvolt
  claude-indito    már megvolt
  ```
  A részletes kimenetben csak „kész: … (már megvolt)” sorok vannak, és három „tenné:” sor: `systemctl --user enable, start` a két szolgáltatásra („ha fut, nem indul újra”), valamint `szinprofil.py telepit` (idempotens, ezért nem számít változásnak). A hőfigyelő egysége és horgai a `/data/cli-add-ons` írásmóddal maradnak, a többi bejegyzés a `~/AI PROJECTS` írásmóddal. Egyiket sem jelzi átírandónak (realpath-összevetés és írásmód-átvétel).

## Nincs kész vagy nincs ellenőrizve
- Éles futtatás sehol nem volt; ezen a gépen tilos. A valódi systemd-, gsettings-, dconf- és Ptyxis-viselkedést csak álparancsok helyettesítették.
- A `szinprofil.py telepit` valódi gsettings mellett idempotens; ezt csak a kódból olvastam ki, nem mértem. A teszt az álgsettings-szel futtatja.
- shellcheck nem futott (nincs telepítve).
- Állapotnapló (`docs/allapot/`) nem készült, döntésnapló-sor sem: a megbízás csak a kódoló-átadót kérte.

## Gyengített ellenőrzés
nincs. T01/T02 teszthez és elvárásához nem nyúltam.

## Eltérések a feladatlaptól
- Részek: a feladatlap „öt részt” említ. Ezek így lettek: kontextus-ikon (keretmérők és CPU/GPU-hőmérő a bővítményben), keretfigyelo, kontextus-horog, hofigyelo, claude-indito (terminálszínek). A keretfigyelő azért lett külön rész, hogy külön kihagyható legyen; ehhez kellett a `kontextus-ikon/install.sh --figyelo-nelkul`.
- Ismeretlen rész vagy kapcsoló esetén a kilépési kód 1, mert a feladatlap csak a 0, 1 és 3 kódot sorolja fel. A részek saját telepítői ismeretlen kapcsolóra továbbra is 2-vel lépnek ki (T02-viselkedés).
- Függőség-hozzárendelés (a feladatlap példáiból következtetve, nem kimondott szabály): kontextus-horog → `claude`; keretfigyelo → `claude` vagy `codex`; claude-indito → zenity, ptyxis, gsettings, python3, `claude`; kontextus-ikon → gnome-shell, python3-gi; hofigyelo → systemctl és érzékelő. A hőfigyelő `claude` nélkül is települ.
- A két őrző ellenőrzésre nincs hibás változat. Csak olyan változat buktatná el őket, amely a valódi HOME-ba ír, ezért a `tests/mutants.sh` a `GUARDS` listában név szerint kiveszi őket a „minden teszt bukjon” követelmény alól.
- A meglévő telepítőkben a feladatlap által engedett kilépési kódon, eltávolító kapcsolón és `--szaraz`-on túl ez is változott: realpath-összevetés és írásmód-átvétel (az E6-hoz és a 6. feltételhez kell), mentés ütközés nélkül, a dokk-lista Pythonban, hibás JSON-nál HIBA. Indok: a közös futásban több rész ugyanabban a másodpercben ír, ezért a korábbi, másodperc pontosságú mentésnév felülírta volna az eredetit; az E6/6. feltétel pedig enélkül nem teljesülne.

## Nyitott
- A settings.json írásának logikája három helyen áll: kontextus-ikon/install.sh, kontextus-horog/install.sh, hofigyelo/install.sh. A közös segédfájl nem szerepelt az érinthető fájlok között. Ha egy helyre kell, az új feladat.
- A keretfigyelő egységébe a telepítéskori PATH kerül (T02). Ha a telepit.sh más PATH-szal fut, mint az eredeti telepítés (például nem Claude Code-terminálból), az egység „változott” lesz, és a szolgáltatás újraindul. Ezen a gépen a mostani PATH egyezett.
- A `kontextus-ikon` eltávolítása a GNOME-bővítményt kikapcsolja és a symlinket törli, de a futó `kontextus_ikon.py` háttérfolyamatot nem állítja le; kijelentkezésig fut.
- A hőfigyelő eltávolítása a naplót (`~/.local/state/hofigyelo/`) és a `$XDG_RUNTIME_DIR/hofigyelo/state.json`-t meghagyja.
- A régi `hofigyelo/README.md` a `settings.json.bak-hofigyelo` mentést említette; a szöveget az új mentésnévre írtam át, a régi fájlhoz nem nyúltam.

## Megjegyzés
A valódi próba helye élesítés után: `sh telepit.sh` (ezen a gépen mind „már megvolt” lesz, a két szolgáltatás `start`-ot kap, újraindítás nélkül), majd egy másik gépen klónozás után `sh telepit.sh`, utána ki- és bejelentkezés.

## Bemásolandó indító prompt
~~~text
HATÓKÖR: T03 review a /data/cli-add-ons repóban (ág: feat/keretmerok): telepit.sh, hofigyelo/install.sh, hofigyelo/hofigyelo.service.in, kontextus-ikon/install.sh, kontextus-horog/install.sh, claude-indito/install.sh, README.md, hofigyelo/README.md, tests/.
KIZÁRVA: éles telepítés ezen a gépen; a valódi ~/.claude, ~/.config, gsettings, systemd módosítása; ~/.codex/auth.json; commit, push.

Olvasd el: MUNKAREND.md, docs/atado/2026-11-15-T03-kodolo-atado.md, docs/feladatok/T03-kozos-telepito.md.
Állapot: a T03 a kapuig zárva, commit nélkül; alap: eeb78bf.
Következő lépés: független review a diffről (hibautak: ismételt és félbeszakadt futás, idegen settings.json-tartalom, szimlinkes útvonal).
Kész, ha: bash tests/telepit_teszt.sh és bash tests/mutants.sh 0, bash kontextus-ikon/tests/run_all.sh és mutants.sh 0, sh telepit.sh --szaraz mind „már megvolt”.
A végén írj átadót ugyanebben a formában.
~~~

## 1. javítókör
A review: `docs/review/T03/r1.md`. A megbízó kérésére sima `mv`-vel került ide a `docs/review/2026-11-15-T03-review.md` helyéről; a tartalmán nem változtattam. A találatok zárását („Zárás:”) itt javaslom, a reviewer fogadja el.

- R1-1 (GNOME nélkül a statusline sem települt): javítva. A `kontextus-ikon/install.sh` a gnome-shell vagy a python3-gi hiányát nem kezeli többé kihagyásként a lépések előtt. Ilyenkor csak a bővítmény, a bekapcsolás, az automatikus indítás és a háttérfolyamat marad ki („kimarad: …”). A statusline (és a keretfigyelő) települ. A rész végül exit 3-mal lép ki, okkal: „nincs gnome-shell …; a bővítmény és az automatikus indítás kimaradt, a statusline települt”. Külön rész nem lett belőle. Tesztek: „R1-1 nincs gnome-shell: a statusline települ, az automatikus indítás kimarad”, „R1-1 … a statusLine a settings.json-ban”, „R1-1 … a bővítményt nem kapcsolja be”. Mutánsok: KI21, KI22, az új mintára átírt KI1 és KI2.
- R1-2 (a szimlinkelt settings.json helyére sima fájl került): javítva mindhárom írónál (`kontextus-ikon`, `kontextus-horog`, `hofigyelo`). Írás előtt `path = os.path.realpath(path)`, így a mentés, az ideiglenes fájl és a csere a célfájl mellett történik, a szimlink megmarad. Tesztek: a részenkénti 4. feltétel-ciklus mindhárom részre szimlinkelt settings.json-nal fut („R1-2 <rész> egyedül: a szimlink megmarad, a célfájl kapja a bejegyzést”, „… eltávolítás után is érintetlenek, a szimlink marad”). Mutánsok: KI26, K10, H32.
- R1-3 (üres `--csak`/`--kihagy` lista): javítva. Ha a kapcsoló szerepelt, de a listában nincs név, a válasz `hiba "a --csak listája üres"`, exit 1, és semmi nem fut. Tesztek: „R1-3 üres részlista (--csak ,)”, „(--csak=)”, „(--kihagy=,,)”, „(--kihagy "")”. Mutánsok: T19, T20.
- R1-4 (`$`, backtick vagy `"` jel a klón útvonalában): a megbízó szerint nem kell javítani. A README „Telepítés másik gépre” szakaszába bekerült a mondat: a klón útvonala ne tartalmazzon `$`, `` ` `` vagy `"` karaktert.
- R1-5 (az atomikusságot nem bizonyította teszt): javítva. A ciklus nézi, hogy a célfájl inode-ja megváltozik-e („R1-5/R1-6 <rész> egyedül: atomikus csere (új inode), az eredeti jog (0640) megmarad”). Mutánsok közvetlen `open(path, "w")` írással: KI27, K11, H33, mind pirosak.
- R1-6 (az ideiglenes fájl az umask szerinti joggal jött létre): javítva. Az ideiglenes fájl `os.open(…, O_WRONLY|O_CREAT|O_EXCL, 0o600)`-val jön létre, és az eredeti jogot (`os.chmod`) csak a csere előtt kapja meg. Új fájl 0600-zal jön létre; ez eltérés a korábbi umask szerinti 0664-től. Teszt: ugyanaz az R1-5/R1-6 ellenőrzés (0640 megmarad). Mutáns: H34 (chmod nélkül). Hogy az ideiglenes fájl a létrehozás pillanatában 0600-as, az csak olvasva igazolt; a teszt nem tudja elkapni a köztes állapotot.
- R1-7 (az egység pythonja szövegesen volt összevetve): javítva. A `hofigyelo/install.sh` a meglévő ExecStart pythonját realpath szerint veti össze; ha ugyanaz a fájl, a meglévő írásmód marad. A `/usr/bin/python3` előnyben részesítése nem készült el; a megbízás csak a realpath-összevetést kérte. Teszt: az E6 szimlinkes esetben az előre megírt egység pythonja most egy másik szimlinken át mutat ugyanarra a pythonra (`$E/alt/python3`), és „E6 szimlinken át: a hőfigyelő egysége és horgai érintetlenek”. Mutáns: H30.
- R1-8 (gsettings séma nélkül HIBA lett): javítva. Új `gnome_sema()` ellenőrzés: `gsettings list-keys org.gnome.shell`. A claude-indito telepítése séma nélkül kihagyás („nincs GNOME Shell-séma (org.gnome.shell)”). Eltávolításkor a dokk kimarad, a `szinprofil.py eltavolit` viszont a sémától függetlenül lefut. Ha a szinprofil.py hibát ad, az figyelmeztetés, nem HIBA. A kontextus-ikon eltávolítása és bekapcsolási lépése is a sémát ellenőrzi. Az álgsettings `nosema` jelzőfájllal a séma hiányát utánozza. Tesztek: „R1-8 gsettings van, GNOME Shell-séma nincs: exit 3, nincs HIBA”, „R1-8 séma nélkül: az indító kihagyva, okkal”, „R1-8 séma nélküli eltávolítás: exit 0, nincs HIBA”, „… az indító és a színprofilok törölve”. Mutánsok: KI23, C13, C14.
- R1-9 (szárazon törölte a keretfigyelo.json-t): javítva. Az `uninstall_figyelo` szárazon az `rm` előtt visszatér (`[ "$SZARAZ" = 1 ] && return 0`); élesen az `rm -f` hiányzó fájlnál nem nyúl semmihez. Teszt: „R1-9 szárazon eltávolítva sem törli a keretfigyelo.json-t”. Mutáns: KI24. A T02 I2 mutánsa továbbra is illeszkedik, és piros.
- R1-10 (a friss telepítés refreshInterval nélkül írt): javítva. A friss statusLine: `{"type": "command", "command": …, "refreshInterval": 30}`. A meglévőt nem írja felül; más klónhelyről csak a `command` íródik át. Tesztek: „E1 statusline beállítva, refreshInterval 30-cal”, „R1-10 új klónhely: a statusline útvonala átíródik, a meglévő refreshInterval (10) marad”. Mutánsok: KI25, KI20.
- R1-11 (python3 nélkül a hőfigyelő eltávolítása semmit nem bontott): javítva. Eltávolításkor az egység python nélkül is lebomlik (disable --now, törlés, daemon-reload). Csak a horgok kivétele marad ki: exit 3, „nincs python3: a szolgáltatás lebontva, a horgok kivétele kimaradt”. Tesztek: „R1-11 python3 nélkül: az egység leállítva és törölve”, „… kihagyva, okkal …, exit 3”. Mutáns: H31.

Kapuk a javítás után (ebben a munkamenetben futottak):
- `bash tests/telepit_teszt.sh`: kilépési kód 0, 132 ok, „MIND ZÖLD”.
- `bash tests/mutants.sh`: kilépési kód 0. 106 változat, mind piros; a 2 őrzőn kívül minden teszt elbukik legalább egyre.
- `bash kontextus-ikon/tests/run_all.sh`: kilépési kód 0. `bash kontextus-ikon/tests/mutants.sh`: kilépési kód 0 (bővítmény 30, python+telepítő 47 változat). Azért futott újra, mert az `uninstall_figyelo` változott.
- `sh -n` az öt telepítőn: mind 0. `bash -n` a két tesztszkripten: 0. `py_compile` az öt beágyazott Python-blokkon: 0. shellcheck továbbra sincs telepítve.
- Ezen a gépen `sh telepit.sh --szaraz` futott a `~/AI PROJECTS` és a `/data` útvonalról is, valamint `sh telepit.sh --szaraz --eltavolitas`: mindhárom exit 0. Telepítésnél mind az öt rész „már megvolt”, eltávolításnál mind „eltávolítaná”. Előtte és utána összevetettem: sha256 (settings.json, a ~/.config egységei, autostart, indító), a settings.json jogai, a gsettings (favorite-apps, enabled-extensions, Ptyxis profile-uuids), a mentések száma és a keretfigyelo.json. Az állapot változatlan (`cmp` 0).
