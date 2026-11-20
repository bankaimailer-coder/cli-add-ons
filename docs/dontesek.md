# Döntések

Ez a repó döntésnaplója. A rögzített döntést ne nyisd újra. Ha valami ellentmond neki, jelezd „ütközésként” a usernek. (S65)

Szabályok:
- Régi sort nem írunk át. Új, dátumozott sor pontosítja vagy írja felül, és a régi sor végére odaírjuk: „pontosítja: D<n>”. (S66)
- Minden sorban áll: azonosító, dátum, döntés, indok, és hogy mit pontosít. (S68)
- Munkamódot és eszközt a user bármikor módosíthat. Üzleti döntést csak új tény nyit meg. (S67)
- Ha egy döntés indoka elavul, jelöld a döntésnél, új sorral. (K72)
- Új sort csak akkor írj, ha a döntést a user meghozta. A nyitott kérdés a `docs/dontest-ker.md` fájlba kerül.

| Azonosító | Dátum | Döntés | Indok | Mit pontosít |
|-----------|-------|--------|-------|--------------|
| D1 | <éééé-hh-nn> | A repó a munkarend sablonból indult (verzió: lásd `.munkarend-verzio`). | Közös munkarend a kódolási projektekhez. | nincs |
| D2 | 2026-11-20 | A repó munkarendje a sablon 2.5-ös változatáról (`be7da06`) a 2.8-asra frissült (`b40cfcd`). A 2.6 arányossá tette a feladatlapot és a zárást, és a stackfüggő szabályokat az 5. szakaszba vitte; a 2.7 leírta a Codex-átnéző beállítását (`docs/review/codex-atnezo.md`); a 2.8 gyorsító és minőségi szabályokat hozott (kommentszabály, viselkedést mérő teszt, egyszerűsítő kör, futószalag), és a gyakori-leletek listáját (`docs/review/gyakori-leletek.md`). | A user szava (2026-11-20): a Munkarend 2.8 kerüljön minden repóba. | nincs |
| D3 | 2026-11-20 | A repó munkarendje a sablon 2.8-as változatáról (`b40cfcd`) a 2.9-esre frissült (`ea970f2`). Két új sor: minden munkamenet kontextusa 250 ezer tokenre tervezett, 300 ezernél megáll, a segédügynököké is (2.9 Kontextus); egy feladatra összesen legfeljebb 5 segédügynök indulhat, és a segéd nem indít további segédet (2.10 Ügynökök). | A user szava (2026-11-20): a kontextuskeret és a segédügynökök száma kerüljön be a munkarendbe, minden repóba. | nincs |
