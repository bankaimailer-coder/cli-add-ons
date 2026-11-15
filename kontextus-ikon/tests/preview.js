// PNG-előnézet a keretmérőről friss, régi és visszaállt állapotban, 1x és 2x méretben:
//   gjs -m kontextus-ikon/tests/preview.js <kimeneti mappa>
// Soronként: friss (80% maradt), régi (80% maradt, stale), visszaállt (nincs adat); oszlop: Claude, Codex.
import GLib from 'gi://GLib';
import Cairo from 'cairo';

const HERE = GLib.path_get_dirname(GLib.filename_from_uri(import.meta.url)[0]);
const EXT = GLib.build_filenamev([HERE, '..', 'gnome-extension', 'kontextus@kontextus-ikon']);
const {drawLimit, CLAUDE_RGB, CODEX_RGB} = await import(`file://${EXT}/meter.js`);

const out = ARGV[0];
if (!out) {
    printerr('használat: gjs -m preview.js <kimeneti mappa>');
    imports.system.exit(2);
}
const STATES = [['friss', 80, false], ['regi', 80, true], ['visszaallt', null, false]];
const BRANDS = [['5h', CLAUDE_RGB, 'claude'], ['H', CODEX_RGB, 'openai']];
const W = 36, H = 20, GAP = 6;   // logikai pixel, mint az extension.js LIMIT_W × LIMIT_H

for (const scale of [1, 2]) {
    const cw = (W + GAP) * scale, ch = (H + GAP) * scale;
    const surf = new Cairo.ImageSurface(Cairo.Format.ARGB32, cw * BRANDS.length + GAP * scale,
        ch * STATES.length + GAP * scale);
    const cr = new Cairo.Context(surf);
    cr.setSourceRGB(0.12, 0.12, 0.12);   // sötét panel-háttér
    cr.paint();
    STATES.forEach(([, left, stale], r) => {
        BRANDS.forEach(([tag, rgb, brand], c) => {
            cr.save();
            cr.translate(GAP * scale + c * cw, GAP * scale + r * ch);
            drawLimit(cr, W * scale, H * scale, left, tag, rgb, brand, stale);
            cr.restore();
        });
    });
    const path = GLib.build_filenamev([out, `keretmero-allapotok-${scale}x.png`]);
    surf.writeToPNG(path);
    cr.$dispose();
    print(path);
}
