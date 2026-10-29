import AppKit

/// The menu bar the app shows while the Settings window makes it a regular
/// app: the standard app, Edit and Window menus. Without them ⌘Q, ⌘W, ⌘, and
/// copy and paste in the search field would do nothing, because AppKit
/// routes those shortcuts through the menu bar.
@MainActor
enum MainMenu {
    static func make(settingsTarget: AnyObject, settingsAction: Selector) -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu(settingsTarget: settingsTarget, settingsAction: settingsAction)))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(windowMenu()))
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func appMenu(settingsTarget: AnyObject, settingsAction: Selector) -> NSMenu {
        let menu = NSMenu(title: "Sleepy Notch")
        menu.addItem(withTitle: "About Sleepy Notch",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "Settings…", action: settingsAction, keyEquivalent: ",")
        settings.target = settingsTarget
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Sleepy Notch",
                     action: #selector(NSApplication.hide(_:)),
                     keyEquivalent: "h")
        let hideOthers = menu.addItem(withTitle: "Hide Others",
                                      action: #selector(NSApplication.hideOtherApplications(_:)),
                                      keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All",
                     action: #selector(NSApplication.unhideAllApplications(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sleepy Notch",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = menu
        return menu
    }
}
