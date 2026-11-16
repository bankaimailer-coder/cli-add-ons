# Claude kontextus-ikon

A GNOME felső sávjában mutatja a nyitott Claude Code terminálok kontextushasználatát és a memória telítettségét.

Két része van:

- `kontextus_ikon.py`: háttérfolyamat, amely 3 másodpercenként kiszámolja a nyitott Claude Code terminálok
  kontextusát, 500k tokennél értesítést küld, és D-Bus-on (`hu.bfuzzee.KontextusIkon`) átadja az adatokat.
- `gnome-extension/kontextus@kontextus-ikon`: GNOME Shell-bővítmény, amely kirajzolja:
  - a kontextusmérőket a sáv bal oldalán, az ablakválasztó után (terminálonként egy körív és a szám);
  - a jobb oldalon, a rendszerikonok (mikrofon, Wi-Fi, akku) előtt: az öt keretmérőt (Claude 5 órás, heti, Fable;
    Codex 5 órás, heti), a hőmérőt és a memória-chipet, benne a százalékkal;
  - és végrehajtja az ablakugrást („Ugrás a terminálba” a kontextusmérő menüjében).

## Telepítés

    git clone https://github.com/bankaimailer-coder/cli-add-ons.git ~/projects/cli-extensions
    sh ~/projects/cli-extensions/kontextus-ikon/install.sh

Utána egyszer ki kell jelentkezni és vissza (a GNOME-bővítmény csak bejelentkezéskor töltődik be).
Root nem kell; a klón bárhová kerülhet, a telepítő a saját helyéből számolja az útvonalakat.
Többször is futtatható, ami már be van állítva, azt nem módosítja. A telepítő:

1. ellenőrzi a függőségeket (python3, python3-gi, GNOME Shell verzió a `metadata.json`-ban);
2. symlinkeli a bővítményt a `~/.local/share/gnome-shell/extensions/` alá;
3. bekapcsolja a meglévő bekapcsolt bővítmények mellé (`org.gnome.shell enabled-extensions`);
4. megírja az automatikus indítást (`~/.config/autostart/kontextus-ikon.desktop`);
5. felveszi a statusline-t a `~/.claude/settings.json`-ba (előtte mentést készít; meglévő, eltérő statusline-t nem ír felül);
6. elindítja a háttérfolyamatot.

Amíg a bővítmény nem fut, a Python a kontextusmérőket a sáv jobb oldalán, appindicator-ikonként mutatja.

Kézi indítás (egy sor, a terminálból függetlenül fut tovább):

    setsid python3 ~/projects/cli-extensions/kontextus-ikon/kontextus_ikon.py >/dev/null 2>&1 &

Ellenőrzés ikon nélkül (kiírja, amit a kontextusmérők mutatnának):

    python3 ~/projects/cli-extensions/kontextus-ikon/kontextus_ikon.py --once

Automatikus indítás: `~/.config/autostart/kontextus-ikon.desktop` (a telepítő írja). Kikapcsolás: töröld azt a fájlt. Egyszerre csak egy példány fut; a második indítás kilép.

Kontextusmérők: csak akkor látszanak, ha fut legalább egy Claude Code terminál. Szín: `PROJECT_COLORS` szerint
(nemesventilatorhaz kék, a többi zöld), `RED_FROM` (500k) fölött piros. A menüben repó, session, állapot, tokenszám.

Subagentek: ha egy terminál sessionjének fut legalább egy subagentje, a szám után egy kisebb körív mutatja a
legnagyobb kontextusú futó subagentet (ugyanazzal a színezéssel); a menüben a futó subagentek listája látszik.
Futónak számít, amelyik `.meta.json`-jában nincs `"finished": true`, és a transcriptje `SUB_STALE_SEC` (10 perc)
óta változott.
Beállítások a `kontextus_ikon.py` elején: `PROJECT_COLORS`, `DEFAULT_COLOR`, `RED_FROM`, `GAUGE_MAX`, `KINDS`,
`POLL_SEC`, `WARN_AT`, `SUB_STALE_SEC`.

Ugrás a terminálba: a Python a session terminálfülére ideiglenes egyedi címet ír, a bővítmény előrehozza az ilyen
című Ptyxis-ablakot, majd az eredeti cím visszaáll. Ha a session egy ablak nem aktív fülén fut, az ablak nem található.

Memória-chip: mindig látszik; a használt memória (MemTotal - MemAvailable, mint a `free`) százalékban.
A rajza a `chip.js`-ben, a kontextusmérőé a `gauge.js`-ben van.

Keretmérők: öt mérő egymás mellett, mindegyik a MEGMARADT keretet mutatja. Bal oldalt a márka ikonja: a
Claude-mérőkön a Claude-csillag (narancs), a Codex-mérőkön az OpenAI-csomó (törtfehér). Az ikon alulról a
megmaradt keret arányáig teli (tele = a teljes keret megvan), a kiürült része halvány tónusban látszik, így a forma
mindig felismerhető. Mellette fent egy apró jel (`5h` = 5 órás, `H` = heti, `F` = Fable heti), alatta a megmaradt
százalék (100 − elhasznált). 25% maradék alatt az ikon kitöltése és a szám sárga, 10% alatt piros. A két csoport
között nagyobb a köz. Ha egy adat nincs meg (nincs forrás, elavult, vagy az ablak azóta visszaállt), a mérő szürke
ikon és „–”, becsült számot nem mutat. Kattintásra a menü mérőnként kiírja a százalékot („maradt 55% (elhasználva
45%)”), a visszaállás idejét (és hogy mennyi van hátra), az adat idejét, illetve a „nincs adat” okát.
15 másodpercenként frissül; a rajz (vektoros, Cairo) a `meter.js`-ben, az olvasás a `limits.js`-ben.

- Claude 5 órás és heti: a Claude Code a statusline-nak adja át (`rate_limits.five_hour` / `seven_day`, `resets_at`-tel).
  A `statusline.py` ezeket kiírja a `$XDG_RUNTIME_DIR/kontextus-ikon/keretek.json` fájlba; amelyik ablakot egy
  hívás nem kapja meg, azt a visszaállásáig megtartja. Csak akkor frissül, amikor fut Claude Code terminál.
- Claude Fable heti: a fiók `/usage` adata (`api/oauth/usage`, lásd lent), ugyanabba a fájlba. Visszaállási időt
  csak akkor mutat, ha a válasz sora tartalmaz ilyet; visszaállási idő nélkül 3 óráig érvényes.
- Codex 5 órás és heti: a Codex CLI a session-naplóba (`~/.codex/sessions/ÉÉÉÉ/HH/NN/*.jsonl`) minden
  `token_count` eseménnyel kiírja a `rate_limits` mezőt (`primary`/`secondary`: `used_percent`, `window_minutes`,
  `resets_at`). A bővítmény a legfrissebb fájlok végéből a legutolsót olvassa; az ablakot a hossza alapján
  választja (300 perc = 5 órás, 10080 perc = heti). Csak olvas, a `~/.codex` többi tartalmához (pl. `auth.json`)
  nem nyúl. Az adat a legutolsó Codex-futás pillanatképe.

Hőmérők: a keretmérők és a memória-chip között, a CPU és a GPU külön. Az ikon egy chip-foglalat (dupla keret,
oldalanként 4 láb), benne fordulatszámmérő mutatóval és jobb oldalt lánggal; a CPU-é világoslila (`#c084fc`), a
GPU-é cián (`#00ffff`). Mellette a hőmérséklet: a CPU-nál a 30 másodperces medián (ebből számol a hőfigyelő
szintje), a GPU-nál a pillanatnyi érték. A szám színe a szint: rendben fehér, meleg sárga, forró és kritikus piros.
Egy mérő csak akkor színeződik, ha a saját értéke is eléri a szint kilépési küszöbét (a `hofigyelo.py`
`CPU_TH`/`GPU_TH` értékei), így a hűvösebb eszköz nem pirosodik a másik miatt. A menüben a részletek (CPU: medián,
pillanatnyi, ACPI; GPU: érték), a szint és az állapotfájl időbélyege. Forrás: a `hofigyelo.service` állapotfájlja
(`$XDG_RUNTIME_DIR/hofigyelo/state.json`, csak olvasás); ha hiányzik vagy 30 másodpercnél régebbi, mindkét mérő
szürke „–”. Ha a GPU alszik (nincs `gpu_c`), a GPU-mérő marad a helyén, „nincs adat” állapotban. 5 másodpercenként
frissül; az ikon vektoros (Cairo), a panelmérethez és a HiDPI-hez skálázódik.

CLI-sor: a `statusline.py` (a `~/.claude/settings.json` `statusLine` bejegyzése, így minden Claude Code terminálban)
kiírja az 5 órás és a heti keret kihasználtságát, mindkettő mellé a Fable 5.2 becsült részét, pl.
„5 órás: 18% (ebből Fable 5.2: ~12%) | heti: 83% (ebből Fable 5.2: ~23%)”. A zárójeles szám azt mutatja, hogy a
keret felhasznált százalékából mennyi ment Fable 5.2-re.

A fiók Fable heti keretét a statusline a `/usage` mögötti végpontról kéri le (`api/oauth/usage`, a CLI saját
OAuth-tokenjével, 2 perces gyorsítótár: `~/.cache/claude-account-usage.json`), és „Fable heti: N%” formában írja ki.
A becslés csak akkor jelenik meg, ha ez a lekérdezés nem sikerül.

A Fable-rész becslés: külön Fable-keretet a Claude Code nem ad át, ezért a sor a gép helyi transcriptjeiből
(`~/.claude/projects`) számol. Az adott időablak modellhívásait API-listaáron súlyozza (`PRICES` a `statusline.py`
elején), és a keret százalékát a Fable arányában osztja el. Más gépen vagy a claude.ai-on elhasznált keretet nem
látja. A számítás 30 másodpercenként frissül, a gyorsítótára a `~/.cache/claude-fable-share.json`.
