# Claude kontextus-ikon

A GNOME felső sávjában mutatja a nyitott Claude Code terminálok kontextushasználatát és a memória telítettségét.

Két része van:

- `kontextus_ikon.py`: háttérfolyamat, amely 3 másodpercenként kiszámolja a nyitott Claude Code terminálok
  kontextusát, 500k tokennél értesítést küld, és D-Bus-on (`hu.bfuzzee.KontextusIkon`) átadja az adatokat.
- `gnome-extension/kontextus@kontextus-ikon`: GNOME Shell-bővítmény, amely kirajzolja:
  - a kontextusmérőket a sáv bal oldalán, az ablakválasztó után (terminálonként egy körív és a szám);
  - a memória-chipet a jobb oldalon, közvetlenül a rendszerikonok (mikrofon, Wi-Fi, akku) előtt, benne a százalékkal;
  - és végrehajtja az ablakugrást („Ugrás a terminálba” a kontextusmérő menüjében).

A bővítmény symlinkkel van a `~/.local/share/gnome-shell/extensions/` alatt, bekapcsolva a
`org.gnome.shell enabled-extensions` beállításban. Új vagy módosított bővítmény a ki- és bejelentkezés után töltődik be.
Amíg a bővítmény nem fut, a Python a kontextusmérőket a sáv jobb oldalán, appindicator-ikonként mutatja.

Kézi indítás (egy sor, a terminálból függetlenül fut tovább):

    setsid python3 ~/cli-extensions/kontextus-ikon/kontextus_ikon.py >/dev/null 2>&1 &

Ellenőrzés ikon nélkül (kiírja, amit a kontextusmérők mutatnának):

    python3 ~/cli-extensions/kontextus-ikon/kontextus_ikon.py --once

Automatikus indítás: `~/.config/autostart/kontextus-ikon.desktop` (a mappában lévő `kontextus-ikon.desktop` másolata).
Kikapcsolás: töröld azt a fájlt. Egyszerre csak egy példány fut; a második indítás kilép.

Kontextusmérők: csak akkor látszanak, ha fut legalább egy Claude Code terminál. Szín: `PROJECT_COLORS` szerint
(nemesventilatorhaz kék, a többi zöld), `RED_FROM` (500k) fölött piros. A menüben repó, session, állapot, tokenszám.
Beállítások a `kontextus_ikon.py` elején: `PROJECT_COLORS`, `DEFAULT_COLOR`, `RED_FROM`, `GAUGE_MAX`, `KINDS`,
`POLL_SEC`, `WARN_AT`.

Ugrás a terminálba: a Python a session terminálfülére ideiglenes egyedi címet ír, a bővítmény előrehozza az ilyen
című Ptyxis-ablakot, majd az eredeti cím visszaáll. Ha a session egy ablak nem aktív fülén fut, az ablak nem található.

Memória-chip: mindig látszik; a használt memória (MemTotal - MemAvailable, mint a `free`) százalékban.
A rajza a `chip.js`-ben, a kontextusmérőé a `gauge.js`-ben van.

CLI-sor: a `statusline.py` (a `~/.claude/settings.json` `statusLine` bejegyzése, így minden Claude Code terminálban)
kiírja az 5 órás és a heti keret kihasználtságát, pl. „5 órás: 18% | heti: 78%”. A Fable-keretet a Claude Code
jelenleg nem adja át; ha megjelenik, a sor magától kiírja.
