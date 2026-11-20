# Review-kimenetek

Ide kerül minden review-kör kimenete, feladatonként külön mappában, hogy a döntés a mentett kimenetekből visszakövethető legyen. (S64)

- Útvonal: `docs/review/<feladat azonosítója>/r<n>.md`, ahol `<n>` a kör sorszáma. A javítókör új fájl.
- A reviewer csak olvas, nem szerkeszt kódot. (S52) A minimumot kapja: a kérdést, a diffet, a feladatlapot és a kapu jelentését. Az író javaslatát és ítéletét nem kapja meg. (K55, K56)
- A reviewer nézze a hibautakat (rossz bemenet, ismételt és egyidejű hívás, félbeszakadás), a hatókört és a betű szerinti megfelelést: van teszt, de a neve szerinti okból bukna-e. (S53, S55)
- Javítókörben a reviewer csak a javító diffet nézi. A találatnál többet változtató javítás is találat. (S61)
- Ha két javítókör után ugyanaz a hiba áll fenn, a reviewer és a kódoló ne folytassa ugyanazzal a megközelítéssel: a user dönt. Ha a körök haladnak, folytatható. (K85)
- Döntésütközésben a reviewer nem dönt, az a useré. (S59)

## Mi a találat

Találat az, amelyhez a reviewer meg tudja nevezni a hibás bemenetet vagy eseménysort. Nem találat a stílus, az ízlés, a méret, a kapu által már jelzett hiba, és az el nem olvasott kódról szóló találgatás. (S58) A kértnél többet vagy mást csináló helyes kód találat. (S54) A gyengített ellenőrzés mindig találat. (S56)

Súlyosság:
- blocker: megállítja a merge-et.
- major: megállítja a merge-et.
- minor: a munkaegység zárásáig javítani vagy írásban indokolni kell.
(S49)

## A találat formátuma

```markdown
### R<kör>-<sorszám> <blocker | major | minor>: <egy mondat>
- Hely: <fájl:sor>
- Hibás bemenet vagy eseménysor: <mi történik, és mi lenne az elvárt>
- Bizonyíték: <idézet a kódból, vagy parancs és kilépési kód; ha csak olvasva: „csak olvasva”>
- Zárás: <üres, amíg nyitott>
```

## Zárás

Minden találatot le kell zárni, a zárást a kódoló javasolja, a reviewer fogadja el. (S60)
- „javítva”: a commit, és hogy mi változott. A javítás az okot szüntesse meg, ne a tünetet.
- „indokolva marad”: miért marad, erre a kódra nézve.

Ne javíts ki automatikusan minden leletet, mert az felesleges absztrakciót és lehetetlen esetekre írt teszteket szül. (K23 lelet) Szabály alóli kivételt csak a független reviewer hagyhat jóvá, az író nem. (S50)
