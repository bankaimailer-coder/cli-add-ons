#!/usr/bin/env python3
"""Claude Code statusline: kiírja a használati kereteket (5 órás, heti), és a futó subagentek közül
a legnagyobb kontextust (agentenként, nem összegezve)."""

import glob
import json
import os
import sys
import time

NAMES = {"five_hour": "5 órás", "seven_day": "heti"}
ACTIVE_SECONDS = 90  # an agent transcript written within this window counts as running
CTX_LIMIT = 200_000  # per-agent context above this is shown in red
TAIL_BYTES = 256 * 1024


def label(key):
    if key in NAMES:
        return NAMES[key]
    if "fable" in key.lower():
        return "Fable"
    return key


def last_context(path):
    """Context size of the agent's latest model call, read from the tail of its transcript."""
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        f.seek(max(0, f.tell() - TAIL_BYTES))
        lines = f.read().decode("utf-8", "replace").splitlines()
    for line in reversed(lines):
        try:
            msg = json.loads(line).get("message") or {}
        except ValueError:
            continue
        u = msg.get("usage")
        if u and msg.get("role") == "assistant":
            return (u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0)
                    + u.get("cache_creation_input_tokens", 0))
    return 0


def subagents_part(d):
    """'agentek: N fut, max XK / 200K' for this session's running subagents (workflow and Agent tool)."""
    tp = d.get("transcript_path")
    if not tp:
        return None
    base = os.path.join(os.path.splitext(tp)[0], "subagents")
    now = time.time()
    sizes = []
    for path in glob.glob(os.path.join(base, "**", "agent-*.jsonl"), recursive=True):
        if now - os.path.getmtime(path) <= ACTIVE_SECONDS:
            sizes.append(last_context(path))
    if not sizes:
        return None
    top = max(sizes)
    text = f"agentek: {len(sizes)} fut, max {top // 1000}K / {CTX_LIMIT // 1000}K"
    return f"\033[31m{text}\033[0m" if top > CTX_LIMIT else text


def main():
    raw = sys.stdin.read()
    try:  # TEMPORARY debug (2026-11-10): what the CLI sends; remove after the check
        with open(os.path.expanduser("~/.cache/statusline-debug.json"), "w", encoding="utf-8") as f:
            f.write(raw)
    except OSError:
        pass
    try:
        d = json.loads(raw)
    except ValueError:
        return
    rl = d.get("rate_limits") or {}
    parts = []
    for key, v in rl.items():
        if isinstance(v, dict) and v.get("used_percentage") is not None:
            parts.append(f"{label(key)}: {round(v['used_percentage'])}%")
    try:
        sub = subagents_part(d)
    except OSError:
        sub = None
    if sub:
        parts.append(sub)
    if parts:
        print(" | ".join(parts))


if __name__ == "__main__":
    try:
        main()
    except Exception:  # a statusline sose akassza meg a CLI-t
        pass
