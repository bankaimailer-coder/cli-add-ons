# T01 Codex-keretmérő: az adat frissessége látszódjon, néma hibák és tesztek

- Forrás: a 2026-11-15-i ellenőrzés (a user kérésére, a MUNKAREND.md 2. része szerint): elavult adat frissként jelenik meg; a korlát nincs kimondva; öt üres `catch {}`; nincs teszt. Az ellenőrzés tényei: az utolsó helyi Codex-napló 12:46-os, a heti érték (53% maradt) helyes, az 5 órás keret 15:28-kor visszaállt.
- Besorolás: rutin (kijelzés és hibakezelés egy helyi bővítményben; adatot nem töröl, hitelesítő adatot nem érint).
- Cél: a keretmérőn első ránézésre látszódjon, ha a Codex-adat (és általában bármelyik keretadat) régi, mert a bővítmény csak a helyi Codex-futásokból tud; a hibák ne tűnjenek el némán; az adatfeldolgozást automatikus tesztek védjék.
- Lefedett esetek:
  - E1: friss adat (1 óránál újabb) → a mérő a megszokott módon látszik.
  - E2: régi adat (1 óránál régebbi, de az ablak még nem állt vissza) → a mérő láthatóan jelzi, hogy régi; a menüben az utolsó helyi Codex-futás ideje áll.
  - E3: az ablak visszaállt, azóta nincs új adat → „–”, a menüben: visszaállt, és mióta nincs helyi futás.
  - E4: nincs Codex-napló / nincs `rate_limits` / csonka sor / olvasási hiba → „nincs adat”, a menüben konkrét ok; az olvasási hiba a GNOME-naplóba is bekerül (egyszer, nem minden frissítéskor).
  - E5: hiányzik az egyik ablak (5 órás vagy heti) az adatból → az a mérő „nincs adat”, a másik működik.
- Elfogadási feltételek:
  1. E1-E5 mindegyikére van automatikus teszt fixture-fájlokkal (nem a valódi `~/.codex` adattal), és a tesztek egy paranccsal futnak (bizonyítja: a teszt parancsa, kilépési kód 0).
  2. Minden tesztnek van legalább egy szándékosan hibás változata, amelyre piros (pl. a küszöb megfordítása vagy a visszaállás-ellenőrzés kivétele), és ezt a zárójelentés parancsszinten megmutatja. (MUNKAREND 2.5)
  3. A `limits.js`-ben nincs olyan `catch`, amely okot és naplózást nélkül nyel el; ahol a hiba várt (pl. nem létező mappa, idegen sor), ott a kód megjegyzésben indokolja, és a menüben látszó ok konkrét (bizonyítja: `grep -n 'catch' limits.js` kimenete a zárójelentésben, soronkénti indokkal).
  4. Az elavultság-küszöb egy helyen van megadva, és a Claude-mérőkre is ugyanúgy hat (a Claude-adatnál a statusline utolsó írásának ideje számít).
  5. A README kimondja a korlátot: a Codex-mérő csak a gépen, ebben a fiókban futó Codex CLI naplójából tud; a ChatGPT-alkalmazásban, weben, más gépen vagy fiókban elhasznált keret a következő helyi futásig nem látszik.
  6. `node --check` minden módosított JS-fájlon: kilépési kód 0. A valódi adaton futtatott olvasó (`gjs -m`) kimenete a zárójelentésben.
  7. PNG-előnézet a friss, a régi és a visszaállt állapotról 1x és 2x méretben a scratchpadbe.
- Érinthető fájlok: `kontextus-ikon/gnome-extension/kontextus@kontextus-ikon/limits.js`, `meter.js`, `extension.js`; `kontextus-ikon/README.md`; új tesztfájlok és fixture-ök a `kontextus-ikon/tests/` alatt; máshoz nem nyúlhat.
- Útvonal-megkötés: a `statusline.py` nem változhat (ha az E4 Claude-oldala miatt kellene, állj meg és jelezd).
- Nincs benne: a szerveroldali keretlekérdezés (Codex `/status`-szerű lekérés a bejelentkezési tokennel) – ez külön vizsgálat, a user döntése után külön feladat; a GNOME Shell újraindítása; commit és push (a user szavára).
- Szükséges kapuk: a tesztparancs zöld; a hibás változatok pirosak; `node --check` zöld.
- Függ: nincs · Méret: egy kontextusba fér.
- Nyitott kérdés, amely érinti: nincs.
