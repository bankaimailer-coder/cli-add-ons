# Átadó (2026-11-15): T01 Codex-keretmérő – adatfrissesség, néma hibák, tesztek, kódoló (a kapuig zárva, review előtt)
- Feladatlap: docs/feladatok/T01-codex-adat-frissesseg.md · Ág: feat/keretmerok · Alap-commit: e3028f7 · Review: nincs még

## Mi készült
- `kontextus-ikon/gnome-extension/kontextus@kontextus-ikon/limits.js`: egy helyen megadott elavultság-küszöb (`STALE_AFTER = 3600`, `isStale(ts, t)`), amely a Claude- és a Codex-mérőre is hat; minden mérő kap `stale` és `tsLabel` mezőt. A „most” paraméter: `window_(…, t)`, `readClaude(path, t)`, `readCodex(root, t)` (alapértékkel, a bővítmény hívása nem változott). A `catch` ágak: a hiányzó fájl/mappa várt eset konkrét okkal; minden más hiba továbbmegy vagy `reportOnce` útján egyszer a naplóba kerül (`console.warn`, a tesztben `setLogger`-rel cserélhető), és az ok a menüben látszik. `lastRateLimits` exportálva, `{rl, ts}` vagy `{why}` (nincs rate_limits / csonka sor). A visszaállt ablaknál az utolsó adat ideje is megmarad (E3). Hőfigyelő: csak a `readJson` új alakjához igazítva.
- `meter.js`: tiszta `limitStyle(left, stale, tag, rgb)`; régi adatnál szürke szám, halvány (0.45) ikonkitöltés, „régi” jel.
- `extension.js`: a `stale` átadása a rajznak, újrarajzolás a stale változásakor; menüsor: „RÉGI ADAT”, `<forrás> HH:MM (X óta)`, visszaállt ablaknál is az utolsó adat ideje; a Codex-forrássor kimondja: „csak a gépen futó Codex CLI-ből”.
- `kontextus-ikon/README.md`: a régi-adat jelzés, a Codex-korlát, a naplózás és a tesztparancsok.
- `kontextus-ikon/tests/run.js` (18 teszt, E1-E5), `tests/mutants.sh` (15 hibás változat), `tests/preview.js` (PNG-előnézet), `tests/fixtures/` (kézzel írt minta-sorok; az olvashatatlan fájl/mappa esetét a teszt ideiglenes mappában állítja elő).

## Ellenőrzések ebben a munkamenetben
- `gjs -m kontextus-ikon/tests/run.js`: kilépési kód 0, 18 ok, 0 hibás.
- `bash kontextus-ikon/tests/mutants.sh`: kilépési kód 0 = mind a 15 változat piros (mindegyik exit 1), és mind a 18 teszt legalább egy változatra elbukik.
- `node --check` a limits.js, meter.js, extension.js, tests/run.js, tests/preview.js fájlon: mind 0; `bash -n tests/mutants.sh`: 0.
- `gjs -m <scratchpad>/valodi.js` (readClaude + readCodex valódi adaton, 18:03): exit 0. Codex 5h: „a keret visszaállt, azóta nincs friss adat”, visszaállt 15:28:06, utolsó helyi futás 12:46:19; Codex heti: maradt 53%, stale: true; Claude heti 48% friss; Fable 79% friss; Claude 5h: „ez az ablak nincs a statusline adatában”.
- `gjs -m kontextus-ikon/tests/preview.js <scratchpad>`: exit 0, keretmero-allapotok-1x.png és -2x.png (szemre ellenőrizve).

## Nincs kész vagy nincs ellenőrizve
- Élő GNOME-sávban nincs ellenőrizve (a Shell újraindítása tilos volt): a menüsorok formázása (`limitLine`, `tsNote`, `fmtDur` az extension.js-ben) és a stale-változáskori újrarajzolás nincs automatikus teszttel lefedve, mert az extension.js shell-modulokat importál.
- A GNOME-naplóba írás (`console.warn` a Shellben) élőben nincs ellenőrizve; a tesztben a logger cserélt.
- Az olvashatatlan fájl/mappa tesztje root-ként futtatva hamisan bukna (a chmod 000 rootra nem hat); csak normál felhasználóként futott.
- Állapotnapló (docs/allapot/) és munkamenet-átadó nem készült: a megbízás csak ezt a kódoló-átadót engedte a listán kívül.

## Gyengített ellenőrzés
nincs

## Nyitott
- Értelmezés (4. feltétel): a Claude-adat korát ablakonként a `v.ts` adja (a statusline az adott ablakot ekkor írta; Fable-nél a fiók-lekérdezés ideje), nem a fájlszintű `ts`. Indok: a statusline a meg nem kapott ablakot a régi értékkel és régi `ts`-sel megtartja, a fájlszintű idővel ez frissnek látszana. Ha a user a fájlszintű időt akarja, az M14 változat pont ezt mutatja (és a teszt erre piros).
- 1x méretben a „régi” jel nagyon apró; a fő jelzés a szürke szám. Ha kevés, más jelölés kell (user döntése).
- A régi visszaállási idő nélküli Claude-adat 3 óra után továbbra is „nincs adat” (`CLAUDE_MAX_AGE`), ez a korábbi viselkedés, nem változtattam.
- Ötletlista, nem építettem be: az extension.js többi üres `catch`-e (readMemPct stb.) nem tartozott a feladathoz.

## Megjegyzés
A valódi próba helye: ki- és bejelentkezés után a sávban a Codex 5h „–”, a Codex heti szürke „53” „régi” jellel kell látsszon, a menüben az utolsó helyi Codex-futás idejével.
