import Foundation

///
/// Facility to read values from a bundle's own Info.plist file.
///
enum InfoPlist {
    ///
    /// Property list keys.
    ///
    private enum Key {
        ///
        /// Property list key.
        ///
        static let minimumSupportedServerMajorVersion = "MinimumSupportedNextcloudMajorVersion"

        ///
        /// Property list key.
        ///
        static let privacyPolicy = "PrivacyPolicy"

        ///
        /// Property list key.
        ///
        static let support = "SupportURL"
    }

    ///
    /// The lowest Nextcloud major version the app accepts.
    ///
    static var minimumSupportedServerMajorVersion: Int {
        guard let value = Bundle.main.object(forInfoDictionaryKey: Key.minimumSupportedServerMajorVersion) else {
            preconditionFailure("Info.plist is missing the \"\(Key.minimumSupportedServerMajorVersion)\" entry.")
        }

        if let intValue = value as? Int {
            return intValue
        }

        if let stringValue = value as? String, let intValue = Int(stringValue) {
            return intValue
        }

        preconditionFailure("Info.plist entry \"\(Key.minimumSupportedServerMajorVersion)\" must be an integer or a string representing one but was \(type(of: value)).")
    }

    ///
    /// The URL of Cirruscope's online privacy policy.
    ///
    static var privacyPolicy: URL {
        guard let value = Bundle.main.object(forInfoDictionaryKey: Key.privacyPolicy) else {
            preconditionFailure("Info.plist is missing the \"\(Key.privacyPolicy)\" entry.")
        }

        guard let stringValue = value as? String, let url = URL(string: stringValue) else {
            preconditionFailure("Info.plist entry \"\(Key.privacyPolicy)\" must be a string representing a valid URL but was \(value).")
        }

        return url
    }

    ///
    /// The URL of Cirruscope's online support page.
    ///
    static var support: URL {
        guard let value = Bundle.main.object(forInfoDictionaryKey: Key.support) else {
            preconditionFailure("Info.plist is missing the \"\(Key.support)\" entry.")
        }

        guard let stringValue = value as? String, let url = URL(string: stringValue) else {
            preconditionFailure("Info.plist entry \"\(Key.support)\" must be a string representing a valid URL but was \(value).")
        }

        return url
    }
}
