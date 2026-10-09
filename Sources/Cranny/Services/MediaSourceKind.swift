import AppKit

/// What kind of app a Now Playing source is, for the "Only show music" setting.
enum MediaSourceKind: Equatable {
    case musicApp, browser, other

    /// Music apps by bundle ID. Apps that declare the Music category in their Info.plist
    /// count too, so this mainly covers ones that don't.
    static let musicApps: Set<String> = [
        "com.apple.Music", "com.apple.iTunes",
        "com.spotify.client",
        "com.tidal.desktop",
        "com.amazon.music",
        "com.deezer.deezer-desktop",
        "com.qobuz.QobuzDesktop",
        "com.pandora.desktop",
        "com.idagio.desktop",
        "com.kkbox.KKBOX",
        "com.netease.163music",
        "com.tencent.QQMusicMac",
        "app.ytmd",                      // YouTube Music Desktop App
        "uk.co.wearecocoon.YT-Music",    // YT Music
        "ch.laurinbrandner.nuage",       // Nuage, for SoundCloud
        "tv.plex.plexamp",
        "co.brushedtype.doppler-macos",
        "com.swinsian.Swinsian",
        "com.coppertino.Vox",
        "com.audirvana.Audirvana", "com.audirvana.Audirvana-Plus",
        "com.foobar2000.mac",
    ]

    init(bundleID: String) {
        guard !bundleID.isEmpty else { self = .other; return }
        if Self.musicApps.contains(bundleID) { self = .musicApp; return }
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        if let app, Bundle(url: app)?.infoDictionary?["LSApplicationCategoryType"] as? String == "public.app-category.music" {
            self = .musicApp
        } else if Self.isBrowser(bundleID) {
            self = .browser
        } else {
            self = .other
        }
    }

    /// Browsers are the apps that open web links. Their helpers and installed web apps
    /// (like `com.google.Chrome.app.…`) count as the browser.
    private static func isBrowser(_ bundleID: String) -> Bool {
        if bundleID.hasPrefix("com.apple.WebKit") { return true }
        let browsers = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
            .compactMap { Bundle(url: $0)?.bundleIdentifier }
        return browsers.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
    }
}
