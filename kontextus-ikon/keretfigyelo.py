#!/usr/bin/env python3
"""Keretfigyelő: háttérszolgáltatás, amely munkamenettől függetlenül méri a Claude- és a Codex-keretet, és az
eredményt a GNOME-bővítménynek kiírja: $XDG_RUNTIME_DIR/kontextus-ikon/keretfigyelo.json (csak ez a folyamat
írja; a statusline a saját keretek.json fájlját írja, így a két forrás nem verseng egy fájlért).

- Claude (5 órás, heti, Fable heti): a statusline.py account_usage() függvénye (a fiók /usage végpontja, a CLI
  saját OAuth-tokenjével, csak olvasva); a gyorsítótár és a gyakoriság (USAGE_EVERY) közös a statusline-nal.
- Codex (5 órás, heti): tartósan futó `codex app-server` (stdio, soronként egy JSON-üzenet): initialize,
  initialized, majd CODEX_EVERY másodpercenként account/rateLimits/read; az account/rateLimits/updated
  értesítésre azonnal ír. A Codex-tokent az app-server kezeli, ez a program nem nyúl hozzá.

Futtatás: python3 keretfigyelo.py           (folyamatosan, a systemd-egység így indítja)
          python3 keretfigyelo.py --once    (egy Claude- és egy Codex-lekérés, kiírja, a fájlt nem írja)
Tokent, fejlécet, választ nem naplóz; a naplóba (stderr) csak állapotváltás-okok kerülnek."""

import json
import os
import queue
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import statusline  # noqa: E402  (egy HTTP-kliens, egy gyorsítótár: a statusline-é)

# ---- beállítások (egy helyen; a Claude-gyakoriság a statusline.py USAGE_EVERY értéke) ----------------
CODEX_EVERY = 60          # mp, Codex-lekérés gyakorisága
HEARTBEAT_EVERY = 30      # mp, ennyi időnként akkor is ír, ha nincs változás (a bővítmény ebből látja, hogy fut)
CODEX_TIMEOUT = 30        # mp, ennyi idő alatt kell válaszolnia az app-servernek
BACKOFF = (5, 15, 60, 300, 900)   # mp, az app-server újraindítása előtti várakozás a sikertelen indítások után
STATE_NAME = "keretfigyelo.json"
CLIENT_INFO = {"name": "kontextus_keretfigyelo", "title": "Kontextus-ikon keretfigyelő", "version": "1"}
DAY_MINUTES = 24 * 60


def log(msg):
    print(f"keretfigyelo: {msg}", file=sys.stderr, flush=True)


def state_path():
    run = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return os.path.join(run, "kontextus-ikon", STATE_NAME)


def write_state(path, state):
    """Atomikus írás: ideiglenes fájl ugyanabban a mappában, majd átnevezés."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False)
    os.replace(tmp, path)


def backoff(failures):
    """Várakozás mp-ben a failures-edik egymás utáni sikertelen indítás után (1-től)."""
    return BACKOFF[min(max(failures, 1), len(BACKOFF)) - 1]


# ---- Claude ---------------------------------------------------------------

def claude_block(usage):
    """A statusline.account_usage() eredménye a bővítmény formájában:
    {"five_hour"|"seven_day"|"fable": {"pct", "resets_at", "ts", "source"}, "why", "ok_at"}."""
    out = {"why": usage.get("why"), "ok_at": usage.get("ok_at")}
    ts = usage.get("ok_at")
    if not ts:
        return out
    for key, v in (usage.get("windows") or {}).items():
        if isinstance(v, dict) and v.get("pct") is not None:
            out[key] = {"pct": v["pct"], "resets_at": v.get("resets_at"), "ts": ts, "source": "fiók"}
    rows = usage.get("rows") or {}
    fable = next((n for n in rows if "fable" in n.lower()), None)
    if fable is not None:
        out["fable"] = {"pct": rows[fable], "resets_at": (usage.get("resets") or {}).get(fable), "ts": ts,
                        "source": "fiók", "name": fable}
    return out


# ---- Codex ----------------------------------------------------------------

def codex_snapshot(result):
    """A codex keret pillanatképe egy account/rateLimits/read válaszból (vagy értesítésből); nem várt alakra None."""
    if not isinstance(result, dict):
        return None
    by_id = result.get("rateLimitsByLimitId")
    snap = (by_id.get("codex") if isinstance(by_id, dict) else None) or result.get("rateLimits")
    if not isinstance(snap, dict):
        return None
    if (snap.get("limitId") or "codex") != "codex":
        return None
    return snap


def codex_windows(snap, ts):
    """{"five_hour"|"weekly": {"pct", "resets_at", "ts", "window_minutes", "source"}, "plan"}; az ablakot a
    hossza választja (legfeljebb egy nap = 5 órás, több = heti), a primary/secondary sorrendet nem feltételezi."""
    out = {"plan": snap.get("planType")}
    for w in (snap.get("primary"), snap.get("secondary")):
        if not isinstance(w, dict) or not isinstance(w.get("usedPercent"), (int, float)) \
                or isinstance(w.get("usedPercent"), bool):
            continue
        mins = w.get("windowDurationMins")
        if not isinstance(mins, int):
            continue
        key = "five_hour" if mins <= DAY_MINUTES else "weekly"
        out[key] = {"pct": w["usedPercent"], "resets_at": w.get("resetsAt"), "ts": ts,
                    "window_minutes": mins, "source": "app-server"}
    return out


def codex_error_reason(err):
    """Az app-server hibaválaszából rövid, konkrét ok (a szerver üzenete hitelesítő adatot nem tartalmaz)."""
    if not isinstance(err, dict):   # nem várt alak (pl. csak szöveg): az ok maga a szöveg
        return f"a Codex app-server hibát adott: {str(err)[:120]}"
    msg = str(err.get("message") or "")
    if "codex account authentication required" in msg:
        return "nincs Codex-bejelentkezés"
    if "chatgpt authentication required" in msg:
        return "a Codex nem ChatGPT-fiókkal van bejelentkezve (API-kulcs), a keret nem kérdezhető le"
    return f"a Codex app-server hibát adott: {msg[:120] or err.get('code')}"


def find_codex():
    """A codex parancs útvonala (PATH, majd ~/.local/bin), vagy None."""
    return (os.environ.get("KERETFIGYELO_CODEX") or shutil.which("codex")
            or shutil.which("codex", path=os.path.expanduser("~/.local/bin")))


class Codex:
    """Egy `codex app-server` folyamat kezelése. Az események (üzenet, kilépés) egy sorba kerülnek; a step()
    dolgozza fel őket. Minden döntés a kívülről kapott időt (now) használja."""

    def __init__(self, command=None, every=CODEX_EVERY, timeout=CODEX_TIMEOUT):
        self.command = command          # None: find_codex() indításkor
        self.every, self.timeout = every, timeout
        self.events = queue.Queue()
        self.proc = None
        self.gen = 0                    # a folyamat sorszáma: a régi folyamat késő eseményei kimaradnak
        self.failures = 0
        self.next_start = 0.0
        self.next_read = 0.0
        self.pending = {}               # kérés-id -> (metódus, küldés ideje)
        self.ready = False              # az initialize válasza megjött
        self.next_id = 0
        self.data = {}                  # utolsó sikeres ablakok (five_hour, weekly, plan)
        self.ok_at = None
        self.why = "még nincs Codex-lekérdezés"
        self.answers = 0                # lekérés-válaszok és sikertelen indítások száma (a --once ebből tudja, hogy kész)

    # -- folyamat --
    def start(self, now):
        cmd = self.command or ([find_codex(), "app-server"] if find_codex() else None)
        if not cmd:
            self._fail(now, "a Codex nincs telepítve (nincs codex parancs)")
            return
        try:
            self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                         stderr=subprocess.DEVNULL, text=True, encoding="utf-8",
                                         errors="replace", bufsize=1)
        except OSError as e:
            self._fail(now, f"a Codex app-server nem indul ({type(e).__name__})")
            return
        self.gen += 1
        self.ready, self.pending = False, {}
        threading.Thread(target=self._reader, args=(self.proc, self.gen), daemon=True).start()
        self._send("initialize", {"clientInfo": CLIENT_INFO, "capabilities": None}, now)

    def _reader(self, proc, gen):
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except ValueError:
                msg = None
            self.events.put(("msg", gen, msg))
        self.events.put(("exit", gen, proc.wait()))

    def stop(self):
        proc, self.proc = self.proc, None
        if proc is None:
            return
        self.gen += 1   # a saját leállítás késő kilépés-eseménye már a régi sorszámmal jön: kimarad
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        for pipe in (proc.stdin, proc.stdout):
            try:
                pipe.close()
            except (OSError, ValueError):
                pass

    def _fail(self, now, why):
        self.stop()
        self.failures += 1
        self.answers += 1
        self.why = why
        self.next_start = now + backoff(self.failures)
        log(f"Codex: {why}; újraindítás {backoff(self.failures)} mp múlva")

    def _send(self, method, params, now, notify=False):
        msg = {"method": method}
        if params is not None:
            msg["params"] = params
        if not notify:
            self.next_id += 1
            msg["id"] = self.next_id
            self.pending[self.next_id] = (method, now)
        try:
            self.proc.stdin.write(json.dumps(msg) + "\n")
            self.proc.stdin.flush()
        except (OSError, ValueError):
            pass  # a kilépés eseménye jön a sorból

    # -- ütemezés --
    def tick(self, now):
        """Indítás, lekérés és időkorlát a now pillanatban."""
        if self.proc is None:
            if now >= self.next_start:
                self.start(now)
            return
        if any(now - sent > self.timeout for _, sent in self.pending.values()):
            self._fail(now, f"a Codex app-server {self.timeout} mp alatt nem válaszolt")
            return
        if self.ready and now >= self.next_read and not self.pending:
            self._send("account/rateLimits/read", {"excludeResetCreditDetails": True}, now)
            self.next_read = now + self.every

    def wake_at(self):
        """A következő időpont, amikor a tick-nek dolga lehet."""
        if self.proc is None:
            return self.next_start
        times = [sent + self.timeout for _, sent in self.pending.values()]
        if self.ready and not self.pending:
            times.append(self.next_read)
        return min(times) if times else None

    def step(self, now, wait):
        """Egy esemény feldolgozása (legfeljebb wait mp várakozással). True, ha a Codex-adat vagy az ok változott."""
        try:
            kind, gen, payload = self.events.get(timeout=max(0.0, wait))
        except queue.Empty:
            return False
        if gen != self.gen:
            return False
        if kind == "exit":
            self._fail(now, f"a Codex app-server kilépett (kód {payload})")
            return True
        return self.handle(payload, now)

    def handle(self, msg, now):
        if not isinstance(msg, dict):
            return False   # nem JSON vagy nem objektum: kimarad (az időkorlát kezeli, ha a válasz így vész el)
        if msg.get("method") == "account/rateLimits/updated":
            snap = codex_snapshot(msg.get("params"))
            return self._apply(snap, now) if snap else False
        if "method" in msg:
            return False   # más értesítés vagy szerverkérés: nem érdekel
        mid = msg.get("id")
        if not isinstance(mid, int) or isinstance(mid, bool):
            return False   # a mi kéréseink id-je egész; más alakú id nem a miénk
        req = self.pending.pop(mid, None)
        if req is None:
            return False
        method = req[0]
        if method != "initialize":
            self.answers += 1
        if "error" in msg:
            self.why = codex_error_reason(msg["error"])
            if method == "initialize":
                self._fail(now, self.why)
            else:
                self.failures = 0
                log(f"Codex: {self.why}")
            return True
        if method == "initialize":
            self.ready = True
            self._send("initialized", None, now, notify=True)
            self.next_read = now
            return False
        snap = codex_snapshot(msg.get("result"))
        if snap is None:
            self.why = "a Codex-válaszban nincs codex keret"
            return True
        return self._apply(snap, now)

    def _apply(self, snap, now):
        # az ablakonkénti frissítés: amelyik ablak nincs az új pillanatképben, az a saját idejével megmarad
        new = codex_windows(snap, now)
        if new.get("plan") is None:
            new.pop("plan")
        self.data = {**self.data, **new}
        self.ok_at, self.why, self.failures = now, None, 0
        return True

    def block(self):
        return {**self.data, "why": self.why, "ok_at": self.ok_at}


# ---- fő ciklus -------------------------------------------------------------

def build_state(claude, codex, now, started):
    return {"ts": now, "started": started, "pid": os.getpid(), "claude": claude, "codex": codex,
            "every": {"claude": statusline.USAGE_EVERY, "codex": CODEX_EVERY, "heartbeat": HEARTBEAT_EVERY}}


def claude_now(now):
    try:
        return claude_block(statusline.account_usage(now, wait=True))
    except Exception as e:  # váratlan hiba: az ok a fájlba és a naplóba kerül, a szolgáltatás fut tovább
        log(f"Claude: váratlan hiba ({type(e).__name__})")
        return {"why": f"váratlan hiba a Claude-lekérdezésben ({type(e).__name__})", "ok_at": None}


def run(path, clock=time.time, stop=None, codex=None):
    stop = stop or threading.Event()
    codex = codex or Codex()
    started = clock()
    claude, next_claude, next_write, last_why = {}, 0.0, 0.0, None
    try:
        while not stop.is_set():
            now = clock()
            changed = False
            if now >= next_claude:
                claude = claude_now(now)
                next_claude = now + statusline.USAGE_EVERY
                changed = True
                if claude.get("why") != last_why and claude.get("why"):
                    log(f"Claude: {claude['why']}")
                last_why = claude.get("why")
            codex.tick(now)
            wake = min(t for t in (next_claude, next_write, codex.wake_at()) if t is not None)
            changed |= codex.step(clock(), min(wake - clock(), 1.0))
            now = clock()
            if changed or now >= next_write:
                write_state(path, build_state(claude, codex.block(), now, started))
                next_write = now + HEARTBEAT_EVERY
    finally:
        codex.stop()
        try:
            os.remove(path)   # leállításkor eltűnik: a bővítmény azonnal látja, hogy a figyelő nem fut
        except OSError:
            pass


def once(timeout=CODEX_TIMEOUT, codex=None):
    """Egy friss Claude- és egy Codex-lekérés; az eredmény a kimenetre (token nélkül). Sem a közös
    gyorsítótárat, sem az állapotfájlt nem írja: a Claude-lekérés egy ideiglenes, utána törölt gyorsítótárral fut."""
    now = time.time()
    with tempfile.TemporaryDirectory(prefix="keretfigyelo-once-") as tmp:
        claude = claude_block(statusline.account_usage(now, cache_path=os.path.join(tmp, "usage.json"), wait=True))
    codex = codex or Codex(timeout=timeout)
    t0 = time.time()
    try:
        while time.time() - t0 < timeout + 1 and not codex.answers:
            codex.tick(time.time())
            codex.step(time.time(), 0.5)
    finally:
        codex.stop()
    return {"claude": claude, "codex": codex.block()}


def fmt_window(name, v):
    if not isinstance(v, dict) or v.get("pct") is None:
        return f"{name}: nincs adat"
    reset = time.strftime("%m.%d. %H:%M", time.localtime(v["resets_at"])) if v.get("resets_at") else "?"
    at = time.strftime("%H:%M:%S", time.localtime(v["ts"]))
    return f"{name}: elhasználva {v['pct']}%, maradt {100 - v['pct']}%, visszaáll {reset}, adat ideje {at}"


def systemd_quote(s, exec_arg=False):
    """Egy systemd-egységbeli érték idézve: idézőjelek közé, a \\ és a " escape-elve, a % (fajlagos-kifejtés)
    %%-ként, ExecStart-argumentumban a $ (változó-kifejtés) $$-ként; így szóközös útvonal is egy argumentum."""
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%")
    if exec_arg:
        s = s.replace("$", "$$")
    return '"' + s + '"'


def render_unit(template, python, script, path):
    with open(template, encoding="utf-8") as f:
        text = f.read()
    return (text.replace("@PYTHON@", systemd_quote(python, True)).replace("@SCRIPT@", systemd_quote(script, True))
            .replace("@PATHENV@", systemd_quote("PATH=" + path)))


def main(argv):
    if "--unit" in argv:   # az install.sh hívja: a kitöltött systemd-egység a kimenetre
        sys.stdout.write(render_unit(os.path.join(HERE, "keretfigyelo.service.in"), sys.executable,
                                     os.path.abspath(__file__), os.environ.get("PATH", "")))
        return 0
    if "--once" in argv:
        r = once()
        c, x = r["claude"], r["codex"]
        print("Friss lekérés (a közös gyorsítótár és az állapotfájl nélkül).")
        print("Claude:", c.get("why") or "rendben")
        for key, name in (("five_hour", "  5 órás"), ("seven_day", "  heti"), ("fable", "  Fable heti")):
            print(fmt_window(name, c.get(key)))
        print("Codex:", x.get("why") or "rendben", f"(plan: {x.get('plan')})" if x.get("plan") else "")
        for key, name in (("five_hour", "  5 órás"), ("weekly", "  heti")):
            print(fmt_window(name, x.get(key)))
        return 0
    stop = threading.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: stop.set())
    log(f"indul; állapotfájl: {state_path()}")
    run(state_path(), stop=stop)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
