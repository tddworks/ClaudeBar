#!/usr/bin/env python3
"""Prepare transparent menu-bar masks from the existing provider artwork.

Developer-only dependency: Pillow. Runtime rendering has no image-processing
heuristics or dependency. Re-run after replacing the source logos and inspect
both appearances. Foreground selection is deliberately curated per asset:
colored tiles and photographs cannot safely be converted using alpha alone.
SVG marks are reused with their tile removed and their fills normalized.
"""
import json
import re
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'Sources/App/Resources/Assets.xcassets'
# Foreground, not the opaque tile. Cropping removes decorative tile borders.
MASKS = {
    'ClaudeIcon': ('dark', 100, .12),
    'CodexIcon': ('light', 230, .08),
    'CommandCodeIcon': ('light', 230, .12),
    'BedrockIcon': ('light', 230, .18),
    'GrokIcon': ('light', 230, .12),
    'MiniMaxIcon': ('light', 230, .10),
    'VercelIcon': ('light', 230, .10),
    'ZaiIcon': ('light', 230, .16),
    'OmpIcon': ('dark', 100, .12),
    'MistralIcon': ('light', 245, .10),
    'KimiIcon': ('light', 230, .12),
    'GeminiIcon': ('blue', 35, .08),
}

def save_catalog(name, files):
    dest = ASSETS / (name + 'MenuBar.imageset')
    dest.mkdir(exist_ok=True)
    (dest / 'Contents.json').write_text(json.dumps({
        'images': files, 'info': {'author': 'xcode', 'version': 1},
        'properties': {'template-rendering-intent': 'template',
            **({'preserves-vector-representation': True} if any(f['filename'].endswith('.svg') for f in files) else {})},
    }, indent=2) + '\n')
    return dest

for name, (kind, threshold, crop) in MASKS.items():
    source_dir = ASSETS / (name + '.imageset')
    sources = sorted(source_dir.glob('*.png'), key=lambda p: Image.open(p).width, reverse=True)
    # Light artwork has dark foreground for these existing appearance variants.
    source = next((p for p in sources if 'dark' in p.name), sources[0])
    image = Image.open(source).convert('RGBA')
    alpha = Image.new('L', image.size)
    values = []
    for r, g, b, a in image.getdata():
        value = (min(r, g, b) - threshold if kind == 'light' else
                 threshold - max(r, g, b) if kind == 'dark' else
                 b - r - threshold)
        values.append(round(a * max(0, min(1, value / 10))))
    alpha.putdata(values)
    margin = int(image.width * crop)
    box = (margin, margin, image.width-margin, image.height-margin)
    cropped = Image.new('L', image.size)
    cropped.paste(alpha.crop(box), box)
    bbox = cropped.getbbox()
    if not bbox:
        raise ValueError(f'Empty mask: {name}')
    mark = cropped.crop(bbox)
    files = []
    dest = save_catalog(name, files)
    for scale in (1, 2, 3):
        size = 64 * scale
        fitted = mark.copy()
        fitted.thumbnail((size * 7 // 8, size * 7 // 8), Image.Resampling.LANCZOS)
        mask = Image.new('L', (size, size))
        mask.paste(fitted, ((size-fitted.width)//2, (size-fitted.height)//2))
        result = Image.new('RGBA', (size,size), 'white')
        result.putalpha(mask)
        filename = f'mark_{size}.png'
        result.save(dest / filename)
        files.append({'filename': filename, 'idiom': 'universal', 'scale': f'{scale}x'})
    save_catalog(name, files)

for name in ('CursorIcon', 'AmpCodeIcon'):
    source = ASSETS / (name + '.imageset') / (name + '.svg')
    svg = source.read_text()
    svg = re.sub(r'<rect[^>]*?/>', '', svg)
    svg = re.sub(r'(fill|stroke)="#[0-9A-Fa-f]+"', r'\1="#FFFFFF"', svg)
    dest = save_catalog(name, [{'filename':'mark.svg', 'idiom':'universal'}])
    (dest / 'mark.svg').write_text(svg)

# The gradient Antigravity artwork already supplies a clean outline as a clip.
from xml.etree import ElementTree as ET
root = ET.fromstring((ROOT / 'Sources/App/Resources/Antigravity.svg').read_text())
ns = {'s': 'http://www.w3.org/2000/svg'}
path = root.find('.//s:clipPath/s:path', ns).attrib['d']
svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-20 -20 474 440"><path fill="white" d="{path}"/></svg>\n'
dest = save_catalog('AntigravityIcon', [{'filename':'mark.svg', 'idiom':'universal'}])
(dest / 'mark.svg').write_text(svg)

# The two-tone OpenCode window needs an outline, rather than a solid block.
dest = save_catalog('OpenCodeIcon', [{'filename':'mark.svg', 'idiom':'universal'}])
(dest / 'mark.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path fill="white" fill-rule="evenodd" d="M3 1h10v14H3V1zm1.5 1.5v3H11.5v-3h-7z"/></svg>\n')

# Copilot's raster illustration is replaced by GitHub's own small-size mark.
# Its upstream source and MIT license are kept alongside the source artwork.
dest = save_catalog('CopilotIcon', [{'filename':'mark.svg', 'idiom':'universal'}])
(dest / 'mark.svg').write_text((ROOT / 'Sources/App/Resources/MenuBarIconSources/copilot-16.svg').read_text())
