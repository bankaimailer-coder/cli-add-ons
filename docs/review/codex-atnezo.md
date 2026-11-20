# Codex mint ügynök-alapú kódátnéző: beállítás és kontextus

> Repófüggetlen összefoglaló, bármelyik projektben használható. Állapot: 2026-11-18, `codex-cli 0.169.0`.
> Jelölés: **mérve** = egy gépen ellenőrizve; **forrás** = külső leírás, nem ellenőrizve (becslésként kezelendő).
> A munkarendben a 2.8 Review szakasz hivatkozik rá. Ha a mérések elavulnak, ezt a fájlt frissítsd a sablonban, és vidd át a repókba.

## Ajánlott modell: GPT-6.2 Sol (`gpt-6.2-sol`)

**Kódátnézésre a `gpt-6.2-sol` az ajánlott modell, max gondolkodási szinten.**

- **Forrás:** az OpenAI a Codex környezetben PR-átnézésre és visszajelzés alapján történő javításra ezt ajánlja.
  Ügynök-alapú átnézésben közel kétszer annyi valódi hibát talál, mint az elődje, a téves riasztások száma nem nő. Az
  Astrától kb. 1 százalékponttal marad el, jóval olcsóbban. Előfizetéses keretből kb. kétszer-háromszor több átnézés fér
  bele, mint a `gpt-5.6-sol`-lal.
- **Mikor Astra (`gpt-6.2-astra`):** több modulon vagy szolgáltatáson átívelő hibakeresés, illetve a teljes kódbázis
  felépítéséről szóló, architektúra-szintű kérdés.
- **Gyengeség (forrás):** hajlamos túlbonyolított javításokat javasolni. Az utasításban kösd ki, hogy a javaslat a
  legkisebb, a hibát megszüntető módosítás legyen, átszervezés és új absztrakció nélkül.

## A modellt mindig add meg kifejezetten

- **Mérve:** ha a hívás nem ad meg modellt, a gép `~/.codex/config.toml` alapértéke fut. Ez gépenként más lehet, és
  könnyen egy előző generációs modell marad. Egy projektben hetekig így futott az átnézés, és senki nem vette észre.
- Ezért a hívásban add meg:
  ```sh
  codex exec -m gpt-6.2-sol -c model_reasoning_effort="max" --sandbox read-only --ephemeral ...
  ```
- A beállítást ne a gép `config.toml`-jába írd, hanem a parancsba vagy a repó saját szkriptjébe. Így minden gépen
  ugyanaz fut.
- Elérhető modellek listája: `codex debug models`.

## Gondolkodási szint

- Max (vagy legalább High) az átnézéshez. **Forrás:** a Medium alatti szint inkább csak gyors szintaktikai ellenőrzésre
  elég.

## Ügynök-alapú (agentic) működés

- A modell nem egyetlen diffet olvas, hanem önállóan bejárja a repót: keres (grep), fájlrészleteket olvas, parancsot
  futtat. **Mérve:** egy közepes átnézés kb. 120 parancsfuttatással zajlott.
- Olvasási módban futtasd (`--sandbox read-only`): az átnéző jelez, a javítást külön lépésben végezd.
- **Alügynökök (mérve):** a többügynökös mód (`multi_agent_v2`) „stable”, de alapból ki van kapcsolva, és magától nem
  indít alügynököt. Bekapcsolás futásonként:
  ```sh
  codex exec --enable multi_agent_v2 ...
  ```
  Nagy, szétosztható átnézésnél (sok szabály, sok modul) az utasításban kérd, hogy a vezénylő a csoportokat
  alügynököknek ossza ki. Hogy olvasási módban működik-e, és megadható-e az alügynökök modellje külön, azt előbb egy
  kis próbán mérd le.
- Ellenőrizd a naplóban (`codex exec --json` eseményei), hogy mi történt valójában: indult-e alügynök, hány parancs
  futott, mennyi token fogyott.

## Kontextus

- **Határ: egyetlen ágens kontextusa se menjen 250K token fölé, se a vezénylőé, se az alügynököké.**
- **Forrás:**
  - **0-272K token:** a legpontosabb, minimális felejtéssel. Ez kb. 15-20 ezer sor kód.
  - **272K bemenet fölött:** a kérés bemeneti ára kétszeres, a kimeneti másfélszeres, vagyis előfizetésnél kétszer
    olyan gyorsan fogy a keret.
  - **Codex alapbeállítás:** a munkamenet kb. 258K-500K tokenre korlátozva, a modell papíron 1M-et tud.
  - **500K fölött:** a több fájlon átívelő következtetés pontossága 90% alá esik.
  - **Ügynök-módban** a modell célzott kereséssel építi a tudását, a kontextusa jellemzően 50K-150K marad.
- **Beállítás (forrás, ellenőrizd a saját verziódon):** `model_context_window`, és valószínűleg
  `model_auto_compact_token_limit`. Futásonként add meg: `-c kulcs=érték`.
- **Gyakorlat:** ne töltsd be az egész repót. Bontsd a munkát akkora csoportokra, hogy egy ágens 250K alatt maradjon.
  Lockfile, generált fájl és tesztadat ne kerüljön az átadott anyagba.

## Keret (mérve, egy fiók egy napja; csak nagyságrend)

- Egy átnézési kör 1,2M-6,7M bemeneti token volt, a nagy része gyorsítótárból.
- Egy ötórás keretbe kb. 8-10M bemeneti token fért, ez 2-3 közepes kör.
- A Codex saját keretkijelzése egy szkriptből olvasva elavult lehet. Ha a futás „usage limit” hibával áll meg, az
  eseménynaplóban látszik, mikor töltődik újra.

## Ha egy gépi ellenőrzés kiváltja az átnézést

- Ha a folyamatodban egy „kész” gépi ellenőrzés miatt bizonyos szabályokat már nem adsz át az átnézőnek, győződj meg
  róla, hogy az ellenőrzés tényleg minden hozzárendelt szabályt figyel. **Mérve:** egy projektben egy ellenőrzés 43
  szabályhoz volt rendelve, de ebből csak néhányat ellenőrzött ténylegesen. A többit sem a gép, sem az átnéző nem nézte.
- A nem fedett szabályokat rendeld egy „tervezett” ellenőrzéshez, hogy az átnéző továbbra is megkapja őket.

## Tanulság

Egy átnéző eszköz beállítását (modell, szint, mit kap meg és mit nem, indít-e alügynököt) bevezetéskor mérd meg,
ne feltételezd.

Mérés előtt nézz utána az adott feladatra vonatkozó jó gyakorlatnak: a hivatalos dokumentációban (OpenAI Codex-leírás,
`codex --help`, a kiadási jegyzetek), a GitHubon (a Codex-repó issue-i és vitái, mások beállításai) és technikai
fórumokon. A mérés ezt ellenőrzi a saját gépen és verzión, nem helyettesíti. Ami innen jön, az **forrás** jelölésű,
amíg nem mérted le.
