# Munkarend

Ez a fájl a repó munkarendje: a szabályok, és az a struktúra, amelyben a munka nyoma a repóban marad (döntésnapló, feladatlapok, átadók, állapotnapló, review-kimenetek). Egy általános sablonból indult (a verzió a `.munkarend-verzio` fájlban áll), és ehhez a repóhoz kell igazítani: a végén a „Repó-specifikus kiegészítések” szakaszt töltsd ki, és ahol a repó eltér a sablontól, ott írd le az indokot. Minden munkamenet elején ezt a fájlt olvasd el először.

A zárójeles kód a szabály forrása: **N** a Nemes Ventilátorház szövegírási szokásai, **S** a soborbo-leads kódolási protokollja, **K** a szakács modell. A **lelet** jelű K-tétel kutatási megfigyelés, nem saját méréssel igazolt szabály. Irányt mutat, de ha ütközik egy elfogadott szabállyal, az elfogadott szabály dönt.

Sorrend ütközéskor: a user kifejezett szava, utána a repóban rögzített döntés (`docs/dontesek.md`) és a repó-specifikus kiegészítés, utána ez a sablonszöveg.

## 1. Munkamenet eleje és vége

### Elején olvasd el
1. Ezt a fájlt, a végén álló repó-specifikus kiegészítésekkel együtt.
2. A legfrissebb átadót a `docs/atado/` alól. A legfrissebb az érvényes, és kimondhatja, mit ír felül a korábbiakból. (S80)
3. A `docs/dontesek.md` sorait, amelyek a feladatot érintik.
4. A feladat lapját a `docs/feladatok/` alól. Feladatlap nélkül ne kódolj. (S8, S14)
5. A nyitott kérdéseket a `docs/dontest-ker.md` fájlban.
6. A `git status` kimenetét és az aktuális ágat. A munka a fő ágból vagy a feladat saját munkaágából induljon, ne egy régi helyi ágból. (S79)

### Végén frissítsd
1. Írd meg a zárójelentést: mi készült, a lefutott ellenőrzések paranccsal és kilépési kóddal, és tételesen az, ami nincs kész vagy nincs ellenőrizve. (S57, S95, K75)
2. Írj új átadót a `docs/atado/` alá, a végén bemásolható indító prompttal. (S76, S85)
3. Írj új állapotnapló-lapot a `docs/allapot/` alá a usernek, kód nélkül. (S76, S77)
4. A munkamenetben született döntést írd új sorként a `docs/dontesek.md` fájlba, a nyitott kérdést a `docs/dontest-ker.md` fájlba.
5. Ha fogy a kontextus vagy a keret, ne kezdj új részlépést. Zárd le, amit lehet, írd meg az átadót, és állj meg. (S81)
6. Commitolni, pusholni csak akkor szabad, ha a user kérte. (S75, K86)

## 2. Szabályok

### 2.1 Hamis „kész” és hamis zöld
- A „kész” állítás nem bizonyíték. A gépi ellenőrzés kimenete az: a parancs és a kilépési kód. (K29, S35)
- Csak azt nevezd lefutottnak, ami ebben a munkamenetben futott. (S36)
- A zárójelentésben tételesen sorold fel, mi nincs kész és mi nincs ellenőrizve. (S57, S95, K75)
- Ami nincs mérve, azt nevezd hipotézisnek, és mondd ki, mi cáfolná. (K3)
- A kudarc és a „nem tudom” elfogadott válasz. A szépítés hiba. (K1)

### 2.2 Hatókör és túltervezés
- Csak a feladatlapon megnevezett fájlokhoz nyúlj. Ha máshol is változtatni kellene, állj meg, és jelentsd. (S27, K24)
- A kértnél többet csináló helyes kód is hiba: kéretlen refaktor, extra teszt, extra absztrakció. (S54, K22 lelet)
- A menet közben jött új ötletet írd listára, ne építsd be. A „kis módosítás” is külön kör. (K15, K16)
- Új absztrakciót csak ismétlődő mintából vezess be. Dolgozz kevés fogalommal. A beállítás adat legyen, ne kód. (K45, S96, S97, K46)
- Ne javíts ki automatikusan minden reviewer-leletet. (K23 lelet)
- Az első szelet legyen kicsi: kevés komponens, egy réteg. (K25)

### 2.3 Egy igazságforrás
- Minden szabálynak, adatnak és logikának egy helye legyen, a többi hely hivatkozzon rá. (K40, N105)
- Egy HTTP-kliens, egy formázó- és egy fordítófüggvény legyen, ne másolatok. (S102)
- Generált kódot ne szerkessz kézzel. A származtatott terméket géppel vesd össze a forrásával. (K42, K43)
- A terv, a döntés és a szabály a repóban éljen, ne gépi memóriában vagy `/tmp`-ben. (S2, S3)

### 2.4 Csendes hibák, törékeny futás
- Ne legyen néma hiba: a `catch` továbbdob, jelent vagy típusos hibát ad. Minden határon legyen séma-ellenőrzés. (S99)
- A döntést hozó függvény legyen tiszta, és az időt kívülről kapja. (S98)
- Mellékhatás csak a tranzakció után jöjjön, idempotensen. (S100, S101)
- A külső hívásnak legyen időkorlátja. A pénzt egész számként tárold. (K79)
- A kommentben tett ígéret nem védelem. Írj hozzá tesztet, vagy vedd ki. (K30)
- Kódra ne szabj mesterséges méretkorlátot. (S34)

### 2.5 Tesztek
- A tesztnek el kell tudnia bukni: egy szándékosan hibás változatra legyen piros. (S38, K36)
- A zöld szükséges, de nem elégséges. A körkörös teszt és a bekötetlen kódra írt teszt nem lefedettség. (S39, K80)
- A generált tesztek mellé írj kézzel elfogadási próbát. (S40)
- A gyengített ellenőrzés (lazított assert, kódhoz igazított elvárt érték, törölt vagy kihagyott teszt) mindig hiba. Jelentsd külön tételként. (S56)
- Jóváhagyott tesztelvárást a kódoló nem szerkeszt. (S28, S72)
- A „másodikra zöld” bizonytalan teszt, ne ismételd csendben. Az időt és a véletlent rögzítsd a tesztben. (S41, S42)
- Adatbázist ne helyettesíts. Valódi külső szolgáltatást teszt ne érjen el. (S43)

### 2.6 Kontrollált változtatás
- Írás előtt legyen mentés vagy commitolt állapot. (N98)
- Haladj fokozatosan: próbafutás, egy elem, ellenőrzés, egy csoport, végül a tömeges lépés. Tömeges lépés előtt mutasd meg a diffet és a visszaállítás útját. (N99, N100)
- Csere után olvasd vissza az eredményt. (N81)
- Lefutott migrációt és publikus azonosítót ne írj át. Helyette új elem jöjjön. (K44, N100)
- `git add` előtt nézd meg a `git status` kimenetét. Idegen változást ne állíts vissza. `--force` soha. (N103)
- Commit, push, merge és élesítés csak a user szavára történhet. (S75, K86)
- Új függőséget csak indokkal és pontos verzióval vegyél fel. (S74)

### 2.7 Kitalált követelmények, csendes döntések
- Ne találj ki üzleti szabályt. (S11)
- Nyitott kérdést kód vagy teszt ne döntsön el csendben. Írd a `docs/dontest-ker.md` fájlba. (S73, N88)
- Rögzített döntést ne nyiss újra. Ha valami ellentmond neki, jelezd „ütközésként”. (S65)
- Ami adatból eldönthető, az teendő, nem kérdés. (N86)
- Ha a user vitatja az állításodat, ne védd, hanem mérd újra. (N89)

### 2.8 Review
- Saját munkádat ne te értékeld. A reviewer a diffet, a feladatlapot és a kapujelentést kapja meg, a te javaslatod nélkül. (K55, K56)
- Találat az, amelyhez megnevezhető a hibás bemenet vagy eseménysor. A stílus nem találat. (S58)
- A reviewer nézze a hibautakat: rossz bemenet, ismételt és egyidejű hívás, félbeszakadás. (S53)
- A blocker és a major megállítja a merge-et. (S49)
- Minden találatot zárj le: „javítva” vagy „indokolva marad”. A javítás az okot szüntesse meg. (S60)

### 2.9 Kontextus két munkamenet között
- Kódolás előtt legyen feladatlap: cél, ellenőrizhető elfogadási feltételek, érinthető fájlok, „nincs benne” lista. (S8, S14, S19)
- Ami nem fér egy kontextusba, ott a feladatot bontsd, ne a kódot. (S15)
- A munkamenet végén írj átadót bemásolható indító prompttal. (S76, S85)
- A kontextus végén ne kezdj új részlépést. (S81)
- A hosszú kimenetet írd fájlba, és csak a hibás részt olvasd be. (S33)

### 2.10 Ügynökök
- Egy író legyen, mellette csak olvasó segédek. (S24, S90)
- Párhuzamos író csak külön ágon és nem átfedő fájlokon dolgozhat. (S31)
- A segéd állítása mutató, nem tény. Mielőtt építesz rá, olvasd el a hivatkozott helyet. (S92, K10)
- Legfeljebb két javítókör jöhet, utána a user dönt. (K85)

### 2.11 Amit repónként kell beállítani
Ezek az elvek érvényesek, de az eszközük vagy a menetük a repótól függ. Az 5. szakaszban rögzítsd, mi a helyzet ebben a repóban.
- Gépi kapuk: hook, pre-commit, CI, szándékosan hibás tesztváltozatok, a jóváhagyott fájlok hash-e. A lehetőségeket az `eszkozok/opcionalis/README.md` írja le a sablonrepóban.
- Folyamatfüggő elemek: az esettáblázat jóváhagyása, a kényes és rutin besorolás, kényes feladatnál két reviewer.

## 3. A repó struktúrája

| Hely | Mire való | Ki írhatja |
|------|-----------|------------|
| `MUNKAREND.md` | Szabályok és a repó-specifikus kiegészítések. | A user, vagy az ügynök a user kérésére. A sablonrészt csak tudatos frissítéssel módosítsd. |
| `CLAUDE.md`, `AGENTS.md` | Rövid mutató erre a fájlra. A Claude Code az elsőt, a Codex a másodikat olvassa. | A user. A repó saját utasításai a mutató alá kerülnek. |
| `docs/dontesek.md` | Döntésnapló: azonosító, dátum, döntés, indok, mit pontosít. | Bárki hozzáírhat új sort, ha a döntést a user meghozta. Régi sort senki nem ír át. |
| `docs/dontest-ker.md` | Nyitott kérdések a usernek, javaslattal. | Az ügynök írja a kérdést, a user a választ. Az eldőlt kérdés új sorként a döntésnaplóba kerül. |
| `docs/feladatok/` | Feladatlapok, kódolás előtt. Minta: `_SABLON.md`. | Az előkészítő (vezérlő) írja, a user hagyja jóvá. A kódoló nem szerkeszti. |
| `docs/atado/` | Átadók a következő munkamenetnek. Minta: `_SABLON.md`. | Az ügynök a munkamenet végén új fájlt ír. Régit nem írunk át, az újabb mondja ki, mit ír felül. |
| `docs/allapot/` | Emberi nyelvű állapotnapló a usernek. | Az ügynök munkamenetenként új lapot ír. |
| `docs/review/` | Review-kimenetek feladatonként, és a találatok zárása. | A reviewer írja a találatot. A zárást a kódoló javasolja, a reviewer fogadja el. |
| `.munkarend-verzio` | Melyik sablon-commitból indult vagy frissült a repó. | Az init szkript, és frissítéskor az, aki a frissítést elvégzi. |

Fájlnevek: `docs/feladatok/<azonosító>-<rövid-név>.md`, `docs/atado/<éééé-hh-nn>-<téma>.md`, `docs/allapot/<éééé-hh-nn>-<n>.md`, `docs/review/<feladat>/r<n>.md`.

## 4. Háttér

A szabályok indoka és forrása a `szerkesztesi-szabalyrend` repóban áll: helyben `/data/szerkesztesi-szabalyrend` (a forráskivonatok a `forrasok/` mappában, sorszám szerint), GitHubon `bankaimailer-coder/szerkesztesi-szabalyrend`. Ha egy szabály indoka kell, ott keresd a forráskód alapján, és ne ide másold.

## 5. Repó-specifikus kiegészítések

Töltsd ki a `<…>` helyeket. Ami nem vonatkozik a repóra, oda írd: „nincs”. Ne hagyj üres sort jelölés nélkül.

- Tesztparancs (a teljes kapusor, olcsótól drágáig): `<parancs>`
- Gyors ellenőrzés munka közben: `<parancs>`
- Védett fájlok (jóváhagyott, a kódoló nem szerkeszti; pl. esettáblázat, tesztelvárás, migrációk): `<útvonalak>`
- Generált fájlok és a parancs, amely frissíti őket: `<útvonal: parancs>`
- Kényes feladat ebben a repóban (ami adatot töröl, jogosultságot, pénzt, migrációt, külső üzenetet vagy személyes adatot érint, plusz a repó saját listája): `<lista>`
- Review: ki a reviewer, rutin és kényes feladatnál hány: `<…>`
- Gépi kapuk, amelyek működnek (hook, pre-commit, CI), a korlátjuk és a megkerülési útjuk: `<…>`
- Élesítés módja, és ki indíthatja: `<…>`
- Push és ágkezelés (alapból push csak a user szavára): `<…>`
- Párhuzamos ügynökök felső határa ezen a gépen: `<szám>`
- Kivételek a szabályok alól (melyik szabály, hol, miért, ki hagyta jóvá): `<…>`
- Eltérések a sablontól, indokkal: `<…>`

A repó egyéb saját utasításai a `CLAUDE.md` és az `AGENTS.md` mutatósorai alá kerülnek, a két fájlban azonos szöveggel.

