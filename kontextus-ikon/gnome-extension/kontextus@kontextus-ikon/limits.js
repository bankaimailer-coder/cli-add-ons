// Keretmérők és hőfigyelő adatai, csak GLib/Gio: shell nélkül is futtatható (gjs -m).
//  - Claude: a statusline.py által írt $XDG_RUNTIME_DIR/kontextus-ikon/keretek.json;
//  - Codex: a legfrissebb ~/.codex/sessions/**/*.jsonl utolsó token_count eseményének rate_limits mezője
//    (csak olvasás, a fájl végéből; hitelesítő adatot nem nyit meg);
//  - keretfigyelő (keretfigyelo.py, systemd felhasználói szolgáltatás): $XDG_RUNTIME_DIR/kontextus-ikon/keretfigyelo.json;
//    ha fut, mérőnként a frissebb adat nyer (readLimits);
//  - hőfigyelő: $XDG_RUNTIME_DIR/hofigyelo/state.json.
// Minden mérő: {pct (elhasznált %), left (megmaradt % = 100 - pct), resetsAt, ts, stale, tsLabel, ...} vagy
// {pct: null, left: null, why: '...'} (nincs adat), becslés soha. stale: az adat STALE_AFTER-nél régebbi.
// Az időt („most”) minden döntő függvény paraméterként kapja, így a tesztben rögzíthető.
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';

const RUN_DIR = GLib.get_user_runtime_dir();
export const CLAUDE_FILE = GLib.build_filenamev([RUN_DIR, 'kontextus-ikon', 'keretek.json']);
export const HEAT_FILE = GLib.build_filenamev([RUN_DIR, 'hofigyelo', 'state.json']);
export const CODEX_SESSIONS = GLib.build_filenamev([GLib.get_home_dir(), '.codex', 'sessions']);
export const FIGYELO_FILE = GLib.build_filenamev([RUN_DIR, 'kontextus-ikon', 'keretfigyelo.json']);

// Elavultság-küszöb, egy helyen, minden keretmérőre (Claude és Codex): ennél régebbi adat „régi”.
// Claude-nál az ablak statusline-írásának ideje, Codexnél az utolsó helyi Codex-futás (token_count) ideje számít.
export const STALE_AFTER = 3600;
// a keretfigyelő (keretfigyelo.py) legfeljebb 30 mp-enként ír; ennél régebbi állapotfájl = a figyelő nem fut
export const FIGYELO_MAX_AGE = 120;
const CLAUDE_MAX_AGE = 3 * 3600;   // visszaállási idő nélküli adat (pl. Fable) ennyi ideig érvényes
const HEAT_MAX_AGE = 30;           // a hőfigyelő 5 mp-enként ír; ennél régebbi állapot = nincs adat
const CODEX_TAIL = 512 * 1024;     // ennyit olvas egy session-fájl végéből
const CODEX_FILES = 4;             // legfeljebb ennyi legfrissebb fájlban keres

const now = () => Date.now() / 1000;

// ---- hibajelentés: a váratlan hiba a GNOME-naplóba kerül, ugyanaz a hiba csak egyszer ----------
let logger = msg => console.warn(msg);
export function setLogger(fn) {
    logger = fn;
}
const reported = new Map();   // kulcs (útvonal) -> utoljára naplózott üzenet
function reportOnce(key, why, e) {
    const msg = `${why}: ${e.message}`;
    if (reported.get(key) !== msg) {
        reported.set(key, msg);
        logger(`kontextus-ikon: ${key}: ${msg}`);
    }
    return msg;
}
const clearReport = key => reported.delete(key);

const isNotFound = e => e instanceof GLib.Error &&
    (e.matches(GLib.FileError, GLib.FileError.NOENT) || e.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND));

// {data} vagy {why}: a hiányzó fájl várt eset (konkrét ok, naplózás nélkül), minden más hiba naplózva
function readJson(path, label) {
    let bytes;
    try {
        [, bytes] = GLib.file_get_contents(path);
    } catch (e) {
        if (isNotFound(e))
            return {why: `nincs ${label}`};
        return {why: reportOnce(path, `${label}: olvasási hiba`, e)};
    }
    try {
        const data = JSON.parse(new TextDecoder().decode(bytes));
        clearReport(path);
        return {data};
    } catch (e) {
        return {why: reportOnce(path, `hibás ${label}`, e)};
    }
}

const noData = why => ({pct: null, left: null, why});

// az elavultság-döntés: időbélyeg nélküli adat is régi, mert a korát nem tudjuk
export const isStale = (ts, t) => !ts || t - ts > STALE_AFTER;

// pct + visszaállás érvényessége a t pillanatban: lejárt ablak = nincs adat; régi adat = stale
export function window_(pct, resetsAt, ts, t, extra = {}) {
    if (typeof pct !== 'number' || !Number.isFinite(pct))
        return {...noData('nincs adat'), ...extra};
    if (resetsAt && resetsAt <= t)
        return {...noData('a keret visszaállt, azóta nincs friss adat'), resetsAt, ts: ts || null, ...extra};
    if (!resetsAt && ts && t - ts > CLAUDE_MAX_AGE)
        return {...noData('elavult adat (visszaállási idő nélkül)'), ts, ...extra};
    const left = Math.max(0, Math.min(100, 100 - pct));
    return {pct, left, resetsAt: resetsAt || null, ts: ts || null, stale: isStale(ts, t), ...extra};
}

// ---- Claude ---------------------------------------------------------------

// path és t: a teszt kedvéért paraméter; az ablak kora az ablak statusline-írásának ideje (v.ts),
// mert a statusline a meg nem kapott ablakot a régi időbélyegével tartja meg
export function readClaude(path = CLAUDE_FILE, t = now()) {
    const {data, why} = readJson(path, 'keretek.json (a statusline még nem írt?)');
    const c = data?.claude ?? {};
    const get = key => {
        if (!data)
            return noData(why);
        const v = c[key];
        if (!v)
            return noData('ez az ablak nincs a statusline adatában');
        const tsLabel = v.source === 'fiók' ? 'utolsó fiók-lekérdezés' : 'utolsó statusline-írás';
        return window_(v.pct, v.resets_at, v.ts ?? data.ts, t, {source: v.source, tsLabel});
    };
    return {
        fiveHour: get('five_hour'),
        weekly: get('seven_day'),
        fable: get('fable'),
        fileTs: data?.ts ?? null,
    };
}

// ---- Codex ----------------------------------------------------------------

// a nem létező mappa várt eset (nincs Codex, vagy az adott nap mappája közben eltűnt): üres lista;
// minden más hiba (pl. jogosultság) továbbmegy a hívóhoz, amely konkrét okkal jelenti
function childNames(path, wantDirs) {
    const out = [];
    let en;
    try {
        en = Gio.File.new_for_path(path).enumerate_children('standard::name,standard::type',
            Gio.FileQueryInfoFlags.NONE, null);
    } catch (e) {
        if (isNotFound(e))
            return out;
        throw e;
    }
    try {
        let info;
        while ((info = en.next_file(null))) {
            const isDir = info.get_file_type() === Gio.FileType.DIRECTORY;
            if (isDir === wantDirs)
                out.push(info.get_name());
        }
    } finally {
        en.close(null);
    }
    return out.sort().reverse();
}

// a legfrissebb napok .jsonl fájljai, módosítás szerint csökkenő sorrendben
function codexFiles(root) {
    const files = [];
    outer:
    for (const y of childNames(root, true)) {
        for (const m of childNames(GLib.build_filenamev([root, y]), true)) {
            for (const d of childNames(GLib.build_filenamev([root, y, m]), true)) {
                const dir = GLib.build_filenamev([root, y, m, d]);
                for (const f of childNames(dir, false)) {
                    if (f.endsWith('.jsonl'))
                        files.push(GLib.build_filenamev([dir, f]));
                }
                if (files.length >= CODEX_FILES)
                    break outer;
            }
        }
    }
    const withTime = files.map(path => {
        try {
            const info = Gio.File.new_for_path(path).query_info('time::modified,standard::size',
                Gio.FileQueryInfoFlags.NONE, null);
            return {path, mtime: info.get_attribute_uint64('time::modified'), size: info.get_size()};
        } catch (e) {
            // a listázás és a lekérdezés között törölt fájl várt eset: kimarad; más hiba továbbmegy
            if (isNotFound(e))
                return null;
            throw e;
        }
    }).filter(Boolean);
    return withTime.sort((a, b) => b.mtime - a.mtime).slice(0, CODEX_FILES);
}

// a fájl [start, size) tartománya, legfeljebb CODEX_TAIL bájt a végéről: {text, end}; a tail-olvasás első, csonka
// sora kimarad, a félig írt (újsor nélküli) utolsó sor benne marad, hogy a lastRateLimits „csonka”-ként számolja;
// end: az utolsó ép sor vége (innen folytatja a következő, inkrementális olvasás, így a félig írt sort is újraolvassa)
export const codexStats = {bytesRead: 0};   // a teszt kedvéért: mennyit olvasott eddig
function readRange(path, start, size) {
    const from = Math.max(start, size - CODEX_TAIL);
    const stream = Gio.File.new_for_path(path).read(null);
    try {
        if (from > 0)
            stream.seek(from, GLib.SeekType.SET, null);
        let bytes = from < size ? stream.read_bytes(size - from, null).toArray() : new Uint8Array();
        codexStats.bytesRead += bytes.length;
        const last = bytes.lastIndexOf(10);
        let text = new TextDecoder().decode(bytes);
        if (from > start)
            text = text.slice(text.indexOf('\n') + 1);   // a levágott eleje csonka sor
        return {text, end: from + last + 1};
    } finally {
        stream.close(null);
    }
}

// utolsó rate_limits-pillanatkép a szöveg végéből: {rl, ts} vagy {why}
export function lastRateLimits(text) {
    const lines = text.split('\n');
    let bad = 0;
    for (let i = lines.length - 1; i >= 0; i--) {
        if (!lines[i].includes('"rate_limits"'))
            continue;
        let j;
        try {
            j = JSON.parse(lines[i]);
        } catch {
            // várt eset: a futó Codex éppen írja az utolsó sort (csonka); megszámoljuk, és ha nincs ép
            // pillanatkép, a menüben ez az ok áll; a korábbi ép sorokat tovább keressük
            bad++;
            continue;
        }
        const rl = j?.payload?.rate_limits;
        if (rl && (rl.limit_id ?? 'codex') === 'codex' && (rl.primary || rl.secondary))
            return {rl, ts: Date.parse(j.timestamp) / 1000 || null};
    }
    return {why: bad ? 'csonka rate_limits-sor a Codex-naplóban, ép pillanatkép nincs'
        : 'nincs rate_limits a Codex-naplóban'};
}

// {key, snap, file, why, inc: {path, end}}: ugyanarra a fájlállapotra nem olvas újra; ha csak a legfrissebb
// fájl nőtt, csak a hozzáírt részt olvassa (futó Codex alatt ez a Shell fő szálán fut, ne 512 KB-onként)
let codexCache = null;

const CODEX_TS_LABEL = 'utolsó helyi Codex-futás';

// root és t: a teszt kedvéért paraméter
export function readCodex(root = CODEX_SESSIONS, t = now()) {
    const both = why => ({
        fiveHour: {...noData(why), tsLabel: CODEX_TS_LABEL},
        weekly: {...noData(why), tsLabel: CODEX_TS_LABEL},
        file: null,
    });
    let files;
    try {
        files = codexFiles(root);
        clearReport(root);
    } catch (e) {
        return both(reportOnce(root, 'a Codex-naplók listázása nem sikerült', e));
    }
    if (!files.length)
        return both('nincs Codex-napló (a ~/.codex/sessions üres vagy nincs)');
    const key = files.map(f => `${f.path}:${f.mtime}:${f.size}`).join('|');
    let snap = null, file = null, why = null, inc = null;
    const top = files[0], c = codexCache;
    if (c?.key === key) {
        ({snap, file, why, inc} = c);
    } else if (c?.inc && c.inc.path === top.path && top.size >= c.inc.end) {
        // csak a legfrissebb fájl nőtt (vagy csak más fájl változott): a hozzáírt rész
        ({snap, file, why} = c);
        try {
            const r = readRange(top.path, c.inc.end, top.size);
            clearReport(top.path);
            inc = {path: top.path, end: r.end};
            const found = lastRateLimits(r.text);
            if (found.rl) {
                snap = found;
                file = top.path;
                why = null;
            }
        } catch (e) {
            inc = null;
            why = reportOnce(top.path, 'a Codex-napló olvasása nem sikerült', e);
        }
        codexCache = {key, snap, file, why, inc};
    } else {
        for (const f of files) {
            let r;
            try {
                r = readRange(f.path, 0, f.size);
                clearReport(f.path);
            } catch (e) {
                why ??= reportOnce(f.path, 'a Codex-napló olvasása nem sikerült', e);
                continue;
            }
            if (f === top)
                inc = {path: f.path, end: r.end};
            const found = lastRateLimits(r.text);
            if (found.rl) {
                snap = found;
                file = f.path;
                break;
            }
            why ??= found.why;
        }
        codexCache = {key, snap, file, why, inc};
    }
    if (!snap)
        return both(why);
    // a primary/secondary sorrendet nem feltételezi: az ablak hossza dönt (300 perc / 10080 perc)
    const wins = [snap.rl.primary, snap.rl.secondary].filter(Boolean);
    const pick = test => {
        const w = wins.find(x => test(x.window_minutes));
        return w ? window_(w.used_percent, w.resets_at, snap.ts, t,
            {windowMinutes: w.window_minutes, tsLabel: CODEX_TS_LABEL})
            : {...noData('ez az ablak hiányzik a Codex-adatból'), tsLabel: CODEX_TS_LABEL};
    };
    return {
        fiveHour: pick(m => m <= 24 * 60),
        weekly: pick(m => m > 24 * 60),
        plan: snap.rl.plan_type ?? null,
        file,
        ts: snap.ts,
    };
}

// ---- keretfigyelő (háttérszolgáltatás) és a források összefésülése ------------------------

// {running: true, ts, claude, codex} vagy {running: false, why}; path és t: a teszt kedvéért paraméter
export function readFigyelo(path = FIGYELO_FILE, t = now()) {
    const {data, why} = readJson(path, 'futó keretfigyelő (keretfigyelo.json)');
    if (!data)
        return {running: false, why};
    if (typeof data.ts !== 'number')
        return {running: false, why: 'hibás keretfigyelo.json (nincs ts)'};
    if (t - data.ts > FIGYELO_MAX_AGE)
        return {running: false, why: 'a keretfigyelő nem fut (az állapotfájl elavult)', ts: data.ts};
    return {running: true, ts: data.ts, claude: data.claude ?? {}, codex: data.codex ?? {}};
}

// a figyelő egy blokkja (claude vagy codex) mérőértékekké: {mérőkulcs: window_(...)}; a hiányzó ablak oka a
// blokk oka (pl. „nincs Codex-bejelentkezés”), ha van
function figyeloWindows(block, keys, t, tsLabel) {
    const out = {};
    for (const [key, src] of Object.entries(keys)) {
        const v = block?.[src];
        // note: a figyelő legutóbbi hibája (pl. lejárt bejelentkezés), az utolsó jó adat mellett
        out[key] = v ? window_(v.pct, v.resets_at, v.ts, t, {source: v.source, tsLabel, note: block.why ?? null})
            : {...noData(block?.why ?? 'ez az ablak hiányzik a keretfigyelő adatából'), tsLabel};
    }
    return out;
}

const has = v => typeof v?.pct === 'number';

// két forrás ugyanarra a mérőre: a számmal bíró, frissebb nyer; ha egyiknek sincs száma, a második (a
// keretfigyelő) oka a konkrétabb
export function fresher(a, b) {
    if (has(a) && has(b))
        return (b.ts ?? 0) > (a.ts ?? 0) ? b : a;
    if (has(a))
        return a;
    return b ?? a;
}

const CLAUDE_KEYS = {fiveHour: 'five_hour', weekly: 'seven_day', fable: 'fable'};
const CODEX_KEYS = {fiveHour: 'five_hour', weekly: 'weekly'};

// minden keretmérő: a statusline-fájl és a helyi Codex-napló (T01), és ha fut, a keretfigyelő adata;
// mérőnként a frissebb. paths: {claude, codex, figyelo} a teszt kedvéért
export function readLimits(t = now(), paths = {}) {
    const claude = readClaude(paths.claude, t);
    const codex = readCodex(paths.codex, t);
    const figyelo = readFigyelo(paths.figyelo, t);
    if (!figyelo.running)
        return {claude, codex, figyelo};
    const fc = figyeloWindows(figyelo.claude, CLAUDE_KEYS, t, 'utolsó fiók-lekérdezés (keretfigyelő)');
    const fx = figyeloWindows(figyelo.codex, CODEX_KEYS, t, 'utolsó Codex-lekérdezés (keretfigyelő)');
    const pick = (local, fig) => Object.fromEntries(Object.keys(fig).map(k => [k, fresher(local[k], fig[k])]));
    return {
        claude: {...claude, ...pick(claude, fc)},
        codex: {...codex, ...pick(codex, fx), plan: figyelo.codex.plan ?? codex.plan ?? null},
        figyelo,
    };
}

// a figyelendő Codex-mappák: a legfrissebb napló napi mappája és fölötte a hónap, az év és a sessions-gyökér
// (ez utóbbiak új nap/hónap/év mappájának létrejöttét jelzik, hogy az új nap első futása is azonnal látsszon)
export function codexWatchDirs(root, file) {
    const dirs = [];
    if (file) {
        let d = GLib.path_get_dirname(file);
        for (let i = 0; i < 3 && d.startsWith(`${root}/`); i++) {
            dirs.push(d);
            d = GLib.path_get_dirname(d);
        }
    }
    dirs.push(root);
    return dirs;
}

// a menü keretfigyelő-sora; fmt: időformázó (unix mp -> szöveg)
export function figyeloStatus(fig, fmt) {
    if (!fig.running)
        return `Keretfigyelő: NEM FUT (${fig.why}); csak a statusline és a helyi Codex-napló adata látszik`;
    return `Keretfigyelő: fut (${fmt(fig.ts)}) · Claude: ${fig.claude.why ?? 'rendben'} · ` +
        `Codex: ${fig.codex.why ?? 'rendben'}`;
}

// ---- hőfigyelő ------------------------------------------------------------

export const HEAT_LEVELS = {
    ok: 'rendben', warm: 'meleg', hot: 'forró', critical: 'kritikus',
};

// a hofigyelo.py kilépési küszöbei (CPU_TH / GPU_TH második értéke): egy eszköz száma akkor kapja meg
// a szolgáltatás szintjét, ha maga is eléri azt; így a hűvösebb eszköz nem színeződik a másik miatt
const LEAVE = {
    cpu: {warm: 88, hot: 91, critical: 94},
    gpu: {warm: 84, hot: 91, critical: 93},
};
const ORDER = ['ok', 'warm', 'hot', 'critical'];

function deviceLevel(dev, temp, level) {
    let own = 'ok';
    for (const name of ORDER.slice(1)) {
        if (temp >= LEAVE[dev][name])
            own = name;
    }
    const g = ORDER.indexOf(level);
    return g < 0 ? 'ok' : ORDER[Math.min(g, ORDER.indexOf(own))];
}

const num = v => (typeof v === 'number' && Number.isFinite(v) ? v : null);

// {ts, level, since, message, why?, cpu: {temp, now, median, acpi, level, why?}, gpu: {temp, level, why?}}
// temp === null: az adott mérő „nincs adat” állapotban (a mérő ettől nem tűnik el)
export function readHeat() {
    const {data: s, why} = readJson(HEAT_FILE, 'állapotfájl');
    const empty = w => ({why: w, cpu: {temp: null, why: w}, gpu: {temp: null, why: w}});
    if (!s)
        return empty(why);
    if (typeof s.ts !== 'number')
        return empty('hibás állapotfájl (nincs ts)');
    if (now() - s.ts > HEAT_MAX_AGE)
        return {...empty('elavult állapotfájl (a hőfigyelő nem fut?)'), ts: s.ts};
    const level = String(s.level);
    // a szint a CPU 30 mp-es mediánjából számol, ezért a CPU-mérő száma is az
    const cpuT = num(s.cpu_median_c) ?? num(s.cpu_c);
    const gpuT = num(s.gpu_c);
    return {
        ts: s.ts, level, since: s.since ?? null, message: s.message ?? '',
        cpu: cpuT === null ? {temp: null, why: 'nincs CPU-érték az állapotfájlban'}
            : {temp: cpuT, now: num(s.cpu_c), median: num(s.cpu_median_c), acpi: num(s.acpi_c),
                level: deviceLevel('cpu', cpuT, level)},
        gpu: gpuT === null ? {temp: null, why: 'nincs GPU-érték (a GPU alszik?)'}
            : {temp: gpuT, level: deviceLevel('gpu', gpuT, level)},
    };
}
