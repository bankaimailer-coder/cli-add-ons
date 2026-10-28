#!/usr/bin/env python3
"""Claude Code kontextus-ikon a GNOME felső sávjába.

Minden nyitott Claude Code terminálablakhoz (élő folyamat a ~/.claude/sessions/
alatt) külön ikon: körív-mérő a kontextushasználattal, mellette a szám.
StatusNotifierItem + com.canonical.dbusmenu közvetlenül Gio D-Bus-on,
nincs szükség AppIndicator-kötésre. Az ubuntu-appindicators bővítmény jeleníti meg.
"""

import glob
import json
import math
import os
import sys
import time

from gi.repository import Gio, GLib

# ---- Beállítások ---------------------------------------------------------
PROJECT_COLORS = {         # repó (mappanév) -> ikonszín; a többi DEFAULT_COLOR
    "nemesventilatorhaz": "blue",
}
DEFAULT_COLOR = "green"
RED_FROM = 500_000         # ettől minden ikon piros, projekttől függetlenül
GAUGE_MAX = 500_000        # ennyinél tele a mérő
GAUGE_STYLE = "arc"        # "arc" = sebességmérő-körív, "pie" = kördiagram
KINDS = ("interactive",)   # mely folyamatok kapnak ikont; háttérjobokkal: ("interactive", "bg")
POLL_SEC = 3               # frissítés gyakorisága
WARN_AT = 500_000          # ennél egyszer figyelmeztet (sessionönként)
SESSIONS_DIR = os.path.expanduser("~/.claude/sessions")
PROJECTS_DIR = os.path.expanduser("~/.claude/projects")
TAIL_CHUNK = 256 * 1024    # ennyit olvas egyszerre a fájl végéről
TAIL_MAX = 16 * 1024 * 1024  # legfeljebb ennyit olvas visszafelé

COLORS = {  # (R, G, B)
    "green": (0x33, 0xD1, 0x7A),
    "yellow": (0xF6, 0xD3, 0x2D),
    "red": (0xE0, 0x1B, 0x24),
    "blue": (0x35, 0x84, 0xE4),
    "purple": (0x91, 0x41, 0xAC),
    "white": (0xFF, 0xFF, 0xFF),
    "gray": (0x9A, 0x99, 0x96),
}
TRACK = (0xDE, 0xDD, 0xDA, 90)   # a kitöltetlen pálya (R, G, B, átlátszóság)
BUS_NAME = "hu.bfuzzee.KontextusIkon"

# ---- Adat ----------------------------------------------------------------


def last_assistant_usage(path):
    """A fájl végéről visszafelé olvasva az utolsó fő-szálbeli assistant-sor."""
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        pos = f.tell()
        buf = b""
        read = 0
        while pos > 0 and read < TAIL_MAX:
            step = min(TAIL_CHUNK, pos)
            pos -= step
            f.seek(pos)
            buf = f.read(step) + buf
            read += step
            lines = buf.split(b"\n")
            # az első darab lehet csonka, ha még nem értünk a fájl elejére
            buf = lines[0] if pos > 0 else b""
            complete = lines[1:] if pos > 0 else lines
            for raw in reversed(complete):
                if b'"type":"assistant"' not in raw:
                    continue
                try:
                    d = json.loads(raw)
                except ValueError:
                    continue
                if d.get("type") != "assistant" or d.get("isSidechain"):
                    continue
                msg = d.get("message") or {}
                u = msg.get("usage")
                if not u or msg.get("model") == "<synthetic>":
                    continue
                return (u.get("input_tokens", 0)
                        + u.get("cache_read_input_tokens", 0)
                        + u.get("cache_creation_input_tokens", 0))
    return None


def proc_alive(pid, proc_start):
    """Él-e a folyamat; az indulási idő véd a pid-újrahasznosítás ellen."""
    try:
        with open(f"/proc/{pid}/stat") as f:
            start = f.read().rsplit(")", 1)[1].split()[19]
    except (OSError, IndexError):
        return False
    return proc_start is None or str(proc_start) == start


def live_sessions():
    """Élő Claude Code folyamatok: pid -> a sessions/<pid>.json tartalma."""
    out = {}
    for p in glob.glob(os.path.join(SESSIONS_DIR, "*.json")):
        try:
            with open(p) as f:
                d = json.load(f)
        except (OSError, ValueError):
            continue
        if d.get("kind") not in KINDS or not d.get("sessionId"):
            continue
        if proc_alive(d.get("pid"), d.get("procStart")):
            out[d["pid"]] = d
    return out


class UsageCache:
    """sessionId -> jsonl útvonal és utolsó kontextusérték, csak változáskor olvas újra."""

    def __init__(self):
        self.paths = {}
        self.vals = {}

    def get(self, sid):
        path = self.paths.get(sid)
        if not path or not os.path.exists(path):
            hits = glob.glob(os.path.join(PROJECTS_DIR, "*", sid + ".jsonl"))
            if not hits:
                return None, None
            path = self.paths[sid] = hits[0]
        s = os.stat(path)
        key = (s.st_mtime, s.st_size)
        cached = self.vals.get(path)
        if not cached or cached[0] != key:
            cached = self.vals[path] = (key, last_assistant_usage(path))
        return cached[1], s.st_mtime


def color_for(tokens, repo):
    if tokens is None:
        return "gray"
    if tokens >= RED_FROM:
        return "red"
    return PROJECT_COLORS.get(repo, DEFAULT_COLOR)


def fmt_k(t):
    return f"{round(t / 1000)}k"


def fmt_tokens(t):
    return f"{t:,}".replace(",", " ")

# ---- Ikon (ARGB32, big-endian) ------------------------------------------


def make_gauge(size, frac, rgb, style=None):
    """Körív-mérő vagy kördiagram: halvány pálya, rajta arányos színes kitöltés.

    Élsimítás 4x4 részmintával.
    """
    style = style or GAUGE_STYLE
    frac = max(0.0, min(1.0, frac))
    ss = 4
    c = size / 2
    r_out = size / 2 - 0.5
    if style == "pie":
        r_in, start, sweep = 0.0, 270.0, 360.0      # felülről, óramutató szerint
    else:
        r_in, start, sweep = r_out * 0.58, 135.0, 270.0  # alul nyitott sebességmérő
    px = bytearray(size * size * 4)
    for y in range(size):
        for x in range(size):
            a_sum = r_sum = g_sum = b_sum = 0.0
            for sy in range(ss):
                for sx in range(ss):
                    dx = x + (sx + 0.5) / ss - c
                    dy = y + (sy + 0.5) / ss - c
                    d = math.hypot(dx, dy)
                    if d > r_out or d < r_in:
                        continue
                    t = (math.degrees(math.atan2(dy, dx)) - start) % 360
                    if t > sweep:
                        continue
                    if t <= sweep * frac:
                        col, a = rgb, 1.0
                    else:
                        col, a = TRACK[:3], TRACK[3] / 255
                    a_sum += a
                    r_sum += col[0] * a
                    g_sum += col[1] * a
                    b_sum += col[2] * a
            if a_sum:
                n = ss * ss
                i = (y * size + x) * 4
                px[i:i + 4] = bytes((round(a_sum / n * 255), round(r_sum / a_sum),
                                     round(g_sum / a_sum), round(b_sum / a_sum)))
    return (size, size, bytes(px))

# ---- D-Bus interfészek --------------------------------------------------


SNI_XML = """
<node>
 <interface name="org.kde.StatusNotifierItem">
  <property name="Category" type="s" access="read"/>
  <property name="Id" type="s" access="read"/>
  <property name="Title" type="s" access="read"/>
  <property name="Status" type="s" access="read"/>
  <property name="WindowId" type="i" access="read"/>
  <property name="IconName" type="s" access="read"/>
  <property name="IconPixmap" type="a(iiay)" access="read"/>
  <property name="IconThemePath" type="s" access="read"/>
  <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
  <property name="ItemIsMenu" type="b" access="read"/>
  <property name="Menu" type="o" access="read"/>
  <property name="XAyatanaLabel" type="s" access="read"/>
  <property name="XAyatanaLabelGuide" type="s" access="read"/>
  <method name="Activate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
  <method name="SecondaryActivate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
  <method name="ContextMenu"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
  <method name="Scroll"><arg type="i" direction="in"/><arg type="s" direction="in"/></method>
  <signal name="NewIcon"/>
  <signal name="NewTitle"/>
  <signal name="NewToolTip"/>
  <signal name="NewStatus"><arg type="s"/></signal>
  <signal name="XAyatanaNewLabel"><arg type="s"/><arg type="s"/></signal>
 </interface>
</node>
"""

MENU_XML = """
<node>
 <interface name="com.canonical.dbusmenu">
  <property name="Version" type="u" access="read"/>
  <property name="TextDirection" type="s" access="read"/>
  <property name="Status" type="s" access="read"/>
  <property name="IconThemePath" type="as" access="read"/>
  <method name="GetLayout">
   <arg type="i" direction="in"/><arg type="i" direction="in"/><arg type="as" direction="in"/>
   <arg type="u" direction="out"/><arg type="(ia{sv}av)" direction="out"/>
  </method>
  <method name="GetGroupProperties">
   <arg type="ai" direction="in"/><arg type="as" direction="in"/>
   <arg type="a(ia{sv})" direction="out"/>
  </method>
  <method name="GetProperty">
   <arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/>
  </method>
  <method name="Event">
   <arg type="i" direction="in"/><arg type="s" direction="in"/>
   <arg type="v" direction="in"/><arg type="u" direction="in"/>
  </method>
  <method name="EventGroup">
   <arg type="a(isvu)" direction="in"/><arg type="ai" direction="out"/>
  </method>
  <method name="AboutToShow">
   <arg type="i" direction="in"/><arg type="b" direction="out"/>
  </method>
  <method name="AboutToShowGroup">
   <arg type="ai" direction="in"/><arg type="ai" direction="out"/><arg type="ai" direction="out"/>
  </method>
  <signal name="ItemsPropertiesUpdated">
   <arg type="a(ia{sv})"/><arg type="a(ia{sa})"/>
  </signal>
  <signal name="LayoutUpdated"><arg type="u"/><arg type="i"/></signal>
  <signal name="ItemActivationRequested"><arg type="i"/><arg type="u"/></signal>
 </interface>
</node>
"""

SNI_IFACE = Gio.DBusNodeInfo.new_for_xml(SNI_XML).interfaces[0]
MENU_IFACE = Gio.DBusNodeInfo.new_for_xml(MENU_XML).interfaces[0]
APP_XML = """
<node>
 <interface name="hu.bfuzzee.KontextusIkon">
  <method name="Sessions"><arg type="s" direction="out"/></method>
  <method name="Jump"><arg type="i" direction="in"/></method>
  <signal name="Changed"><arg type="s"/></signal>
 </interface>
</node>
"""
APP_PATH = "/hu/bfuzzee/KontextusIkon"
PANEL_BUS = "hu.bfuzzee.KontextusIkon.Panel"   # ha ez fut, a bővítmény rajzol, nem kell sávikon
SNI_PATH = "/StatusNotifierItem"
MENU_PATH = "/MenuBar"
QUIT_ID = 100
JUMP_ID = 97               # „Ugrás a terminálba”, utána elválasztó (98)
JUMP_BUS = "hu.bfuzzee.KontextusIkon.Ablak"   # a gnome-extension/ablakugro bővítmény
JUMP_PATH = "/hu/bfuzzee/KontextusIkon/Ablak"
STATUS_HU = {"busy": "dolgozik", "idle": "vár", "shell": "shell"}


def session_lines(data):
    """A menü tájékoztató sorai egy sessionhöz."""
    tokens, repo, sid, mtime, status, name = data
    items = [f"Repó: {repo}", f"Session: {sid[:8]}"]
    if name:
        items.append(f"Név: {name}")
    items.append("Állapot: " + STATUS_HU.get(status, status or "?"))
    if mtime:
        t = time.localtime(mtime)
        fmt = "%H:%M:%S" if time.strftime("%Y%m%d", t) == time.strftime("%Y%m%d") \
            else "%Y-%m-%d %H:%M"
        items.append("Frissült: " + time.strftime(fmt, t))
    items.append("Kontextus: " + ("még nincs adat" if tokens is None
                                  else fmt_tokens(tokens) + " token"))
    return items


def panel_row(key, data):
    """Egy session a GNOME-bővítménynek (JSON-sor)."""
    tokens = data[0]
    return {
        "key": key,
        "label": "–" if tokens is None else fmt_k(tokens),
        "frac": 0.0 if tokens is None else round(min(1.0, tokens / GAUGE_MAX), 2),
        "color": list(COLORS[color_for(tokens, data[1])]),
        "lines": session_lines(data),
        "jump": True,
    }


class Item:
    """Egy ikon a sávban. Saját D-Bus kapcsolat, így bezárásakor a sáv eltávolítja."""

    def __init__(self, key, on_quit, on_jump):
        self.key = key
        self.on_quit = on_quit
        self.on_jump = on_jump
        self.data = None          # (tokens, repo, sid, mtime, status, name)
        self.label = ""
        self.pixmaps = []
        self.icon_key = None
        self.menu_items = []
        self.revision = 1
        addr = Gio.dbus_address_get_for_bus_sync(Gio.BusType.SESSION, None)
        self.conn = Gio.DBusConnection.new_for_address_sync(
            addr, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
            | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
        self.sni_name = f"org.kde.StatusNotifierItem-{os.getpid()}-{key}"
        self.conn.register_object(SNI_PATH, SNI_IFACE, self.sni_call, self.sni_prop, None)
        self.conn.register_object(MENU_PATH, MENU_IFACE, self.menu_call, self.menu_prop, None)
        Gio.bus_own_name_on_connection(self.conn, self.sni_name,
                                       Gio.BusNameOwnerFlags.NONE, None, None)

    def register(self):
        self.conn.call("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
                       "org.kde.StatusNotifierWatcher", "RegisterStatusNotifierItem",
                       GLib.Variant("(s)", (self.sni_name,)), None,
                       Gio.DBusCallFlags.NONE, -1, None, None)

    def close(self):
        self.conn.close_sync(None)

    def emit(self, path, iface, signal, params=None):
        self.conn.emit_signal(None, path, iface, signal, params)

    def update(self, data):
        """data: (tokens|None, repo, sid, mtime|None, status, name); None = nincs session."""
        first = self.data is None and not self.pixmaps
        self.data = data
        tokens = data[0] if data else None
        frac = 0.0 if tokens is None else round(min(1.0, tokens / GAUGE_MAX), 2)
        color = color_for(tokens, data[1] if data else None)
        if (frac, color) != self.icon_key:
            self.icon_key = (frac, color)
            self.pixmaps = [make_gauge(s, frac, COLORS[color]) for s in (22, 24, 32, 48)]
            if not first:
                self.emit(SNI_PATH, "org.kde.StatusNotifierItem", "NewIcon")
        label = "–" if tokens is None else fmt_k(tokens)
        if label != self.label:
            self.label = label
            if not first:
                self.emit(SNI_PATH, "org.kde.StatusNotifierItem", "XAyatanaNewLabel",
                          GLib.Variant("(ss)", (label, "000k")))
        if not first:
            self.emit(SNI_PATH, "org.kde.StatusNotifierItem", "NewToolTip")
        self.build_menu()

    def tooltip_text(self):
        if not self.data:
            return "Nincs nyitott Claude Code terminál"
        tokens, repo = self.data[0], self.data[1]
        return f"{repo}: " + ("még nincs adat" if tokens is None
                              else fmt_tokens(tokens) + " token")

    def build_menu(self):
        items = session_lines(self.data) if self.data else ["Nincs nyitott Claude Code terminál"]
        if items != self.menu_items:
            self.menu_items = items
            self.revision += 1
            self.emit(MENU_PATH, "com.canonical.dbusmenu", "LayoutUpdated",
                      GLib.Variant("(ui)", (self.revision, 0)))

    # -- StatusNotifierItem
    def sni_prop(self, conn, sender, path, iface, prop):
        v = {
            "Category": ("s", "ApplicationStatus"),
            "Id": ("s", f"kontextus-ikon-{self.key}"),
            "Title": ("s", "Claude kontextus"),
            "Status": ("s", "Active"),
            "WindowId": ("i", 0),
            "IconName": ("s", ""),
            "IconPixmap": ("a(iiay)", self.pixmaps),
            "IconThemePath": ("s", ""),
            "ToolTip": ("(sa(iiay)ss)", ("", [], "Claude kontextus", self.tooltip_text())),
            "ItemIsMenu": ("b", True),
            "Menu": ("o", MENU_PATH),
            "XAyatanaLabel": ("s", self.label),
            "XAyatanaLabelGuide": ("s", "000k"),
        }.get(prop)
        return GLib.Variant(*v) if v else None

    def sni_call(self, conn, sender, path, iface, method, params, inv):
        inv.return_value(None)
        # dupla kattintás = Activate, középső kattintás = SecondaryActivate
        if method in ("Activate", "SecondaryActivate") and self.data:
            GLib.idle_add(self.on_jump, self.key)

    # -- dbusmenu
    def item_props(self, i):
        if i == 0:
            return {"children-display": GLib.Variant("s", "submenu")}
        if i == QUIT_ID:
            return {"label": GLib.Variant("s", "Kilépés")}
        if i in (QUIT_ID - 1, JUMP_ID + 1):
            return {"type": GLib.Variant("s", "separator")}
        if i == JUMP_ID:
            return {"label": GLib.Variant("s", "Ugrás a terminálba")}
        return {"label": GLib.Variant("s", self.menu_items[i - 1]),
                "enabled": GLib.Variant("b", False)}

    def item_ids(self):
        jump = [JUMP_ID, JUMP_ID + 1] if self.data else []
        return jump + list(range(1, len(self.menu_items) + 1)) + [QUIT_ID - 1, QUIT_ID]

    def layout(self, i):
        children = []
        if i == 0:
            children = [GLib.Variant("(ia{sv}av)", (c, self.item_props(c), []))
                        for c in self.item_ids()]
        return (i, self.item_props(i), children)

    def on_event(self, i, ev):
        if ev != "clicked":
            return
        if i == QUIT_ID:
            GLib.idle_add(self.on_quit)
        elif i == JUMP_ID and self.data:
            GLib.idle_add(self.on_jump, self.key)

    def menu_prop(self, conn, sender, path, iface, prop):
        v = {"Version": ("u", 3), "TextDirection": ("s", "ltr"),
             "Status": ("s", "normal"), "IconThemePath": ("as", [])}.get(prop)
        return GLib.Variant(*v) if v else None

    def menu_call(self, conn, sender, path, iface, method, params, inv):
        a = params.unpack()
        valid = [0] + self.item_ids()
        if method == "GetLayout":
            pid = a[0] if a[0] in valid else 0
            inv.return_value(GLib.Variant("(u(ia{sv}av))", (self.revision, self.layout(pid))))
        elif method == "GetGroupProperties":
            ids = [i for i in (a[0] or valid) if i in valid]
            inv.return_value(GLib.Variant("(a(ia{sv}))",
                                          ([(i, self.item_props(i)) for i in ids],)))
        elif method == "GetProperty":
            p = self.item_props(a[0]).get(a[1], GLib.Variant("s", ""))
            inv.return_value(GLib.Variant("(v)", (p,)))
        elif method == "Event":
            inv.return_value(None)
            self.on_event(a[0], a[1])
        elif method == "EventGroup":
            for (i, ev, _d, _t) in a[0]:
                self.on_event(i, ev)
            inv.return_value(GLib.Variant("(ai)", ([],)))
        elif method == "AboutToShow":
            inv.return_value(GLib.Variant("(b)", (False,)))
        elif method == "AboutToShowGroup":
            inv.return_value(GLib.Variant("(aiai)", ([], [])))
        else:
            inv.return_value(None)


def collect(cache):
    """Az élő terminál-sessionök adatai, indulási sorrendben: [(pid, data), ...]."""
    out = []
    for pid, d in sorted(live_sessions().items(), key=lambda kv: kv[1].get("startedAt", 0)):
        sid = d["sessionId"]
        tokens, mtime = cache.get(sid)
        cwd = d.get("cwd") or ""
        repo = os.path.basename(cwd.rstrip("/")) or "?"
        out.append((pid, (tokens, repo, sid, mtime, d.get("status"), d.get("name"))))
    return out


class App:
    def __init__(self, loop):
        self.loop = loop
        self.conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.cache = UsageCache()
        self.items = {}           # pid (vagy "none") -> Item
        self.warned = set()       # sessionök, amelyekről már ment figyelmeztetés
        self.watcher_up = False
        self.panel_up = False
        self.panel_json = "[]"
        self.conn.register_object(APP_PATH, Gio.DBusNodeInfo.new_for_xml(APP_XML).interfaces[0],
                                  self.app_call, None, None)
        self.sync()
        Gio.bus_watch_name_on_connection(
            self.conn, "org.kde.StatusNotifierWatcher",
            Gio.BusNameWatcherFlags.NONE, self.on_watcher, self.on_watcher_gone)
        Gio.bus_watch_name_on_connection(
            self.conn, PANEL_BUS, Gio.BusNameWatcherFlags.NONE,
            self.on_panel, self.on_panel_gone)
        GLib.timeout_add_seconds(POLL_SEC, self.tick)

    def quit(self):
        for it in self.items.values():
            it.close()
        self.loop.quit()

    def on_watcher(self, conn, name, owner):
        self.watcher_up = True
        for it in self.items.values():
            it.register()

    def on_watcher_gone(self, conn, name):
        self.watcher_up = False

    # -- GNOME-bővítmény (gnome-extension/kontextus@kontextus-ikon)
    def on_panel(self, conn, name, owner):
        self.panel_up = True
        self.sync()

    def on_panel_gone(self, conn, name):
        self.panel_up = False
        self.sync()

    def app_call(self, conn, sender, path, iface, method, params, inv):
        if method == "Sessions":
            inv.return_value(GLib.Variant("(s)", (self.panel_json,)))
        elif method == "Jump":
            inv.return_value(None)
            GLib.idle_add(self.jump, params.unpack()[0])
        else:
            inv.return_value(None)

    def tick(self):
        try:
            self.sync()
        except Exception as e:  # egy hibás olvasás ne állítsa le az ikont
            print("frissítési hiba:", e, file=sys.stderr)
        return True

    def sync(self):
        # ikon csak akkor van, ha fut legalább egy Claude Code terminál
        rows = collect(self.cache)
        panel_json = json.dumps([panel_row(k, d) for k, d in rows], ensure_ascii=False)
        if panel_json != self.panel_json:
            self.panel_json = panel_json
            self.conn.emit_signal(None, APP_PATH, "hu.bfuzzee.KontextusIkon", "Changed",
                                  GLib.Variant("(s)", (panel_json,)))
        for _k, data in rows:
            self.check_warning(data)
        # ha a bővítmény rajzol, nem kell saját sávikon
        wanted = set() if self.panel_up else {k for k, _ in rows}
        for k in list(self.items):
            if k not in wanted:
                self.items.pop(k).close()
        for k, data in rows:
            if k not in wanted:
                continue
            it = self.items.get(k)
            if it is None:
                it = self.items[k] = Item(k, self.quit, self.jump)
                it.update(data)
                if self.watcher_up:
                    it.register()
            else:
                it.update(data)

    def check_warning(self, data):
        tokens, repo, sid = data[0], data[1], data[2]
        if tokens is None or tokens < WARN_AT or sid in self.warned:
            return
        self.warned.add(sid)
        self.notify(f"Claude Code: {fmt_k(tokens)} token",
                    f"{repo} (session {sid[:8]}): elértük a token keret felét. "
                    "Írj átadót!")

    def jump(self, pid):
        """A pid terminálfülére ideiglenes egyedi címet ír, a bővítmény előrehozza
        azt az ablakot, majd a terminál címveremből visszaáll az eredeti cím."""
        try:
            tty = os.readlink(f"/proc/{pid}/fd/0")
        except OSError:
            tty = ""
        if not tty.startswith("/dev/pts/"):
            self.notify("Ugrás nem sikerült", "Nem találom a session terminálját.", 1)
            return False
        marker = f"kontextus-ikon-ugras-{pid}-{time.monotonic_ns() % 100000}"
        # CSI 22;0t: cím mentése a verembe; OSC 2: új cím
        if not self.tty_write(tty, f"\x1b[22;0t\x1b]2;{marker}\x07"):
            return False
        tries = [0]

        def attempt():
            tries[0] += 1
            try:
                r = self.conn.call_sync(JUMP_BUS, JUMP_PATH, JUMP_BUS, "FocusByTitle",
                                        GLib.Variant("(s)", (marker,)), None,
                                        Gio.DBusCallFlags.NONE, 1000, None)
                found = r.unpack()[0]
            except GLib.Error as e:
                self.tty_write(tty, "\x1b[23;0t")   # CSI 23;0t: eredeti cím vissza
                if "ServiceUnknown" in str(e):
                    self.notify("Ugrás nem elérhető",
                                "Az ablakugró bővítmény még nem fut: jelentkezz ki és be.", 1)
                else:
                    print("ugrási hiba:", e, file=sys.stderr)
                return False
            if found or tries[0] >= 6:
                self.tty_write(tty, "\x1b[23;0t")
                if not found:
                    self.notify("Ugrás nem sikerült",
                                "Nem találom az ablakot. Lehet, hogy a session egy "
                                "háttérben lévő fülön fut; válts rá kézzel.", 1)
                return False
            return True

        GLib.timeout_add(150, attempt)
        return False

    @staticmethod
    def tty_write(tty, data):
        try:
            fd = os.open(tty, os.O_WRONLY | os.O_NOCTTY)
            try:
                os.write(fd, data.encode())
            finally:
                os.close(fd)
            return True
        except OSError as e:
            print("terminál írási hiba:", e, file=sys.stderr)
            return False

    def notify(self, summary, body, urgency=2):
        hints = {"urgency": GLib.Variant("y", urgency)}  # 2 = kritikus: nem tűnik el magától
        self.conn.call("org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                       "org.freedesktop.Notifications", "Notify",
                       GLib.Variant("(susssasa{sv}i)",
                                    ("Claude kontextus", 0, "dialog-warning",
                                     summary, body, [], hints, -1)),
                       None, Gio.DBusCallFlags.NONE, -1, None, None)


def main():
    if "--once" in sys.argv:  # ellenőrzéshez: kiírja, amit az ikonok mutatnának
        rows = collect(UsageCache())
        if not rows:
            print("– gray (nincs nyitott Claude Code terminál)")
        for pid, (tokens, repo, sid, mtime, status, name) in rows:
            print(pid, "–" if tokens is None else fmt_k(tokens), color_for(tokens, repo),
                  tokens, repo, sid, status, name)
        return
    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    # egy példány: ha már fut, kilép
    r = conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                       "org.freedesktop.DBus", "RequestName",
                       GLib.Variant("(su)", (BUS_NAME, 4)),  # DO_NOT_QUEUE
                       None, Gio.DBusCallFlags.NONE, -1, None)
    if r.unpack()[0] not in (1, 4):
        print("Már fut egy példány.", file=sys.stderr)
        return
    loop = GLib.MainLoop()
    App(loop)
    loop.run()


if __name__ == "__main__":
    main()
