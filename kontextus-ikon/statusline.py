#!/usr/bin/env python3
"""Claude Code statusline: kiírja a használati kereteket (5 órás, heti), mindkettő mellé a Fable 5.2
becsült részét, és a futó subagentek közül a legnagyobb kontextust (agentenként, nem összegezve)."""

import datetime
import glob
import json
import os
import sys
import time

NAMES = {"five_hour": "5 órás", "seven_day": "heti"}
ACTIVE_SECONDS = 90  # an agent transcript written within this window counts as running
CTX_LIMIT = 200_000  # per-agent context above this is shown in red
TAIL_BYTES = 256 * 1024

# Fable share: the CLI sends no separate Fable limit, so it is estimated from the local transcripts.
FABLE_PREFIX = "claude-fable-5-2"
FABLE_LABEL = "Fable 5.2"
WINDOWS = {"five_hour": 5 * 3600, "seven_day": 7 * 86400}  # window lengths in seconds
# API list prices in $/MTok (input, output, cache read), used only as weights between token kinds and models.
PRICES = {
    "claude-fable-5-2": (8.0, 40.0, 0.20),
    "claude-opus-5-5": (4.0, 20.0, 0.20),
    "claude-sonnet-5-5": (2.0, 10.0, 0.10),
    "claude-haiku-5-5": (0.10, 0.50, 0.01),
}
DEFAULT_PRICE = (4.0, 20.0, 0.20)
CACHE_WRITE_5M, CACHE_WRITE_1H = 1.25, 2.0  # multipliers on the input price (assumed)
PROJECTS_DIR = os.path.expanduser("~/.claude/projects")
SHARE_CACHE = os.path.expanduser("~/.cache/claude-fable-share.json")
SCAN_EVERY = 30  # seconds between transcript scans
KEEP_SECONDS = 8 * 86400


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


def message_cost(model, u):
    """Weighted cost of one model call in dollars at list price."""
    pin, pout, pread = DEFAULT_PRICE
    for prefix, price in PRICES.items():
        if model.startswith(prefix):
            pin, pout, pread = price
            break
    cc = u.get("cache_creation") or {}
    w1h = cc.get("ephemeral_1h_input_tokens", 0)
    w5m = cc.get("ephemeral_5m_input_tokens", 0)
    if not (w1h or w5m):
        w5m = u.get("cache_creation_input_tokens", 0)
    return (u.get("input_tokens", 0) * pin + u.get("output_tokens", 0) * pout
            + u.get("cache_read_input_tokens", 0) * pread
            + w5m * pin * CACHE_WRITE_5M + w1h * pin * CACHE_WRITE_1H) / 1e6


def scan_file(path, offset, msgs):
    """Read the complete lines after offset, record each model call by message id; return the new offset."""
    with open(path, "rb") as f:
        f.seek(offset)
        data = f.read()
    end = data.rfind(b"\n") + 1
    for line in data[:end].splitlines():
        if b'"usage"' not in line:
            continue
        try:
            j = json.loads(line)
            msg = j.get("message") or {}
            u = msg.get("usage")
            model = msg.get("model") or ""
            if not u or msg.get("role") != "assistant" or model == "<synthetic>":
                continue
            ts = datetime.datetime.fromisoformat(j["timestamp"].replace("Z", "+00:00")).timestamp()
            cost = message_cost(model, u)
        except (ValueError, KeyError, TypeError, AttributeError):
            continue
        mid = msg.get("id") or j.get("uuid")
        old = msgs.get(mid)
        if old is None or cost > old[2]:  # the same call is logged once per content block
            msgs[mid] = [ts, 1 if model.startswith(FABLE_PREFIX) else 0, cost]
    return offset + end


def load_calls():
    """Model calls of the last KEEP_SECONDS as {id: [ts, is_fable, cost]}, from an incrementally updated cache."""
    now = time.time()
    try:
        with open(SHARE_CACHE, encoding="utf-8") as f:
            c = json.load(f)
        files, msgs = c["files"], c["msgs"]
        if now - c["scanned"] < SCAN_EVERY:
            return msgs
    except (OSError, ValueError, KeyError, TypeError):
        files, msgs = {}, {}
    seen = {}
    for path in glob.glob(os.path.join(PROJECTS_DIR, "**", "*.jsonl"), recursive=True):
        try:
            st = os.stat(path)
            if now - st.st_mtime > KEEP_SECONDS:
                continue
            offset = files.get(path, 0)
            if st.st_size < offset:
                offset = 0
            seen[path] = scan_file(path, offset, msgs) if st.st_size > offset else offset
        except OSError:
            continue
    msgs = {k: v for k, v in msgs.items() if now - v[0] <= KEEP_SECONDS}
    tmp = f"{SHARE_CACHE}.{os.getpid()}.tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"scanned": now, "files": seen, "msgs": msgs}, f)
        os.replace(tmp, SHARE_CACHE)
    except OSError:
        pass
    return msgs


def fable_points(calls, key, v):
    """Estimated part of the window's used percentage that went to Fable, or None if it can't be told."""
    length, resets = WINDOWS.get(key), v.get("resets_at")
    if not length or not resets:
        return None
    start = resets - length
    total = fable = 0.0
    for ts, is_fable, cost in calls.values():
        if ts >= start:
            total += cost
            if is_fable:
                fable += cost
    if not total:
        return None
    return v["used_percentage"] * fable / total


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
    calls = None
    for key, v in rl.items():
        if isinstance(v, dict) and v.get("used_percentage") is not None:
            text = f"{label(key)}: {round(v['used_percentage'])}%"
            try:
                if calls is None:
                    calls = load_calls()
                pts = fable_points(calls, key, v)
            except Exception:
                pts = None
            if pts is not None:
                text += f" (ebből {FABLE_LABEL}: ~{round(pts)}%)"
            parts.append(text)
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
