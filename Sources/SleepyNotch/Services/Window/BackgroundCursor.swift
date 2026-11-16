import AppKit

/// Lets this app set the cursor while another app is frontmost.
///
/// The notch panel never activates the app, and the window server ignores
/// `NSCursor.set()` from an app in the background: the app behind keeps
/// the cursor it last chose (over a search field, the text I-beam, left
/// showing on top of the card). The window server has a per-connection
/// switch for exactly this, "SetsCursorInBackground", turned on once at
/// launch. Private, so it's looked up with `dlsym`; if it's missing the
/// cursor simply behaves as before.
enum BackgroundCursor {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    static func enable() {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY),
              let main = dlsym(handle, "SLSMainConnectionID"),
              let set = dlsym(handle, "SLSSetConnectionProperty")
        else { return }
        let connection = unsafeBitCast(main, to: MainConnection.self)()
        _ = unsafeBitCast(set, to: SetProperty.self)(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}
