import Foundation

/// Bold or Quiet, saved in the app's settings (owner, 2026-11-23: "let's make a bold/quiet and light/dark 4 theme combo",
/// then "Looks good, Bold default (Recommended)"). Light, dark or matching the system is the separate Appearance setting.
public enum ThemeChoice {
    public static let key = "themeFlavor"

    /// Bold unless Quiet was chosen. Anything else saved there, from a later version or by hand, reads as Bold.
    public static func load(_ defaults: UserDefaults = AppDefaults.store) -> Palette.Flavor {
        defaults.string(forKey: key).flatMap(Palette.Flavor.init(rawValue:)) ?? .bold
    }

    public static func save(_ flavor: Palette.Flavor, _ defaults: UserDefaults = AppDefaults.store) {
        defaults.set(flavor.rawValue, forKey: key)
    }
}
