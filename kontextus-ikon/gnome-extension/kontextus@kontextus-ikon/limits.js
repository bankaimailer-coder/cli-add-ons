// Keretmérők és hőfigyelő adatai, csak GLib/Gio: shell nélkül is futtatható (gjs -m).
//  - Claude: a statusline.py által írt $XDG_RUNTIME_DIR/kontextus-ikon/keretek.json;
//  - Codex: a legfrissebb ~/.codex/sessions/**/*.jsonl utolsó token_count eseményének rate_limits mezője
//    (csak olvasás, a fájl végéből; hitelesítő adatot nem nyit meg);
//  - hőfigyelő: $XDG_RUNTIME_DIR/hofigyelo/state.json.
// Minden mérő: {pct, resetsAt, ts, ...} vagy {pct: null, why: '...'} (nincs adat), becslés soha.
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';

const RUN_DIR = GLib.get_user_runtime_dir();
export const CLAUDE_FILE = GLib.build_filenamev([RUN_DIR, 'kontextus-ikon', 'keretek.json']);
export const HEAT_FILE = GLib.build_filenamev([RUN_DIR, 'hofigyelo', 'state.json']);
const CODEX_SESSIONS = GLib.build_filenamev([GLib.get_home_dir(), '.codex', 'sessions']);

const CLAUDE_MAX_AGE = 3 * 3600;   // visszaállási idő nélküli adat (pl. Fable) ennyi ideig érvényes
const HEAT_MAX_AGE = 30;           // a hőfigyelő 5 mp-enként ír; ennél régebbi állapot = nincs adat
const CODEX_TAIL = 512 * 1024;     // ennyit olvas egy session-fájl végéből
const CODEX_FILES = 4;             // legfeljebb ennyi legfrissebb fájlban keres

const now = () => Date.now() / 1000;

function readJson(path) {
    try {
        const [, bytes] = GLib.file_get_contents(path);
        return JSON.parse(new TextDecoder().decode(bytes));
    } catch {
        return null;
    }
}

const noData = why => ({pct: null, why});

// pct + visszaállás érvényessége: lejárt ablak vagy elavult adat = nincs adat
function window_(pct, resetsAt, ts, extra = {}) {
    if (typeof pct !== 'number')
        return noData('nincs adat');
    const t = now();
    if (resetsAt && resetsAt <= t)
        return {...noData('a keret visszaállt, friss adat még nincs'), resetsAt, ts};
    if (!resetsAt && ts && t - ts > CLAUDE_MAX_AGE)
        return {...noData('elavult adat'), ts};
    return {pct, resetsAt: resetsAt || null, ts: ts || null, ...extra};
}

// ---- Claude ---------------------------------------------------------------

export function readClaude() {
    const data = readJson(CLAUDE_FILE);
    const c = data?.claude ?? {};
    const get = key => {
        const v = c[key];
        return v ? window_(v.pct, v.resets_at, v.ts, {source: v.source}) : noData('nincs adat');
    };
    return {
        fiveHour: get('five_hour'),
        weekly: get('seven_day'),
        fable: get('fable'),
        fileTs: data?.ts ?? null,
    };
}

// ---- Codex ----------------------------------------------------------------

function childNames(path, wantDirs) {
    const out = [];
    try {
        const en = Gio.File.new_for_path(path).enumerate_children('standard::name,standard::type',
            Gio.FileQueryInfoFlags.NONE, null);
        let info;
        while ((info = en.next_file(null))) {
            const isDir = info.get_file_type() === Gio.FileType.DIRECTORY;
            if (isDir === wantDirs)
                out.push(info.get_name());
        }
        en.close(null);
    } catch {
        // nincs ilyen mappa
    }
    return out.sort().reverse();
}

// a legfrissebb napok .jsonl fájljai, módosítás szerint csökkenő sorrendben
function codexFiles() {
    const files = [];
    outer:
    for (const y of childNames(CODEX_SESSIONS, true)) {
        for (const m of childNames(GLib.build_filenamev([CODEX_SESSIONS, y]), true)) {
            for (const d of childNames(GLib.build_filenamev([CODEX_SESSIONS, y, m]), true)) {
                const dir = GLib.build_filenamev([CODEX_SESSIONS, y, m, d]);
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
        } catch {
            return null;
        }
    }).filter(Boolean);
    return withTime.sort((a, b) => b.mtime - a.mtime).slice(0, CODEX_FILES);
}

function readTail(path, size) {
    const stream = Gio.File.new_for_path(path).read(null);
    try {
        const start = Math.max(0, size - CODEX_TAIL);
        if (start > 0)
            stream.seek(start, GLib.SeekType.SET, null);
        const bytes = stream.read_bytes(size - start, null);
        let text = new TextDecoder().decode(bytes.toArray());
        if (start > 0)
            text = text.slice(text.indexOf('\n') + 1);   // az első, csonka sor eldobása
        return text;
    } finally {
        stream.close(null);
    }
}

// utolsó rate_limits-pillanatkép a fájl végéből
function lastRateLimits(text) {
    const lines = text.split('\n');
    for (let i = lines.length - 1; i >= 0; i--) {
        if (!lines[i].includes('"rate_limits"'))
            continue;
        try {
            const j = JSON.parse(lines[i]);
            const rl = j.payload?.rate_limits;
            if (rl && (rl.limit_id ?? 'codex') === 'codex' && (rl.primary || rl.secondary))
                return {rl, ts: Date.parse(j.timestamp) / 1000 || null};
        } catch {
            // csonka vagy idegen sor
        }
    }
    return null;
}

let codexCache = null;   // {key, result}: ugyanarra a fájlállapotra nem olvas újra

export function readCodex() {
    const files = codexFiles();
    if (!files.length)
        return {fiveHour: noData('nincs Codex-session'), weekly: noData('nincs Codex-session'), file: null};
    const key = files.map(f => `${f.path}:${f.mtime}:${f.size}`).join('|');
    let snap = null, file = null;
    if (codexCache?.key === key) {
        ({snap, file} = codexCache);
    } else {
        for (const f of files) {
            try {
                snap = lastRateLimits(readTail(f.path, f.size));
            } catch {
                snap = null;
            }
            if (snap) {
                file = f.path;
                break;
            }
        }
        codexCache = {key, snap, file};
    }
    if (!snap)
        return {fiveHour: noData('nincs rate_limits a Codex-sessionökben'), weekly: noData('nincs adat'), file: null};
    // a primary/secondary sorrendet nem feltételezi: az ablak hossza dönt (300 perc / 10080 perc)
    const wins = [snap.rl.primary, snap.rl.secondary].filter(Boolean);
    const pick = test => {
        const w = wins.find(x => test(x.window_minutes));
        return w ? window_(w.used_percent, w.resets_at, snap.ts, {windowMinutes: w.window_minutes})
            : noData('ez az ablak hiányzik az adatból');
    };
    return {
        fiveHour: pick(m => m <= 24 * 60),
        weekly: pick(m => m > 24 * 60),
        plan: snap.rl.plan_type ?? null,
        file,
        ts: snap.ts,
    };
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
    const s = readJson(HEAT_FILE);
    const empty = why => ({why, cpu: {temp: null, why}, gpu: {temp: null, why}});
    if (!s || typeof s.ts !== 'number')
        return empty('nincs állapotfájl');
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
