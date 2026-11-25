#!/usr/bin/env python3
"""Builds Waffr's icon font: a small subset of Lucide (ISC license).

The app ships only the glyphs listed in ICONS, at the 300 stroke weight, as
fonts/WaffrIcons.ttf, and reads them through lib/core/theme/app_icons.dart.

Usage (needs `pip install fonttools`):
  dart pub cache add lucide_icons_flutter -v 4.0.3
  python3 tool/build_icons.py ~/.pub-cache/hosted/pub.dev/lucide_icons_flutter-4.0.3

To add an icon: add a line to ICONS (app name, Lucide name, mirrored in RTL)
and run the script again. Both generated files are committed.

Icons Lucide does not have are drawn as stroked 24x24 SVGs in tool/icons/
(listed in CUSTOM_ICONS) and turned into glyphs here; that step also needs
`pip install picosvg` (for its stroke-to-outline conversion).
"""
import re
import sys
from pathlib import Path

from fontTools import subset
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.svgLib.path import parse_path
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent

# app name, Lucide name (camelCase), mirrored in right-to-left layouts.
ICONS = [
    # Navigation and chrome
    ("home", "house", False),
    ("reports", "chartNoAxesColumn", False),
    ("online", "globe", False),
    ("profile", "userRound", False),
    ("settings", "settings", False),
    ("bell", "bell", False),
    ("bellRing", "bellRing", False),
    ("bellOff", "bellOff", False),
    ("back", "arrowLeft", True),
    ("chevronBack", "chevronLeft", True),
    ("chevronForward", "chevronRight", True),
    ("chevronDown", "chevronDown", False),
    ("chevronUp", "chevronUp", False),
    ("close", "x", False),
    ("more", "ellipsis", False),
    ("moreVertical", "ellipsisVertical", False),
    ("dragHandle", "gripHorizontal", False),
    ("search", "search", False),
    ("searchOff", "searchX", False),
    ("tune", "slidersHorizontal", False),
    # Actions
    ("add", "plus", False),
    ("remove", "minus", False),
    ("removeCircle", "circleMinus", False),
    ("check", "check", False),
    ("checkAll", "checkCheck", False),
    ("checkCircle", "circleCheck", False),
    ("circle", "circle", False),
    ("edit", "pencil", False),
    ("editNote", "notebookPen", False),
    ("trash", "trash2", False),
    ("trashForever", "trash", False),
    ("undo", "undo2", True),
    ("share", "share2", False),
    ("backspace", "delete", False),
    ("refresh", "refreshCw", False),
    ("repeat", "repeat", False),
    ("swap", "arrowLeftRight", False),
    ("logOut", "logOut", True),
    ("pause", "circlePause", False),
    ("block", "ban", False),
    # State and feedback
    ("info", "info", False),
    ("help", "circleQuestionMark", True),
    ("warning", "triangleAlert", False),
    ("error", "circleAlert", False),
    ("eye", "eye", False),
    ("eyeOff", "eyeOff", False),
    ("star", "star", False),
    ("heart", "heart", False),
    ("sparkles", "sparkles", False),
    ("lightbulb", "lightbulb", False),
    ("tips", "wandSparkles", False),
    ("thumbsUp", "thumbsUp", False),
    ("celebration", "partyPopper", False),
    ("flame", "flame", False),
    ("trophy", "trophy", False),
    ("award", "award", False),
    ("medal", "medal", False),
    ("verified", "badgeCheck", False),
    ("hourglass", "hourglass", False),
    # Money
    ("wallet", "wallet", False),
    ("banknote", "banknote", False),
    ("creditCard", "creditCard", False),
    ("receipt", "receiptText", False),
    ("exchange", "circleDollarSign", False),
    ("withdraw", "arrowUpFromLine", False),
    ("deposit", "arrowDownToLine", False),
    ("arrowUpRight", "arrowUpRight", False),
    ("arrowDownRight", "arrowDownRight", False),
    ("arrowDownLeft", "arrowDownLeft", False),
    # Charts and insight
    ("trendingUp", "trendingUp", True),
    ("trendingDown", "trendingDown", True),
    ("trendingFlat", "moveRight", True),
    ("chartPie", "chartPie", False),
    ("chartLine", "chartLine", True),
    ("chartStacked", "chartColumnStacked", False),
    ("chartCombined", "chartNoAxesCombined", False),
    ("chartSpline", "chartSpline", False),
    ("gauge", "gauge", False),
    ("target", "target", False),
    ("flag", "flag", False),
    ("brain", "brain", False),
    # Time
    ("calendar", "calendar", False),
    ("calendarDays", "calendarDays", False),
    ("calendarRange", "calendarRange", False),
    ("calendarCheck", "calendarCheck", False),
    ("calendarX", "calendarX", False),
    ("calendarRepeat", "calendarSync", False),
    ("calendarEdit", "calendarCog", False),
    ("history", "history", False),
    ("pending", "clipboardClock", False),
    # Lists and text
    ("list", "list", True),
    ("listChecks", "listChecks", True),
    ("notes", "textAlignStart", True),
    ("tag", "tag", True),
    ("shapes", "shapes", False),
    ("fileText", "fileText", False),
    ("newspaper", "newspaper", False),
    ("book", "bookOpen", False),
    # People and security
    ("user", "user", False),
    ("userOff", "userX", False),
    ("idCard", "idCard", False),
    ("lock", "lock", False),
    ("key", "keyRound", False),
    ("fingerprint", "fingerprintPattern", False),
    ("shield", "shield", False),
    ("shieldAlert", "shieldAlert", False),
    ("shieldCheck", "shieldCheck", False),
    # Device and system
    ("phone", "smartphone", False),
    ("rotate3d", "rotate3d", False),
    ("vibrate", "vibrate", False),
    ("sun", "sun", False),
    ("moon", "moon", False),
    ("language", "languages", False),
    ("wifi", "wifi", False),
    ("cloudSync", "cloudSync", False),
    ("database", "database", False),
    ("wrench", "wrench", False),
    # Categories
    ("food", "utensils", False),
    ("burger", "hamburger", False),
    ("coffee", "coffee", False),
    ("bus", "bus", False),
    ("car", "car", False),
    ("taxi", "carTaxiFront", False),
    ("bike", "bike", False),
    ("fuel", "fuel", False),
    ("plane", "plane", False),
    ("shoppingBag", "shoppingBag", False),
    ("shoppingCart", "shoppingCart", False),
    ("shoppingBasket", "shoppingBasket", False),
    ("shirt", "shirt", False),
    ("gift", "gift", False),
    ("pill", "pill", False),
    ("hospital", "hospital", False),
    ("gamepad", "gamepad2", False),
    ("movie", "clapperboard", False),
    ("tv", "tv", False),
    ("football", "volleyball", False),
    ("dumbbell", "dumbbell", False),
    ("education", "graduationCap", False),
    ("briefcase", "briefcase", False),
    ("baby", "baby", False),
    ("pet", "pawPrint", False),
    ("droplet", "droplet", False),
    ("scissors", "scissors", False),
    # More category icons for the custom-category picker
    ("pizza", "pizza", False),
    ("croissant", "croissant", False),
    ("sandwich", "sandwich", False),
    ("drumstick", "drumstick", False),
    ("beef", "beef", False),
    ("soup", "soup", False),
    ("salad", "salad", False),
    ("apple", "apple", False),
    ("milk", "milk", False),
    ("egg", "egg", False),
    ("cookie", "cookie", False),
    ("iceCream", "iceCreamCone", False),
    ("soda", "cupSoda", False),
    ("cookingPot", "cookingPot", False),
    ("restaurant", "utensilsCrossed", False),
    ("motorbike", "motorbike", False),
    ("train", "trainFront", False),
    ("tram", "tramFront", False),
    ("ship", "ship", False),
    ("truck", "truck", False),
    ("parking", "circleParking", False),
    ("luggage", "luggage", False),
    ("hotel", "hotel", False),
    ("tent", "tentTree", False),
    ("palmTree", "palmtree", False),
    ("mapPin", "mapPin", False),
    ("ticket", "ticket", False),
    ("umbrella", "umbrella", False),
    ("building", "building2", False),
    ("sofa", "sofa", False),
    ("bed", "bed", False),
    ("lamp", "lamp", False),
    ("washingMachine", "washingMachine", False),
    ("fridge", "refrigerator", False),
    ("hammer", "hammer", False),
    ("paintRoller", "paintRoller", False),
    ("plug", "plug", False),
    ("electricity", "zap", False),
    ("router", "router", False),
    ("sprout", "sprout", False),
    ("flower", "flower2", False),
    ("footprints", "footprints", False),
    ("watch", "watch", False),
    ("gem", "gem", False),
    ("glasses", "glasses", False),
    ("perfume", "sprayCan", False),
    ("bath", "bath", False),
    ("brush", "brush", False),
    ("stethoscope", "stethoscope", False),
    ("syringe", "syringe", False),
    ("heartPulse", "heartPulse", False),
    ("bandage", "bandage", False),
    ("swimming", "waves", False),
    ("school", "school", False),
    ("backpack", "backpack", False),
    ("library", "libraryBig", False),
    ("laptop", "laptop", False),
    ("monitor", "monitor", False),
    ("printer", "printer", False),
    ("hardHat", "hardHat", False),
    ("family", "users", False),
    ("cake", "cake", False),
    ("charity", "heartHandshake", False),
    ("handHeart", "handHeart", False),
    ("handCoins", "handCoins", False),
    ("mosque", "mosque", False),
    ("cat", "cat", False),
    ("dog", "dog", False),
    ("fish", "fish", False),
    ("bone", "bone", False),
    ("music", "music", False),
    ("headphones", "headphones", False),
    ("camera", "camera", False),
    ("popcorn", "popcorn", False),
    ("puzzle", "puzzle", False),
    ("dice", "dices", False),
    ("bank", "landmark", False),
    ("coins", "coins", False),
    ("percent", "percent", False),
    ("scale", "scale", False),
    ("insurance", "shieldPlus", False),
    ("cloud", "cloud", False),
]

# Icons drawn for Waffr: app name -> (SVG in tool/icons, code point, mirrored).
# Code points sit in the Private Use Area, clear of Lucide's E000-E8FF.
CUSTOM_ICONS = {
    # The Waffr wallet: the savings tab and everything that meant "savings"
    # (it replaced Lucide's piggy bank).
    "savings": ("waffr_wallet.svg", 0xF600, False),
}

LICENSE = """ISC License

Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2022 as part
of Feather (MIT). All other copyright (c) for Lucide are held by Lucide
Contributors 2022.

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
"""


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    package = Path(sys.argv[1])
    source = (package / "lib" / "lucide_icons_300.dart").read_text()
    codes = {
        name: int(code)
        for name, code in re.findall(
            r"static const IconData (\w+) = const IconData\((\d+)", source
        )
    }
    missing = sorted({lucide for _, lucide, _ in ICONS if lucide not in codes})
    if missing:
        sys.exit(f"Not in Lucide: {missing}")
    names = [name for name, _, _ in ICONS]
    if len(names) != len(set(names)):
        sys.exit("Duplicate app icon names")

    font_path = package / "assets" / "build_font" / "LucideVariable-w300.ttf"
    upem = 1000
    options = subset.Options()
    options.layout_features = []
    options.name_IDs = [1, 2]
    options.notdef_outline = False
    options.glyph_names = False
    options.hinting = False
    font = TTFont(font_path)
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=sorted({codes[l] for _, l, _ in ICONS}))
    subsetter.subset(font)
    for name, (svg, code, _) in CUSTOM_ICONS.items():
        _add_svg_glyph(font, f"waffr_{name}", code, ROOT / "tool" / "icons" / svg, upem)
    out_font = ROOT / "fonts" / "WaffrIcons.ttf"
    font.save(out_font)

    lines = [
        "// GENERATED by tool/build_icons.py. Do not edit by hand.",
        "//",
        "// Waffr's icon set: thin line icons from Lucide (ISC license), shipped",
        "// as the small subset font fonts/WaffrIcons.ttf. Add an icon in the",
        "// tool's ICONS table and run it again.",
        "",
        "import 'package:flutter/widgets.dart';",
        "",
        "/// Every icon the app draws. Use these instead of Material `Icons`.",
        "abstract final class AppIcons {",
        "  static const String _family = 'WaffrIcons';",
    ]
    entries = [(name, f"Lucide `{lucide}`.", codes[lucide], mirrored)
               for name, lucide, mirrored in ICONS]
    entries += [(name, f"Waffr icon drawn in `tool/icons/{svg}`.",
                 code, mirrored)
                for name, (svg, code, mirrored) in CUSTOM_ICONS.items()]
    for name, doc, code, mirrored in entries:
        extra = ", matchTextDirection: true" if mirrored else ""
        lines += [
            "",
            f"  /// {doc}",
            f"  static const IconData {name} = IconData(",
            f"    0x{code:x},",
            f"    fontFamily: _family{extra},",
            "  );",
        ]
    lines += ["}", ""]
    (ROOT / "lib" / "core" / "theme" / "app_icons.dart").write_text("\n".join(lines))
    (ROOT / "assets" / "licenses" / "Lucide-ISC.txt").write_text(LICENSE)
    print(f"{len(entries)} icons, {out_font.stat().st_size} bytes")


def _add_svg_glyph(font, glyph_name, code, svg_path, upem):
    """Adds the stroked SVG at [svg_path] to [font] as an outline glyph.

    The strokes are expanded to outlines by picosvg, the pieces are merged
    with skia-pathops (so overlaps do not cancel out), and the 24x24 grid is
    scaled to the em with y flipped, as Lucide's own glyphs are.
    """
    import pathops
    from picosvg.svg import SVG

    picture = SVG.parse(str(svg_path)).topicosvg()
    merged = pathops.Path()
    for shape in picture.shapes():
        piece = pathops.Path()
        parse_path(shape.as_path().d, piece.getPen())
        merged = pathops.op(merged, piece, pathops.PathOp.UNION)
    scale = upem / 24
    glyph_pen = TTGlyphPen(None)
    # Outer contours end up clockwise after the y flip, as TrueType wants.
    merged.draw(TransformPen(Cu2QuPen(glyph_pen, 1.0, reverse_direction=True),
                             (scale, 0, 0, -scale, 0, upem)))
    glyph = glyph_pen.glyph()
    font["glyf"][glyph_name] = glyph
    font["hmtx"][glyph_name] = (upem, 0)
    order = font.getGlyphOrder()
    if glyph_name not in order:
        font.setGlyphOrder(order + [glyph_name])
    for table in font["cmap"].tables:
        if table.isUnicode():
            table.cmap[code] = glyph_name
    glyph.recalcBounds(font["glyf"])


if __name__ == "__main__":
    main()
