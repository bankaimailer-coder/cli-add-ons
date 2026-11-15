# T02 Keretfigyelő: folyamatos Claude- és Codex-keretmérés háttérszolgáltatással

- Forrás: a user kérése (2026-11-15): minden gépen, ahol a Codex és a Claude be van jelentkezve, folyamatosan mérhető legyen a fogyasztás; a repóból telepíthető legyen. A Codex-lekérés módja: a 2026-11-15-i vizsgálat (Codex 0.166.0 forrása): `codex app-server` stdio JSON-RPC, `initialize`, majd `account/rateLimits/read` (modellhívás és tokenköltség nélkül); értesítés: `account/rateLimits/updated`. A Claude-lekérés módja: a meglévő `kontextus-ikon/statusline.py` `account_model_rows()` függvénye (`https://api.anthropic.com/api/oauth/usage`, `~/.claude/.credentials.json`, 120 mp-es gyakoriság). Előzmény: T01 (`docs/feladatok/T01-codex-adat-frissesseg.md`, kész, commit nélkül).
- Besorolás: kényes (hitelesítő adatot olvas, és külső szolgáltatást hív).
- Cél: egy felhasználói háttérszolgáltatás folyamatosan, munkamenettől függetlenül méri a Claude-keretet (5 órás, heti, Fable) és a Codex-keretet (5 órás, heti), és az eredményt abba az állapotfájlba írja, amelyet a GNOME-bővítmény olvas; a bővítmény a változást azonnal megjelenítse. Ahol a Claude vagy a Codex nincs telepítve vagy bejelentkezve, ott ez érthetően látszódjon, és a többi mérő működjön.
- Lefedett esetek:
  - E1: Claude bejelentkezve → 5 órás, heti és Fable keret a fiókból, legfeljebb 2 percenként frissítve.
  - E2: Claude nincs bejelentkezve, vagy lejárt a token (401) → „nincs Claude-bejelentkezés” / „a Claude-bejelentkezés lejárt”; a szolgáltatás a tokent nem frissíti.
  - E3: Codex bejelentkezve → 5 órás és heti keret a `codex app-server`-ből, percenként lekérdezve; ha az `account/rateLimits/updated` értesítés megérkezik, azonnal frissül.
  - E4: Codex nincs telepítve vagy nincs bejelentkezve, az app-server hibát ad vagy kilép → konkrét ok; újraindítás növekvő várakozással (backoff), a sávot nem akasztja.
  - E5: helyi Codex-futás → a `~/.codex/sessions` új token_count eseménye azonnal frissít (a T01 olvasója tartalékként megmarad).
  - E6: a szolgáltatás nem fut → a bővítmény a mai módon (statusline-fájl, helyi Codex-napló) működik, és jelzi, hogy a figyelő nem fut.
  - E7: régi adatnál a mérő jele (5h, H, F) megmarad; a régiséget a szürkítés és egy apró jel mutatja (a T01 „régi” felirata most a jelet takarja).
- Elfogadási feltételek:
  1. E1-E7 mindegyikére automatikus teszt, a HTTP-válaszok és az app-server üzenetei kézzel írt mintákból (valódi hálózat és valódi token nélkül); a tesztek egy paranccsal futnak, kilépési kód 0.
  2. Minden új tesztnek van szándékosan hibás változata, amelyre piros; a T01 18 tesztje és 15 hibás változata továbbra is így viselkedik.
  3. A szolgáltatás a tokent csak olvassa, soha nem frissíti és nem írja; tokent, fejlécet vagy választ nem naplóz. Ezt teszt vagy `grep` igazolja, a zárójelentés idézi.
  4. Az állapotfájl írása atomikus (ideiglenes fájl + átnevezés), és a statusline meglévő írásával nem verseng (egy forrás írjon egy kulcsot, vagy külön fájl; a megoldást a zárójelentés indokolja).
  5. A lekérési gyakoriság egy helyen állítható; alapérték: Claude 120 mp (a statusline-nal közös gyorsítótárral, hogy ne kérdezzenek kétszer), Codex 60 mp.
  6. A szolgáltatás systemd felhasználói egységként fut, telepítő és eltávolító paranccsal (idempotens), útvonal-függetlenül (bármelyik klónból, szóközös útvonallal is), root nélkül.
  7. Valódi próba ezen a gépen: a szolgáltatás egyszeri futása (pl. `--once` kapcsoló) a valódi bejelentkezéssel kiírja a Claude- és a Codex-keretet; a zárójelentés a kimenetet (számok, idők) mutatja, tokent nem.
  8. A README leírja a működést, az adatforrásokat, a kockázatot (belső végpontok, kísérleti app-server) és a kikapcsolást.
- Érinthető fájlok: új `kontextus-ikon/keretfigyelo.py` (vagy hasonló nevű) és systemd-egység sablonja; `kontextus-ikon/install.sh`; `kontextus-ikon/statusline.py` (csak a közös gyorsítótár és az írási ütközés miatt, a meglévő viselkedés megtartásával); `kontextus-ikon/gnome-extension/kontextus@kontextus-ikon/limits.js`, `extension.js`, `meter.js`; `kontextus-ikon/README.md`; `kontextus-ikon/tests/`; máshoz nem nyúlhat.
- Útvonal-megkötés: a `~/.codex` és a `~/.claude` alá nem írhat; az `auth.json`-t nem olvashatja (a Codex-tokent a Codex app-server kezeli).
- Nincs benne: a közös, egész repót telepítő szkript (T03); a GNOME Shell újraindítása; a szolgáltatás élesítése ezen a gépen (a telepítő parancsát a zárójelentés megadja); commit és push.
- Szükséges kapuk: tesztek zöldek, hibás változatok pirosak, `node --check` és `python3 -m py_compile` zöld.
- Függ: T01 · Méret: egy kontextusba fér; ha nem, a Claude- és a Codex-ágat bontsd két részre, és jelezd.
- Nyitott kérdés, amely érinti: nincs.
