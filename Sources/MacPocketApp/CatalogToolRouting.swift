import AppKit
import MacPocketCore

extension PocketModel {
    func openCatalogTool(_ id: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let tab = NetworkTab(rawValue: id) { navigation.open(tab); return }
        if let section = ApplicationsSection(rawValue: id) { applications.section = section; navigation.select(.applications); return }
        switch id {
        case "keep-awake": navigation.select(.power)
        case "command-bar": navigation.open(.commandBar)
        case "shelf": navigation.open(.shelf)
        case "dock-preview": navigation.open(.dockPreview)
        case "practical-tools": navigation.open(.practical)
        case "similar-images": navigation.open(.similarImages)
        case "screen-cleaning": navigation.open(.screenCleaning)
        case "quick-actions": navigation.open(.quickActions)
        case "quit-guard": navigation.open(.quitGuard)
        case "brightness": navigation.open(.brightness)
        case "freezer": navigation.open(.freezer)
        case "screen-grab": navigation.open(.screenGrab)
        case "mouse-buttons": navigation.open(.mouseButtons)
        case "mouse-scroll": navigation.open(.mouseScroll)
        case "audio": navigation.open(.audio)
        case "mixer": navigation.open(.mixer)
        case "recorder": navigation.open(.recorder)
        case "screenshot": navigation.open(.screenshot)
        case "bluetooth-battery": navigation.open(.bluetoothBattery)
        case "displays": navigation.open(.displays)
        case "menu-bar-organizer": navigation.open(.menuBarOrganizer)
        case "cable-impact": navigation.open(.cableImpact)
        case "peripherals": navigation.open(.peripherals)
        case "usb-eject": navigation.open(.usbEject)
        case "disk-health": navigation.open(.diskHealth)
        case "system-data": navigation.open(.systemData)
        case "power-schedule": navigation.open(.powerSchedule)
        case "startup-items": navigation.open(.startupItems)
        case "maintenance": navigation.open(.maintenance)
        case "task-manager": navigation.open(.taskManager)
        case "system-reports": navigation.open(.diagnostics)
        case "window-switcher": navigation.open(.windowSwitcher)
        case "hidden-settings": navigation.open(.hiddenSettings)
        case "clipboard": navigation.open(.clipboard)
        case "window-layout": navigation.open(.windowLayout)
        case "downloads": storage.useRoot(home.appendingPathComponent("Downloads"))
        navigation.select(.storage)
        case "duplicates": storage.scope = .duplicates
        navigation.select(.storage)
        case "large-old": storage.scope = .old
        navigation.select(.storage)
        case "system-junk": navigation.select(.cleanup)
        case "trash": navigation.select(.cleanup)
        default: break
        }
    }
}
