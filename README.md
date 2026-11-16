# CLI add-ons

Kiegészítők a Claude Code CLI-hoz Ubuntu GNOME alatt.

- [`kontextus-ikon`](kontextus-ikon/): a nyitott Claude Code terminálok kontextushasználata a felső sávban
  (körív-mérők az ablakválasztó mellett), ugrás a terminálba, a rendszerikonok mellett keretmérők (Claude és
  Codex), hőmérők és memória-chip, valamint egy statusline, amely minden CLI alján kiírja a keretek kihasználtságát.
- [`claude-indito`](claude-indito/): dokkba tűzött ikon, amely választóablakból indítja a Claude Code-ot
  a kiválasztott munkamappában (új beszélgetés vagy folytatás), repónkénti terminálszínekkel.
- [`kontextus-horog`](kontextus-horog/): Claude Code hook, amely méri a kontextust (alügynökökben is), és 500k-nál
  soft stopot, 600k-nál erős stopot kér.
- [`hofigyelo`](hofigyelo/): túlmelegedés elleni védelem. Háttérszolgáltatás méri a CPU és a GPU hőmérsékletét
  (ebből olvasnak a sáv hőmérői), melegedéskor figyelmeztet és visszavesz a terhelésből; a horga forró gépen
  nem engedi az ügynököknek új build, teszt vagy Chrome indítását.

## Telepítés

    git clone https://github.com/bankaimailer-coder/cli-add-ons.git ~/projects/cli-extensions
    sh ~/projects/cli-extensions/install.sh

A közös telepítő sorban lefuttatja mind a négy összetevő saját telepítőjét. Root nem kell, többször is futtatható;
ha egy összetevő elbukik (például hiányzik hozzá egy program), a többi lefut, a végén összesítés jön. Utána egyszer
ki kell jelentkezni és vissza, hogy a sáv mérői megjelenjenek.

- Csak egyes összetevők: `sh install.sh kontextus-ikon hofigyelo`
- A hőfigyelő horgai nélkül (csak a szolgáltatás és a hőmérők): `sh install.sh --horog-nelkul`

Az összetevők külön is telepíthetők a saját mappájuk `install.sh` fájljával; a részletek a mappák README-jében.
