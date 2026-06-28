import Foundation

/// Look up a localized string from the Features module bundle.
/// Falls back to the key itself (the Russian text) when no translation is found.
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}
