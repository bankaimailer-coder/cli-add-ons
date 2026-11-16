# Claude indító

Dokkba tűzött ikon. Rákattintva választóablak jön fel a munkamappákkal, utána egy második kérdés:
új beszélgetés vagy a legutóbbi folytatása. Ezután új terminálablak (Ptyxis) nyílik a kiválasztott
mappában, és elindul benne a `claude`. Ha kilépsz a Claude-ból, a terminál nyitva marad.

Minden repó ablaka saját színt kap (saját Ptyxis-profil saját palettával), így több egyszerre
nyitott Claude-ablak is ránézésre megkülönböztethető. Ugyanaz a repó mindig ugyanazt a színt kapja.

## Telepítés

```sh
sh install.sh
```

Ez a dokk-ikon mellett a színprofilokat is létrehozza. Többször is futtatható.

## Mappák szerkesztése

A lista a [`mappak.txt`](mappak.txt) fájlban van, soronként egy repó `Név | mappa | szín` alakban.
Újratelepítés nem kell, csak színváltozás vagy új repó után a profilok frissítése (lásd lent).

## Színek

A szín a sor harmadik oszlopa (`#rrggbb`, sötét háttér). Ha nincs megadva, a repó nevéből számolt
szín lesz (mindig ugyanaz). Az azonos nevű sorok (kis- és nagybetű nem számít) ugyanazt a színt kapják,
így egy repó minden gépen ugyanolyan. A szöveg színét a háttérhez igazítja (legalább 7:1 kontraszt).

```sh
python3 szinprofil.py lista        # repó -> szín
python3 szinprofil.py telepit      # profilok létrehozása/frissítése (a mappak.txt szerint)
python3 szinprofil.py eltavolit    # a saját profilok és paletták törlése
python3 szinprofil.py elonezet /tmp/szinek.html   # színminták böngészőben
```

A `telepit` csak az ezen a gépen létező mappákhoz készít profilt, a profil neve a repó neve.
A saját profiljait az állapotfájlból ismeri fel (`~/.local/share/claude-indito/profilok.tsv`),
a palettákat a `~/.local/share/org.gnome.Ptyxis/palettes/claude-indito-*.palette` fájlokba írja.
Más (kézzel készült) profilhoz nem nyúl, a mappak.txt-ből kikerült repók saját profilját törli.
Ha nincs profil egy repóhoz, az indító a szokásos profillal nyit ablakot.

## Kézzel indított `claude` és `codex` (nem kötelező)

Ha egy sima terminálablakban indítod a `claude`-ot vagy a `codex`-et, a [`szinezo.sh`](szinezo.sh)
a futás idejére a repó színére állítja a terminál hátterét és szövegét, kilépéskor visszaállítja.
Bekapcsolás: a `~/.bashrc` végére

```sh
. "$HOME/AI PROJECTS/cli-add-ons/claude-indito/szinezo.sh"
```

Ez csak a terminál belsejét színezi (a fejlécet nem), és kimarad az indító saját profilos ablakaiban.
A repót a mappa alapján keresi a mappak.txt-ben; ha nincs ott, a mappa nevéből számol színt.
