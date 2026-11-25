#!/usr/bin/env python3
"""Builds the Android home-widget icons from the app's own icon font.

Each icon in WIDGET_ICONS is read from fonts/WaffrIcons.ttf (made by
tool/build_icons.py), so the widgets draw exactly the line icons the app
draws, the Waffr wallet included. Output: vector drawables in
android/app/src/main/res/drawable, tinted with @color/widget_accent.

Usage (needs `pip install fonttools`):
  python3 tool/build_widget_icons.py
"""
import re
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent

# Drawable name -> AppIcons name.
WIDGET_ICONS = {
    "ic_widget_wallet": "savings",
    "ic_widget_expense": "arrowUpRight",
    "ic_widget_income": "arrowDownLeft",
    "ic_widget_event": "calendarRepeat",
    "ic_widget_flame": "flame",
    "ic_widget_target": "target",
    "ic_widget_chart": "chartPie",
    "ic_widget_receipt": "receipt",
    "ic_widget_plus": "add",
}


def main() -> None:
    source = (ROOT / "lib" / "core" / "theme" / "app_icons.dart").read_text()
    codes = {
        name: int(code, 16)
        for name, code in re.findall(
            r"static const IconData (\w+) = IconData\(\s*0x([0-9a-f]+)", source
        )
    }
    font = TTFont(ROOT / "fonts" / "WaffrIcons.ttf")
    cmap = font.getBestCmap()
    glyphs = font.getGlyphSet()
    upem = font["head"].unitsPerEm
    out_dir = ROOT / "android" / "app" / "src" / "main" / "res" / "drawable"
    for drawable, icon in WIDGET_ICONS.items():
        pen = SVGPathPen(glyphs)
        # Font units (y up, em tall) to a 24 x 24 viewport (y down).
        glyphs[cmap[codes[icon]]].draw(
            TransformPen(pen, (24 / upem, 0, 0, -24 / upem, 0, 24))
        )
        path = re.sub(r"(\d+\.\d{3})\d+", r"\1", pen.getCommands())
        (out_dir / f"{drawable}.xml").write_text(
            f"""<?xml version="1.0" encoding="utf-8"?>
<!-- AppIcons.{icon} from fonts/WaffrIcons.ttf (the app's own line icons),
     converted by tool/build_widget_icons.py. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="@color/widget_accent"
        android:pathData="{path}" />
</vector>
"""
        )
    print(f"{len(WIDGET_ICONS)} widget icons")


if __name__ == "__main__":
    main()
