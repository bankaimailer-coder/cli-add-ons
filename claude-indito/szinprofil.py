#!/usr/bin/env python3
"""Repónkénti Ptyxis-színprofilok a Claude indítóhoz.

A mappak.txt minden repója saját Ptyxis-profilt kap saját palettával (sötét háttér,
a háttérhez igazított, jól olvasható szöveg). A szín a sor harmadik oszlopából jön
(`Név | mappa | #rrggbb`); ha nincs megadva, a névből számolt tartalék szín.

  python3 szinprofil.py lista            név -> szín (forrással)
  python3 szinprofil.py telepit          profilok és paletták létrehozása/frissítése
  python3 szinprofil.py eltavolit        a saját profilok és paletták törlése
  python3 szinprofil.py uuid NÉV         a repó profiljának UUID-ja (az indítónak)
  python3 szinprofil.py szin [MAPPA]     háttér és szöveg színe a mappához (a burkolónak)
  python3 szinprofil.py elonezet FÁJL    HTML-előnézet a színmintákkal

Csak a saját profiljait kezeli: ezek UUID-jai az állapotfájlban vannak
(~/.local/share/claude-indito/profilok.tsv). Más profilhoz nem nyúl.
"""
import hashlib
import html
import math
import os
import re
import subprocess
import sys
import uuid as uuidlib

HERE = os.path.dirname(os.path.realpath(__file__))
HOME = os.path.expanduser('~')
LIST = os.environ.get('CLAUDE_INDITO_LIST', os.path.join(HERE, 'mappak.txt'))
DATA = os.environ.get('XDG_DATA_HOME', os.path.join(HOME, '.local', 'share'))
STATE = os.environ.get('CLAUDE_INDITO_STATE', os.path.join(DATA, 'claude-indito', 'profilok.tsv'))
PALETTES = os.path.join(DATA, 'org.gnome.Ptyxis', 'palettes')
PALETTE_PREFIX = 'claude-indito-'
SCHEMA = 'org.gnome.Ptyxis'
PROFILE_SCHEMA = 'org.gnome.Ptyxis.Profile'
PROFILE_PATH = '/org/gnome/Ptyxis/Profiles/%s/'


# ---------------------------------------------------------------- színek

def hex_to_rgb(hx):
    return tuple(int(hx[i:i + 2], 16) / 255 for i in (1, 3, 5))


def rgb_to_hex(rgb):
    return '#' + ''.join('%02x' % round(min(1, max(0, c)) * 255) for c in rgb)


def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _gamma(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def luminance(hx):
    r, g, b = (_lin(c) for c in hex_to_rgb(hx))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def oklch_to_hex(L, C, h):
    """OKLCH -> sRGB; ha kilóg a színtérből, a telítettséget csökkenti."""
    while True:
        a, b = C * math.cos(math.radians(h)), C * math.sin(math.radians(h))
        l_ = L + 0.3963377774 * a + 0.2158037573 * b
        m_ = L - 0.1055613458 * a - 0.0638541728 * b
        s_ = L - 0.0894841775 * a - 1.2914855480 * b
        l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
        rgb = (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
               -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
               -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        if all(-1e-4 <= c <= 1 + 1e-4 for c in rgb) or C <= 0:
            return rgb_to_hex(_gamma(max(0, c)) for c in rgb)
        C -= 0.005


def fallback_color(name):
    """Névből számolt tartalék szín: hash -> színárnyalat, sötét, közepesen telített."""
    d = hashlib.sha1(name.casefold().encode()).digest()
    hue = int.from_bytes(d[:2], 'big') * 360 / 65536
    L = 0.30 + d[2] / 255 * 0.08          # 0.30..0.38 világosság
    return oklch_to_hex(L, 0.10, hue)


def mix(a, b, t):
    ra, rb = hex_to_rgb(a), hex_to_rgb(b)
    return rgb_to_hex(x + (y - x) * t for x, y in zip(ra, rb))


# ANSI-színek: sötét háttérhez világos, világos háttérhez sötét készlet
ANSI_DARK_BG = ['#000000', '#ff6b6b', '#8ae234', '#fce94f', '#82aaff', '#d68fd6', '#5ee0e0', '#d5d5d5',
                '#8a8a8a', '#ff8f8f', '#b5f07a', '#fff3a0', '#a9c4ff', '#ebb0eb', '#9af0f0', '#ffffff']
ANSI_LIGHT_BG = ['#ffffff', '#c01c28', '#26a269', '#a2734c', '#12488b', '#a347ba', '#2aa1b3', '#1b1b1b',
                 '#5e5c64', '#e01b24', '#2ec27e', '#c88800', '#1a5fb4', '#c061cb', '#33c7de', '#000000']


def palette_colors(bg):
    """Háttérhez illő előtér, kurzor és ANSI-színek. Az előtér kontraszt alapján
    világos vagy sötét, enyhén a háttér felé színezve."""
    light_fg, dark_fg = '#f2f2f2', '#141414'
    dark_bg = contrast(bg, light_fg) >= contrast(bg, dark_fg)
    base = '#ffffff' if dark_bg else '#000000'
    fg = mix(light_fg if dark_bg else dark_fg, bg, 0.04)
    if contrast(bg, fg) < 7:              # gyenge kontrasztnál tiszta fehér/fekete
        fg = base
    ansi = list(ANSI_DARK_BG if dark_bg else ANSI_LIGHT_BG)
    ansi[0] = mix(bg, '#000000', 0.45) if dark_bg else mix(bg, '#ffffff', 0.45)
    return fg, ansi


# ---------------------------------------------------------------- mappak.txt

def read_rows(path=LIST):
    """(név, mappa, szín vagy None) sorok, a fájl sorrendjében."""
    rows = []
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            parts = [p.strip() for p in line.split('|')]
            if len(parts) == 1:
                name, folder, color = '', parts[0], None
            else:
                name, folder = parts[0], parts[1]
                color = parts[2] if len(parts) > 2 and parts[2] else None
            folder = re.sub(r'^~', HOME, folder)
            if not name:
                name = folder[len(HOME) + 1:] if folder.startswith(HOME + '/') else folder
            if color is not None:
                if not re.fullmatch(r'#[0-9a-fA-F]{6}', color):
                    print('FIGYELEM: hibás szín (%s), tartalék lesz: %s' % (color, name), file=sys.stderr)
                    color = None
                else:
                    color = color.lower()
            rows.append((name, folder, color))
    return rows


def repos(rows, existing_only):
    """Egyedi repók név szerint (kis- és nagybetű nem számít), az első megadott színnel."""
    out = {}
    for name, folder, color in rows:
        if existing_only and not os.path.isdir(folder):
            continue
        key = name.casefold()
        if key not in out:
            out[key] = {'name': name, 'color': color}
        elif out[key]['color'] is None and color:
            out[key]['color'] = color
    for r in out.values():
        r['source'] = 'megadott' if r['color'] else 'tartalék'
        r['color'] = r['color'] or fallback_color(r['name'])
    return out


def slug(name):
    s = re.sub(r'[^a-z0-9]+', '-', name.casefold().encode('ascii', 'ignore').decode()).strip('-')
    return '%s-%s' % (s or 'repo', hashlib.sha1(name.casefold().encode()).hexdigest()[:6])


# ---------------------------------------------------------------- gsettings

def gs(*args):
    return subprocess.run(['gsettings', *args], check=True, capture_output=True, text=True).stdout.strip()


def gv_str(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'") + "'"


def profile_uuids():
    return re.findall(r"'([0-9a-f]{32})'", gs('get', SCHEMA, 'profile-uuids'))


def set_profile_uuids(uuids):
    gs('set', SCHEMA, 'profile-uuids', '[' + ', '.join(gv_str(u) for u in uuids) + ']')


def read_state():
    state = {}
    if os.path.exists(STATE):
        with open(STATE, encoding='utf-8') as f:
            for line in f:
                p = line.rstrip('\n').split('\t')
                if len(p) >= 4 and re.fullmatch(r'[0-9a-f]{32}', p[0]):
                    state[p[1].casefold()] = {'uuid': p[0], 'name': p[1], 'palette': p[2], 'color': p[3]}
    return state


def write_state(state):
    if not state:
        if os.path.exists(STATE):
            os.remove(STATE)
        return
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write('# A Claude indító saját Ptyxis-profiljai (uuid, név, paletta, szín). Kézzel ne szerkeszd.\n')
        for e in sorted(state.values(), key=lambda e: e['name'].casefold()):
            f.write('%s\t%s\t%s\t%s\n' % (e['uuid'], e['name'], e['palette'], e['color']))
    os.replace(tmp, STATE)


def write_palette(pid, name, bg):
    fg, ansi = palette_colors(bg)
    os.makedirs(PALETTES, exist_ok=True)
    lines = ['[Palette]', 'Name=Claude: %s' % name, 'Background=%s' % bg, 'Foreground=%s' % fg,
             'Cursor=%s' % fg]
    lines += ['Color%d=%s' % (i, c) for i, c in enumerate(ansi)]
    path = os.path.join(PALETTES, pid + '.palette')
    content = '\n'.join(lines) + '\n'
    old = open(path, encoding='utf-8').read() if os.path.exists(path) else None
    if old != content:
        with open(path + '.tmp', 'w', encoding='utf-8') as f:
            f.write(content)
        os.replace(path + '.tmp', path)


def remove_profile(entry, uuids):
    """Egy saját profil törlése: kivétel a listából, beállításai és palettája törlése."""
    u = entry['uuid']
    if u in uuids:
        uuids.remove(u)
    subprocess.run(['dconf', 'reset', '-f', PROFILE_PATH % u], check=False)
    path = os.path.join(PALETTES, entry['palette'] + '.palette')
    if entry['palette'].startswith(PALETTE_PREFIX) and os.path.exists(path):
        os.remove(path)


# ---------------------------------------------------------------- parancsok

def cmd_lista():
    for r in repos(read_rows(), existing_only=False).values():
        here = '' if any(os.path.isdir(f) for n, f, c in read_rows() if n.casefold() == r['name'].casefold()) else '  (nincs ezen a gépen)'
        print('%-24s %s  %s%s' % (r['name'], r['color'], r['source'], here))


def cmd_telepit():
    wanted = repos(read_rows(), existing_only=True)
    state = read_state()
    uuids = profile_uuids()
    default = gs('get', SCHEMA, 'default-profile-uuid').strip("'")
    labels = {}
    for u in uuids:
        if not any(e['uuid'] == u for e in state.values()):
            labels[gs('get', '%s:%s' % (PROFILE_SCHEMA, PROFILE_PATH % u), 'label').strip("'").casefold()] = u

    # a mappak.txt-ből kikerült repók saját profiljainak törlése
    for key in [k for k in state if k not in wanted]:
        if state[key]['uuid'] == default:
            print('  kihagyva: %s (ez az alapértelmezett profil)' % state[key]['name'])
            continue
        remove_profile(state[key], uuids)
        print('  törölve: %s' % state.pop(key)['name'])

    for key, r in wanted.items():
        e = state.get(key) or {'uuid': uuidlib.uuid4().hex, 'palette': PALETTE_PREFIX + slug(r['name'])}
        e.update(name=r['name'], color=r['color'])
        write_palette(e['palette'], r['name'], r['color'])
        path = '%s:%s' % (PROFILE_SCHEMA, PROFILE_PATH % e['uuid'])
        gs('set', path, 'label', gv_str(r['name']))
        gs('set', path, 'palette', gv_str(e['palette']))
        if e['uuid'] not in uuids:
            uuids.append(e['uuid'])
        state[key] = e
        note = '  (van már kézi profil ilyen címkével, azt nem bántom)' if key in labels else ''
        print('  kész: %-24s %s%s' % (r['name'], r['color'], note))
        write_state(state)          # menet közben is, hogy hiba esetén se vesszen el UUID

    set_profile_uuids(uuids)
    write_state(state)
    print('  %d profil, állapot: %s' % (len(state), STATE))


def cmd_eltavolit():
    state = read_state()
    uuids = profile_uuids()
    default = gs('get', SCHEMA, 'default-profile-uuid').strip("'")
    for key in list(state):
        if state[key]['uuid'] == default:
            print('  kihagyva: %s (ez az alapértelmezett profil; előbb válassz másikat)' % state[key]['name'])
            continue
        remove_profile(state[key], uuids)
        print('  törölve: %s' % state.pop(key)['name'])
    set_profile_uuids(uuids)
    write_state(state)


def cmd_uuid(name):
    e = read_state().get(name.casefold())
    if e and e['uuid'] in profile_uuids():
        print(e['uuid'])
        return 0
    return 1


def cmd_szin(folder):
    """A mappához tartozó repó színe: a leghosszabb illeszkedő mappak.txt-sor, különben
    a mappa nevéből számolt tartalék. Kimenet: háttér előtér."""
    folder = os.path.realpath(folder)
    rows = read_rows()
    best = None
    for name, f, color in rows:
        if os.path.isdir(f):
            rf = os.path.realpath(f)
            if (folder == rf or folder.startswith(rf + '/')) and (best is None or len(rf) > len(best[0])):
                best = (rf, name)
    if best:
        bg = repos(rows, existing_only=False)[best[1].casefold()]['color']
    else:
        top = subprocess.run(['git', '-C', folder, 'rev-parse', '--show-toplevel'],
                             capture_output=True, text=True).stdout.strip()
        bg = fallback_color(os.path.basename(top or folder))
    print(bg, palette_colors(bg)[0])


def cmd_elonezet(out):
    rs = list(repos(read_rows(), existing_only=False).values())
    cells = []
    for r in rs:
        fg, ansi = palette_colors(r['color'])
        sample = ''.join('<span style="color:%s">■</span>' % c for c in ansi[1:7])
        cells.append('<div class="t" style="background:%s;color:%s"><b>%s</b><code>%s · %s</code>'
                     '<code>$ claude  %s</code><small>kontraszt %.1f:1</small></div>'
                     % (r['color'], fg, html.escape(r['name']), r['color'], r['source'], sample,
                        contrast(r['color'], fg)))
    page = ('<!doctype html><meta charset="utf-8"><title>Claude indító színek</title><style>'
            'body{background:#888;font:14px system-ui;margin:16px}'
            '.g{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:10px}'
            '.t{padding:12px;border-radius:8px;display:flex;flex-direction:column;gap:4px}'
            'code{font:12px monospace}small{opacity:.7}</style><div class="g">%s</div>' % ''.join(cells))
    with open(out, 'w', encoding='utf-8') as f:
        f.write(page)
    print('  kész: %s' % out)


def main(argv):
    cmds = {'lista': (cmd_lista, 0), 'telepit': (cmd_telepit, 0), 'eltavolit': (cmd_eltavolit, 0),
            'uuid': (cmd_uuid, 1), 'szin': (cmd_szin, 1), 'elonezet': (cmd_elonezet, 1)}
    if len(argv) < 2 or argv[1] not in cmds:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    fn, nargs = cmds[argv[1]]
    args = argv[2:2 + nargs]
    if argv[1] == 'szin' and not args:
        args = [os.getcwd()]
    if len(args) < nargs:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    return fn(*args) or 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
