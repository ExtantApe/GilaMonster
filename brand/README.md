# GilaMonster brand

## The idea

A Gila monster: slow, sturdy, and much tougher than it looks. The colors come from the real animal, a basalt-black
body beaded with red-orange, salmon and amber, plus one cool note of turquoise. Cream and basalt do most of the
work. Red-orange is the brand, turquoise is for doing things, and amber is a warm accent.

## Icon

A 16 × 16 pixel-art Gila monster seen from above: a basalt body with red-orange beads mixed with salmon and amber, a
blunt beaded head and turquoise eyes, on a flat cream tile. Chosen by the owner on 2026-11-23 (D276, "C1, warm mix").
The only drawn file is [`kit/mark.txt`](kit/mark.txt), a grid with its palette. Everything else is built from it, so
change that and rebuild rather than editing the outputs:

```bash
swift scripts/brand-kit.swift brand/kit
```

That checks the outline against the tile in typical color vision and with protanopia, deuteranopia, tritanopia and
achromatopsia simulated, and writes nothing if it falls under 3:1. The lowest is 12.2:1. It puts these here in
`brand/`, where the app build and the README look for them:

- `icon.svg`: the master. `icon-small.svg`: the master for 16 to 32 px, where the tile runs to the edge and each art
  pixel is a whole screen pixel.
- `icon-1024.png`: drawn from the master.
- `AppIcon.icns`: macOS, every size at 1× and 2×. `GilaMonster.ico`: Windows, 16 to 256.
- `MenuBarTemplate.png` and `MenuBarTemplate@2x.png`: the menu-bar icon, every drawn pixel in black on clear. macOS
  tints a template itself for light and dark menu bars and for Increase Contrast.
- Flat cream tile, `#F5EBDD`. The outline is basalt, so the mark only goes on light backgrounds. There's no dark tile.

Profile marks are built into `kit/out/`. [`kit/README.md`](kit/README.md) lists them. Banners, release images and a
README header come once the wordmark is designed. Until then the README shows `icon-1024.png`.

## Wordmark and tagline

Not designed yet. Until they are, the name is set in plain text: GilaMonster, one word, capital G and M.

## Fonts

Open-licence fonts only (owner, 2026-11-14). Every font lives in [`fonts/`](fonts/) with its SIL Open Font License
1.1 beside it, and the app build copies the font and its licence into the app together.

Pixel type (K820, owner's pick 2026-11-26). Each face has one job:

- **Pixelify Sans, weight 700** ([`fonts/pixelifysans`](fonts/pixelifysans)): the one title of a screen, such as
  Overview's status sentence or "Lab". Largest size, once per screen, 27.5 pt on a Retina screen.
- **Departure Mono 1.500** ([`fonts/departuremono`](fonts/departuremono)): headings, labels, buttons, badges, tabs
  and numbers, at 11 pt. Card headings are capitals with one font pixel of extra spacing. Nothing else gets extra
  spacing. The font's own repository carries an MIT licence for its website code. The font files are under the OFL
  that ships in the font download, and that is the file kept here.
- **The system font**: anything that wraps, which is help text, errors, explanations, the Allow prompt's words and
  Overview's line under the title. System menus, the menu bar, text fields and Settings are the system's too. The app
  asks for it through Apple's APIs, which is a different thing from setting a logo in it.
- **Lilita One** ([`fonts/lilitaone`](fonts/lilitaone)): the display face from before the pixel type. It draws the
  status sentence, a player's name and the Allow prompt's sentence when the **Pixel font** setting is off.
- Fredoka came with the earlier kit and isn't used by the app.

Both pixel faces are drawn on an 11-pixel em, so they are sharp only when one font pixel is a whole number of screen
pixels. Labels are 11 pt at the default text size. For larger text the target is 11 times the system's body size
over 13, moved up to the next sharp size and never down: 11, 16.5, 22 or 27.5 pt on a Retina screen, and 11, 22 or
33 pt on a 1x screen. Buttons, paddings, columns, the sidebar, switches and symbols grow by the same amount.

Shortcut signs, arrows, ticks and the small triangle (⌘ ⌥ ⇧ ⌃ → ← ↑ ↓ ✓ ▾) are always set in the system font,
through `SymbolText`. Departure Mono lacks ⇧ ⌃ ✓ and ▾, and `gilamonster-check` reads both fonts' character maps and
fails if a label has a character its face can't draw. Departure Mono's zero is slashed in every form it has.

The rules are in `Sources/GilaMonsterCore/PixelType.swift`. No outlines, shadows or glow on type, and no colors
beyond the table below.

## Color

**Turquoise does things. Red-orange is the pop.**

- **Red-orange** (`pop`) marks the one thing to do next: the main button on a page, plus the brand's own text
  (`popText`). Used sparingly, it stays meaningful. Never use it for state, warnings or decoration.
- **Turquoise** (`accent`) is for links, selection, focus, toggles and the Up state.
- **Cream and basalt** are the surfaces. Basalt is a warm grey-black, never pure black.
- **Danger is a deep crimson, never the brand red-orange**, and danger buttons are outlined. A destructive action
  should never look like the main action.

| Role | Light | Dark | Increase Contrast (light / dark) |
|---|---|---|---|
| Background | `#F6EFE3` | `#1E1C20` | `#F6EFE3` / `#1E1C20` |
| Surface | `#FDFAF4` | `#262428` | `#FDFAF4` / `#262428` |
| Raised | `#EFE6D6` | `#302D33` | `#EFE6D6` / `#302D33` |
| Border (cards and dividers only) | `#E0D4C0` | `#403C45` | `#B8A88F` / `#6A6470` |
| Control outline (buttons, fields) | `#857868` | `#8E8893` | `#6B5F52` / `#ABA5B0` |
| Ink | `#2A282C` | `#F5EBDD` | `#2A282C` / `#F5EBDD` |
| Muted | `#544B43` | `#C4B9AC` | `#433B35` / `#D9CFC3` |
| Accent (turquoise): links, selection, focus, toggles | `#12666B` | `#34B4BB` | `#0C4E52` / `#62D3D9` |
| Pop (the main button's fill) | `#B13917` | `#EA8060` | `#8E2C10` / `#F2A58C` |
| Text on the pop | `#FFFFFF` | `#1E1C20` | `#FFFFFF` / `#1E1C20` |
| Pop text | `#9C3216` | `#F09374` | `#7A260F` / `#F7B9A4` |
| Warning, and a server starting | `#7C5200` | `#F2A541` | `#5A3B00` / `#F5BC66` |
| Danger, and a server that's down | `#A8173A` | `#FF8DA0` | `#780E29` / `#FFBDC9` |
| Info, and a server that's up | `#12666B` | `#34B4BB` | `#0C4E52` / `#62D3D9` |
| Stopped | `#4B474F` | `#B9B5BE` | `#4B474F` / `#B9B5BE` |

These are the Bold theme's values. Quiet is the same except for the main button, which is `#EE6236` with black text
in light and dark (`#F08A63` with Increase Contrast), and paler info and warning washes. The basalt spine's colors
are in the tokens file too.

Source of truth: [`kit/themes-tokens.json`](kit/themes-tokens.json). `scripts/palette-tokens.py` writes
`Sources/GilaMonsterCore/PaletteTokens.swift` from it, so change the JSON and run the script. This table was last
copied from it on 2026-11-26.

The plugin source badges are the one set of colors outside the tokens file. They are written by hand in
`Sources/GilaMonsterCore/Palette.swift` and held by the same checks. The "web" badge's icon gray, `#4B474F` in light
and `#B9B5BE` in dark, is the same pair as the **Stopped** token, so it matches a token by value without being read
from it. This web swatch is meant (Brand, 2026-11-27): it is the plugin-source badge's own gray, darker and cooler
than today's Muted (`#544B43`), and it is held at 3:1 against its tint as an icon, the same floor as the accent.
Keep it listed here under the source badges. The "web" badge's tint (`#FAF3EA` / `#252327`) is the Raised color from
before 2026-11-25 and matches no token now.

Every pair the app draws meets WCAG AA (4.5:1 for text, 3:1 for controls and icons) in light, dark and both
increased-contrast appearances, and still does with protanopia, deuteranopia, tritanopia or achromatopsia simulated.
With Increase Contrast on, text is held to 7:1 and controls and icons to 4.5:1. `gilamonster-check` fails if any pair
drops below, so CI catches it. How the values were reached: [`kit/palette.md`](kit/palette.md).

Icon art colors, for illustration only and never for text: red-orange `#E4572E`, salmon `#F28B82`, amber `#F2A541`,
turquoise `#1C8C92`, basalt `#2A282C`, cream `#F5EBDD`. The art red-orange can't carry text: with protanopia it
drops to 3.45:1 under dark text and 3.17:1 under white.

## Voice

Plain and specific. Say what happened and what to do next. Friendly without being cute: the name carries the fun, so
the interface doesn't need to.

## Shape

Soft rounded tiles and controls, labels beside every icon, and state shown by shape and word as well as color.

- App icon tile: 824 × 824 on a 1024 canvas, corner radius about 185, flat cream.
- Controls: 32 pt buttons at the default text size, growing with larger text. Radius 8, 1 pt border. Cards radius
  10. 2 pt focus ring.
- Icons with labels. An icon alone gets an accessibility label and a tooltip.
- State is shown by **shape and word as well as color**: Up is a filled circle, Starting a ring, Down a triangle,
  Stopped a square.

SwiftUI's prominent button sets its own text color, which can't be relied on for contrast here, so `ThemeButtonStyle`
sets it explicitly. Increase Contrast in System Settings gets the stronger values in the table.

## Accessibility

- **Pixel font** in Settings turns the pixel type off: "Headings, labels, buttons and numbers use a pixel typeface.
  Turn this off to use the system font for them." Off also puts Lilita One back on the status sentence, a
  player's name and the Allow prompt's sentence, as before the pixel type. It is on by default. On a first launch it starts off when the
  Mac's text size is above the default, Bold Text is on, or every screen is 1x. After that it stays as the owner
  left it.
- Text follows the system's text size. Pixel labels move up to the next sharp size and never down, and controls
  grow with them so nothing is cut off.
- With **Bold Text** on, labels, buttons and numbers use the system font, because Departure Mono has one weight.
  macOS bolds the system font itself, so the app asks for the usual weight and nothing is thickened twice. The
  title keeps Pixelify Sans 700.
- On a 1x screen above the default text size, labels, buttons and numbers use the system font, because the next
  sharp pixel size there is double.
- Muted labels at 11 pt keep the Muted color: it is 6.9:1 or better on the background, surface and raised colors.
- Card headings are drawn in capitals, and VoiceOver is given the heading as written.
- The Allow prompt never breaks a server's name across lines. A long name gets a line to itself and the window grows
  for it. A name wider than the widest window is cut in the middle, with the whole name in its tooltip and in what
  VoiceOver reads.
- A font that fails to load is replaced by the system font, and each pixel font names the system font for any
  character it lacks, so text is never lost.
- Standard controls and SF Symbols are used where the system has them, so VoiceOver and keyboard navigation work as
  expected. The controls GilaMonster draws itself (buttons, the Lab's switch, disclosure rows) are named, reachable
  by keyboard and show a focus ring.
- The console is a real text view: selectable across lines and readable by VoiceOver.
- Animation respects Reduce Motion.
- Destructive actions are never the default button. Deleting a world means typing its name.
