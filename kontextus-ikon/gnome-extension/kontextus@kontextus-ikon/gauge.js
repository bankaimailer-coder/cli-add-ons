// Körív-mérő (alul nyitott sebességmérő) rajza cairóval, shell nélkül is futtatható.

const TRACK = [0.87, 0.87, 0.85, 0.35];

// cr: cairo Context, size: oldalhossz pixelben, frac: 0-1, rgb: [0-1, 0-1, 0-1]
export function drawGauge(cr, size, frac, rgb) {
    frac = Math.max(0, Math.min(1, frac));
    const rOut = size / 2 - 0.5;
    const width = rOut * 0.42;
    const r = rOut - width / 2;
    const c = size / 2;
    const start = 0.75 * Math.PI;           // bal alsó sarok
    const sweep = 1.5 * Math.PI;            // 270°, alul nyitott
    cr.setLineWidth(width);
    cr.arc(c, c, r, start, start + sweep);
    cr.setSourceRGBA(...TRACK);
    cr.stroke();
    if (frac > 0) {
        cr.arc(c, c, r, start, start + sweep * frac);
        cr.setSourceRGB(...rgb);
        cr.stroke();
    }
}
