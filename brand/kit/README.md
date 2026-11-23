# GilaMonster brand kit

**Icon chosen** by the owner on 2026-11-23 (D276): C1, warm mix, in the main palette (D272). The app icon, menu-bar
template and profile marks are built. Banners, a README header and release images come once the wordmark is designed.

## The idea

A Gila monster from above, drawn as 16 × 16 pixel art: the reticulate form, a basalt body with a network of
red-orange beads mixed with salmon and amber, and turquoise eyes as the one cool note.

## Which rules it follows

No EXTANT APE kit exists yet, so this follows the rules for one: D147 (the minimum asset list), D148 (inheritance
and tiers) and D149 (WCAG). GilaMonster is a desktop app, so its tier is a Mac `.icns` and a Windows `.ico` from one
master, release images, a repo banner, the GitHub social preview and a README header, plus circle and square profile
marks. It isn't a family theme for anything else.

## One master

`mark.txt` is the only drawn file: a grid of 16 rows, one character per pixel, with a palette. This is GilaMonster's
mark, C1 warm mix, chosen by the owner on 2026-11-23 (D276). To build the kit:

```bash
swift scripts/brand-kit.swift brand/kit
```

The builder checks every held pair first, in typical color vision and with protanopia, deuteranopia, tritanopia and
achromatopsia simulated, and refuses to write anything if one fails (D149):

- The mark's outline on the cream tile: 3:1. Last build 12.38:1, lowest 12.21:1 (protanopia).
- The mark's outline on white: 3:1. Last build 14.60:1, lowest 14.55:1 (deuteranopia).

The beads sit inside the outline, so they decorate and don't carry the shape. The builder lists their ratios on the
basalt body without holding them: red-orange 3.96:1 (2.98:1 with protanopia), salmon 6.11:1, amber 7.12:1 and
turquoise 3.63:1. The silhouette reads the same in every kind of color vision.

The builder's banner, header and release-image code was taken out with the old wordmark. It comes back, with its
text pairs checked the same way, once the GilaMonster wordmark is designed.

## What's in `out/`

| File | Size | For |
| --- | --- | --- |
| `mark.svg` | vector | The mark itself, pixel for pixel |
| `mark-circle-{1024,400}.png` | 1024, 400 | Profile marks shown as circles (X, Bluesky) |
| `mark-square-{1024,400}.png` | 1024, 400 | Profile marks shown as squares (LinkedIn company, GitHub) |
| `icon.svg` | vector | The app icon's master |
| `icon-small.svg` | vector, 32 | The master for 16 to 32 px: the tile runs to the edge and each art pixel is a whole screen pixel |
| `icon-1024.png`, `icon-32.png` | 1024, 32 | Drawn from the masters |
| `AppIcon.icns` | 16 to 1024 | macOS, every size at 1× and 2×, made with `iconutil` |
| `GilaMonster.ico` | 16 to 256 | Windows: 16, 24, 32, 48, 64, 128 and 256, read back to check every size is there |
| `MenuBarTemplate.png`, `MenuBarTemplate@2x.png` | 16, 32 | The menu-bar template: black on clear, one art pixel per point |

The profile marks come in one version. The basalt outline needs the cream behind it, so a dark version would lose the
legs.

See [`palette.md`](palette.md) for the app's color tokens, checked the same way.

## Platform sizes, checked 2026-11-14

- **GitHub social preview:** 1280 × 640.
- **X:** profile 400 × 400, header 1500 × 500.
- **LinkedIn:** profile 400 × 400, personal banner 1584 × 396. Guides disagree on the company page banner: most say
  1128 × 191, and one says 1128 × 376. This kit uses 1128 × 191; check LinkedIn's upload preview.
- **Bluesky:** it publishes no official pixel sizes. Guides give 400 × 400 or 1000 × 1000 for the avatar, which shows
  as a circle, and 1500 × 500 or 3000 × 1000 for the banner. The image limit is 1,000,000 bytes. This kit uses the
  larger sizes, and the builder fails if a banner goes over the limit.

Sources: [Buffer](https://buffer.com/resources/social-media-image-sizes/),
[Hootsuite](https://blog.hootsuite.com/social-media-image-sizes/),
[Constant Contact](https://www.constantcontact.com/blog/social-media-image-sizes/),
[OpenTweet's Bluesky guide](https://opentweet.io/tools/bluesky-banner-size),
[Sendcove's Bluesky guide](https://www.sendcove.app/integrations/bluesky/image-sizes).

## Still to do

- Design the wordmark and tagline, then add the banners, README header and release images back to the builder.
- Upload a GitHub social preview in the repo's settings once one is built. GitHub has no command for it.
- See the icon in the Dock, on a phone and on Windows.
