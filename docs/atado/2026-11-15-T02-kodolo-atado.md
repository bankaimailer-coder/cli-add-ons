# Átadó (2026-11-15): T02 Keretfigyelő – folyamatos Claude- és Codex-keretmérés háttérszolgáltatással, kódoló (a kapuig zárva, review előtt)
- Feladatlap: docs/feladatok/T02-keretfigyelo-szolgaltatas.md · Ág: feat/keretmerok · Alap-commit: e3028f7 (a T01 változásai commit nélkül alatta) · Review: nincs még

## Mi készült
- `kontextus-ikon/keretfigyelo.py` (új): a szolgáltatás. Claude: `statusline.account_usage(wait=True)`; Codex: tartós `codex app-server` (stdio, soronként egy JSON; `initialize` → `initialized` → percenként `account/rateLimits/read` `{"excludeResetCreditDetails": true}`), az `account/rateLimits/updated` értesítésre azonnal ír, ablakonként összefésülve. Hibaokok (nincs telepítve, nincs bejelentkezve, API-kulcs, hibaválasz, kilépés, 30 mp-es időkorlát), újraindítás 5/15/60/300/900 mp után. Kimenet: `$XDG_RUNTIME_DIR/kontextus-ikon/keretfigyelo.json` (atomikus; szívverés 30 mp; leállításkor törli). `--once` (egy lekérés, kiírás, fájlírás nélkül), `--unit` (a kitöltött systemd-egység, idézve: szóköz, `%`, `$`, `"`, `\`).
- `kontextus-ikon/keretfigyelo.service.in` (új): az egység sablonja.
- `kontextus-ikon/statusline.py`: a fiók-lekérdezés `account_usage()` lett (közös gyorsítótár, zárfájl, `USAGE_EVERY` egy helyen; a `limits[]` sorai: `session` → 5 órás, `weekly_all` → heti, `weekly_scoped` → modellsor); konkrét okok (`UsageError`: nincs bejelentkezés, lejárt: 401 vagy `expiresAt`, HTTP-kód, hálózati hiba, nem JSON). `account_model_rows()` és a `keretek.json` írása változatlan viselkedésű.
- `kontextus-ikon/install.sh`: 7. lépés a keretfigyelő; `--figyelo`, `--figyelo-eltavolitas`; `KONTEXTUS_SYSTEMCTL` a próbához.
- `gnome-extension/.../limits.js`: `readFigyelo`, `fresher`, `readLimits` (mérőnként a frissebb forrás; a figyelő oka a hiányzó ablaknál, `note` a régi adat mellett), `FIGYELO_MAX_AGE = 120`.
- `meter.js`: E7: a jel régi adatnál is marad, `mark` (apró pont jobb fent).
- `extension.js`: `readLimits`; fájlfigyelés (a statusline/figyelő mappája és a legfrissebb Codex-napló mappája, 1 mp-es késleltetéssel); harmadik menüsor a figyelő állapotával; `note` a mérősorban.
- `kontextus-ikon/README.md`: a keretfigyelő működése, forrásai, kockázata, telepítése és kikapcsolása; a tesztparancsok.
- `kontextus-ikon/tests/`: `test_keretfigyelo.py` (25 teszt), `run.js` +7 teszt (összesen 25), `install_figyelo.sh` (15 ellenőrzés), `run_all.sh` (egy parancs), `mutants.sh` (+10 JS, +29 Python, +10 telepítő változat; a T01 15 változata változatlan), `fixtures/appserver/` (app-server-utánzat és kézzel írt üzenetek), `fixtures/claude/usage.json`, `credentials*.json` (minta-token), `fixtures/figyelo/`.

## Ellenőrzések ebben a munkamenetben
- `bash kontextus-ikon/tests/run_all.sh`: kilépési kód 0; gjs 25 ok, python 25 ok, telepítő 15 ok („MIND ZÖLD”).
- `bash kontextus-ikon/tests/mutants.sh`: kilépési kód 0; 25 bővítmény- és 39 python/telepítő-változat, mind piros; minden teszt (25+25+15) legalább egy változatra elbukik.
- `node --check` limits.js, meter.js, extension.js, tests/run.js, tests/preview.js: mind 0. `python3 -m py_compile` statusline.py, keretfigyelo.py, tests/test_keretfigyelo.py, minta_app_server.py: 0. `sh -n install.sh`, `bash -n` a három tesztszkriptre: 0.
- Valódi próba (`python3 -I <scratchpad>/proba/valodi_proba.py 120`, a keretfigyelő kódjával, egy Claude- és egy Codex-lekérés, külön gyorsítótárral): exit 0. Claude 1,10 mp: heti 53% elhasználva (vissza 11.19. 19:00), Fable 21% (vissza 11.19. 19:00), 5 órás: nincs sor (a CLI statusline-adatában sincs `five_hour`). Codex 2,34 mp (plus): 5 órás 20% (vissza 11.15. 22:42), heti 51% (vissza 11.20. 08:28). Utána 120 mp figyelés új lekérés nélkül: `account/rateLimits/updated` nem jött; csak `remoteControl/status/changed` (0,22 mp) és `account/updated` (1,72 mp).
- `KERETFIGYELO_CODEX=/nincs/codex python3 kontextus-ikon/keretfigyelo.py --once` (a Claude a friss közös gyorsítótárból, hálózat nélkül): exit 0; heti 54%, Fable 21%, Codex: „nem indul (FileNotFoundError)”.
- `gjs -m kontextus-ikon/tests/preview.js <scratchpad>`: exit 0; a 2x képen a régi sorban az `5h`/`H` jel megmarad, mellette a pont.

## Nincs kész vagy nincs ellenőrizve
- Élő GNOME-sávban nincs ellenőrizve (a Shell újraindítása tilos): a fájlfigyelés (`_watch`, `_watchCodex`), az új menüsorok és a „NEM FUT” sor; a még nem létező mappa figyelése (`monitor_directory`) sem.
- A systemd-szolgáltatás valódi futása nincs ellenőrizve (élesítés tilos volt); a telepítő csak ideiglenes HOME-mal és systemctl-utánzattal futott, a `systemd-analyze --user verify` a kitöltött egységre figyelmeztetés nélkül lefutott. A teljes `sh install.sh` (kapcsoló nélkül) nem futott, mert a valódi gsettings-et érintené.
- Az 5 órás Claude-sor (`kind: "session"`) valódi válaszon nincs ellenőrizve: a próbakor nem volt ilyen sor; a leképezés a Claude Code 2.1.325 beépített sémaleírásából jön („'session', 'weekly_all' or 'weekly_scoped'”).
- Az üzenetkeretezés forrása: a `stdio.rs` és az értesítést kibocsátó `bespoke_event_handling.rs` nincs a helyi forrásmásolatban. Az üzenetalak (`{"method","id","params"}`, `jsonrpc` mező nélkül; `{"method":"initialized"}`) a `common.rs` szerializálási tesztjeiből, a mezőnevek a `v2_account.rs`-ből és a `codex app-server generate-json-schema` kimenetéből; a soronkénti keretezést a valódi próba igazolta (minden válasz egy sorban jött és értelmeződött), forrásból nem.
- Az `account/rateLimits/updated`: hipotézis, hogy az app-server csak a saját folyamatában futó munkamenet (turn) közben küldi; tétlenül 120 mp alatt nem jött. Cáfolná, ha tétlen app-server is küldené, vagy ha egy másik folyamatban (CLI) futó turn alatt is megjönne.
- Állapotnapló (docs/allapot/) nem készült: a megbízás csak ezt a kódoló-átadót kérte.

## Gyengített ellenőrzés
nincs. Egy T01-elvárás megváltozott, a feladatlap E7 esete szerint (nem lazítás): `tests/run.js` „E2 mérő” tesztjében `eq(stale.tag, 'régi', …)` helyett `eq(stale.tag, '5h', …)` és `eq(stale.mark, true, …)`. A T01 M3 változata továbbra is megöli ezt a tesztet.

## Nyitott
- A `statusline.py` a `~/.claude/settings.json` szerint a `/home/bfuzzee/AI PROJECTS/cli-add-ons` symlinken át ebből a munkakönyvtárból fut: a módosítás commit nélkül is azonnal él minden Claude Code terminálban (a próba alatt hibátlanul írta a közös gyorsítótárat, már az 5 órás/heti ablakokkal).
- A lekérési gyakoriság két helyen áll, gyakoriságonként egy helyen: Claude `USAGE_EVERY` a `statusline.py`-ban (közös a statusline-nal), Codex `CODEX_EVERY` a `keretfigyelo.py`-ban. Ha a user egyetlen helyet akar, az új döntés.
- A Codex hibaválaszának szövege (legfeljebb 120 karakter) az okba és a naplóba kerül; a szerver üzenete a forrás szerint nem tartalmaz hitelesítő adatot.
- A `codex app-server` a saját fájljait a `~/.codex` alá írja (napló, adatbázis, szükség esetén tokenfrissítés); ezt a figyelő nem írja, de az általa indított folyamat igen.
- Az app-server `stderr`-je eldobva (`DEVNULL`), hogy semmi ne kerüljön a naplóba; hibakereséshez ez kevés lehet.
- A meglévő `statusline.py` ideiglenes debug-írása (`~/.cache/statusline-debug.json`, 2026-11-10) nem a feladat része, nem nyúltam hozzá.

## Megjegyzés
Telepítés ezen vagy más gépen: `sh kontextus-ikon/install.sh --figyelo` (vagy a teljes `sh kontextus-ikon/install.sh`); eltávolítás: `sh kontextus-ikon/install.sh --figyelo-eltavolitas`. A valódi próba helye élesítés után: `systemctl --user status kontextus-keretfigyelo.service`, `cat $XDG_RUNTIME_DIR/kontextus-ikon/keretfigyelo.json`, majd ki- és bejelentkezés után a menü utolsó sora: „Keretfigyelő: fut (…) · Claude: rendben · Codex: rendben”, a Codex-mérők friss számmal helyi Codex-futás nélkül is.

## Javítókör 1
A független review 6 találata (a reprodukciók: scratchpad/review/repro_double_fail.py, repro_parse.py; javítás után mindkettő a helyes eredményt adja).
- R1 (major) késő kilépés-esemény a saját leállítás után: javítva. `Codex.stop()` lépteti a `gen`-t, így a leállított folyamat `("exit", régi gen)` eseménye kimarad. Teszt: `test_E4_nem_valaszol_idokorlat` az időkorlát után még eseményt dolgoz fel, és `failures == 1`-et vár; P30 öli meg.
- R2 (major) sémaváltozás és csonka törzs a Claude-lekérésben: javítva. A `fetch_usage` az `http.client.HTTPException`-t (pl. `IncompleteRead`) „hálózati hiba”-ként, a `parse_usage` `AttributeError/TypeError/KeyError/ValueError`-ját „hibás válasz (ismeretlen formátum)”-ként `UsageError`-rá alakítja; így a hiba is gyorsítótárba kerül, és az utolsó jó adat megmarad. Teszt: `test_E2_hibas_sema_hibakent_gyorsitotarba_kerul`, `test_E2_csonka_torzs_hibakent_gyorsitotarba_kerul`; P31 és P32 öli meg.
- R3 (minor) nem várt alakú app-server-üzenetek: javítva. A `codex_snapshot` nem objektumra (result, params) None-t ad, a `handle` csak egész id-t fogad, a `codex_windows` csak számot fogad el százaléknak. Teszt: `test_E4_nem_vart_alaku_uzenetek_kimaradnak` (új `hibas-sema` forgatókönyv); P33, P34 és P35 öli meg.
- R4 (minor) teljes 512 KB-os szinkron farokolvasás minden Codex-írás után: javítva. A `readCodex` a legfrissebb fájlból csak a hozzáírt részt olvassa (`readRange`, az utolsó ép sor végétől); a félig írt sor kimarad, és a befejezése után kerül beolvasásra. Teszt: „T02 R4 futó Codex…” (az olvasott bájtszám = a hozzáírt sor hossza), „T02 R4 félig írt sor…”; J11 és J12 öli meg.
- R5 (minor) a `--once` a közös gyorsítótárból válaszolt, és írt bele: javítva. Ideiglenes, utána törölt gyorsítótárral mindig friss lekérést végez, és ezt ki is írja; a README ezt pontosan leírja. Teszt: `test_once_friss_lekeres_a_kozos_gyorsitotar_nelkul`; P36 öli meg.
- R6 (minor) az E5 fájlfigyelés és az E6 menüsor teszt nélkül, az új nap mappája nincs figyelve: javítva. Tiszta függvények lettek: `codexWatchDirs` (nap, hónap, év és a sessions-gyökér) és `figyeloStatus`; az `extension.js` ezeket használja. Teszt: „T02 R6 figyelt Codex-mappák…”, „T02 R6 E6 a figyelő menüsora…”; J13 és J14 öli meg. A monitorok élő bekötése továbbra sincs ellenőrizve (Shell nélkül).
- Kapu a javítás után: `bash kontextus-ikon/tests/run_all.sh` exit 0 (gjs 29, python 29, telepítő 15); `bash kontextus-ikon/tests/mutants.sh` exit 0 (29 bővítmény- és 46 python/telepítő-változat, mind piros, minden teszt elbukik legalább egyre); `node --check` (5 fájl) 0; `py_compile` (4 fájl) 0; `sh -n`/`bash -n` 0. Hálózati hívás ebben a körben nem volt.

## Javítókör 2
- N1 (minor) nem objektum `error` (pl. `{"id": 1, "error": "szöveg"}`) AttributeError-t dobott: javítva. A `codex_error_reason` nem objektumra is konkrét okot ad: „a Codex app-server hibát adott: <szöveg>”. A `hibas-sema` forgatókönyv az első lekérésre szöveges errort küld, a másodikra a korábbi nem várt alakú üzeneteket; ezt a `test_E4_nem_vart_alaku_uzenetek_kimaradnak` lefedi, és a P37 öli meg.
- N2 (minor) a readRange levágta az újsor nélküli utolsó sort, ezért az ok „nincs rate_limits” lett „csonka” helyett: javítva. A szöveg a félig írt utolsó sort is tartalmazza, így a `lastRateLimits` csonkaként számolja; az `end` továbbra is az utolsó ép sor vége, így a következő olvasás újraolvassa. Új fixture: `tests/fixtures/codex/csonka-ujsor-nelkul`. Teszt: „T02 N2 új munkamenet első, újsor nélküli csonka rate_limits-sora”; a J15 öli meg.
- Kapu: `run_all.sh` exit 0 (gjs 30, python 29, telepítő 15); `mutants.sh` exit 0 (30 bővítmény- és 47 python/telepítő-változat, mind piros, és minden teszt elbukik legalább egyre); `node --check` 0; `py_compile` 0; `sh -n`/`bash -n` 0.
