import Foundation
import ServiceManagement

// "Start Glance when I log in." macOS keeps the list of such apps; this
// adds Glance to it or removes it. The entry also shows up in
// System Settings > General > Login Items, where it can be switched off too.
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    // Returns true if the change worked.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }

    // Glance switches "start at login" on by itself the first time an
    // installed copy runs. A copy in a build folder (started from Xcode or
    // by the tests) never does, so no stray login item is created.
    static func shouldEnableAutomatically(bundlePath: String, alreadyDone: Bool) -> Bool {
        !alreadyDone && bundlePath.contains("/Applications/")
    }
}
