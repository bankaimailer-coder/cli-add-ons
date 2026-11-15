// A keretmérők adatfeldolgozásának tesztjei (E1-E5, T01 feladatlap; a keretfigyelő-részek: T02 E1-E7),
// függőség nélkül:
//   gjs -m kontextus-ikon/tests/run.js
// A fixture-ök kézzel írt minta-sorok (tests/fixtures), nem valódi ~/.codex adat. A „most” rögzített.
// KONTEXTUS_EXT_DIR: a tesztelt bővítménymappa (alapból a repóbeli; a mutants.sh a hibás másolatra állítja).
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';

const HERE = GLib.path_get_dirname(GLib.filename_from_uri(import.meta.url)[0]);
const EXT = GLib.getenv('KONTEXTUS_EXT_DIR') ??
    GLib.build_filenamev([HERE, '..', 'gnome-extension', 'kontextus@kontextus-ikon']);
const L = await import(`file://${EXT}/limits.js`);
const M = await import(`file://${EXT}/meter.js`);
const FX = GLib.build_filenamev([HERE, 'fixtures']);
const codexDir = name => GLib.build_filenamev([FX, 'codex', name]);
const claudeFile = name => GLib.build_filenamev([FX, 'claude', name]);

// a fixture-ök időpontjai (UTC): utolsó Codex-futás 12:46, az 5 órás ablak 15:28-kor áll vissza
const T0 = Date.parse('2026-11-15T12:46:00Z') / 1000;
const RESET_5H = 1794756480;      // T0 + 2 ó 42 p
const RESET_WEEK = 1795005960;    // T0 + 3 nap

const logs = [];
L.setLogger(msg => logs.push(msg));

let failed = 0, passed = 0;
function test(name, fn) {
    try {
        fn();
        passed++;
        print(`ok   ${name}`);
    } catch (e) {
        failed++;
        print(`FAIL ${name}\n       ${e.message}`);
    }
}
function eq(actual, expected, what) {
    if (actual !== expected)
        throw new Error(`${what}: várt ${JSON.stringify(expected)}, kapott ${JSON.stringify(actual)}`);
}
function match(actual, re, what) {
    if (typeof actual !== 'string' || !re.test(actual))
        throw new Error(`${what}: várt ${re}, kapott ${JSON.stringify(actual)}`);
}

// ideiglenes Codex-mappa olvashatatlan fájllal vagy mappával (jogosultsági hiba előállítása)
function unreadableTree(what) {
    const root = GLib.dir_make_tmp('kontextus-teszt-XXXXXX');
    const day = GLib.build_filenamev([root, '2026', '11', '15']);
    GLib.mkdir_with_parents(day, 0o755);
    const file = GLib.build_filenamev([day, 'rollout-minta.jsonl']);
    GLib.file_set_contents(file, '{}\n');
    GLib.chmod(what === 'file' ? file : day, 0);
    return {root, cleanup: () => {
        GLib.chmod(day, 0o755);
        GLib.chmod(file, 0o644);
        Gio.File.new_for_path(file).delete(null);
        for (const d of [day, GLib.path_get_dirname(day), GLib.build_filenamev([root, '2026']), root])
            Gio.File.new_for_path(d).delete(null);
    }};
}

// ---- E1: friss adat --------------------------------------------------------
test('E1 Codex friss adat: a legutolsó codex-pillanatkép, nem régi', () => {
    const r = L.readCodex(codexDir('alap'), T0 + 600);
    eq(r.fiveHour.left, 80, '5 órás maradt');
    eq(r.weekly.left, 53, 'heti maradt');
    eq(r.fiveHour.stale, false, '5 órás stale');
    eq(r.weekly.stale, false, 'heti stale');
    eq(r.fiveHour.ts, T0, 'adat ideje');
    eq(r.plan, 'plus', 'plan');
});

test('E1 küszöb: pontosan STALE_AFTER korú adat még friss, egy mp-cel régebbi már régi', () => {
    eq(L.isStale(T0, T0 + L.STALE_AFTER), false, 'a küszöbön');
    eq(L.isStale(T0, T0 + L.STALE_AFTER + 1), true, 'a küszöb után');
    eq(L.STALE_AFTER, 3600, 'a küszöb 1 óra');
});

// ---- E2: régi adat, az ablak még nem állt vissza -----------------------------
test('E2 Codex régi adat: a szám marad, stale, az utolsó helyi futás ideje megvan', () => {
    const r = L.readCodex(codexDir('alap'), T0 + 2 * 3600);
    eq(r.fiveHour.left, 80, '5 órás maradt');
    eq(r.fiveHour.stale, true, '5 órás stale');
    eq(r.weekly.stale, true, 'heti stale');
    eq(r.fiveHour.ts, T0, 'utolsó futás ideje');
    eq(r.fiveHour.tsLabel, 'utolsó helyi Codex-futás', 'a menü címkéje');
});

test('E2 mérő: régi adatnál a kinézet eltér a frisstől (szürke szám, halvány kitöltés, „régi” jel)', () => {
    const rgb = M.CODEX_RGB;
    const fresh = M.limitStyle(80, false, '5h', rgb), stale = M.limitStyle(80, true, '5h', rgb);
    eq(fresh.text, '80', 'friss szám');
    eq(stale.text, '80', 'régi szám');
    eq(fresh.alpha, 1, 'friss kitöltés');
    eq(stale.alpha < 1, true, 'régi kitöltés halvány');
    eq(stale.tag, '5h', 'régi adatnál is a mérő jele (E7, T02)');
    eq(stale.mark, true, 'a régiség apró jele (E7, T02)');
    eq(fresh.tag, '5h', 'friss jel');
    eq(JSON.stringify(stale.textRgb) !== JSON.stringify(fresh.textRgb), true, 'a szám színe eltér');
    eq(M.limitStyle(null, false, '5h', rgb).text, '–', 'nincs adat');
});

test('E2 Claude: ugyanaz a küszöb hat; a megtartott ablak a saját írási idejével számít', () => {
    const fresh = L.readClaude(claudeFile('keretek.json'), T0 + 600);
    eq(fresh.fiveHour.left, 70, '5 órás maradt');
    eq(fresh.fiveHour.stale, false, '5 órás friss');
    eq(fresh.weekly.stale, true, 'a 2 órája írt heti ablak régi');
    eq(fresh.fiveHour.tsLabel, 'utolsó statusline-írás', 'címke');
    const old = L.readClaude(claudeFile('keretek.json'), T0 + 3600 + 1);
    eq(old.fiveHour.stale, true, 'egy óra után az 5 órás is régi');
    eq(old.fiveHour.left, 70, 'a szám marad');
});

// ---- E3: az ablak visszaállt ------------------------------------------------
test('E3 Codex visszaállt ablak: nincs szám, ok + visszaállás ideje + utolsó futás ideje', () => {
    const r = L.readCodex(codexDir('alap'), RESET_5H + 60);
    eq(r.fiveHour.left, null, '5 órás maradt');
    match(r.fiveHour.why, /visszaállt/, 'ok');
    eq(r.fiveHour.resetsAt, RESET_5H, 'visszaállás ideje');
    eq(r.fiveHour.ts, T0, 'utolsó futás ideje');
    eq(r.weekly.left, 53, 'a heti még él');
    eq(r.weekly.stale, true, 'de régi');
});

test('E3 Claude visszaállt ablak: nincs szám', () => {
    const r = L.readClaude(claudeFile('keretek.json'), RESET_5H);
    eq(r.fiveHour.left, null, '5 órás maradt');
    match(r.fiveHour.why, /visszaállt/, 'ok');
});

// ---- E4: nincs adat, konkrét okkal ------------------------------------------
test('E4 nincs Codex-mappa: nincs adat, konkrét ok', () => {
    const r = L.readCodex(codexDir('nincs-ilyen'), T0);
    eq(r.fiveHour.left, null, 'maradt');
    match(r.fiveHour.why, /nincs Codex-napló/, '5 órás ok');
    match(r.weekly.why, /nincs Codex-napló/, 'heti ok');
});

test('E4 csak nem-jsonl fájl a Codex-mappában: nincs Codex-napló', () => {
    const r = L.readCodex(codexDir('ures'), T0);
    match(r.fiveHour.why, /nincs Codex-napló/, 'ok');
});

test('E4 nincs rate_limits (null): nincs adat, „nincs rate_limits” ok', () => {
    const r = L.readCodex(codexDir('nincsrl'), T0);
    eq(r.fiveHour.left, null, 'maradt');
    match(r.fiveHour.why, /^nincs rate_limits/, '5 órás ok');
    match(r.weekly.why, /^nincs rate_limits/, 'heti ok');
});

test('E4 csonka sor, ép pillanatkép nélkül: nincs adat, „csonka” ok', () => {
    const r = L.readCodex(codexDir('csonka'), T0);
    eq(r.fiveHour.left, null, 'maradt');
    match(r.fiveHour.why, /csonka/, 'ok');
});

test('T02 N2 új munkamenet első, újsor nélküli csonka rate_limits-sora: „csonka” ok', () => {
    const r = L.readCodex(codexDir('csonka-ujsor-nelkul'), T0);
    eq(r.fiveHour.left, null, 'maradt');
    match(r.fiveHour.why, /^csonka rate_limits-sor/, 'ok');
});

test('E4 csonka utolsó sor előtt ép pillanatkép: az ép sort használja', () => {
    const r = L.readCodex(codexDir('csonkautan'), T0 + 600);
    eq(r.fiveHour.left, 80, '5 órás maradt');
    eq(r.weekly.left, 53, 'heti maradt');
});

test('E4 olvashatatlan Codex-napló: olvasási hiba az okban, a naplóba egyszer kerül', () => {
    const t = unreadableTree('file');
    try {
        logs.length = 0;
        const r1 = L.readCodex(t.root, T0);
        L.readCodex(t.root, T0);
        match(r1.fiveHour.why, /olvasása nem sikerült/, 'ok');
        eq(logs.length, 1, 'naplósorok');
    } finally {
        t.cleanup();
    }
});

test('E4 olvashatatlan napi mappa: listázási hiba az okban, a naplóba egyszer kerül', () => {
    const t = unreadableTree('dir');
    try {
        logs.length = 0;
        const r1 = L.readCodex(t.root, T0);
        L.readCodex(t.root, T0);
        match(r1.fiveHour.why, /listázása nem sikerült/, 'ok');
        eq(logs.length, 1, 'naplósorok');
    } finally {
        t.cleanup();
    }
});

test('E4 Claude: hiányzó keretek.json konkrét ok, naplózás nélkül', () => {
    logs.length = 0;
    const r = L.readClaude(claudeFile('nincs-ilyen.json'), T0);
    eq(r.fiveHour.left, null, 'maradt');
    match(r.fiveHour.why, /^nincs keretek\.json/, 'ok');
    eq(logs.length, 0, 'naplósorok');
});

test('E4 Claude: hibás keretek.json „hibás” ok, a naplóba egyszer kerül', () => {
    logs.length = 0;
    const r = L.readClaude(claudeFile('hibas.json'), T0);
    L.readClaude(claudeFile('hibas.json'), T0);
    match(r.weekly.why, /^hibás keretek\.json/, 'ok');
    eq(logs.length, 1, 'naplósorok');
});

// ---- E5: az egyik ablak hiányzik ---------------------------------------------
test('E5 csak az 5 órás ablak van meg: a heti „nincs adat”, az 5 órás működik', () => {
    const r = L.readCodex(codexDir('csak5h'), T0 + 600);
    eq(r.fiveHour.left, 80, '5 órás maradt');
    eq(r.weekly.left, null, 'heti maradt');
    match(r.weekly.why, /hiányzik/, 'heti ok');
});

test('E5 Claude: a hiányzó Fable-ablak „nincs adat”, a többi működik', () => {
    const r = L.readClaude(claudeFile('keretek.json'), T0 + 600);
    eq(r.fable.left, null, 'Fable maradt');
    match(r.fable.why, /nincs a statusline adatában/, 'ok');
    eq(r.weekly.left, 40, 'heti maradt');
});

// ---- T02: a keretfigyelő állapotfájlja és a források összefésülése -------------------
const figyelo = name => GLib.build_filenamev([FX, 'figyelo', name]);
const FIG_TS = 1794747410;   // a figyelo/*.json szívverése (T0 + 650)
const paths = (fig, claude = 'keretek.json', codex = 'alap') =>
    ({figyelo: figyelo(fig), claude: claudeFile(claude), codex: codexDir(codex)});

test('T02 E6 nem fut a figyelő (nincs állapotfájl): a T01-források változatlanul, ok a menünek', () => {
    const r = L.readLimits(T0 + 700, paths('nincs-ilyen.json'));
    eq(r.figyelo.running, false, 'fut');
    match(r.figyelo.why, /^nincs futó keretfigyelő/, 'ok');
    eq(r.claude.fiveHour.left, 70, 'Claude 5 órás a statusline-ból');
    eq(r.codex.fiveHour.left, 80, 'Codex 5 órás a helyi naplóból');
    eq(r.codex.fiveHour.tsLabel, 'utolsó helyi Codex-futás', 'forrás');
});

test('T02 E6 elavult szívverés: a figyelő nem fut; a küszöbön még fut', () => {
    eq(L.readFigyelo(figyelo('fut.json'), FIG_TS + L.FIGYELO_MAX_AGE).running, true, 'a küszöbön');
    const r = L.readFigyelo(figyelo('fut.json'), FIG_TS + L.FIGYELO_MAX_AGE + 1);
    eq(r.running, false, 'a küszöb után');
    match(r.why, /nem fut/, 'ok');
    eq(L.FIGYELO_MAX_AGE, 120, 'küszöb');
    eq(L.readFigyelo(figyelo('nincs-ts.json'), FIG_TS).running, false, 'ts nélkül');
});

test('T02 E1/E3 fut a figyelő: a frissebb fiók- és app-server-adat nyer', () => {
    const r = L.readLimits(T0 + 700, paths('fut.json'));
    eq(r.figyelo.running, true, 'fut');
    eq(r.claude.fiveHour.left, 65, 'Claude 5 órás a figyelőből');
    eq(r.claude.weekly.left, 38, 'Claude heti a figyelőből');
    eq(r.claude.fable.left, 79, 'Fable a figyelőből');
    eq(r.claude.fiveHour.tsLabel, 'utolsó fiók-lekérdezés (keretfigyelő)', 'Claude forrás');
    eq(r.codex.fiveHour.left, 75, 'Codex 5 órás az app-serverből');
    eq(r.codex.weekly.left, 50, 'Codex heti az app-serverből');
    eq(r.codex.fiveHour.stale, false, 'friss');
    eq(r.codex.plan, 'pro', 'plan a figyelőből');
});

test('T02 E5 a helyi Codex-futás frissebb a figyelő adatánál: a helyi napló nyer', () => {
    const r = L.readLimits(T0 + 700, paths('regi-codex.json'));
    eq(r.codex.fiveHour.left, 80, 'Codex 5 órás a helyi naplóból');
    eq(r.codex.fiveHour.ts, T0, 'a helyi futás ideje');
    eq(r.codex.weekly.left, 53, 'Codex heti a helyi naplóból');
});

test('T02 E2/E4 lejárt Claude- és hiányzó Codex-bejelentkezés: konkrét ok, a meglévő adat marad', () => {
    const r = L.readLimits(T0 + 700, paths('lejart.json', 'nincs-ilyen.json', 'nincs-ilyen'));
    match(r.claude.fiveHour.why, /lejárt \(401\)/, 'Claude 5 órás ok');
    eq(r.claude.weekly.left, 42, 'az utolsó jó heti adat');
    eq(r.claude.weekly.stale, true, 'régi');
    match(r.claude.weekly.note, /lejárt/, 'a menü megjegyzése');
    eq(r.codex.fiveHour.why, 'nincs Codex-bejelentkezés', 'Codex ok');
    eq(r.codex.weekly.why, 'nincs Codex-bejelentkezés', 'Codex heti ok');
});

test('T02 E2 lejárt figyelő-adat mellett a friss statusline nyer', () => {
    const r = L.readLimits(T0 + 700, paths('lejart.json'));
    eq(r.claude.fiveHour.left, 70, 'Claude 5 órás a statusline-ból');
    eq(r.claude.fiveHour.source, 'statusline', 'forrás');
});

test('T02 E7 régi adat: a jel megmarad, az apró jel csak régi adatnál van', () => {
    const rgb = M.CLAUDE_RGB;
    for (const tag of ['5h', 'H', 'F']) {
        eq(M.limitStyle(40, true, tag, rgb).tag, tag, `régi ${tag}`);
        eq(M.limitStyle(40, true, tag, rgb).mark, true, `régi ${tag} jele`);
        eq(M.limitStyle(40, false, tag, rgb).mark, false, `friss ${tag} jele`);
    }
    eq(M.limitStyle(null, true, 'H', rgb).mark, false, 'nincs adat: nincs régiség-jel');
});

// ---- T02 javítókör 1: inkrementális Codex-olvasás (R4), figyelt mappák és a figyelő menüsora (R6) ----
const SAMPLE = GLib.build_filenamev([FX, 'codex', 'alap', '2026', '11', '15', 'rollout-minta.jsonl']);
const tokenLine = (pct, ts) => `{"timestamp":"${ts}","type":"event_msg","payload":{"type":"token_count",` +
    `"info":null,"rate_limits":{"limit_id":"codex","primary":{"used_percent":${pct},"window_minutes":300,` +
    `"resets_at":1794756480},"secondary":{"used_percent":47.0,"window_minutes":10080,"resets_at":1795005960},` +
    `"plan_type":"plus"}}}\n`;
function append(path, text) {
    const s = Gio.File.new_for_path(path).append_to(Gio.FileCreateFlags.NONE, null);
    s.write_all(new TextEncoder().encode(text), null);
    s.close(null);
}
function tempCodex() {
    const root = GLib.dir_make_tmp('kontextus-inc-XXXXXX');
    const day = GLib.build_filenamev([root, '2026', '11', '15']);
    GLib.mkdir_with_parents(day, 0o755);
    const file = GLib.build_filenamev([day, 'rollout-minta.jsonl']);
    GLib.file_set_contents(file, GLib.file_get_contents(SAMPLE)[1]);
    return {root, file, cleanup: () => {
        Gio.File.new_for_path(file).delete(null);
        for (const d of [day, GLib.path_get_dirname(day), GLib.build_filenamev([root, '2026']), root])
            Gio.File.new_for_path(d).delete(null);
    }};
}

test('T02 R4 futó Codex: csak a hozzáírt részt olvassa, és az új pillanatkép azonnal látszik', () => {
    const t = tempCodex();
    try {
        eq(L.readCodex(t.root, T0 + 600).fiveHour.left, 80, 'kezdő érték');
        const line = tokenLine(35.0, '2026-11-15T12:50:00.000Z');
        const before = L.codexStats.bytesRead;
        append(t.file, line);
        const r = L.readCodex(t.root, T0 + 600);
        eq(L.codexStats.bytesRead - before, new TextEncoder().encode(line).length, 'olvasott bájtok');
        eq(r.fiveHour.left, 65, 'az új érték');
        eq(r.ts, Date.parse('2026-11-15T12:50:00Z') / 1000, 'az új adat ideje');
    } finally {
        t.cleanup();
    }
});

test('T02 R4 félig írt sor: kimarad, a befejezése után beolvassa', () => {
    const t = tempCodex();
    try {
        L.readCodex(t.root, T0 + 600);
        const line = tokenLine(10.0, '2026-11-15T12:55:00.000Z');
        append(t.file, line.slice(0, 60));
        eq(L.readCodex(t.root, T0 + 600).fiveHour.left, 80, 'a félig írt sor még nem számít');
        append(t.file, line.slice(60));
        eq(L.readCodex(t.root, T0 + 600).fiveHour.left, 90, 'a befejezett sor számít');
    } finally {
        t.cleanup();
    }
});

test('T02 R6 figyelt Codex-mappák: nap, hónap, év és a gyökér (az új nap első futása is látszik)', () => {
    eq(JSON.stringify(L.codexWatchDirs('/r', '/r/2026/11/15/x.jsonl')),
        JSON.stringify(['/r/2026/11/15', '/r/2026/11', '/r/2026', '/r']), 'mappák');
    eq(JSON.stringify(L.codexWatchDirs('/r', null)), JSON.stringify(['/r']), 'napló nélkül a gyökér');
});

test('T02 R6 E6 a figyelő menüsora: „NEM FUT” okkal, illetve fut az okokkal', () => {
    const fmt = ts => `@${ts}`;
    const off = L.figyeloStatus(L.readFigyelo(figyelo('nincs-ilyen.json'), FIG_TS), fmt);
    match(off, /^Keretfigyelő: NEM FUT \(nincs futó keretfigyelő/, 'nem fut');
    match(off, /csak a statusline és a helyi Codex-napló/, 'tartalék');
    const on = L.figyeloStatus(L.readFigyelo(figyelo('lejart.json'), FIG_TS), fmt);
    eq(on, `Keretfigyelő: fut (@${FIG_TS}) · Claude: a Claude-bejelentkezés lejárt (401) · Codex: nincs Codex-bejelentkezés`,
        'fut');
    match(L.figyeloStatus(L.readFigyelo(figyelo('fut.json'), FIG_TS), fmt), /Claude: rendben · Codex: rendben$/, 'rendben');
});

print(`\n${passed} ok, ${failed} hibás`);
if (failed)
    imports.system.exit(1);
