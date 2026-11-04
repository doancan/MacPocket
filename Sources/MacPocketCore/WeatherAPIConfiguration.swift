import Foundation

/// Configuration verified against the installed iStat Menus Setapp weather client.
/// This embeds the current installation identity in every compiled copy.
/// Keep the identity out of logs and diagnostic reports.
public enum WeatherAPIConfiguration {
    public static let endpoint = URL(string: "https://weather.istatmenus.app/api/1/weather/")!
    public static let clientVersion = "7.x"
    public static let provider = 0
    public static let setapp = "1"

    // Deliberately embedded at the user's request; shared by builds made from this source.
    static let deviceIdentifier = "48ABD5BE-8613-45CB-A0F7-3821F0E36938"
}
