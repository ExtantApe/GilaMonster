# GilaMonster palette tokens

**Since K786 (2026-11-25), the app uses the desert base, calmed down** (owner's pick: "B: desert base, calmed down"):
page `#F6EFE3`, cards `#FDFAF4`, raised `#EFE6D6` in light; page `#1E1C20`, cards `#262428`, raised `#302D33` in dark;
and a basalt spine (`#2A282C` light, `#151417` dark) in both. The hues below are unchanged; the full set, with the
Increase Contrast values held to 7:1 for text and 4.5:1 for controls, is `themes-tokens.json`, and `gilamonster-check`
holds every pair. The table below is the round that set the hues.

The main palette, chosen by the owner on 2026-11-23 (D272), with the icon (D276). These are the text and graphic
tokens behind `Sources/GilaMonsterCore/Palette.swift`. Every value is held to 4.5:1 against both
of its backgrounds (cream `#F5EBDD` and white in light; basalt `#2A282C` and deep `#1E1C20` in dark), in typical color
vision and with protanopia, deuteranopia, tritanopia and achromatopsia simulated, the same way `gilamonster-check` holds
the current palette. The Increase Contrast values are held to 7:1 the same way.

The round 4 values passed in typical vision but five fell under 4.5:1 with a simulation (the lowest was red-orange on
dark, 3.63:1 with protanopia). Each was moved in lightness only, keeping its hue and saturation, until it passed. The
number after each value is its lowest ratio across both backgrounds and every simulation.

| Token | Light | Dark | Light, Increase Contrast | Dark, Increase Contrast |
|---|---|---|---|---|
| Red-orange (brand) | `#B13917` 4.51 (was `#C03E19`) | `#EA8060` 4.50 (was `#E76A45`) | `#822A11` 7.04 | `#F1AC97` 7.02 |
| Salmon | `#A8433D` 4.51 (was `#B34841`) | `#F28B82` 5.24 | `#7C312D` 7.01 | `#F5AAA3` 7.02 |
| Amber | `#95580B` 4.51 (was `#9A5B0B`) | `#F2A541` 6.26 | `#6D4008` 7.04 | `#F4B058` 7.01 |
| Turquoise (links, focus, up) | `#166F74` 4.53 (was `#17757A`) | `#21A4AB` 4.51 (was `#209EA5`) | `#105155` 7.08 | `#2BCED6` 7.03 |
| Starting | `#8F5D00` 4.51 (was `#946000`) | `#F2A541` 6.26 | `#694400` 7.02 | `#F4B058` 7.01 |
| Down | `#B0183C` 5.01 | `#FF7D93` 4.93 | `#8B132F` 7.03 | `#FFA5B4` 7.03 |
| Stopped (mid grey) | `#4B474F` 7.64 | `#B9B5BE` 7.21 | `#4B474F` 7.64 | `#B9B5BE` 7.21 |
| Ink | `#2A282C` 12.21 | `#F5EBDD` 12.21 | same | same |

## Status

Each state has a shape and a word as well as a color: up is a filled circle, starting a ring, down a triangle and
stopped a square. With color blindness simulated the four colors can look nearly alike (up and down drop to 1.01:1
against each other), so the shapes and words carry the meaning. Don't show a state by color alone.

## Icon art colors

For the icon and illustration only, never text: red-orange `#E4572E`, salmon `#F28B82`, amber `#F2A541`, turquoise
`#1C8C92`, basalt `#2A282C`, cream `#F5EBDD`.

## In the app

0.4.0 uses these under role names: turquoise is `accent`, red-orange is `pop` (fill, with `onPop` text) and `popText`,
and the status colors are `info`, `warning` and `danger`. `gilamonster-check` holds every pair in light, dark and both
Increase Contrast appearances. The bold and quiet themes planned for 0.4.1 are drafted in the ops design review.
