#!/usr/bin/env python3
"""Builds index.html from studio.template.html and the themes in themes/, so the
studio's presets are exactly the theme.json files the app would load."""
import json, pathlib
here = pathlib.Path(__file__).parent
presets = {p.stem: json.loads(p.read_text()) for p in sorted((here / "themes").glob("*.json"))}
page = (here / "studio.template.html").read_text().replace("__PRESETS__", json.dumps(presets, indent=1))
(here / "index.html").write_text(page)
print(f"index.html: {', '.join(presets)}")
