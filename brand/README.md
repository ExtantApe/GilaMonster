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

Open-licence fonts only (owner, 2026-11-14). Any font the kit uses lives in [`fonts/`](fonts/) with its SIL Open Font
License beside it. The fonts there now came with the earlier kit, and none is chosen for GilaMonster yet. The app's own
interface uses the system font through Apple's APIs, which is a different thing from setting a logo in it.

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
| Background | `#F5EBDD` | `#1E1C20` | |
| Surface | `#FFFFFF` | `#2A282C` | |
| Raised | `#FAF3EA` | `#252327` | |
| Border (cards and dividers only) | `#E2D4C0` | `#403C44` | `#5A5560` / `#B0ABB6` |
| Control outline (buttons, fields) | `#857D88` | `#8F8A95` | `#5A5560` / `#B0ABB6` |
| Ink | `#2A282C` | `#F5EBDD` | `#000000` / `#FFFFFF` |
| Muted | `#4B474F` | `#B9B5BE` | |
| Accent (turquoise) | `#166F74` | `#21A4AB` | `#105155` / `#2BCED6` |
| Pop (red-orange fill), with `onPop` text `#FFFFFF` / `#1E1C20` | `#B13917` | `#EA8060` | `#822A11` / `#F1AC97` |
| Pop text | `#B13917` | `#EA8060` | `#822A11` / `#F1AC97` |
| Warning | `#95580B` | `#F2A541` | `#6D4008` / `#F4B058` |
| Danger | `#B0183C` | `#FF7D93` | `#8B132F` / `#FFA5B4` |
| Info | `#166F74` | `#21A4AB` | `#105155` / `#2BCED6` |

Every pair the app draws meets WCAG AA (4.5:1 for text, 3:1 for controls and icons) in light, dark and both
increased-contrast appearances, and still does with protanopia, deuteranopia, tritanopia or achromatopsia simulated.
`gilamonster-check` fails if any pair drops below, so CI catches it. Source of truth:
`Sources/GilaMonsterCore/Palette.swift`. How the values were reached: [`kit/palette.md`](kit/palette.md).

Icon art colors, for illustration only and never for text: red-orange `#E4572E`, salmon `#F28B82`, amber `#F2A541`,
turquoise `#1C8C92`, basalt `#2A282C`, cream `#F5EBDD`. The art red-orange can't carry text: with protanopia it
drops to 3.45:1 under dark text and 3.17:1 under white.

## Voice

Plain and specific. Say what happened and what to do next. Friendly without being cute: the name carries the fun, so
the interface doesn't need to.

## Shape

Soft rounded tiles and controls, labels beside every icon, and state shown by shape and word as well as color.

- App icon tile: 824 × 824 on a 1024 canvas, corner radius about 185, flat cream.
- Controls: 32 pt buttons, radius 8, 1 pt border. Cards radius 10. 2 pt focus ring.
- Icons with labels. An icon alone gets an accessibility label and a tooltip.
- State is shown by **shape and word as well as color**: Up is a filled circle, Starting a ring, Down a triangle,
  Stopped a square.

SwiftUI's prominent button sets its own text color, which can't be relied on for contrast here, so `ThemeButtonStyle`
sets it explicitly. Increase Contrast in System Settings gets the stronger values in the table.

## Accessibility

- Uses system text styles, standard controls and SF Symbols, so VoiceOver and keyboard navigation work as expected.
- The console is a real text view: selectable across lines and readable by VoiceOver.
- Animation respects Reduce Motion.
- Destructive actions are never the default button. Deleting a world means typing its name.
