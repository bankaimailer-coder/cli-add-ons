# Átadó-sablonok

Két fajta átadó van. A kódoló-átadó egy feladat végén készül, a munkamenet-átadó a munkamenet végén vagy parkoláskor. Mindkettő új fájl: `docs/atado/<éééé-hh-nn>-<téma>.md`. Régi átadót ne írj át. A legfrissebb az érvényes, és kimondhatja, mit ír felül a korábbiakból. (S80)

Csak azt nevezd lefutottnak, amit ebben a munkamenetben futtattál, a parancs és a kilépési kód megadásával. (S36) A `<…>` jelű részt töltsd ki, a nem értelmezhető sort hagyd ki.

## 1. Kódoló-átadó (egy feladat végén)

```markdown
# Átadó (<dátum>): <feladat azonosítója> <cím>, kódoló (<állapot, pl. „a kapuig zárva”>)
- Feladatlap: <útvonal> · Ág: <ág> · Alap-commit: <hash> · Review: <állapot>

## Mi készült
- <útvonal>: <mi változott, mely esetek, hány teszt>

## Ellenőrzések ebben a munkamenetben
- <parancs>: kilépési kód <n>, <darabszám>, jelentés: <útvonal>

## Nincs kész vagy nincs ellenőrizve
- <tételesen; ha nincs: „nincs”>

## Gyengített ellenőrzés
<lazított assert, módosított elvárt érték, törölt vagy kihagyott teszt; ha nincs: „nincs”>

## Nyitott
- <értelmezési pont, amit nem mértem, ami nem az én feladatom>

## Javítókör <n> (ha volt)
- <találat>: <javítva, mi változott | indokolva marad, miért>

## Megjegyzés
<apró viselkedés-eltérés, a valódi próba helye>
```

## 2. Munkamenet-átadó (a munkamenet végén vagy parkoláskor)

```markdown
# Átadó (<dátum, napszak>): <a helyzet egy mondatban>
> Felülírja: <korábbi átadó vagy „semmit”>. Tiltás: <„ne indíts …, amíg …”, ha van>.

## Ma eldőlt
- <döntés> (hivatkozás: <D-azonosító a docs/dontesek.md fájlból>)

## Mire várunk
<a megállás oka; kitől, milyen döntést; DK-azonosító>

## Állapot
| Munkamappa vagy ág | Commit | Állapot | Ellenőrizve (parancs) |
|--------------------|--------|---------|-----------------------|

## Ellenőrzések ebben a munkamenetben
- <parancs>: kilépési kód <n>, <darabszám>, jelentés: <útvonal>

## Nyitott
- <értelmezési pont, amit nem mértem, ami nem az én feladatom>

## Teendő, sorrendben
1. <…>

## Bemásolandó indító prompt
~~~text
HATÓKÖR: <mi a feladat, melyik repó vagy mappa>
KIZÁRVA: <ahova nem írhat, amit nem dönthet el>

Olvasd el: MUNKAREND.md, <ez az átadó útvonala>, <feladatlap>.
Állapot: <egy mondat>. Az utolsó ellenőrzött commit: <hash>.
Következő lépés: <az első teendő>.
Kész, ha: <ellenőrizhető feltétel>.
A végén írj átadót ugyanebben a formában.
~~~
```
