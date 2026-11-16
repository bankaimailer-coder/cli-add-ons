# Hőfigyelő

Túlmelegedés elleni védelem az ASUS Vivobook Pro 15 M6500QC-hez (Ryzen 7 5800H + RTX 3050 Laptop), kódoló ügynököknek.

## Részei

- `hofigyelo.py`: felhasználói szolgáltatás (`hofigyelo.service`). 5 másodpercenként méri a CPU-t (k10temp Tctl), a laptop ACPI-zónáját és az NVIDIA GPU-t. A GPU-t csak akkor kérdezi le, ha az amúgy is ébren van. Számolja a Puppeteer-Chrome-okat is.
- `hofigyelo_horog.py`: Claude Code horog (PreToolUse/Bash, PostToolUse, UserPromptSubmit) a `~/.claude/settings.json`-ban.

## Telepítés

    sh ~/projects/cli-extensions/hofigyelo/install.sh

Root nem kell, többször is futtatható. A telepítő megírja és elindítja a felhasználói szolgáltatást
(`~/.config/systemd/user/hofigyelo.service`, bejelentkezéskor magától indul), és bejegyzi a horgokat a
`~/.claude/settings.json`-ba (előtte mentést készít). A `--horog-nelkul` kapcsolóval csak a szolgáltatás települ;
a felső sáv hőmérőihez ennyi elég. AMD processzoron a `k10temp`, Intelen a `coretemp` érzékelőből olvas.

A küszöbök a fenti ASUS géphez készültek; más gépen a `hofigyelo.py` elején a `CPU_TH` és a `GPU_TH` állítható.

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

## Kezelés

- **Állapot:** `systemctl --user status hofigyelo` és `cat $XDG_RUNTIME_DIR/hofigyelo/state.json`.
- **Kikapcsolás:** `systemctl --user disable --now hofigyelo`, és töröld a horgokat a `~/.claude/settings.json`-ból. A telepítő mentése: `settings.json.backup-ÉÉÉÉHHNN-ÓÓPPMM`.
