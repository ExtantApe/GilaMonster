// Written by scripts/palette-tokens.py from brand/kit/themes-tokens.json. Don't edit by hand: change the JSON
// and run the script, then gilamonster-check.

extension Palette {
    /// The page behind everything.
    public static let background = Swatch(bold: (0xF5EBDD, 0x1F1C19, 0xF5EBDD, 0x1F1C19), quiet: (0xF5EBDD, 0x1F1C19, 0xF5EBDD, 0x1F1C19))
    /// Cards and fields.
    public static let surface = Swatch(bold: (0xFFFFFF, 0x2A2622, 0xFFFFFF, 0x2A2622), quiet: (0xFFFFFF, 0x2A2622, 0xFFFFFF, 0x2A2622))
    /// Outlines of cards and dividers. Decoration only: anything a person clicks or types in uses controlBorder.
    public static let border = Swatch(bold: (0xDCCFBD, 0x4D4742, 0xDCCFBD, 0x4D4742), quiet: (0xDCCFBD, 0x4D4742, 0xDCCFBD, 0x4D4742))
    /// Outlines of buttons and fields: 3:1 against every surface.
    public static let controlBorder = Swatch(bold: (0x8B8179, 0x948C84, 0x7D736B, 0x948C84), quiet: (0x8B8179, 0x948C84, 0x7D736B, 0x948C84))
    /// Body text.
    public static let ink = Swatch(bold: (0x2A2622, 0xF5EBDD, 0x2A2622, 0xF5EBDD), quiet: (0x2A2622, 0xF5EBDD, 0x2A2622, 0xF5EBDD))
    /// Secondary text.
    public static let muted = Swatch(bold: (0x4E4741, 0xBEB8B1, 0x4E4741, 0xC8C2BB), quiet: (0x4E4741, 0xBEB8B1, 0x4E4741, 0xC8C2BB))
    /// Structure: icons, toggles, selection, links and focus.
    public static let accent = Swatch(bold: (0x166F74, 0x21A8AF, 0x155156, 0x21D0D7), quiet: (0x166F74, 0x21A8AF, 0x155156, 0x21D4DB))
    /// Behind selected and highlighted rows.
    public static let accentWash = Swatch(bold: (0xC9E9EA, 0x123A3C, 0xC9E9EA, 0x123A3C), quiet: (0xE3F0F0, 0x1F3233, 0xE3F0F0, 0x1F3233))
    /// The main action's fill. One per page.
    public static let pop = Swatch(bold: (0xF2A541, 0xF2A541, 0xF2A541, 0xF2A541), quiet: (0xEE6236, 0xEE6236, 0xEE8A5E, 0xEE8A5E))
    /// Text on the main action.
    public static let onPop = Swatch(bold: (0x2A2622, 0x2A2622, 0x231F1B, 0x231F1B), quiet: (0x000000, 0x000000, 0x000000, 0x000000))
    /// The brand color as text, and the main button's outline.
    public static let popText = Swatch(bold: (0xB13917, 0xEA8060, 0x952B17, 0xEAAC8C), quiet: (0xB13917, 0xEA8060, 0x952B17, 0xEAAC8C))
    /// Warnings.
    public static let warning = Swatch(bold: (0x91560B, 0xF2A541, 0x6B430B, 0xF2B057), quiet: (0x91560B, 0xF2A541, 0x6B430B, 0xF2B25B))
    /// Behind a warning.
    public static let warningWash = Swatch(bold: (0xFDEBCB, 0x33271A, 0xFDEBCB, 0x33271A), quiet: (0xF7EBD6, 0x33291C, 0xF7EBD6, 0x33291C))
    /// Errors, a server that's down, and destructive actions.
    public static let danger = Swatch(bold: (0xB0183C, 0xF7889A, 0x9C1832, 0xF7A4B6), quiet: (0xB0183C, 0xF7889A, 0x9C1832, 0xF7A4B6))
    /// Information.
    public static let info = Swatch(bold: (0x166F74, 0x21A8AF, 0x166B70, 0x21B0B7), quiet: (0x166F74, 0x21A8AF, 0x166F74, 0x21ACB3))
    /// Behind information.
    public static let infoWash = Swatch(bold: (0xC9E9EA, 0x123A3C, 0xC9E9EA, 0x123A3C), quiet: (0xE3F0F0, 0x1F3233, 0xE3F0F0, 0x1F3233))
    /// A server that's up.
    public static let up = Swatch(bold: (0x166F74, 0x21A8AF, 0x165B60, 0x21CCD3), quiet: (0x166F74, 0x21A8AF, 0x165B60, 0x21CCD3))
    /// A server starting or stopping.
    public static let starting = Swatch(bold: (0x91560B, 0xF2A541, 0x794A0B, 0xF2AD51), quiet: (0x91560B, 0xF2A541, 0x794A0B, 0xF2AD51))
    /// Progress fill.
    public static let meter = Swatch(bold: (0xB13917, 0xEA8060, 0xAB3617, 0xEA9070), quiet: (0x4E4741, 0xBEB8B1, 0x4E4741, 0xBEB8B1))
    /// Window bar (not drawn yet).
    public static let bar = Swatch(bold: (0xB13917, 0x7A2F1A, 0x952B17, 0x7A2F1A), quiet: (0xEAE0D1, 0x1A1714, 0xEAE0D1, 0x1A1714))
    /// Text on the bar.
    public static let barInk = Swatch(bold: (0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF), quiet: (0x2A2622, 0xF5EBDD, 0x2A2622, 0xF5EBDD))
    /// Sidebar (not drawn yet).
    public static let side = Swatch(bold: (0x173D40, 0x112B2C, 0x173D40, 0x112B2C), quiet: (0xEAE0D1, 0x25211E, 0xEAE0D1, 0x25211E))
    /// Sidebar text.
    public static let sideInk = Swatch(bold: (0xF5EBDD, 0xF5EBDD, 0xF5EBDD, 0xF5EBDD), quiet: (0x2A2622, 0xF5EBDD, 0x2A2622, 0xF5EBDD))
    /// Sidebar secondary text.
    public static let sideMuted = Swatch(bold: (0xC3D6D7, 0xA9C6C7, 0xC3D6D7, 0xA9C6C7), quiet: (0x4E4741, 0xBEB8B1, 0x4D4640, 0xBEB8B1))
    /// Selected sidebar row.
    public static let sel = Swatch(bold: (0xF2A541, 0xF2A541, 0xF2A541, 0xF2A541), quiet: (0xDCCFBC, 0x3D3833, 0xDCCFBC, 0x3D3833))
    /// Text on the selected row.
    public static let onSel = Swatch(bold: (0x2A2622, 0x2A2622, 0x231F1B, 0x231F1B), quiet: (0x2A2622, 0xF5EBDD, 0x2A2622, 0xF5EBDD))
    /// The mark on the selected row's leading edge.
    public static let selMark = Swatch(bold: (0xF2A541, 0xF2A541, 0xF2A541, 0xF2A541), quiet: (0xB13917, 0xEE6236, 0xA53317, 0xEE764A))
    /// Page header strip (not drawn yet).
    public static let band = Swatch(bold: (0xB13917, 0x7A2F1A, 0x952B17, 0x7A2F1A), quiet: (0xF5EBDD, 0x1F1C19, 0xF5EBDD, 0x1F1C19))
    /// Text on the header strip.
    public static let bandInk = Swatch(bold: (0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF), quiet: (0x2A2622, 0xF5EBDD, 0x2A2622, 0xF5EBDD))
    /// Hover and raised rows: halfway between the page and a card.
    public static let raised = Swatch(bold: (0xFAF5EE, 0x24211E, 0xFAF5EE, 0x24211E), quiet: (0xFAF5EE, 0x24211E, 0xFAF5EE, 0x24211E))
    /// Behind an error. Derived from down and the page, since Brand's set has none.
    public static let dangerWash = Swatch(bold: (0xF2E0D5, 0x392928, 0xECD6CC, 0x3D2F2F), quiet: (0xF2E0D5, 0x392928, 0xECD6CC, 0x3D2F2F))
}
