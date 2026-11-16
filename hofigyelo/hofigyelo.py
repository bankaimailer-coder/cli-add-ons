#!/usr/bin/env python3
"""Hőfigyelő — ASUS Vivobook Pro 15 M6500QC (Ryzen 7 5800H + RTX 3050 Laptop).

5 másodpercenként méri a CPU/GPU hőmérsékletét és a futó Puppeteer-Chrome-okat,
a szintet kiírja egy állapotfájlba (ezt olvassa a Claude Code horog, és ebből
kapnak az ügynökök figyelmeztetést), szintváltáskor asztali értesítést küld,
és szükség esetén maga is visszavesz a terhelésből.

Határértékek (gyártói / firmware):
  - CPU Tjmax: 105 °C (AMD Ryzen 7 5800H)
  - Laptop firmware (ACPI THRM): passzív hűtés 101 °C, kritikus leállás 103 °C
  - GPU (nvidia-smi, VBIOS): cél 87 °C, lassítás 97 °C, leállás 100 °C
  - A ryzenadj-profil performance módban 90 °C-ra korlátozza a CPU-t.

Szintek (30 mp-es medián, hiszterézissel):
  ok -> warm (CPU >= 92 / GPU >= 88): az ügynökök figyelmeztetést kapnak
  hot  (CPU >= 95 / GPU >= 95): az ügynökök felszólítást kapnak a futások leállítására,
       új nehéz feladat (Chrome, build, teszt) tiltva,
       energiamód: balanced
  critical (CPU >= 99 / GPU >= 98): energiamód: power-saver, a Puppeteer-Chrome-ok
       ideiglenesen szünetelnek (SIGSTOP), és lehűlés után automatikusan
       folytatódnak (SIGCONT)
"""
import csv
import json
import os
import signal
import statistics
import subprocess
import sys
import time
from collections import deque
from pathlib import Path

INTERVAL = 5
WINDOW = 6                      # 6 x 5 mp = 30 mp medián
LOG_EVERY = 30                  # CSV-napló sűrűsége (mp)
LEVELS = ["ok", "warm", "hot", "critical"]
# (belépés, kilépés) küszöbök °C-ban
CPU_TH = {"warm": (92, 88), "hot": (95, 91), "critical": (99, 94)}
GPU_TH = {"warm": (88, 84), "hot": (95, 91), "critical": (98, 93)}
CHROME_RED_LANE = 6             # CLAUDE.md: Red Lane legfeljebb 6 Chrome-ügynök
DGPU = Path("/sys/bus/pci/devices/0000:01:00.0/power/runtime_status")

RUN_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "hofigyelo"
STATE = RUN_DIR / "state.json"
LOG_DIR = Path.home() / ".local/state/hofigyelo"


def hwmon(name, label=None):
    for h in Path("/sys/class/hwmon").glob("hwmon*"):
        try:
            if (h / "name").read_text().strip() != name:
                continue
            for t in sorted(h.glob("temp*_input")):
                lf = t.with_name(t.name.replace("_input", "_label"))
                if label is None or (lf.exists() and lf.read_text().strip() == label):
                    return int(t.read_text()) / 1000
        except OSError:
            pass
    return None


def gpu_temp():
    """Csak akkor kérdezi az NVIDIA GPU-t, ha amúgy is ébren van (nem ébreszti fel)."""
    try:
        if DGPU.read_text().strip() != "active":
            return None
        out = subprocess.run(["nvidia-smi", "--query-gpu=temperature.gpu",
                              "--format=csv,noheader,nounits"],
                             capture_output=True, text=True, timeout=5).stdout
        return float(out.strip().splitlines()[0])
    except (OSError, ValueError, IndexError, subprocess.SubprocessError):
        return None


def puppeteer_chromes():
    """A Puppeteer által indított Chrome-példányok fő folyamatai (PID-lista)."""
    pids = []
    for p in Path("/proc").iterdir():
        if not p.name.isdigit():
            continue
        try:
            cmd = (p / "cmdline").read_bytes().split(b"\0")
        except OSError:
            continue
        if cmd and b"chrome" in cmd[0] and any(b"puppeteer_dev_chrome_profile" in a for a in cmd) \
                and not any(a.startswith(b"--type=") for a in cmd):
            pids.append(int(p.name))
    return pids


def chrome_tree(roots):
    """A gyökér-PID-ek és összes leszármazottjuk."""
    children = {}
    for p in Path("/proc").iterdir():
        if p.name.isdigit():
            try:
                ppid = int((p / "stat").read_text().rsplit(")", 1)[1].split()[1])
                children.setdefault(ppid, []).append(int(p.name))
            except (OSError, IndexError, ValueError):
                pass
    out, stack = [], list(roots)
    while stack:
        pid = stack.pop()
        out.append(pid)
        stack.extend(children.get(pid, []))
    return out


def level_for(value, th, current):
    if value is None:
        return "ok"
    lvl = "ok"
    for name in ("warm", "hot", "critical"):
        enter, leave = th[name]
        # aki már ezen a szinten vagy fölötte van, csak a kilépési küszöb alatt esik vissza
        if value >= enter or (LEVELS.index(current) >= LEVELS.index(name) and value >= leave):
            lvl = name
    return lvl


def notify(title, body, urgency="normal"):
    subprocess.run(["notify-send", "-u", urgency, "-a", "Hőfigyelő", title, body],
                   capture_output=True)
    print(f"{title}: {body}", flush=True)


def power_profile(set_to=None):
    try:
        if set_to:
            subprocess.run(["powerprofilesctl", "set", set_to], capture_output=True, timeout=5)
            return set_to
        return subprocess.run(["powerprofilesctl", "get"], capture_output=True,
                              text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None


def signal_pids(pids, sig):
    for pid in pids:
        try:
            os.kill(pid, sig)
        except OSError:
            pass


MESSAGES = {
    "ok": "",
    "warm": ("A gép melegszik (CPU {cpu} °C, GPU {gpu} °C). Ne indíts új párhuzamos "
             "nehéz feladatot (Chrome/Puppeteer, build, teljes tesztkészlet); a futókat "
             "fejezd be, a nem használt böngészőket zárd be."),
    "hot": ("A gép 95 °C FÖLÉ MELEGEDETT (CPU {cpu} °C, GPU {gpu} °C). Állítsd le most a "
            "futó nehéz folyamataidat (build, teszt, dev szerver, Chrome/Puppeteer), zárd be "
            "a böngészőket, és ne indíts újat, amíg a szint vissza nem áll. Az energiamód "
            "balanced-re váltott."),
    "critical": ("KRITIKUS HŐMÉRSÉKLET (CPU {cpu} °C, GPU {gpu} °C). A Puppeteer-Chrome-ok "
                 "szünetelnek, az energiamód power-saver. Ne indíts semmilyen nehéz "
                 "feladatot; várj, amíg a szint visszaáll."),
}


def main():
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    cpu_hist, gpu_hist = deque(maxlen=WINDOW), deque(maxlen=WINDOW)
    level, since = "ok", time.time()
    stopped = []                 # általunk szüneteltetett PID-ek
    saved_profile = None         # az energiamód a beavatkozás előtt
    last_log = 0

    def cleanup(*_):
        signal_pids(stopped, signal.SIGCONT)
        if saved_profile:
            power_profile(saved_profile)
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    # Ha egy korábbi példány összeomlott, ne maradjon szüneteltetett Chrome.
    try:
        old = json.loads(STATE.read_text())
        signal_pids(old.get("stopped_pids", []), signal.SIGCONT)
    except (OSError, ValueError):
        pass

    while True:
        cpu = hwmon("k10temp", "Tctl")
        if cpu is None:          # Intel CPU: coretemp, a teljes tok hőmérséklete
            cpu = hwmon("coretemp", "Package id 0")
        acpi = hwmon("acpitz")
        gpu = gpu_temp()
        if cpu is not None:
            cpu_hist.append(cpu)
        if gpu is None:
            gpu_hist.clear()     # a GPU alszik: nincs mit átlagolni
        else:
            gpu_hist.append(gpu)
        cpu_m = statistics.median(cpu_hist) if cpu_hist else None
        gpu_m = statistics.median(gpu_hist) if gpu_hist else None
        chromes = puppeteer_chromes()

        new = max(level_for(cpu_m, CPU_TH, level), level_for(gpu_m, GPU_TH, level),
                  key=LEVELS.index)

        if new != level:
            up = LEVELS.index(new) > LEVELS.index(level)
            fmt = dict(cpu=round(cpu_m or 0), gpu=round(gpu_m) if gpu_m else "–")
            if new == "ok":
                notify("Hőfigyelő: rendben", f"Lehűlt a gép (CPU {fmt['cpu']} °C).")
            else:
                notify(f"Hőfigyelő: {new}", MESSAGES[new].format(**fmt),
                       "critical" if new == "critical" else "normal")
            if up and new in ("hot", "critical") and saved_profile is None:
                saved_profile = power_profile()
            if new == "hot":
                power_profile("balanced")
            if new == "critical":
                power_profile("power-saver")
                stopped = chrome_tree(chromes)
                signal_pids(stopped, signal.SIGSTOP)
            if LEVELS.index(new) < LEVELS.index("critical") and stopped:
                signal_pids(stopped, signal.SIGCONT)
                stopped = []
            if new in ("ok", "warm") and saved_profile:
                power_profile(saved_profile)
                saved_profile = None
            level, since = new, time.time()

        fmt = dict(cpu=round(cpu_m or 0), gpu=round(gpu_m) if gpu_m else "–")
        state = {
            "ts": time.time(), "level": level, "since": since,
            "cpu_c": cpu, "cpu_median_c": cpu_m, "acpi_c": acpi, "gpu_c": gpu,
            "puppeteer_chromes": len(chromes), "chrome_limit": CHROME_RED_LANE,
            "load1": os.getloadavg()[0], "stopped_pids": stopped,
            "message": MESSAGES[level].format(**fmt) if level != "ok" else "",
        }
        tmp = STATE.with_suffix(".tmp")
        tmp.write_text(json.dumps(state))
        tmp.replace(STATE)

        if time.time() - last_log >= LOG_EVERY or level != "ok":
            last_log = time.time()
            f = LOG_DIR / f"hofok-{time.strftime('%Y-%m-%d')}.csv"
            new_file = not f.exists()
            with f.open("a", newline="") as fh:
                w = csv.writer(fh)
                if new_file:
                    w.writerow(["ido", "cpu_c", "acpi_c", "gpu_c", "chrome", "load1", "szint"])
                w.writerow([time.strftime("%H:%M:%S"), cpu, acpi, gpu, len(chromes),
                            round(state["load1"], 2), level])
                fh.flush()
                os.fsync(fh.fileno())   # hirtelen leállás után is megmaradjon
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
