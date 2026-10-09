import AppKit

/// Tells whether a display is showing a fullscreen app, and which one.
///
/// Native fullscreen apps live in their own Space, which the window server (SkyLight) reports
/// as type 4. Some apps (games, a few video players) fake fullscreen with an ordinary window
/// that covers the whole display, menu bar included, so that is checked as well.
@MainActor
enum FullscreenDetector {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CurrentSpace = @convention(c) (Int32, CFString) -> UInt64
    private typealias SpaceType = @convention(c) (Int32, UInt64) -> Int32

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let mainConnection: MainConnection? = symbol("SLSMainConnectionID")
    private static let currentSpace: CurrentSpace? = symbol("SLSManagedDisplayGetCurrentSpace")
    private static let spaceType: SpaceType? = symbol("SLSSpaceGetType")
    private static let fullscreenSpaceType: Int32 = 4

    private static func symbol<T>(_ name: String) -> T? {
        guard let skyLight, let pointer = dlsym(skyLight, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    /// Bundle identifier of the fullscreen app on the display ("" when it can't be told),
    /// or nil when the display isn't showing a fullscreen app.
    static func fullscreenApp(on screen: NSScreen) -> String? {
        let front = frontWindow(on: screen)
        // A window that covers the whole display only counts as fake fullscreen when its app is
        // the one in front, so overlays from background utilities are never mistaken for it.
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let coversDisplay = front.map {
            $0.pid == frontmostPID && $0.bounds.contains(windowRect(of: screen).insetBy(dx: 1, dy: 1))
        } ?? false
        guard isFullscreenSpace(screen.displayID) || coversDisplay else { return nil }
        guard let pid = front?.pid else { return "" }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
    }

    private static func isFullscreenSpace(_ displayID: CGDirectDisplayID) -> Bool {
        guard let mainConnection, let currentSpace, let spaceType,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let uuidString = CFUUIDCreateString(nil, uuid)
        else { return false }
        let connection = mainConnection()
        return spaceType(connection, currentSpace(connection, uuidString)) == fullscreenSpaceType
    }

    /// The frontmost ordinary window on the display that belongs to a regular (Dock) app.
    /// Cranny's own windows, menu bar utilities and transparent overlays are skipped.
    private static func frontWindow(on screen: NSScreen) -> (pid: pid_t, bounds: CGRect)? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let target = windowRect(of: screen)
        for info in windows {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != getpid(),
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width > 100, bounds.height > 100, bounds.intersects(target)
            else { continue }
            return (pid, bounds)
        }
        return nil
    }

    /// The screen's frame in window-server coordinates (top-left origin on the main display).
    private static func windowRect(of screen: NSScreen) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        return CGRect(x: screen.frame.minX, y: mainHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
    }
}
