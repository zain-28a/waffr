#!/usr/bin/env python3
"""Builds Waffr's icon font: a small subset of Lucide (ISC license).

The app ships only the glyphs listed in ICONS, at the 300 stroke weight, as
fonts/WaffrIcons.ttf, and reads them through lib/core/theme/app_icons.dart.

Usage (needs `pip install fonttools`):
  dart pub cache add lucide_icons_flutter -v 4.0.3
  python3 tool/build_icons.py ~/.pub-cache/hosted/pub.dev/lucide_icons_flutter-4.0.3

To add an icon: add a line to ICONS (app name, Lucide name, mirrored in RTL)
and run the script again. Both generated files are committed.
"""
import re
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent

# app name, Lucide name (camelCase), mirrored in right-to-left layouts.
ICONS = [
    # Navigation and chrome
    ("home", "house", False),
    ("reports", "chartNoAxesColumn", False),
    ("savings", "piggyBank", False),
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
    ("filter", "listFilter", False),
    ("tune", "slidersHorizontal", False),
    ("externalLink", "externalLink", False),
    # Actions
    ("add", "plus", False),
    ("remove", "minus", False),
    ("addCircle", "circlePlus", False),
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
    ("copy", "copy", False),
    ("download", "download", False),
    ("backspace", "delete", False),
    ("refresh", "refreshCw", False),
    ("repeat", "repeat", False),
    ("swap", "arrowLeftRight", False),
    ("logOut", "logOut", True),
    ("logIn", "logIn", True),
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
    ("sparkle", "sparkle", False),
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
    ("zap", "zap", False),
    ("smile", "smile", False),
    # Money
    ("wallet", "wallet", False),
    ("banknote", "banknote", False),
    ("coins", "coins", False),
    ("handCoins", "handCoins", False),
    ("creditCard", "creditCard", False),
    ("receipt", "receiptText", False),
    ("piggyBank", "piggyBank", False),
    ("exchange", "circleDollarSign", False),
    ("percent", "badgePercent", False),
    ("withdraw", "arrowUpFromLine", False),
    ("deposit", "arrowDownToLine", False),
    ("arrowUpRight", "arrowUpRight", False),
    ("arrowDownRight", "arrowDownRight", False),
    ("arrowDownLeft", "arrowDownLeft", False),
    ("arrowUp", "arrowUp", False),
    ("arrowDown", "arrowDown", False),
    # Charts and insight
    ("trendingUp", "trendingUp", True),
    ("trendingDown", "trendingDown", True),
    ("trendingFlat", "moveRight", True),
    ("chartPie", "chartPie", False),
    ("chartLine", "chartLine", True),
    ("chartColumn", "chartNoAxesColumn", False),
    ("chartStacked", "chartColumnStacked", False),
    ("chartCombined", "chartNoAxesCombined", False),
    ("chartSpline", "chartSpline", False),
    ("gauge", "gauge", False),
    ("target", "target", False),
    ("goal", "goal", False),
    ("flag", "flag", False),
    ("brain", "brain", False),
    ("rocket", "rocket", False),
    # Time
    ("calendar", "calendar", False),
    ("calendarDays", "calendarDays", False),
    ("calendarRange", "calendarRange", False),
    ("calendarCheck", "calendarCheck", False),
    ("calendarX", "calendarX", False),
    ("calendarRepeat", "calendarSync", False),
    ("calendarEdit", "calendarCog", False),
    ("calendarClock", "calendarClock", False),
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
    ("userPlus", "userPlus", False),
    ("idCard", "idCard", False),
    ("mail", "mail", False),
    ("lock", "lock", False),
    ("lockOpen", "lockOpen", False),
    ("key", "keyRound", False),
    ("fingerprint", "fingerprintPattern", False),
    ("shield", "shield", False),
    ("shieldAlert", "shieldAlert", False),
    ("shieldCheck", "shieldCheck", False),
    # Device and system
    ("phone", "smartphone", False),
    ("vibrate", "vibrate", False),
    ("rotate3d", "rotate3d", False),
    ("sun", "sun", False),
    ("moon", "moon", False),
    ("palette", "palette", False),
    ("language", "languages", False),
    ("globe", "globe", False),
    ("wifi", "wifi", False),
    ("cloud", "cloud", False),
    ("cloudSync", "cloudSync", False),
    ("cloudOff", "cloudOff", False),
    ("database", "database", False),
    ("wrench", "wrench", False),
    ("mapPin", "mapPin", False),
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
    ("health", "heart", False),
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
]

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
    for name, lucide, mirrored in ICONS:
        extra = ", matchTextDirection: true" if mirrored else ""
        lines += [
            "",
            f"  /// Lucide `{lucide}`.",
            f"  static const IconData {name} = IconData(",
            f"    0x{codes[lucide]:x},",
            f"    fontFamily: _family{extra},",
            "  );",
        ]
    lines += ["}", ""]
    (ROOT / "lib" / "core" / "theme" / "app_icons.dart").write_text("\n".join(lines))
    (ROOT / "assets" / "licenses" / "Lucide-ISC.txt").write_text(LICENSE)
    print(f"{len(ICONS)} icons, {out_font.stat().st_size} bytes")


if __name__ == "__main__":
    main()
