import AppKit

/// A window-server space that sits above the lock screen, for windows
/// that must show while the Mac is locked.
///
/// SkyLight is a private framework, so nothing is linked: the handful of
/// calls are looked up with `dlsym` at first use, and if any is missing
/// (a macOS release that renamed or dropped it) `init` returns nil and the
/// feature quietly stays off.
final class SkyLightSpace {
    /// Where the space sits in the stack. 400 is the level the system uses
    /// for Notification Center while the screen is locked.
    private static let level: Int32 = 400

    private struct Functions {
        let mainConnection: @convention(c) () -> Int32
        let createSpace: @convention(c) (Int32, Int32, Int32) -> Int32
        let setLevel: @convention(c) (Int32, Int32, Int32) -> Int32
        let showSpaces: @convention(c) (Int32, CFArray) -> Int32
        let hideSpaces: @convention(c) (Int32, CFArray) -> Int32
        let addWindows: @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
        let destroySpace: @convention(c) (Int32, Int32) -> Int32
    }

    private static let functions: Functions? = {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard
            let mainConnection = symbol("SLSMainConnectionID", as: (@convention(c) () -> Int32).self),
            let createSpace = symbol("SLSSpaceCreate", as: (@convention(c) (Int32, Int32, Int32) -> Int32).self),
            let setLevel = symbol("SLSSpaceSetAbsoluteLevel", as: (@convention(c) (Int32, Int32, Int32) -> Int32).self),
            let showSpaces = symbol("SLSShowSpaces", as: (@convention(c) (Int32, CFArray) -> Int32).self),
            let hideSpaces = symbol("SLSHideSpaces", as: (@convention(c) (Int32, CFArray) -> Int32).self),
            let addWindows = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", as: (@convention(c) (Int32, Int32, CFArray, Int32) -> Int32).self),
            let destroySpace = symbol("SLSSpaceDestroy", as: (@convention(c) (Int32, Int32) -> Int32).self)
        else { return nil }
        return Functions(
            mainConnection: mainConnection,
            createSpace: createSpace,
            setLevel: setLevel,
            showSpaces: showSpaces,
            hideSpaces: hideSpaces,
            addWindows: addWindows,
            destroySpace: destroySpace
        )
    }()

    static var isAvailable: Bool { functions != nil }

    private let api: Functions
    private let connection: Int32
    private let space: Int32

    init?() {
        guard let api = Self.functions else { return nil }
        let connection = api.mainConnection()
        let space = api.createSpace(connection, 1, 0)
        guard space != 0 else { return nil }
        _ = api.setLevel(connection, space, Self.level)
        self.api = api
        self.connection = connection
        self.space = space
    }

    deinit {
        _ = api.hideSpaces(connection, [space] as CFArray)
        _ = api.destroySpace(connection, space)
    }

    /// Moves a window that's already on screen into the space and shows it.
    func add(_ window: NSWindow) {
        _ = api.addWindows(connection, space, [window.windowNumber] as CFArray, 7)
        _ = api.showSpaces(connection, [space] as CFArray)
    }

    func hide() {
        _ = api.hideSpaces(connection, [space] as CFArray)
    }
}
