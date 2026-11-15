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
6. elindítja a háttérfolyamatot;
7. telepíti, bekapcsolja és elindítja a keretfigyelő szolgáltatást (systemd felhasználói egység, lásd lent).

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
45%)”), a visszaállás idejét (és hogy mennyi van hátra), az adat idejét, illetve a „nincs adat” konkrét okát
(nincs napló, nincs `rate_limits`, csonka sor, olvasási hiba, hiányzó ablak). A váratlan olvasási hiba a
GNOME-naplóba is bekerül (`journalctl --user -b | grep kontextus-ikon`), ugyanaz a hiba csak egyszer.
15 másodpercenként, és az állapotfájlok (a statusline és a keretfigyelő fájlja), a legfrissebb Codex-napló mappája
és fölötte a hónap, az év és a `~/.codex/sessions` mappa változásakor azonnal (legfeljebb másodpercenként) frissül; a
futó Codex naplójából csak a hozzáírt részt olvassa; a rajz (vektoros, Cairo) a `meter.js`-ben, az olvasás a
`limits.js`-ben.

Régi adat: ha egy keretadat 1 óránál régebbi (`STALE_AFTER` a `limits.js`-ben, egy helyen, minden keretmérőre),
de az ablak még nem állt vissza, a mérő a számot szürkén mutatja, az ikon kitöltése halvány, a jel (`5h`, `H`, `F`)
megmarad, és mellette jobb fent egy apró pont jelzi a régiséget; a menüben „RÉGI ADAT”, és hogy mikor volt az utolsó adat (Codexnél: utolsó helyi Codex-futás;
Claude-nál: az ablak utolsó statusline-írása, Fable-nél az utolsó fiók-lekérdezés). Ha az ablak azóta visszaállt,
a mérő „–”, a menüben: visszaállt, és mióta nincs új adat.

**Korlát (Codex, keretfigyelő nélkül):** keretfigyelő nélkül a Codex-mérő csak a gépen, ebben a felhasználói
fiókban futó Codex CLI naplójából tud. A ChatGPT-alkalmazásban, a weben, más gépen vagy más fiókban elhasznált keret
a következő helyi Codex-futásig nem látszik; addig a mérő a legutolsó helyi pillanatképet mutatja, egy óra után
régiként. A keretfigyelő (lent) ezt a korlátot oldja fel.

- Claude 5 órás és heti: a Claude Code a statusline-nak adja át (`rate_limits.five_hour` / `seven_day`, `resets_at`-tel).
  A `statusline.py` ezeket kiírja a `$XDG_RUNTIME_DIR/kontextus-ikon/keretek.json` fájlba; amelyik ablakot egy
  hívás nem kapja meg, azt a visszaállásáig megtartja. Csak akkor frissül, amikor fut Claude Code terminál.
- Claude Fable heti: a fiók `/usage` adata (`api/oauth/usage`, lásd lent), ugyanabba a fájlba. Visszaállási időt
  csak akkor mutat, ha a válasz sora tartalmaz ilyet; visszaállási idő nélkül 3 óráig érvényes.
- Codex 5 órás és heti: a Codex CLI a session-naplóba (`~/.codex/sessions/ÉÉÉÉ/HH/NN/*.jsonl`) minden
  `token_count` eseménnyel kiírja a `rate_limits` mezőt (`primary`/`secondary`: `used_percent`, `window_minutes`,
  `resets_at`). A bővítmény a legfrissebb fájlok végéből a legutolsót olvassa; az ablakot a hossza alapján
  választja (300 perc = 5 órás, 10080 perc = heti). Csak olvas, a `~/.codex` többi tartalmához (pl. `auth.json`)
  nem nyúl. Az adat a legutolsó helyi Codex-futás pillanatképe (lásd a korlátot fent).

## Keretfigyelő (folyamatos keretmérés, háttérszolgáltatás)

A `keretfigyelo.py` systemd felhasználói szolgáltatásként (`kontextus-keretfigyelo.service`) fut, attól függetlenül,
hogy van-e nyitott Claude Code vagy Codex munkamenet, és a `$XDG_RUNTIME_DIR/kontextus-ikon/keretfigyelo.json`
fájlba írja a kereteket (atomikusan: ideiglenes fájl, majd átnevezés). Ezt a fájlt csak ő írja; a statusline a saját
`keretek.json` fájlját írja, így a kettő nem verseng. A bővítmény mindkettőt olvassa, és mérőnként a frissebb adatot
mutatja; a helyi Codex-napló (fent) tartalékként megmarad, és ha egy helyi Codex-futás frissebb, az nyer.

- Claude (5 órás, heti, Fable heti): a fiók `/usage` végpontja (`api.anthropic.com/api/oauth/usage`, a válasz
  `limits[]` sorai: `session` = 5 órás, `weekly_all` = heti, `weekly_scoped` modellnévvel = Fable), a Claude Code
  saját OAuth-tokenjével a `~/.claude/.credentials.json`-ból. A tokent csak olvassa: nem frissíti, nem írja, nem
  naplózza. A lekérés a `statusline.py` `account_usage()` függvénye; a gyorsítótár (`~/.cache/claude-account-usage.json`)
  és a gyakoriság (`USAGE_EVERY` = 120 mp, a `statusline.py`-ban) közös, és egyszerre csak egy folyamat kérdez (zárfájl
  a gyorsítótár mellett; a statusline nem vár, a gyorsítótárat adja). Ha nincs bejelentkezés vagy lejárt a token
  (401, vagy a hitelesítő fájl `expiresAt` ideje elmúlt), a menüben ez az ok áll, a mérő az utolsó jó adatot
  régiként mutatja; a következő Claude Code indítás frissíti a tokent, utána a figyelő magától helyreáll.
- Codex (5 órás, heti): tartósan futó `codex app-server` (stdio, soronként egy JSON-üzenet): `initialize`,
  `initialized`, majd percenként (`CODEX_EVERY` = 60 mp, a `keretfigyelo.py` elején) `account/rateLimits/read`
  (modellhívás és tokenköltség nélkül). Ha az app-server `account/rateLimits/updated` értesítést küld, azonnal
  frissít (a 2026-11-15-i próbán tétlen app-server 2 perc alatt magától nem küldött ilyet; a percenkénti lekérés a fő
  út). Ha a Codex nincs telepítve, nincs bejelentkezve, API-kulccsal van bejelentkezve, az app-server hibát ad, kilép
  vagy 30 mp-ig nem válaszol, a menüben a konkrét ok áll, és az újraindítás növekvő várakozással jön (5, 15, 60,
  300, 900 mp). A Codex-tokent az app-server kezeli; a figyelő az `auth.json`-t nem olvassa.
- A menü utolsó sora a figyelő állapota: fut-e, és a Claude- és a Codex-lekérés utolsó oka. Ha a figyelő nem fut
  (nincs állapotfájl, vagy 2 percnél régebbi), a menü kiírja, és a mérők a fenti módon (statusline, helyi
  Codex-napló) működnek tovább. Leállításkor a figyelő törli az állapotfájlját.

Kockázat: mindkét forrás nem dokumentált, belső felület. Az `api/oauth/usage` a Claude Code, a VS Code és a webes
felület belső végpontja, a `codex app-server` a Codex saját, kísérletinek jelölt (`[experimental]`) protokollja;
bármelyik formája verzióváltáskor változhat, ilyenkor a mérő „nincs adat” okot mutat, becslést nem. Az app-server a
saját fájljait (`~/.codex` alatt: naplók, állapot-adatbázis, szükség esetén a token frissítése) maga kezeli; ezt a
figyelő nem befolyásolja.

Telepítés, eltávolítás (root nélkül, bármelyik klónból, szóközös útvonallal is; többször futtatható):

    sh kontextus-ikon/install.sh --figyelo                # csak a keretfigyelő: egység, enable, (újra)indítás
    sh kontextus-ikon/install.sh --figyelo-eltavolitas    # leállítás, kikapcsolás, az egység és az állapotfájl törlése

Ideiglenes kikapcsolás: `systemctl --user stop kontextus-keretfigyelo.service` (bejelentkezéskor újraindul), végleges:
`systemctl --user disable --now kontextus-keretfigyelo.service` vagy a fenti eltávolítás. Napló:
`journalctl --user -u kontextus-keretfigyelo.service` (csak okok, token, fejléc, válasz soha). Egyszeri próba a
valódi bejelentkezéssel: `python3 kontextus-ikon/keretfigyelo.py --once`. Ez mindig friss Claude- és Codex-lekérést
végez (ideiglenes, utána törölt gyorsítótárral), a közös gyorsítótárat és az állapotfájlt nem írja; a `~/.codex` alá
az általa indított `codex app-server` a saját fájljait írhatja.

## Tesztek

Kézzel írt minták a `tests/fixtures` alatt (Codex-napló, statusline-fájl, keretfigyelő-állapot, a `/usage` válasza,
app-server-utánzat), rögzített idővel; valódi hálózatot, tokent, Codexet és systemd-t nem érnek el:

    bash kontextus-ikon/tests/run_all.sh        # minden teszt (gjs, python, telepítő), kilépési kód 0 = zöld
    bash kontextus-ikon/tests/mutants.sh        # szándékosan hibás változatok: mindre pirosnak kell lennie
    gjs -m kontextus-ikon/tests/preview.js DIR  # PNG-előnézet: friss, régi, visszaállt; 1x és 2x

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
