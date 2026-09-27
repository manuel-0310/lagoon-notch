import sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset
from fontTools.ttLib.tables._c_m_a_p import CmapSubtable

ICONS = """add airplay bedtime nightlight smartphone pin_drop battery_alert bolt calendar_month check check_circle chevron_left chevron_right cloud
content_paste dark_mode event_available headphones home image inventory_2 keyboard laptop_mac light_mode link
location_off mouse music_note partly_cloudy_day pause photo_camera_front power_off push_pin radio_button_unchecked
rainy restart_alt search shuffle skip_next skip_previous snooze speaker text_fields timer videocam videocam_off
volume_up wb_sunny wifi_tethering play_arrow stop volume_off volume_down volume_mute partly_cloudy_night
foggy weather_snowy thunderstorm grain close settings delete content_copy description folder picture_as_pdf
movie audio_file folder_zip code bluetooth desktop_mac monitor tv speaker_group earbuds headset_mic sports_esports
watch tablet_mac cast flag schedule alarm event open_in_new my_location edit logout
notifications graphic_eq radio_button_checked palette drag_indicator repeat repeat_one flip zoom_in remove
battery_full battery_charging_full power sync lock keyboard_return more_horiz info warning public arrow_back
expand_more video_call call language brightness_low brightness_high hourglass_top timer_off av_timer add_circle
account_circle quick_reference_all keep brightness_medium""".split()

# uso: python3 tools/build_icon_font.py material-symbols-rounded.woff2 LagoonSymbols.ttf Sources/Lagoon/Design/IconFontData.swift
src = sys.argv[1]; out = sys.argv[2]
f = TTFont(src)
cmap = f.getBestCmap()
rev = {}
for cp, g in cmap.items():
    rev.setdefault(g, []).append(cp)
order = set(f.getGlyphOrder())
missing = [i for i in ICONS if i not in order]
if missing:
    print("MISSING:", missing)
chosen = {}
for name in ICONS:
    if name not in order: continue
    g = name + ".fill" if (name + ".fill") in order else name
    cps = sorted(c for c in rev.get(name, []) if 0xE000 <= c <= 0xF8FF or c >= 0xF0000)
    if not cps:
        print("no codepoint", name); continue
    chosen[name] = (cps[0], g)

inst = instancer.instantiateVariableFont(f, {"FILL": 1, "GRAD": 0, "opsz": 24, "wght": 500})
# Replace cmap with only chosen icons -> filled glyph
newmap = {cp: g for (cp, g) in chosen.values()}
for table in inst['cmap'].tables:
    if table.isUnicode():
        table.cmap = {cp: g for cp, g in newmap.items() if (table.format != 4 or cp <= 0xFFFF)}
if 'GSUB' in inst: del inst['GSUB']
opts = subset.Options()
opts.layout_features = []
opts.name_IDs = [1, 2, 3, 4, 6]
opts.notdef_outline = True
opts.hinting = False
opts.glyph_names = False
sub = subset.Subsetter(opts)
sub.populate(unicodes=list(newmap.keys()))
sub.subset(inst)
# rename family to avoid clashes
for rec in inst['name'].names:
    if rec.nameID in (1, 4): rec.string = "Lagoon Symbols"
    if rec.nameID == 6: rec.string = "LagoonSymbols"
    if rec.nameID == 3: rec.string = "LagoonSymbols-1.0"
    if rec.nameID == 2: rec.string = "Regular"
# square metrics: line box = em box
upm = inst['head'].unitsPerEm
print('upm', upm, 'bbox', inst['head'].yMin, inst['head'].yMax)
inst['hhea'].ascent = upm; inst['hhea'].descent = 0; inst['hhea'].lineGap = 0
os2 = inst['OS/2']
os2.sTypoAscender = upm; os2.sTypoDescender = 0; os2.sTypoLineGap = 0
os2.usWinAscent = upm; os2.usWinDescent = 0
inst.save(out)
import os
print('saved', out, os.path.getsize(out), 'icons', len(chosen))
# emit Swift source with the enum + embedded base64 font
import base64, textwrap
KEYWORDS = {"repeat", "public", "default", "import", "class", "struct", "func"}
cases = []
for name, (cp, g) in sorted(chosen.items()):
    ident = ''.join(p.capitalize() if i else p for i, p in enumerate(name.split('_')))
    if ident in KEYWORDS: ident = '`' + ident + '`'
    cases.append(f'    case {ident} = "\\u{{{cp:04X}}}"')
b64 = '\n'.join(textwrap.wrap(base64.b64encode(open(out, 'rb').read()).decode(), 120))
swift = ('// GENERADO por tools/build_icon_font.py — no editar a mano.\n'
         '// Subconjunto estático de "Material Symbols Rounded" (Apache 2.0, Google):\n'
         '// FILL 1 · wght 500 · GRAD 0 · opsz 24, igual que el prototipo.\n\n'
         '/// Íconos disponibles (punto de código PUA → glifo relleno).\n'
         'enum MS: String {\n' + '\n'.join(cases) + '\n}\n\n'
         'enum IconFontData {\n    static let base64: String = \"\"\"\n' + b64 + '\n\"\"\"\n}\n')
if len(sys.argv) > 3:
    open(sys.argv[3], 'w').write(swift)
