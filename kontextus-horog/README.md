# Kontextus-horog

Claude Code PostToolUse hook, amely minden eszközhívás után számolja a hívásokat, és rendszeresen megméri
a kontextust a transcript utolsó assistant üzenetéből (fő sessionben és alügynökben külön).

- Minden mérésnél rendszerüzenetet ír ki: pl. „Kontextus (fő session): 312k / 1000k (31%)”.
- 500k fölött (soft stop): a modell befejezi a futó lépést, megírja a folytató átadót, és megáll.
- 600k fölött (erős stop): ugyanez erősebben, minden mérésnél.

A határok a `kontextus_horog.py` elején vannak (`BEALLITAS`).

## Telepítés

```sh
sh install.sh
```

A telepítő a `~/.claude/settings.json`-ba jegyzi be ennek a mappának a `kontextus_horog.py`-ját (előtte mentést
készít). Ha a horog máshonnan volt bejegyezve, átírja az útvonalat. Másik gépen: `git pull`, majd ugyanez.
