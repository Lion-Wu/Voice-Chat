#if os(macOS)
import AppKit

/// Presents the shared macOS Settings window so that all entry points stay consistent.
enum MacSettingsPresenter {
    static func present() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
#endif
