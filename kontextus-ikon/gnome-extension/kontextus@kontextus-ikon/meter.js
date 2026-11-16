// Keretmérő és hőmérő rajza (cairo + Pango), shell nélkül is futtatható.
// Keretmérő: bal oldalt a márka ikonja (Claude-csillag / OpenAI-csomó), amely alulról a megmaradt
// keret arányáig teli; mellette fent apró jel (5h / H / F), alatta a megmaradt százalék.
// Nincs adat: szürke ikon és „–”.
// Hőmérők (CPU és GPU külön): chip-foglalatba rajzolt fordulatszámmérő lánggal, mellette a fok.
import Pango from 'gi://Pango';
import PangoCairo from 'gi://PangoCairo';

const FONT = 'Ubuntu Sans Condensed Bold';
const WHITE = [1, 1, 1];
const GRAY = [0.6, 0.6, 0.59];

export const CLAUDE_RGB = [0.91, 0.58, 0.44];    // Claude-narancs
export const CODEX_RGB = [0.94, 0.94, 0.92];     // Codex: törtfehér (a narancstól, lilától, ciántól is elüt)
const WARN_RGB = [0.96, 0.83, 0.18];             // 25% maradék alatt
const FULL_RGB = [0.88, 0.11, 0.14];             // 10% maradék alatt
export const CPU_RGB = [0xc0 / 255, 0x84 / 255, 0xfc / 255];   // #c084fc világoslila
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

// Claude-logó egyszerűsítve: középről kiinduló, végükön lekerekített sugarak, kissé eltérő hosszal;
// s × s pixelben, a már beállított forrásszínnel
const CLAUDE_RAYS = [1, 0.8, 0.95, 0.76, 1, 0.84, 0.92, 0.78, 0.98, 0.82, 0.9];
function claudePath(cr, s) {
    const c = s / 2, lw = Math.max(1.3, s * 0.13);
    cr.setLineCap(1);                          // ROUND
    cr.setLineWidth(lw);
    CLAUDE_RAYS.forEach((len, i) => {
        const a = -Math.PI / 2 + i * 2 * Math.PI / CLAUDE_RAYS.length;
        const r = (s / 2 - lw / 2) * len;
        cr.moveTo(c + Math.cos(a) * s * 0.04, c + Math.sin(a) * s * 0.04);
        cr.lineTo(c + Math.cos(a) * r, c + Math.sin(a) * r);
    });
    cr.stroke();
    cr.setLineCap(0);
}

// OpenAI-csomó egyszerűsítve: hat lekerekített szem, 60°-onként elforgatva, középen hatszögű
// nyílással; körvonalként rajzolva
function openaiPath(cr, s) {
    const c = s / 2, lw = Math.max(1.1, s * 0.06);
    const R = s / 2 - lw / 2;
    const L = R * 0.9, W = R * 0.36;           // egy szem hossza és szélessége (középvonalon)
    cr.setLineWidth(lw);
    for (let k = 0; k < 6; k++) {
        cr.save();
        cr.translate(c, c);
        cr.rotate(k * Math.PI / 3);
        // a szem kifelé tolva és megdöntve, így a szomszédok átfedik egymást
        cr.translate(R * 0.25, -R * 0.35);
        cr.rotate(0.52);
        roundRect(cr, -L / 2, -W / 2, L, W, W / 2 - 0.01);
        cr.restore();
    }
    cr.stroke();
}

const BRANDS = {claude: claudePath, openai: openaiPath};

// márkaikon, alulról a frac (0-1) arányáig teli; fölötte halvány tónus, hogy a forma mindig látsszon.
// frac === null: nincs adat, szürke forma. rgb: a halvány rész (márkaszín), fill: a teli rész színe
function drawBrand(cr, s, brand, frac, rgb, fill) {
    const path = BRANDS[brand];
    cr.save();
    if (frac === null)
        cr.setSourceRGBA(...GRAY, 0.8);
    else
        cr.setSourceRGBA(...rgb, 0.3);
    path(cr, s);
    cr.restore();
    if (!frac)
        return;
    cr.save();
    const top = s * (1 - frac);
    cr.rectangle(-1, top, s + 2, s - top + 1);
    cr.clip();
    cr.setSourceRGB(...fill);
    path(cr, s);
    cr.restore();
}

// Keretmérő. cr: cairo Context, w × h: rajzterület pixelben, left: a MEGMARADT keret 0-100 vagy null,
// tag: '5h' | 'H' | 'F', rgb: a márka színe, brand: 'claude' | 'openai'.
// 25% maradék alatt sárga, 10% alatt piros (az ikon kitöltése és a szám is).
export function drawLimit(cr, w, h, left, tag, rgb, brand) {
    const none = left === null || left === undefined;
    const warn = none ? null : left < 10 ? FULL_RGB : left < 25 ? WARN_RGB : null;
    drawBrand(cr, h, brand, none ? null : Math.max(0, Math.min(1, left / 100)), rgb, warn ?? rgb);

    // jel fent, szám lent
    const tx = h + Math.max(1, Math.round(h * 0.1));
    const tw = w - tx;
    const tagH = Math.round(h * 0.38);
    drawText(cr, tag, tx, 0, tw, tagH, none ? GRAY : rgb, tagH * 1.25);
    drawText(cr, none ? '–' : String(Math.round(left)), tx, tagH, tw, h - tagH,
        none ? GRAY : warn ?? WHITE, (h - tagH) * 1.3);
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
