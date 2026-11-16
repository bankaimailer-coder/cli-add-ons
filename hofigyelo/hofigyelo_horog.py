#!/usr/bin/env python3
"""Claude Code horog a Hőfigyelőhöz.

- UserPromptSubmit / PostToolUse: ha a gép melegszik, figyelmeztetést tesz az
  ügynök kontextusába (munkamenetenként és szintenként legfeljebb percenként egyszer).
- PreToolUse (Bash): hot/critical szinten megtiltja új Chrome/Puppeteer, build és
  nehéz teszt indítását; hőmérséklettől függetlenül megtiltja új Chrome indítását,
  ha már 6 Puppeteer-Chrome fut (Red Lane limit).

Ha a Hőfigyelő nem fut (az állapotfájl hiányzik vagy 60 mp-nél régebbi), csendben
nem csinál semmit, hogy soha ne akassza meg az ügynököket.
"""
import json
import os
import re
import sys
import time
from pathlib import Path

RUN_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "hofigyelo"
STATE = RUN_DIR / "state.json"
RANK = {"ok": 0, "warm": 1, "hot": 2, "critical": 3}
CHROME = re.compile(r"\b(chrome|chromium|puppeteer|playwright)\b", re.I)
HEAVY = re.compile(
    r"\b(npm|pnpm|yarn|bun)\s+(run\s+)?(build|test|e2e)\b|\bnpx\s+(jest|vitest|playwright|"
    r"next\s+build|vite\s+build|tsc)\b|\b(cargo|go)\s+(build|test)\b|\bmake\b|\bwebpack\b|"
    r"\bdocker\s+(build|compose\s+up)\b|\bpytest\b|\bgradle\b|\bmvn\b", re.I)


def out(obj):
    print(json.dumps(obj, ensure_ascii=False))
    sys.exit(0)


def main():
    try:
        data = json.load(sys.stdin)
        state = json.loads(STATE.read_text())
    except (OSError, ValueError):
        sys.exit(0)
    if time.time() - state.get("ts", 0) > 60:
        sys.exit(0)

    event = data.get("hook_event_name", "")
    level = state.get("level", "ok")
    rank = RANK.get(level, 0)

    if event == "PreToolUse":
        cmd = (data.get("tool_input") or {}).get("command", "")
        reason = None
        if rank >= RANK["hot"] and (CHROME.search(cmd) or HEAVY.search(cmd)):
            reason = (f"Hőfigyelő: a gép {level} állapotban van "
                      f"(CPU {state.get('cpu_median_c') or 0:.0f} °C). Új Chrome, build vagy "
                      "nehéz teszt most nem indítható. Várj a lehűlésig, vagy végezz könnyű "
                      "munkát (olvasás, szerkesztés).")
        elif CHROME.search(cmd) and state.get("puppeteer_chromes", 0) >= state.get("chrome_limit", 6):
            reason = (f"Hőfigyelő: már {state['puppeteer_chromes']} Puppeteer-Chrome fut, ez a "
                      "gép limitje (Red Lane: 6). Zárj be egy böngészőt, mielőtt újat indítasz.")
        if reason:
            out({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                        "permissionDecision": "deny",
                                        "permissionDecisionReason": reason}})
        sys.exit(0)

    if event in ("PostToolUse", "UserPromptSubmit") and rank >= RANK["warm"]:
        # ritkítás: munkamenetenként + szintenként legfeljebb 60 mp-enként
        sid = re.sub(r"[^A-Za-z0-9_-]", "", data.get("session_id", "x"))[:64]
        mark = RUN_DIR / f"jelzes-{sid}-{level}"
        try:
            if time.time() - mark.stat().st_mtime < 60:
                sys.exit(0)
        except OSError:
            pass
        try:
            mark.touch()
        except OSError:
            pass
        out({"hookSpecificOutput": {"hookEventName": event,
                                    "additionalContext": "[Hőfigyelő] " + state.get("message", "")}})
    sys.exit(0)


if __name__ == "__main__":
    main()
