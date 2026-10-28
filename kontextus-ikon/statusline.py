#!/usr/bin/env python3
"""Claude Code statusline: kiírja a használati kereteket (5 órás, heti)."""

import json
import sys

NAMES = {"five_hour": "5 órás", "seven_day": "heti"}


def label(key):
    if key in NAMES:
        return NAMES[key]
    if "fable" in key.lower():
        return "Fable"
    return key


def main():
    try:
        d = json.load(sys.stdin)
    except ValueError:
        return
    rl = d.get("rate_limits") or {}
    parts = []
    for key, v in rl.items():
        if isinstance(v, dict) and v.get("used_percentage") is not None:
            parts.append(f"{label(key)}: {round(v['used_percentage'])}%")
    if parts:
        print(" | ".join(parts))


if __name__ == "__main__":
    try:
        main()
    except Exception:  # a statusline sose akassza meg a CLI-t
        pass
