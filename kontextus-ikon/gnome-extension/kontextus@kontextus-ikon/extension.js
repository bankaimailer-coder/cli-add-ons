// Kontextus-ikon GNOME-bővítmény:
//  - Claude Code kontextusmérők a felső sáv bal oldalán, az ablakválasztó után
//    (az adatokat a kontextus_ikon.py adja D-Bus-on);
//  - memória-chip a rendszerikonok (mikrofon, Wi-Fi) előtt;
//  - ablakugrás: Wayland alatt külső program nem hozhat előre ablakot, a Shell igen.
import GObject from 'gi://GObject';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import {drawChip} from './chip.js';
import {drawGauge} from './gauge.js';
import {drawLimit, drawHeat, CLAUDE_RGB, CODEX_RGB, CPU_RGB, GPU_RGB} from './meter.js';
import {readClaude, readCodex, readHeat, HEAT_LEVELS} from './limits.js';

const MEM_POLL_SEC = 3;
const LIMIT_POLL_SEC = 15;
const HEAT_POLL_SEC = 5;
const LIMIT_W = 36, LIMIT_H = 20;   // keretmérő (négyzetes márkaikon + jel és szám), logikai pixel
const HEAT_W = 38;                  // hőmérő: négyzetes ikon + a fok
const CHIP_W = 22, CHIP_H = 16;   // logikai pixel
const GAUGE_SIZE = 16;
const SUB_GAUGE_SIZE = 11;      // a legnagyobb futó subagent kisebb köríve

// a Python-folyamat (kontextus_ikon.py)
const APP_BUS = 'hu.bfuzzee.KontextusIkon';
const APP_PATH = '/hu/bfuzzee/KontextusIkon';
// ezt a nevet a bővítmény birtokolja; ebből tudja a Python, hogy nem kell saját sávikon
const PANEL_BUS = 'hu.bfuzzee.KontextusIkon.Panel';

const JUMP_BUS = 'hu.bfuzzee.KontextusIkon.Ablak';
const JUMP_PATH = '/hu/bfuzzee/KontextusIkon/Ablak';
const JUMP_IFACE = `<node>
 <interface name="hu.bfuzzee.KontextusIkon.Ablak">
  <method name="Titles"><arg type="as" direction="out"/></method>
  <method name="FocusByTitle"><arg type="s" direction="in"/><arg type="b" direction="out"/></method>
 </interface>
</node>`;

// ---- ablakugrás -----------------------------------------------------------

class JumpService {
    constructor() {
        this._impl = Gio.DBusExportedObject.wrapJSObject(JUMP_IFACE, this);
        this._impl.export(Gio.DBus.session, JUMP_PATH);
        this._ownId = Gio.bus_own_name(Gio.BusType.SESSION, JUMP_BUS,
            Gio.BusNameOwnerFlags.NONE, null, null, null);
    }

    destroy() {
        Gio.bus_unown_name(this._ownId);
        this._impl.unexport();
        this._impl = null;
    }

    // csak a Ptyxis ablakai
    _windows() {
        return global.get_window_actors()
            .map(a => a.meta_window)
            .filter(w => w && (w.get_wm_class() ?? '').toLowerCase().includes('ptyxis'));
    }

    Titles() {
        return this._windows().map(w => w.get_title() ?? '');
    }

    FocusByTitle(marker) {
        if (!marker)
            return false;
        const win = this._windows().find(w => (w.get_title() ?? '').includes(marker));
        if (!win)
            return false;
        Main.activateWindow(win);
        return true;
    }
}

// ---- memória-chip ---------------------------------------------------------

// használt memória százalékban, ugyanúgy, mint a `free`: (MemTotal - MemAvailable) / MemTotal
function readMemPct() {
    try {
        const [, bytes] = GLib.file_get_contents('/proc/meminfo');
        const text = new TextDecoder().decode(bytes);
        const get = key => Number(text.match(new RegExp(`^${key}:\\s+(\\d+)`, 'm'))?.[1]);
        const total = get('MemTotal'), avail = get('MemAvailable');
        return total ? (total - avail) / total * 100 : null;
    } catch {
        return null;
    }
}

const MemIndicator = GObject.registerClass(
class MemIndicator extends PanelMenu.Button {
    _init() {
        super._init(0.5, 'Memória', true);
        this._pct = readMemPct();
        const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor;
        this._area = new St.DrawingArea({
            width: CHIP_W * scale,
            height: CHIP_H * scale,
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._area.connect('repaint', area => {
            const cr = area.get_context();
            const [w, h] = area.get_surface_size();
            drawChip(cr, w, h, this._pct);
            cr.$dispose();
        });
        this.add_child(this._area);
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, MEM_POLL_SEC, () => {
            const pct = readMemPct();
            if (pct === null || this._pct === null || Math.round(pct) !== Math.round(this._pct)) {
                this._pct = pct;
                this._area.queue_repaint();
            }
            return GLib.SOURCE_CONTINUE;
        });
    }

    destroy() {
        if (this._timer) {
            GLib.source_remove(this._timer);
            this._timer = 0;
        }
        super.destroy();
    }
});

// ---- keretmérők és hőmérő -------------------------------------------------

function fmtTime(ts) {
    const dt = GLib.DateTime.new_from_unix_local(Math.round(ts));
    const today = GLib.DateTime.new_now_local();
    const sameDay = dt.get_year() === today.get_year() && dt.get_day_of_year() === today.get_day_of_year();
    return dt.format(sameDay ? '%H:%M' : '%m.%d. %H:%M');
}

function fmtLeft(ts) {
    const min = Math.max(0, Math.round((ts - Date.now() / 1000) / 60));
    const d = Math.floor(min / 1440), h = Math.floor(min % 1440 / 60), m = min % 60;
    return d ? `${d} n ${h} ó` : h ? `${h} ó ${m} p` : `${m} p`;
}

function limitLine(name, v) {
    if (v.pct === null) {
        let s = `${name}: – (${v.why})`;
        if (v.resetsAt)
            s += `, visszaállt ${fmtTime(v.resetsAt)}`;
        return s;
    }
    let s = `${name}: maradt ${Math.round(v.left)}% (elhasználva ${Math.round(v.pct)}%)`;
    s += v.resetsAt ? ` · visszaáll ${fmtTime(v.resetsAt)} (${fmtLeft(v.resetsAt)} múlva)`
        : ' · visszaállás: ismeretlen';
    if (v.ts)
        s += ` · adat: ${fmtTime(v.ts)}`;
    return s;
}

function newArea(w, h, draw) {
    const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor;
    const area = new St.DrawingArea({
        width: w * scale,
        height: h * scale,
        y_align: Clutter.ActorAlign.CENTER,
    });
    area.connect('repaint', a => {
        const cr = a.get_context();
        const [sw, sh] = a.get_surface_size();
        draw(cr, sw, sh);
        cr.$dispose();
    });
    return area;
}

// fix menüsorok, csak a szövegük frissül (nyitott menünél sem villog)
function infoItems(menu, n) {
    const items = [];
    for (let i = 0; i < n; i++) {
        const it = new PopupMenu.PopupMenuItem('', {reactive: false});
        menu.addMenuItem(it);
        items.push(it);
    }
    return items;
}

const METERS = [   // [csoport, kulcs, jel, szín, menünév, ikon]
    ['claude', 'fiveHour', '5h', CLAUDE_RGB, 'Claude 5 órás', 'claude'],
    ['claude', 'weekly', 'H', CLAUDE_RGB, 'Claude heti', 'claude'],
    ['claude', 'fable', 'F', CLAUDE_RGB, 'Claude Fable heti', 'claude'],
    ['codex', 'fiveHour', '5h', CODEX_RGB, 'Codex 5 órás', 'openai'],
    ['codex', 'weekly', 'H', CODEX_RGB, 'Codex heti', 'openai'],
];

const LimitsIndicator = GObject.registerClass(
class LimitsIndicator extends PanelMenu.Button {
    _init() {
        super._init(0.5, 'Használati keretek', false);
        this._data = {claude: readClaude(), codex: readCodex()};
        const box = new St.BoxLayout({style_class: 'panel-status-menu-box'});
        this._areas = METERS.map(([group, key, tag, rgb, , brand], i) => {
            const area = newArea(LIMIT_W, LIMIT_H,
                (cr, w, h) => drawLimit(cr, w, h, this._data[group][key].left, tag, rgb, brand));
            // csoporton belül kis köz, Claude és Codex között nagyobb
            if (i > 0)
                area.style = `margin-left: ${METERS[i - 1][0] === group ? 3 : 9}px;`;
            box.add_child(area);
            return area;
        });
        this.add_child(box);

        this._items = infoItems(this.menu, METERS.length);
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._srcItems = infoItems(this.menu, 2);
        this._refreshText();

        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, LIMIT_POLL_SEC, () => {
            this._poll();
            return GLib.SOURCE_CONTINUE;
        });
        this._menuSig = this.menu.connect('open-state-changed', (_m, open) => {
            if (open)
                this._poll();
        });
    }

    _poll() {
        const old = this._data;
        try {
            this._data = {claude: readClaude(), codex: readCodex()};
        } catch (e) {
            logError(e, 'kontextus-ikon: keretek');
            return;
        }
        METERS.forEach(([group, key], i) => {
            const a = old[group][key].pct, b = this._data[group][key].pct;
            if ((a === null) !== (b === null) || Math.round(a) !== Math.round(b))
                this._areas[i].queue_repaint();
        });
        this._refreshText();
    }

    _refreshText() {
        METERS.forEach(([group, key, , , name], i) => {
            this._items[i].label.text = limitLine(name, this._data[group][key]);
        });
        const plan = this._data.codex.plan ? ` (${this._data.codex.plan})` : '';
        this._srcItems[0].label.text = 'Claude: statusline (5h, heti) és a fiók /usage adata (Fable)';
        this._srcItems[1].label.text = `Codex${plan}: ~/.codex/sessions, utolsó token_count`;
    }

    destroy() {
        if (this._timer) {
            GLib.source_remove(this._timer);
            this._timer = 0;
        }
        if (this._menuSig) {
            this.menu.disconnect(this._menuSig);
            this._menuSig = 0;
        }
        super.destroy();
    }
});

const HEAT_DEVS = {   // eszköz -> [ikonszín, menünév]
    cpu: [CPU_RGB, 'CPU'],
    gpu: [GPU_RGB, 'GPU'],
};

// egy eszköz (CPU vagy GPU) hőmérője; GPU-érték nélkül is látszik, „nincs adat” állapotban
const HeatIndicator = GObject.registerClass(
class HeatIndicator extends PanelMenu.Button {
    _init(dev) {
        const [rgb, name] = HEAT_DEVS[dev];
        super._init(0.5, `Hőfigyelő ${name}`, false);
        this._dev = dev;
        this._name = name;
        this._data = readHeat();
        this._area = newArea(HEAT_W, LIMIT_H, (cr, w, h) => {
            const d = this._data[dev];
            drawHeat(cr, w, h, d.temp, d.level, rgb);
        });
        this.add_child(this._area);
        this._items = infoItems(this.menu, 5);
        this._refreshText();
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, HEAT_POLL_SEC, () => {
            const old = this._data[dev];
            this._data = readHeat();
            const d = this._data[dev];
            if ((old.temp === null) !== (d.temp === null) || Math.round(old.temp) !== Math.round(d.temp)
                || old.level !== d.level)
                this._area.queue_repaint();
            this._refreshText();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _refreshText() {
        const all = this._data, d = all[this._dev];
        const c = v => (typeof v === 'number' ? `${Math.round(v)} °C` : '–');
        const lines = [];
        if (d.temp === null) {
            lines.push(`${this._name}: nincs adat (${d.why})`);
        } else if (this._dev === 'cpu') {
            lines.push(`CPU: ${c(d.temp)} (30 mp medián, ebből számol a szint)`);
            lines.push(`CPU pillanatnyi: ${c(d.now)} · ACPI: ${c(d.acpi)}`);
        } else {
            lines.push(`GPU: ${c(d.temp)}`);
        }
        if (all.level) {
            const own = d.temp === null ? '' : `, ennek a mérőnek: ${HEAT_LEVELS[d.level] ?? d.level}`;
            lines.push(`Hőfigyelő szintje: ${HEAT_LEVELS[all.level] ?? all.level}${own}`);
            if (all.since)
                lines.push(`A szint ${fmtTime(all.since)} óta áll fenn`);
        }
        if (all.ts)
            lines.push(`Állapotfájl: ${GLib.DateTime.new_from_unix_local(Math.round(all.ts)).format('%Y.%m.%d. %H:%M:%S')}`);
        while (lines.length > this._items.length)
            this._items.push(infoItems(this.menu, 1)[0]);
        this._items.forEach((it, i) => {
            it.label.text = lines[i] ?? '';
            it.visible = i < lines.length;
        });
    }

    destroy() {
        if (this._timer) {
            GLib.source_remove(this._timer);
            this._timer = 0;
        }
        super.destroy();
    }
});

// ---- kontextusmérők ------------------------------------------------------

function callApp(method, params) {
    Gio.DBus.session.call(APP_BUS, APP_PATH, APP_BUS, method, params, null,
        Gio.DBusCallFlags.NONE, -1, null, null);
}

const ContextIndicator = GObject.registerClass(
class ContextIndicator extends PanelMenu.Button {
    _init(key) {
        super._init(0.0, 'Claude kontextus', false);
        this._key = key;
        this._data = null;
        const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor;
        const box = new St.BoxLayout({style_class: 'panel-status-menu-box'});
        this._area = new St.DrawingArea({
            width: GAUGE_SIZE * scale,
            height: GAUGE_SIZE * scale,
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._area.connect('repaint', area => {
            const cr = area.get_context();
            const [w] = area.get_surface_size();
            if (this._data)
                drawGauge(cr, w, this._data.frac, this._data.color.map(c => c / 255));
            cr.$dispose();
        });
        this._label = new St.Label({y_align: Clutter.ActorAlign.CENTER});
        this._subArea = new St.DrawingArea({
            width: SUB_GAUGE_SIZE * scale,
            height: SUB_GAUGE_SIZE * scale,
            y_align: Clutter.ActorAlign.CENTER,
            style: 'margin-left: 4px;',
            visible: false,
        });
        this._subArea.connect('repaint', area => {
            const cr = area.get_context();
            const [w] = area.get_surface_size();
            if (this._data?.sub)
                drawGauge(cr, w, this._data.sub.frac, this._data.sub.color.map(c => c / 255));
            cr.$dispose();
        });
        box.add_child(this._area);
        box.add_child(this._label);
        box.add_child(this._subArea);
        this.add_child(box);
    }

    update(data) {
        const old = this._data;
        this._data = data;
        if (!old || old.frac !== data.frac || String(old.color) !== String(data.color))
            this._area.queue_repaint();
        this._label.text = data.label;
        this._subArea.visible = !!data.sub;
        if (JSON.stringify(old?.sub ?? null) !== JSON.stringify(data.sub ?? null))
            this._subArea.queue_repaint();
        if (old && JSON.stringify(old.lines) === JSON.stringify(data.lines) && old.jump === data.jump)
            return;
        this.menu.removeAll();
        if (data.jump) {
            const jump = new PopupMenu.PopupMenuItem('Ugrás a terminálba');
            jump.connect('activate', () => callApp('Jump', new GLib.Variant('(i)', [this._key])));
            this.menu.addMenuItem(jump);
            this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        }
        for (const line of data.lines)
            this.menu.addMenuItem(new PopupMenu.PopupMenuItem(line, {reactive: false}));
    }
});

class ContextPanel {
    constructor() {
        this._indicators = new Map();     // kulcs (pid) -> ContextIndicator
        this._ownId = Gio.bus_own_name(Gio.BusType.SESSION, PANEL_BUS,
            Gio.BusNameOwnerFlags.NONE, null, null, null);
        this._sigId = Gio.DBus.session.signal_subscribe(APP_BUS, APP_BUS, 'Changed', APP_PATH,
            null, Gio.DBusSignalFlags.NONE,
            (_c, _s, _p, _i, _n, params) => this._apply(params.deepUnpack()[0]));
        this._watchId = Gio.bus_watch_name(Gio.BusType.SESSION, APP_BUS,
            Gio.BusNameWatcherFlags.NONE,
            () => this._fetch(),
            () => this._apply('[]'));
    }

    _fetch() {
        Gio.DBus.session.call(APP_BUS, APP_PATH, APP_BUS, 'Sessions', null,
            new GLib.VariantType('(s)'), Gio.DBusCallFlags.NONE, -1, null,
            (conn, res) => {
                try {
                    this._apply(conn.call_finish(res).deepUnpack()[0]);
                } catch (e) {
                    logError(e, 'kontextus-ikon: Sessions');
                }
            });
    }

    _apply(json) {
        let rows;
        try {
            rows = JSON.parse(json);
        } catch {
            return;
        }
        const wanted = new Set(rows.map(r => r.key));
        for (const [key, ind] of this._indicators) {
            if (!wanted.has(key)) {
                ind.destroy();
                this._indicators.delete(key);
            }
        }
        rows.forEach((row, i) => {
            let ind = this._indicators.get(row.key);
            if (!ind) {
                ind = new ContextIndicator(row.key);
                this._indicators.set(row.key, ind);
                // bal oldal: az ablakválasztó (Tevékenységek) után, indulási sorrendben
                const box = Main.panel._leftBox;
                const act = Main.panel.statusArea.activities;
                const base = act ? box.get_children().indexOf(act.container) + 1 : 0;
                Main.panel.addToStatusArea(`kontextus-ikon-${row.key}`, ind, base + i, 'left');
            }
            ind.update(row);
        });
    }

    destroy() {
        Gio.bus_unwatch_name(this._watchId);
        Gio.DBus.session.signal_unsubscribe(this._sigId);
        Gio.bus_unown_name(this._ownId);
        for (const ind of this._indicators.values())
            ind.destroy();
        this._indicators.clear();
    }
}

// ---- bővítmény -----------------------------------------------------------

export default class KontextusExtension extends Extension {
    enable() {
        this._jump = new JumpService();
        this._mem = new MemIndicator();
        // a gyorsbeállítások (mikrofon, Wi-Fi, akku) elé, közvetlenül melléjük
        const box = Main.panel._rightBox;
        const qs = Main.panel.statusArea.quickSettings;
        let pos = qs ? box.get_children().indexOf(qs.container) : -1;
        if (pos < 0)
            pos = box.get_n_children();
        Main.panel.addToStatusArea('kontextus-ikon-memoria', this._mem, pos, 'right');
        // a memória-chip elé: keretmérők, CPU- és GPU-hőmérő, memória-chip, rendszerikonok
        this._limits = new LimitsIndicator();
        Main.panel.addToStatusArea('kontextus-ikon-keretek', this._limits,
            box.get_children().indexOf(this._mem.container), 'right');
        this._heat = ['cpu', 'gpu'].map(dev => {
            const ind = new HeatIndicator(dev);
            Main.panel.addToStatusArea(`kontextus-ikon-ho-${dev}`, ind,
                box.get_children().indexOf(this._mem.container), 'right');
            return ind;
        });
        this._panel = new ContextPanel();
    }

    disable() {
        this._panel?.destroy();
        this._panel = null;
        this._heat?.forEach(ind => ind.destroy());
        this._heat = null;
        this._limits?.destroy();
        this._limits = null;
        this._mem?.destroy();
        this._mem = null;
        this._jump?.destroy();
        this._jump = null;
    }
}
