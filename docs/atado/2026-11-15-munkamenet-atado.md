# Átadó (2026-11-15, délután): keretmérők, terminálszínek, szabályrend és munkarend kész; a cli-add-ons push és a munkarend élesítése nyitott
> Felülírja: semmit (ez az első átadó ebben a repóban). Tiltás: a 14 repó munkarend-commitját ne pushold, amíg a user ki nem mondja, hogy a munkarend jól működik.

## Ma eldőlt
- A keretmérők a sáv helyett a márka ikonját mutatják (Claude-csillag narancs, ChatGPT-csomó törtfehér), amely a **megmaradt** kerettel arányosan ürül alulról; a szám is a megmaradt százalék. Figyelmeztetés: 25% maradék alatt sárga, 10% alatt piros. (user, 2026-11-15)
- A CPU-hőmérő színe világoslila (#c084fc), a GPU-é cyan (#00ffff). (user)
- A terminálszín a repóhoz tartozik, nem az ablakhoz; a színeket mi választottuk, csak különbözzenek. (user)
- A szabályrend nem a globális CLAUDE.md-be kerül, hanem munkarendként minden repóba (sablon: /data/munkarend, GitHub: bankaimailer-coder/munkarend, template). A Nemes Ventilátorház és a soborbo-leads repójához nem nyúlunk. (user)
- A szerkesztési szabályrend kézzel hívható skill marad (/szerkesztesi-szabalyrend). (user)

## Mire várunk
- A user döntésére: pusholható-e a cli-add-ons `feat/keretmerok` ága. Az ágon benne van a munkarend bevezetése is (`cdcc392`), a user viszont azt kérte, hogy a munkarend még ne kerüljön GitHubra.
- A user visszajelzésére arról, hogy a munkarend jól működik-e a repókban; utána mehet a push mind a 14 repóban.

## Állapot
| Munkamappa vagy ág | Commit | Állapot | Ellenőrizve (parancs) |
|---|---|---|---|
| /data/cli-add-ons `feat/keretmerok` | e munkamenet utolsó commitja | ikonos keretmérők, lila CPU, terminálszínek, munkarend; nincs pusholva | `node --check` a meter.js, extension.js, limits.js fájlon: 0 |
| /data/munkarend `main` | 5709ab6 | GitHubon, privát, template | `bash -n` a két szkripten: 0; init két próbarepón |
| /data/szerkesztesi-szabalyrend `main` | d0f0040 | GitHubon, privát; skill telepítve (~/.claude/skills szimlink) | `install.sh`: kész |
| 14 helyi repó | „Munkarend bevezetése (sablon: 5709ab6)” | helyben commitolva, nincs pusholva | commitonként 9-10 fájl, a user egyéb változásai érintetlenek |
| Ptyxis | 13 saját profil | telepítve; mentés: scratchpad/ptyxis-mentes-elotte.ini | `szinprofil.py telepit`: exit 0 |
| worktree-k: .claude/worktrees/agent-acba…, agent-aedb… | | a munkájuk beolvadt vagy átmásolódott; törölhetők | |

## Ellenőrzések ebben a munkamenetben
- `node --check` a kontextus-ikon három JS-fájlján: kilépési kód 0.
- `gjs -m` a readClaude/readCodex/readHeat függvényekkel valódi adaton (az alügynök futtatta): 0.
- Az új mérők és a lila CPU élő GNOME-sávban **nincs ellenőrizve**: ki- és bejelentkezés kell hozzá.

## Nyitott
- A Claude 5 órás kerete nem érkezik meg a statusline-hoz, ezért az a mérő „–”.
- Alacsony maradéknál (20% alatt) a Claude-csillag kitöltése csak egy kis folt; a szám színe a fő jelzés.
- Egy mérő 36 px széles lett (eddig 22); ha a sáv túl zsúfolt, keskenyíteni kell.
- A MUNKAREND.md „Repó-specifikus kiegészítések” szakasza és a docs/dontesek.md D1 dátuma minden repóban kitöltetlen.
- A user két régi, kézi Ptyxis-profilja (BJJ MIND PALACE, FREEFLOW) a saját profilok mellett megmaradt; törölhetők, ha nem kellenek.
- A ~/AI PROJECTS/budaigrappling nincs a claude-indito mappak.txt-ben a bfuzzee gépre.
- A bfuzzee felhasználónál nincs globális git-azonosító és nincs globális git hooksPath; a szakacs-modell CLAUDE.md „minden írónál” állítása erre a felhasználóra nem igaz.
- Laptophűtő: a terv a chatben elkészült; vásárlólista és mérőszkript nem készült.

## Teendő, sorrendben
1. Kijelentkezés és bejelentkezés után nézd meg az új mérőket és a lila CPU-t a sávban; a user visszajelzése szerint igazíts.
2. Döntés a cli-add-ons pusholásáról (lásd: Mire várunk).
3. Ha a munkarend jól működik: push mind a 14 repóban, a saját águkra.
4. Repónként a MUNKAREND.md végének kitöltése az adott repóban dolgozó munkamenetben.
5. Az elavult worktree-k eltávolítása a user jóváhagyásával.
6. Telepítés a többi gépre (user kérése): a mérőeszközök a GitHubon a `feat/meroeszkozok` ágon vannak (074ac97, munkarend nélkül). Javaslat: merge a `main`-be (a user jóváhagyásával), és egy közös telepítő, amely a kontextus-ikont, a claude-indito profiljait és a hőfigyelőt (szolgáltatás + horgok) egyben telepíti.

## Kiegészítés (2026-11-15, később)
- Push megtörtént: `origin/feat/meroeszkozok` = 074ac97 (hőfigyelő, keretmérők, CPU/GPU-hőmérő, terminálszínek; a munkarend-commit és a docs/ nélkül). A helyi `feat/keretmerok` (munkarenddel) nincs pusholva.

## Bemásolandó indító prompt
```
A cli-add-ons repóban dolgozunk, a MUNKAREND.md szerint. Olvasd el a MUNKAREND.md-t és a docs/atado/2026-11-15-munkamenet-atado.md átadót. Kezdd a „Teendő, sorrendben” 1. pontjával: kérdezd meg, hogyan néznek ki az új keretmérők és a lila CPU-hőmérő a sávban, és mi a döntés a feat/keretmerok ág pusholásáról.
```
