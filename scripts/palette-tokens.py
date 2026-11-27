#!/usr/bin/env python3
"""Writes Sources/GilaMonsterCore/PaletteTokens.swift from brand/kit/themes-tokens.json (Brand's four themes).

  python3 scripts/palette-tokens.py            # then: swift run gilamonster-check, which holds every pair to WCAG

A new palette is a new JSON and this one command. The app's names for colors (Theme.accent, Theme.pop and so on)
never change; this file maps Brand's keys onto them.
"""
import json, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "brand/kit/themes-tokens.json"
OUT = ROOT / "Sources/GilaMonsterCore/PaletteTokens.swift"

# The app's role name, Brand's key, and what it's for.
ROLES = [
    ("background", "bg", "The page behind everything."),
    ("surface", "surface", "Cards and fields."),
    ("border", "border", "Outlines of cards and dividers. Decoration only: anything a person clicks or types in uses controlBorder."),
    ("controlBorder", "control", "Outlines of buttons and fields: 3:1 against every surface."),
    ("ink", "ink", "Body text."),
    ("muted", "muted", "Secondary text."),
    ("accent", "link", "Structure: icons, toggles, selection, links and focus."),
    ("accentWash", "infoWash", "Behind selected and highlighted rows."),
    ("pop", "primary", "The main action's fill. One per page."),
    ("onPop", "onPrimary", "Text on the main action."),
    ("popText", "brandText", "The brand color as text, and the main button's outline."),
    ("warning", "warn", "Warnings."),
    ("warningWash", "warnWash", "Behind a warning."),
    ("danger", "down", "Errors, a server that's down, and destructive actions."),
    ("info", "info", "Information."),
    ("infoWash", "infoWash", "Behind information."),
    ("up", "up", "A server that's up."),
    ("starting", "starting", "A server starting or stopping."),
    ("meter", "meter", "Progress fill."),
    ("bar", "bar", "Window bar (not drawn yet)."), ("barInk", "barInk", "Text on the bar."),
    ("side", "side", "The basalt spine, in both appearances."), ("sideInk", "sideInk", "The selected section's word on the spine."), ("sideMuted", "sideMuted", "The other sections' words on the spine."),
    ("sel", "sel", "Cream tile behind the pixel lizard on the spine."), ("onSel", "onSel", "Basalt on the cream tile."), ("selMark", "selMark", "The selected bead's cream outline."),
    ("band", "band", "Page header strip (not drawn yet)."), ("bandInk", "bandInk", "Text on the header strip."),
    ("raised", "raised", "Selected rows, inventory slots and other raised spots on a page."),
    ("stopped", "stopped", "A server that's stopped, and players who are away."),
    ("beadIdle", "beadIdle", "An unselected section bead's fill on the spine. Decoration: its outline carries it."),
    ("beadEdge", "beadEdge", "An unselected section bead's outline on the spine."),
    ("beadOn", "beadOn", "The selected section bead's fill on the spine."),
    ("pill", "pill", "A badge count's pill on the spine."),
    ("onPill", "onPill", "The number in a badge pill."),
    ("sideFocus", "sideFocus", "The keyboard focus ring on the spine, where the page's own focus color would be too dark."),
]

def hexval(s): return int(s.lstrip("#"), 16)

def mix(a, b, t):
    ca = [(a >> s) & 255 for s in (16, 8, 0)]; cb = [(b >> s) & 255 for s in (16, 8, 0)]
    c = [round(x + (y - x) * t) for x, y in zip(ca, cb)]
    return c[0] << 16 | c[1] << 8 | c[2]

def main():
    themes = json.loads(SRC.read_text())["themes"]
    def four(flavor, key):
        l, d = themes[f"{flavor}-light"], themes[f"{flavor}-dark"]
        return [hexval(l["standard"][key]), hexval(d["standard"][key]), hexval(l["increaseContrast"][key]), hexval(d["increaseContrast"][key])]
    def danger_wash(flavor):
        # Brand's set has no wash for errors: a tint of `down` over the page, held to WCAG by the checks like the rest.
        l, d = themes[f"{flavor}-light"], themes[f"{flavor}-dark"]
        return [mix(hexval(l["standard"]["bg"]), hexval(l["standard"]["down"]), 0.05), mix(hexval(d["standard"]["bg"]), hexval(d["standard"]["down"]), 0.12),
                mix(hexval(l["increaseContrast"]["bg"]), hexval(l["increaseContrast"]["down"]), 0.09), mix(hexval(d["increaseContrast"]["bg"]), hexval(d["increaseContrast"]["down"]), 0.14)]
    h = lambda v: "0x%06X" % v
    lines = ["// Written by scripts/palette-tokens.py from brand/kit/themes-tokens.json. Don't edit by hand: change the JSON",
             "// and run the script, then gilamonster-check.", "", "extension Palette {"]
    def emit(role, b, q, doc):
        lines.append(f"    /// {doc}")
        lines.append(f"    public static let {role} = Swatch(bold: ({', '.join(map(h, b))}), quiet: ({', '.join(map(h, q))}))")
    for role, key, doc in ROLES:
        emit(role, four("bold", key), four("quiet", key), doc)
    # Raised comes straight from Brand's set since K786 (2026-11-25): the paler sand leaves room for every text color
    # on it, and gilamonster-check holds each pair there like the rest.
    emit("dangerWash", danger_wash("bold"), danger_wash("quiet"), "Behind an error. Derived from down and the page, since Brand's set has none.")
    lines.append("}")
    OUT.write_text("\n".join(lines) + "\n")
    print(f"wrote {OUT.relative_to(ROOT)}: {len(ROLES) + 2} tokens, bold and quiet, four appearances each")

if __name__ == "__main__":
    main()
