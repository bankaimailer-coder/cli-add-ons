// Keretmérő és hőmérő rajza (cairo + Pango), shell nélkül is futtatható.
// Keretmérő: bal oldalt függőleges sáv, amely alulról telik; mellette fent apró színes jel
// (5h / H / F), alatta a százalék száma. Nincs adat: üres szürke keret és „–”.
// Hőmérők (CPU és GPU külön): chip-foglalatba rajzolt fordulatszámmérő lánggal, mellette a fok.
import Pango from 'gi://Pango';
import PangoCairo from 'gi://PangoCairo';

const FONT = 'Ubuntu Sans Condensed Bold';
const WHITE = [1, 1, 1];
const GRAY = [0.6, 0.6, 0.59];
const TRACK = [0.87, 0.87, 0.85, 0.3];

export const CLAUDE_RGB = [0.91, 0.58, 0.44];    // Claude-narancs
export const CODEX_RGB = [0.42, 0.71, 1.0];      // Codex-kék
const WARN_RGB = [0.96, 0.83, 0.18];             // 75% fölött
const FULL_RGB = [0.88, 0.11, 0.14];             // 90% fölött
export const CPU_RGB = [0x46 / 255, 0x82 / 255, 0xb4 / 255];   // #4682b4 steelblue
export const GPU_RGB = [0, 1, 1];                               // #00ffff cyan

// szöveg kitöltött útvonalként, a (x, y, w, h) dobozba illesztve; align: 0 bal, 0.5 közép
function drawText(cr, text, x, y, w, h, rgb, maxSize, align = 0.5) {
    const layout = PangoCairo.create_layout(cr);
    const desc = Pango.FontDescription.from_string(FONT);
    let size = maxSize, ink;
    for (;;) {
        desc.set_absolute_size(size * Pango.SCALE);
        layout.set_font_description(desc);
        layout.set_text(text, -1);
        [ink] = layout.get_pixel_extents();
        if ((ink.width <= w && ink.height <= h) || size < 4)
            break;
        size -= 0.5;
    }
    cr.moveTo(x + (w - ink.width) * align - ink.x, y + (h - ink.height) / 2 - ink.y);
    PangoCairo.layout_path(cr, layout);
    cr.setSourceRGB(...rgb);
    cr.fill();
}

// cr: cairo Context, w × h: rajzterület pixelben, pct: 0-100 vagy null, tag: '5h' | 'H' | 'F',
// rgb: a mérő (szolgáltató) színe
export function drawLimit(cr, w, h, pct, tag, rgb) {
    const none = pct === null || pct === undefined;
    const frac = none ? 0 : Math.max(0, Math.min(1, pct / 100));
    const bw = Math.max(4, Math.round(w * 0.22));
    const lw = Math.max(1, Math.round(h / 20));

    // sáv: pálya, kitöltés alulról; nincs adat: csak szürke keret
    if (none) {
        cr.rectangle(lw / 2, lw / 2, bw - lw, h - lw);
        cr.setLineWidth(lw);
        cr.setSourceRGB(...GRAY);
        cr.stroke();
    } else {
        cr.rectangle(0, 0, bw, h);
        cr.setSourceRGBA(...TRACK);
        cr.fill();
    }
    if (frac > 0) {
        const fill = pct >= 90 ? FULL_RGB : pct >= 75 ? WARN_RGB : rgb;
        const top = Math.round(h * (1 - frac));
        cr.rectangle(0, top, bw, h - top);
        cr.setSourceRGB(...fill);
        cr.fill();
    }

    // jel fent, szám lent
    const tx = bw + Math.max(1, Math.round(w * 0.06));
    const tw = w - tx;
    const tagH = Math.round(h * 0.38);
    drawText(cr, tag, tx, 0, tw, tagH, none ? GRAY : rgb, tagH * 1.25);
    drawText(cr, none ? '–' : String(Math.round(pct)), tx, tagH, tw, h - tagH, none ? GRAY : WHITE, (h - tagH) * 1.3);
}

function roundRect(cr, x, y, w, h, r) {
    cr.newSubPath();
    cr.arc(x + w - r, y + r, r, -Math.PI / 2, 0);
    cr.arc(x + w - r, y + h - r, r, 0, Math.PI / 2);
    cr.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI);
    cr.arc(x + r, y + r, r, Math.PI, 1.5 * Math.PI);
    cr.closePath();
}

// chip-foglalat (dupla keretes lekerekített négyzet, oldalanként 4 láb), benne fordulatszámmérő
// mutatóval és jobb oldalt láng; egyetlen színnel, s × s pixelben
function drawSocketIcon(cr, s, rgb) {
    cr.setSourceRGB(...rgb);
    const lw = Math.max(1, Math.round(s / 22));   // egész pixel: panelméretben is éles
    const p = Math.max(2, Math.round(s * 0.11));  // lábhossz
    const t = Math.max(1, Math.round(s * 0.06));  // lábvastagság
    const b = s - 2 * p;                       // chiptest oldala
    // lábak, oldalanként 4
    for (let i = 0; i < 4; i++) {
        const c = Math.round(p + b * (0.2 + i * 0.2) - t / 2);
        cr.rectangle(c, 0, t, p + lw);         // fent
        cr.rectangle(c, s - p - lw, t, p + lw); // lent
        cr.rectangle(0, c, p + lw, t);         // bal
        cr.rectangle(s - p - lw, c, p + lw, t); // jobb
    }
    cr.fill();
    // dupla keret
    cr.setLineWidth(lw);
    roundRect(cr, p + lw / 2, p + lw / 2, b - lw, b - lw, b * 0.2);
    cr.stroke();
    const gap = Math.max(1, Math.round(lw * 1.2));
    const i1 = lw + gap + lw / 2;              // a belső keret középvonala a testtől
    roundRect(cr, p + i1, p + i1, b - 2 * i1, b - 2 * i1, b * 0.13);
    cr.stroke();
    // tartalom: a belső kereten belül, kis ráhagyással
    const pad = i1 + lw / 2 + Math.max(0.5, lw * 0.6);
    const x0 = p + pad, y0 = p + pad, iw = b - 2 * pad;

    // mérő: felső félív, bal oldalon, vastag pályával
    const cx = x0 + iw * 0.42, cy = y0 + iw * 0.86;
    const r = iw * 0.36;
    cr.setLineWidth(iw * 0.16);
    cr.newPath();
    cr.arc(cx, cy, r, Math.PI, 1.82 * Math.PI);
    cr.stroke();
    // mutató a jobb felső negyed felé, tövén kis kör
    const a = 1.72 * Math.PI;
    cr.setLineWidth(Math.max(lw * 0.9, iw * 0.09));
    cr.setLineCap(1);                          // ROUND
    cr.moveTo(cx, cy);
    cr.lineTo(cx + Math.cos(a) * r * 0.85, cy + Math.sin(a) * r * 0.85);
    cr.stroke();
    cr.arc(cx, cy, iw * 0.09, 0, 2 * Math.PI);
    cr.fill();
    cr.setLineCap(0);

    // láng a mérő jobb oldalán: alul kerek, fent hegyes, egy kisebb oldalnyelvvel
    const fx = x0 + iw * 0.68, fw = iw * 0.34;
    const fy = y0 + iw * 0.04, fh = iw * 0.94;
    const X = u => fx + u * fw, Y = v => fy + v * fh;
    cr.moveTo(X(0.5), Y(1));
    cr.curveTo(X(0.05), Y(1), X(-0.05), Y(0.6), X(0.25), Y(0.35));   // bal oldal fel
    cr.curveTo(X(0.3), Y(0.55), X(0.4), Y(0.55), X(0.45), Y(0.5));   // kis bemetszés
    cr.curveTo(X(0.4), Y(0.3), X(0.55), Y(0.12), X(0.8), Y(0));      // fő nyelv csúcsa
    cr.curveTo(X(0.7), Y(0.25), X(1.05), Y(0.45), X(1), Y(0.7));     // jobb oldal le
    cr.curveTo(X(0.98), Y(0.9), X(0.8), Y(1), X(0.5), Y(1));
    cr.closePath();
    cr.fill();
}

const LEVEL_TEXT = {warm: WARN_RGB, hot: FULL_RGB, critical: FULL_RGB};

// Hőmérő: chip-foglalat ikon (a mérő saját színével) és mellette a fok; a szám színe a szint
// (rendben semleges, meleg sárga, forró/kritikus piros). temp: °C vagy null (nincs adat: szürke, „–”)
export function drawHeat(cr, w, h, temp, level, rgb) {
    const none = temp === null || temp === undefined;
    drawSocketIcon(cr, h, none ? GRAY : rgb);
    const tx = h + Math.max(1, Math.round(h * 0.08));
    const text = none ? '–' : `${Math.round(temp)}°`;
    drawText(cr, text, tx, 0, w - tx, h, none ? GRAY : LEVEL_TEXT[level] ?? WHITE, h * 0.75, 0);
}
