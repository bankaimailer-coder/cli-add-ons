# Hőfigyelő

Túlmelegedés elleni védelem az ASUS Vivobook Pro 15 M6500QC-hez (Ryzen 7 5800H + RTX 3050 Laptop), kódoló ügynököknek.

## Részei

- `hofigyelo.py`: felhasználói szolgáltatás (`hofigyelo.service`). 5 másodpercenként méri a CPU-t (k10temp Tctl), a laptop ACPI-zónáját és az NVIDIA GPU-t. A GPU-t csak akkor kérdezi le, ha az amúgy is ébren van. Számolja a Puppeteer-Chrome-okat is.
- `hofigyelo_horog.py`: Claude Code horog (PreToolUse/Bash, PostToolUse, UserPromptSubmit) a `~/.claude/settings.json`-ban.

## Szintek

A szint a 30 másodperces medián alapján változik, és csak a kilépési küszöb alatt csökken.

| Szint | CPU belépés / kilépés | GPU belépés / kilépés | Mi történik |
|---|---|---|---|
| warm | 92 / 88 °C | 88 / 84 °C | Az ügynökök figyelmeztetést kapnak, és értesítés jelenik meg az asztalon. |
| hot | 95 / 91 °C | 95 / 91 °C | Az ügynökök felszólítást kapnak a futások leállítására; új Chrome, build és nehéz teszt indítása tiltva. Az energiamód balanced lesz. |
| critical | 99 / 94 °C | 98 / 93 °C | Az energiamód power-saver lesz, és a Puppeteer-Chrome-ok ideiglenesen szünetelnek (SIGSTOP). |

- A szünetelő Chrome-ok lehűlés után automatikusan folytatódnak (SIGCONT).
- Ha a szint visszaesik ok vagy warm szintre, visszaáll az eredeti energiamód.
- Szinttől függetlenül tiltva van új Chrome indítása, ha már 6 Puppeteer-Chrome fut (Red Lane limit).

## Gyártói határértékek

- **CPU Tjmax:** 105 °C (AMD).
- **Laptop firmware (ACPI THRM):** passzív hűtés 101 °C-nál, kritikus leállás 103 °C-nál.
- **GPU VBIOS** (`nvidia-smi -q -d TEMPERATURE`): célhőmérséklet 87 °C, lassítás 97 °C, leállás 100 °C.
- **A ryzenadj-profil korlátja:** performance módban a CPU legfeljebb 90 °C-ra melegedhet.

## Napló

A hőmérséklet-előzmények a `~/.local/state/hofigyelo/hofok-ÉÉÉÉ-HH-NN.csv` fájlba kerülnek. A program minden sort azonnal lemezre ír (fsync), így egy hirtelen leállás után is látszik, milyen meleg volt előtte.

## Telepítés

`sh hofigyelo/install.sh` (vagy a repó gyökeréből a közös `sh telepit.sh`). Root nem kell.

- Az egységet a `hofigyelo.service.in` sablonból tölti ki (`ExecStart=<python3> -I <a klón>/hofigyelo/hofigyelo.py`),
  és a `~/.config/systemd/user/hofigyelo.service` fájlba írja; bekapcsolja és elindítja. Újraindítás csak akkor
  van, ha az egység változott.
- A három horgot (PreToolUse/Bash, PostToolUse, UserPromptSubmit; `python3 -I <a klón>/hofigyelo/hofigyelo_horog.py`,
  5 mp időkorláttal) a `~/.claude/settings.json`-ba írja, mentéssel (`settings.json.backup-<idő>`) és atomikusan;
  a többi horoghoz nem nyúl, a kettőzött bejegyzést kiveszi.
- Ha nincs ismert hőérzékelő (k10temp, ACPI-zóna, nvidia-smi), kihagyja (kilépési kód 3);
  `--erzekelo-nelkul` kapcsolóval figyelmeztetéssel mégis telepít.
- Ha a meglévő egység vagy horog ugyanerre a fájlra mutat más írásmóddal (szimlinken át), meghagyja; ha egy másik
  klónra, átírja erre.
- `--szaraz`: csak kiírja, mit tenne.

## Kezelés

- **Állapot:** `systemctl --user status hofigyelo` és `cat $XDG_RUNTIME_DIR/hofigyelo/state.json`.
- **Kikapcsolás és eltávolítás:** `sh hofigyelo/install.sh --eltavolitas`: leállítja, kikapcsolja és törli az
  egységet, és kiveszi a hőfigyelő horgait a `~/.claude/settings.json`-ból (mentéssel). A naplót
  (`~/.local/state/hofigyelo/`) meghagyja.
