#!/usr/bin/env python3
"""PostToolUse hook (minden eszköz): kontextus-mérés, kijelzés és soft stop (user döntése, 2026-10-28).

Hívásszámláló session + alügynök szerint (~/.cache/kontextus_horog/). Minden MERES_MINDEN. hívásnál (a SOFT_HATAR után
SURU_MERES-enként) kiolvassa a transcript utolsó assistant üzenetének usage mezőit:
kontextus = input_tokens + cache_read_input_tokens + cache_creation_input_tokens (a statusline used_percentage képlete).
- Mindig: systemMessage a usernek (a CLI-ben nem látja a kontextust).
- >= SOFT_HATAR: additionalContext a modellnek: a most futó lezárható lépést befejezi, újat nem kezd, folytató promptot ír, megáll.
- >= ERŐS_HATAR: ugyanez erősebben, minden méréskor. Hard stop (continue:false) soha (user, 10-28).
Alügynöknél a saját transcript: <session>/subagents/agent-<agent_id>.jsonl. A transcript formátuma belső, verzióváltáskor törhet:
ha nem olvasható, a horog csendben kilép. Próbához a határok felülírhatók: ~/.cache/kontextus_horog/beallitas.json ({"session": <id>, "SOFT_HATAR": …}).
"""
import json
import os
import sys

ALLAPOT_DIR = os.path.expanduser("~/.cache/kontextus_horog")
BEALLITAS = {
    "ABLAK": 1_000_000,
    "MERES_MINDEN": 20,
    "SURU_MERES": 5,
    "SOFT_HATAR": 500_000,
    "EROS_HATAR": 600_000,
}
OLVASAS_LEPES = 1 << 20  # a transcript végéről 1 MB-os darabokban, legfeljebb 16 MB
OLVASAS_MAX = 16 << 20


def beallitas(sid):
    """A beallitas.json felülírja a határokat; ha "session" mezője van, csak arra a sessionre (és alügynökeire)."""
    b = dict(BEALLITAS)
    try:
        with open(os.path.join(ALLAPOT_DIR, "beallitas.json"), encoding="utf-8") as f:
            felul = json.load(f)
        if felul.get("session") in (None, sid):
            b.update({k: int(v) for k, v in felul.items() if k in BEALLITAS})
    except (OSError, ValueError, AttributeError):
        pass
    return b


def utolso_kontextus(path):
    """A transcript végéről visszafelé az utolsó assistant usage; None, ha nincs."""
    try:
        meret = os.path.getsize(path)
        with open(path, "rb") as f:
            olvasott = 0
            while olvasott < min(meret, OLVASAS_MAX):
                olvasott = min(meret, olvasott + OLVASAS_LEPES)
                f.seek(meret - olvasott)
                sorok = f.read(olvasott).split(b"\n")
                if olvasott < meret:
                    sorok = sorok[1:]  # az első sor csonka lehet
                for sor in reversed(sorok):
                    if b'"assistant"' not in sor or b'"usage"' not in sor:
                        continue
                    try:
                        d = json.loads(sor)
                    except ValueError:
                        continue
                    u = (d.get("message") or {}).get("usage")
                    if d.get("type") == "assistant" and u:
                        return (u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0)
                                + u.get("cache_creation_input_tokens", 0))
    except OSError:
        pass
    return None


def atado_utasitas(alugynok, cwd, tokenek, eros, b):
    k = f"{tokenek // 1000}k"
    soft, eros_k = f"{b['SOFT_HATAR'] // 1000}k", f"{b['EROS_HATAR'] // 1000}k"
    if alugynok:
        hova = ("a ~/projects/Soborbo/wt_handoff/session_handoff/HANDOFF_<sorszám>.md fájlba (ha a feladatfájlod más "
                "átadót nevez meg, abba)" if "/projects/Soborbo/" in cwd else "a munkamappád egy HANDOFF.md fájljába")
        mit = (f"a folytató átadót {hova}, az atado-ventilator skill mintájára (a skillt ne hívd): mi kész, mi félkész, "
               "melyik fájlok, a következő lépés, és a futtatandó ellenőrzések. A záró válaszodban add meg a fájl útvonalát, "
               "hogy a főügynök egy friss alügynököt indíthasson vele")
    else:
        mit = ("a folytató promptot: a nemesventilatorhaz repóban az atado-ventilator skillel (átadó + PROMPT_FOLYTATAS), "
               "máshol egy rövid átadó fájlt. Utána mondd a usernek, hogy /clear után ezzel folytathatja")
    if eros:
        return (f"KONTEXTUS-HATÁR ÁTLÉPVE: {k} (>= {eros_k}). Most már ne végezz új munkát: zárd le a futó lépést a legközelebbi "
                f"lezárható ponton, írd meg {mit}, és állj meg.")
    return (f"Kontextus-határ: {k} (>= {soft}). Soft stop: a most futó, lezárható lépést fejezd be, újat ne kezdj. Utána írd meg "
            f"{mit}, és állj meg.")


def ment(fajl, allapot):
    """Atomikus írás: párhuzamos eszközhívásnál sem marad félig írt fájl (egy-egy hívás elveszhet, az nem baj)."""
    tmp = f"{fajl}.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(allapot, f)
    os.replace(tmp, fajl)


def projekt_sajat_horga():
    """Ha a projektnek saját, projektszintű kontextus-horga van (pl. soborbo-leads), a globális nem fut duplán."""
    projekt = os.environ.get("CLAUDE_PROJECT_DIR") or ""
    sajat = os.path.join(projekt, ".claude", "hooks", "kontextus_horog.py")
    return bool(projekt) and os.path.isfile(sajat) and os.path.realpath(sajat) != os.path.realpath(__file__)


def main():
    if projekt_sajat_horga():
        return
    try:
        adat = json.load(sys.stdin)
    except ValueError:
        return
    sid = adat.get("session_id") or "ismeretlen"
    b = beallitas(sid)
    agent_id = adat.get("agent_id") or ""
    transcript = adat.get("transcript_path") or ""
    if agent_id and transcript.endswith(".jsonl"):
        transcript = os.path.join(transcript[:-6], "subagents", f"agent-{agent_id}.jsonl")

    os.makedirs(ALLAPOT_DIR, exist_ok=True)
    allapot_fajl = os.path.join(ALLAPOT_DIR, f"{sid}_{agent_id or 'fo'}.json")
    try:
        with open(allapot_fajl, encoding="utf-8") as f:
            allapot = json.load(f)
    except (OSError, ValueError):
        allapot = {"hivas": 0, "utolso_meres": 0, "hataron": False}
    allapot["hivas"] += 1
    lepes = b["SURU_MERES"] if allapot["hataron"] else b["MERES_MINDEN"]
    meres = allapot["hivas"] - allapot["utolso_meres"] >= lepes
    if meres:
        allapot["utolso_meres"] = allapot["hivas"]
    ment(allapot_fajl, allapot)
    if not meres:
        return

    tokenek = utolso_kontextus(transcript)
    if tokenek is None:
        return
    ki = f"alügynök {adat.get('agent_type') or ''} {agent_id[:8]}".replace("  ", " ") if agent_id else "fő session"
    szazalek = round(100 * tokenek / b["ABLAK"])
    kimenet = {"systemMessage": f"Kontextus ({ki}): {tokenek // 1000}k / {b['ABLAK'] // 1000}k ({szazalek}%), "
                                f"{allapot['hivas']}. hívás"}
    if tokenek >= b["SOFT_HATAR"]:
        eros = tokenek >= b["EROS_HATAR"]
        kimenet["systemMessage"] += " | ÁTADÁS KÉRVE" if not eros else f" | ÁTADÁS KÉRVE ({b['EROS_HATAR'] // 1000}k fölött)"
        kimenet["hookSpecificOutput"] = {
            "hookEventName": "PostToolUse",
            "additionalContext": atado_utasitas(bool(agent_id), adat.get("cwd") or "", tokenek, eros, b),
        }
        if not allapot["hataron"]:
            allapot["hataron"] = True
            ment(allapot_fajl, allapot)
    print(json.dumps(kimenet, ensure_ascii=False))


if __name__ == "__main__":
    main()
