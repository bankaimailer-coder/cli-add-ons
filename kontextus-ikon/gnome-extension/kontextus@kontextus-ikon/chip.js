// Chip alakú memória-ikon rajza (cairo + Pango), shell nélkül is futtatható.
// A test alulról áttetsző fehérrel telik, a százalék mindig tömör fehér, így végig olvasható.
import Pango from 'gi://Pango';
import PangoCairo from 'gi://PangoCairo';

const FONT = 'Ubuntu Sans Condensed Bold';
const WHITE = [1, 1, 1];
const FILL = [1, 1, 1, 0.45];

// cr: cairo Context, w × h: rajzterület pixelben, pct: 0-100 (null = nincs adat)
export function drawChip(cr, w, h, pct) {
    const frac = pct === null ? 0 : Math.max(0, Math.min(1, pct / 100));
    const lw = Math.max(1, Math.round(h / 16));          // vonalvastagság
    const pin = Math.max(2, Math.round(w * 0.1));         // lábak hossza
    const bx = pin, by = 0, bw = w - 2 * pin, bh = h;     // chiptest

    // lábak: oldalanként három
    cr.setSourceRGB(...WHITE);
    for (let i = 1; i <= 3; i++) {
        const y = Math.round(bh * i / 4 - lw / 2);
        cr.rectangle(0, y, pin, lw);
        cr.rectangle(w - pin, y, pin, lw);
    }
    cr.fill();

    // kitöltés alulról, keret
    const fillTop = by + bh * (1 - frac);
    cr.rectangle(bx, fillTop, bw, by + bh - fillTop);
    cr.setSourceRGBA(...FILL);
    cr.fill();
    cr.rectangle(bx + lw / 2, by + lw / 2, bw - lw, bh - lw);
    cr.setLineWidth(lw);
    cr.setSourceRGB(...WHITE);
    cr.stroke();

    // százalék
    const text = pct === null ? '–' : String(Math.round(pct));
    const layout = PangoCairo.create_layout(cr);
    const desc = Pango.FontDescription.from_string(FONT);
    const maxW = bw - 2 * lw - 1, maxH = bh - 2 * lw;
    let size = h * 0.85;
    let ink;
    for (;;) {
        desc.set_absolute_size(size * Pango.SCALE);
        layout.set_font_description(desc);
        layout.set_text(text, -1);
        [ink] = layout.get_pixel_extents();
        if ((ink.width <= maxW && ink.height <= maxH) || size < 5)
            break;
        size -= 0.5;
    }
    const tx = bx + (bw - ink.width) / 2 - ink.x;
    const ty = by + (bh - ink.height) / 2 - ink.y;
    // útvonalként kitöltve: szürkeárnyalatos élsimítás, színes szél nélkül
    cr.moveTo(tx, ty);
    PangoCairo.layout_path(cr, layout);
    cr.setSourceRGB(...WHITE);
    cr.fill();
}
