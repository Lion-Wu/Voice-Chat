import CoreText
import Foundation

public enum RaTeXFontLoader {
    private final class LoadState: @unchecked Sendable {
        let lock = NSLock()
        var didEnsureLoad = false
    }

    private static let loadState = LoadState()

    private static let fontFileNames = [
        "KaTeX_AMS-Regular",
        "KaTeX_Caligraphic-Bold",
        "KaTeX_Caligraphic-Regular",
        "KaTeX_Fraktur-Bold",
        "KaTeX_Fraktur-Regular",
        "KaTeX_Main-Bold",
        "KaTeX_Main-BoldItalic",
        "KaTeX_Main-Italic",
        "KaTeX_Main-Regular",
        "KaTeX_Math-BoldItalic",
        "KaTeX_Math-Italic",
        "KaTeX_SansSerif-Bold",
        "KaTeX_SansSerif-Italic",
        "KaTeX_SansSerif-Regular",
        "KaTeX_Script-Regular",
        "KaTeX_Size1-Regular",
        "KaTeX_Size2-Regular",
        "KaTeX_Size3-Regular",
        "KaTeX_Size4-Regular",
        "KaTeX_Typewriter-Regular"
    ]

    @discardableResult
    public static func ensureLoaded() -> Int {
        loadState.lock.lock()
        defer { loadState.lock.unlock() }
        if loadState.didEnsureLoad { return 0 }

        let loadedFontCount = loadFromPackageBundle()
        loadState.didEnsureLoad = true
        return loadedFontCount
    }

    @discardableResult
    public static func preload() async -> Int {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: ensureLoaded())
            }
        }
    }

    public static func isFontRegistered(_ postScriptName: String) -> Bool {
        #if os(macOS)
        return false
        #else
        let descriptors = CTFontManagerCopyRegisteredFontDescriptors(.process, false) as NSArray
        for item in descriptors {
            let descriptor = item as! CTFontDescriptor
            if let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
               name == postScriptName {
                return true
            }
        }
        return false
        #endif
    }

    @discardableResult
    private static func loadFromPackageBundle() -> Int {
        var loaded = 0
        for fontName in fontFileNames {
            guard let url = fontURL(named: fontName), register(url) else { continue }
            loaded += 1
        }
        return loaded
    }

    private static func fontURL(named name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Resources/fonts")
            ?? Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "fonts")
            ?? Bundle.module.url(forResource: name, withExtension: "ttf")
    }

    private static func register(_ url: URL) -> Bool {
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !ok, let retained = error?.takeRetainedValue() {
            let description = CFErrorCopyDescription(retained) as String
            if description.localizedCaseInsensitiveContains("already") ||
                description.localizedCaseInsensitiveContains("duplicate") {
                return false
            }
        }
        return ok
    }
}
