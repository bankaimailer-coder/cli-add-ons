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

const MEM_POLL_SEC = 3;
const CHIP_W = 22, CHIP_H = 16;   // logikai pixel
const GAUGE_SIZE = 16;

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
        box.add_child(this._area);
        box.add_child(this._label);
        this.add_child(box);
    }

    update(data) {
        const old = this._data;
        this._data = data;
        if (!old || old.frac !== data.frac || String(old.color) !== String(data.color))
            this._area.queue_repaint();
        this._label.text = data.label;
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
        this._panel = new ContextPanel();
    }

    disable() {
        this._panel?.destroy();
        this._panel = null;
        this._mem?.destroy();
        this._mem = null;
        this._jump?.destroy();
        this._jump = null;
    }
}
