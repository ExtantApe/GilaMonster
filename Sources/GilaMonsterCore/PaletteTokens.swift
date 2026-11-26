// Written by scripts/palette-tokens.py from brand/kit/themes-tokens.json. Don't edit by hand: change the JSON
// and run the script, then gilamonster-check.

extension Palette {
    /// The page behind everything.
    public static let background = Swatch(bold: (0xF6EFE3, 0x1E1C20, 0xF6EFE3, 0x1E1C20), quiet: (0xF6EFE3, 0x1E1C20, 0xF6EFE3, 0x1E1C20))
    /// Cards and fields.
    public static let surface = Swatch(bold: (0xFDFAF4, 0x262428, 0xFDFAF4, 0x262428), quiet: (0xFDFAF4, 0x262428, 0xFDFAF4, 0x262428))
    /// Outlines of cards and dividers. Decoration only: anything a person clicks or types in uses controlBorder.
    public static let border = Swatch(bold: (0xE0D4C0, 0x403C45, 0xB8A88F, 0x6A6470), quiet: (0xE0D4C0, 0x403C45, 0xB8A88F, 0x6A6470))
    /// Outlines of buttons and fields: 3:1 against every surface.
    public static let controlBorder = Swatch(bold: (0x857868, 0x8E8893, 0x6B5F52, 0xABA5B0), quiet: (0x857868, 0x8E8893, 0x6B5F52, 0xABA5B0))
    /// Body text.
    public static let ink = Swatch(bold: (0x2A282C, 0xF5EBDD, 0x2A282C, 0xF5EBDD), quiet: (0x2A282C, 0xF5EBDD, 0x2A282C, 0xF5EBDD))
    /// Secondary text.
    public static let muted = Swatch(bold: (0x544B43, 0xC4B9AC, 0x433B35, 0xD9CFC3), quiet: (0x544B43, 0xC4B9AC, 0x433B35, 0xD9CFC3))
    /// Structure: icons, toggles, selection, links and focus.
    public static let accent = Swatch(bold: (0x12666B, 0x34B4BB, 0x0C4E52, 0x62D3D9), quiet: (0x12666B, 0x34B4BB, 0x0C4E52, 0x62D3D9))
    /// Behind selected and highlighted rows.
    public static let accentWash = Swatch(bold: (0xDCEDEC, 0x173A3D, 0xDCEDEC, 0x173A3D), quiet: (0xE9F1F0, 0x1F3233, 0xE9F1F0, 0x1F3233))
    /// The main action's fill. One per page.
    public static let pop = Swatch(bold: (0xB13917, 0xEA8060, 0x8E2C10, 0xF2A58C), quiet: (0xEE6236, 0xEE6236, 0xF08A63, 0xF08A63))
    /// Text on the main action.
    public static let onPop = Swatch(bold: (0xFFFFFF, 0x1E1C20, 0xFFFFFF, 0x1E1C20), quiet: (0x000000, 0x000000, 0x000000, 0x000000))
    /// The brand color as text, and the main button's outline.
    public static let popText = Swatch(bold: (0x9C3216, 0xF09374, 0x7A260F, 0xF7B9A4), quiet: (0x9C3216, 0xF09374, 0x7A260F, 0xF7B9A4))
    /// Warnings.
    public static let warning = Swatch(bold: (0x7C5200, 0xF2A541, 0x5A3B00, 0xF5BC66), quiet: (0x7C5200, 0xF2A541, 0x5A3B00, 0xF5BC66))
    /// Behind a warning.
    public static let warningWash = Swatch(bold: (0xF8E9CC, 0x3A2E1E, 0xF8E9CC, 0x3A2E1E), quiet: (0xF8EEDC, 0x33291C, 0xF8EEDC, 0x33291C))
    /// Errors, a server that's down, and destructive actions.
    public static let danger = Swatch(bold: (0xA8173A, 0xFF8DA0, 0x780E29, 0xFFBDC9), quiet: (0xA8173A, 0xFF8DA0, 0x780E29, 0xFFBDC9))
    /// Information.
    public static let info = Swatch(bold: (0x12666B, 0x34B4BB, 0x0C4E52, 0x62D3D9), quiet: (0x12666B, 0x34B4BB, 0x0C4E52, 0x62D3D9))
    /// Behind information.
    public static let infoWash = Swatch(bold: (0xDCEDEC, 0x173A3D, 0xDCEDEC, 0x173A3D), quiet: (0xE9F1F0, 0x1F3233, 0xE9F1F0, 0x1F3233))
    /// A server that's up.
    public static let up = Swatch(bold: (0x12666B, 0x34B4BB, 0x0C4E52, 0x62D3D9), quiet: (0x12666B, 0x34B4BB, 0x0C4E52, 0x62D3D9))
    /// A server starting or stopping.
    public static let starting = Swatch(bold: (0x7C5200, 0xF2A541, 0x5A3B00, 0xF5BC66), quiet: (0x7C5200, 0xF2A541, 0x5A3B00, 0xF5BC66))
    /// Progress fill.
    public static let meter = Swatch(bold: (0xB13917, 0xEA8060, 0x8E2C10, 0xF2A58C), quiet: (0xB13917, 0xEA8060, 0x8E2C10, 0xF2A58C))
    /// Window bar (not drawn yet).
    public static let bar = Swatch(bold: (0xB13917, 0x7A2F1A, 0x8E2C10, 0x7A2F1A), quiet: (0xB13917, 0x7A2F1A, 0x8E2C10, 0x7A2F1A))
    /// Text on the bar.
    public static let barInk = Swatch(bold: (0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF), quiet: (0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF))
    /// The basalt spine, in both appearances.
    public static let side = Swatch(bold: (0x2A282C, 0x151417, 0x2A282C, 0x151417), quiet: (0x2A282C, 0x151417, 0x2A282C, 0x151417))
    /// The selected section's word on the spine.
    public static let sideInk = Swatch(bold: (0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF), quiet: (0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF))
    /// The other sections' words on the spine.
    public static let sideMuted = Swatch(bold: (0xE7DCCD, 0xE7DCCD, 0xE7DCCD, 0xE7DCCD), quiet: (0xE7DCCD, 0xE7DCCD, 0xE7DCCD, 0xE7DCCD))
    /// Cream tile behind the pixel lizard on the spine.
    public static let sel = Swatch(bold: (0xF5EBDD, 0xF5EBDD, 0xF5EBDD, 0xF5EBDD), quiet: (0xF5EBDD, 0xF5EBDD, 0xF5EBDD, 0xF5EBDD))
    /// Basalt on the cream tile.
    public static let onSel = Swatch(bold: (0x2A282C, 0x2A282C, 0x2A282C, 0x2A282C), quiet: (0x2A282C, 0x2A282C, 0x2A282C, 0x2A282C))
    /// The selected bead's cream outline.
    public static let selMark = Swatch(bold: (0xF5EBDD, 0xF5EBDD, 0xF5EBDD, 0xF5EBDD), quiet: (0xF5EBDD, 0xF5EBDD, 0xF5EBDD, 0xF5EBDD))
    /// Page header strip (not drawn yet).
    public static let band = Swatch(bold: (0xB13917, 0x7A2F1A, 0x8E2C10, 0x7A2F1A), quiet: (0xB13917, 0x7A2F1A, 0x8E2C10, 0x7A2F1A))
    /// Text on the header strip.
    public static let bandInk = Swatch(bold: (0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF), quiet: (0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF))
    /// Selected rows, inventory slots and other raised spots on a page.
    public static let raised = Swatch(bold: (0xEFE6D6, 0x302D33, 0xEFE6D6, 0x302D33), quiet: (0xEFE6D6, 0x302D33, 0xEFE6D6, 0x302D33))
    /// A server that's stopped, and players who are away.
    public static let stopped = Swatch(bold: (0x4B474F, 0xB9B5BE, 0x4B474F, 0xB9B5BE), quiet: (0x4B474F, 0xB9B5BE, 0x4B474F, 0xB9B5BE))
    /// An unselected section bead's fill on the spine. Decoration: its outline carries it.
    public static let beadIdle = Swatch(bold: (0x3A363D, 0x2E2B31, 0x3A363D, 0x2E2B31), quiet: (0x3A363D, 0x2E2B31, 0x3A363D, 0x2E2B31))
    /// An unselected section bead's outline on the spine.
    public static let beadEdge = Swatch(bold: (0x8E8893, 0x8E8893, 0xADA7B2, 0xADA7B2), quiet: (0x8E8893, 0x8E8893, 0xADA7B2, 0xADA7B2))
    /// The selected section bead's fill on the spine.
    public static let beadOn = Swatch(bold: (0xEE6A3F, 0xEE6A3F, 0xF48A5C, 0xF48A5C), quiet: (0xEE6A3F, 0xEE6A3F, 0xF48A5C, 0xF48A5C))
    /// A badge count's pill on the spine.
    public static let pill = Swatch(bold: (0xF5EBDD, 0xF5EBDD, 0xF5EBDD, 0xF5EBDD), quiet: (0xF5EBDD, 0xF5EBDD, 0xF5EBDD, 0xF5EBDD))
    /// The number in a badge pill.
    public static let onPill = Swatch(bold: (0x2A282C, 0x2A282C, 0x2A282C, 0x2A282C), quiet: (0x2A282C, 0x2A282C, 0x2A282C, 0x2A282C))
    /// The keyboard focus ring on the spine, where the page's own focus color would be too dark.
    public static let sideFocus = Swatch(bold: (0x34B4BB, 0x34B4BB, 0x62D3D9, 0x62D3D9), quiet: (0x34B4BB, 0x34B4BB, 0x62D3D9, 0x62D3D9))
    /// Behind an error. Derived from down and the page, since Brand's set has none.
    public static let dangerWash = Swatch(bold: (0xF2E4DB, 0x392A2F, 0xE9D8D0, 0x3E3338), quiet: (0xF2E4DB, 0x392A2F, 0xE9D8D0, 0x3E3338))
}
