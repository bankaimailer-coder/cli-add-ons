# CLI add-ons

Kiegészítők a Claude Code CLI-hoz Ubuntu GNOME alatt.

- [`kontextus-ikon`](kontextus-ikon/): a nyitott Claude Code terminálok kontextushasználata a felső sávban
  (körív-mérők az ablakválasztó mellett), memória-chip a rendszerikonok mellett, ugrás a terminálba,
  és egy statusline, amely minden CLI alján kiírja az 5 órás és a heti keret kihasználtságát.

Telepítés: lásd [`kontextus-ikon/README.md`](kontextus-ikon/README.md#telepítés).

- [`claude-indito`](claude-indito/): dokkba tűzött ikon, amely választóablakból indítja a Claude Code-ot
  a kiválasztott munkamappában (új beszélgetés vagy folytatás).
- [`kontextus-horog`](kontextus-horog/): Claude Code hook, amely méri a kontextust (alügynökökben is), és 500k-nál
  soft stopot, 600k-nál erős stopot kér; a telepítője minden gépen bejegyzi.
- [`hofigyelo`](hofigyelo/): túlmelegedés elleni védelem: CPU/GPU-hőmérséklet figyelése systemd felhasználói
  szolgáltatásként, és Claude Code horgok, amelyek melegedéskor figyelmeztetik, forróságnál visszafogják az ügynököket.

## Telepítés másik gépre

```sh
git clone <a repó címe> ~/cli-add-ons     # bármilyen hely jó, szóközös útvonal is
sh ~/cli-add-ons/telepit.sh
```

A klón útvonala ne tartalmazzon `$`, `` ` `` vagy `"` karaktert (a horgok parancsa ezeket nem idézi helyesen).

Egy parancs mindent feltesz, ami az adott gépen működni tud, root nélkül, és a végén összesítő táblát ír ki
(rész, eredmény, ok). A részek, ebben a sorrendben:

| Rész | Mit tesz fel | Kell hozzá |
|---|---|---|
| `kontextus-ikon` | GNOME-bővítmény (kontextus- és keretmérők, CPU/GPU-hőmérő), memória-chip, statusline (`refreshInterval: 30`) | gnome-shell, python3-gi (a statusline nélkülük is települ) |
| `keretfigyelo` | háttérszolgáltatás: folyamatos Claude- és Codex-keretmérés | `claude` vagy `codex` |
| `kontextus-horog` | Claude Code horog: kontextusmérés, 500k/600k-s stop | `claude` |
| `hofigyelo` | hőfigyelő szolgáltatás és a három horga | systemctl, ismert hőérzékelő (k10temp, ACPI-zóna vagy nvidia-smi) |
| `claude-indito` | dokkba tűzött indító, repónkénti Ptyxis-színprofilok (terminálszínek) | zenity, ptyxis, gsettings, `claude` |

- Ha egy részhez hiányzik valami, az a rész „kihagyva” lesz az okkal együtt, a többi települ. Ha a hiány csomaggal
  pótolható, a kimenet megírja a `pkexec apt install ...` parancsot (de nem futtatja).
- Hőérzékelő nélkül a hőfigyelő csak kifejezett kérésre települ: `sh telepit.sh --csak hofigyelo` (figyelmeztetéssel).
- Részleges telepítés: `--csak kontextus-ikon,hofigyelo`, illetve `--kihagy claude-indito`. Ismeretlen résznévre
  hibát ad a lehetséges nevekkel, és semmi nem fut.
- Próba írás nélkül: `sh telepit.sh --szaraz` kiírja, mit tenne.
- Többször is futtatható: ami megvan, az „már megvolt”, semmi nem duplikálódik, és a szolgáltatás csak akkor indul
  újra, ha az egysége változott. Ha a repót máshová klónozod, és onnan futtatod, a horgok és az egységek az új
  helyre íródnak át (ha ugyanaz a mappa szimlinken át, nem ír át semmit).
- A `~/.claude/settings.json`-t mindig mentéssel (`settings.json.backup-<idő>`) és atomikusan írja, az eredeti
  jogosultsággal; ha szimlink (pl. dotfile-repóba), a célfájlt írja, a szimlink megmarad. A más eszközökhöz
  tartozó horgokhoz és beállításokhoz nem nyúl.

Kilépési kódok: `0` minden kért rész kész (vagy már megvolt), `1` hiba, `3` nem volt hiba, de valamelyik rész kimaradt.

Eltávolítás: `sh telepit.sh --eltavolitas` (vagy `--eltavolitas --csak <rész,...>`). A szolgáltatások leállnak és
törlődnek, a repó horgai és statusline-ja kikerül a settings.json-ból (mentéssel), az indító kikerül a dokkból, a
Ptyxis-profilok törlődnek (`szinprofil.py eltavolit`); más bejegyzéshez nem nyúl.

Telepítés után egyszer **ki kell jelentkezni és vissza**, hogy a GNOME-bővítmény betöltődjön.

A telepítő tesztjei (ideiglenes HOME-mal és álparancsokkal, a valódi beállítások érintése nélkül):
`bash tests/telepit_teszt.sh`; a szándékosan hibás változatok: `bash tests/mutants.sh`.
