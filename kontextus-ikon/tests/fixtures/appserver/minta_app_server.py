#!/usr/bin/env python3
"""Kézzel írt `codex app-server` utánzat a tesztekhez (hálózat és valódi Codex nélkül): stdio, soronként egy
JSON-üzenet, mint a valódi (a 2026-11-15-i próbán mérve). A kapott üzeneteket a LOG fájlba írja (soronként).

    minta_app_server.py FORGATÓKÖNYV LOG

Forgatókönyvek: ok, ertesites, ertesites-masik, nincs-bejelentkezes, apikulcs, kilep, nem-valaszol, szemet,
hibas-sema (első lekérésre szöveges error, a másodikra nem várt alakú értesítés, id és result)."""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
scenario, log_path = sys.argv[1], sys.argv[2]
reads = 0


def fixture(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return json.load(f)


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


for line in sys.stdin:
    msg = json.loads(line)
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(json.dumps(msg) + "\n")
    method, mid = msg.get("method"), msg.get("id")
    if method == "initialize":
        if scenario == "kilep":
            sys.exit(3)
        if scenario == "szemet":
            sys.stdout.write("ez nem JSON\n")
        send({"id": mid, "result": {"userAgent": "minta/0.0", "codexHome": "/nincs", "platformFamily": "unix",
                                    "platformOs": "linux"}})
        send({"method": "account/updated", "params": {"authMode": "chatgpt", "planType": "plus"}})
    elif method == "account/rateLimits/read":
        if scenario == "nem-valaszol":
            continue
        reads += 1
        if scenario == "hibas-sema" and reads == 1:
            send({"id": mid, "error": "szöveges hiba"})
        elif scenario == "hibas-sema":
            send({"method": "account/rateLimits/updated", "params": [1, 2]})
            send({"method": "account/rateLimits/updated", "params": {"rateLimits": {"primary": {"usedPercent": "sok",
                                                                                       "windowDurationMins": 300}}}})
            send({"id": [mid], "result": {}})
            send({"id": {"x": 1}, "result": {}})
            send({"id": mid, "result": "szöveg"})
        elif scenario == "nincs-bejelentkezes":
            send({"id": mid, "error": {"code": -32600,
                                       "message": "codex account authentication required to read rate limits"}})
        elif scenario == "apikulcs":
            send({"id": mid, "error": {"code": -32600,
                                       "message": "chatgpt authentication required to read rate limits"}})
        else:
            send({"id": mid, "result": fixture("rate-limits.json")})
            if scenario == "ertesites":
                send(fixture("updated.json"))
            elif scenario == "ertesites-masik":
                send(fixture("updated-masik.json"))
