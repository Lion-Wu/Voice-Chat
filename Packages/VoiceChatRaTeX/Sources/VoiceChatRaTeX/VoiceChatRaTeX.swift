import CoreGraphics
import Foundation

#if os(iOS) && canImport(RaTeXFFI)
import RaTeXFFI
#endif

#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

public struct VoiceChatRaTeXColor: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
        self.alpha = min(1, max(0, alpha))
    }

    var cssHex: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var displayListColor: RaTeXDisplayColor {
        RaTeXDisplayColor(
            r: Float(red),
            g: Float(green),
            b: Float(blue),
            a: Float(alpha)
        )
    }
}

public final class VoiceChatRaTeXFormula: @unchecked Sendable {
    private let renderer: RaTeXDisplayListRenderer

    public var width: CGFloat {
        renderer.width
    }

    public var height: CGFloat {
        renderer.height
    }

    public var depth: CGFloat {
        renderer.depth
    }

    public var totalHeight: CGFloat {
        renderer.totalHeight
    }

    init(displayList: RaTeXDisplayList, fontSize: CGFloat) {
        renderer = RaTeXDisplayListRenderer(displayList: displayList, fontSize: fontSize)
    }

    public func draw(in context: CGContext) {
        renderer.draw(in: context)
    }
}

public final class VoiceChatRaTeXEngine: @unchecked Sendable {
    public static let shared = VoiceChatRaTeXEngine()

    private let nativeLock = NSLock()

    private init() {}

    public func render(
        latex: String,
        displayMode: Bool,
        fontSize: CGFloat,
        color: VoiceChatRaTeXColor
    ) -> VoiceChatRaTeXFormula? {
        guard fontSize.isFinite, fontSize > 0 else { return nil }
        guard latex.count <= VoiceChatRaTeXRenderLimits.maxLatexLength else { return nil }
        guard let displayList = parseDisplayList(
            latex: latex,
            displayMode: displayMode,
            color: color
        ) else {
            return nil
        }
        guard Self.isSafeDisplayList(displayList, fontSize: fontSize) else { return nil }
        let normalizedDisplayList = Self.normalizedDefaultFrameColorIfNeeded(
            in: displayList,
            latex: latex,
            color: color
        )
        guard Self.isSafeDisplayList(normalizedDisplayList, fontSize: fontSize) else { return nil }
        RaTeXFontLoader.ensureLoaded()
        return VoiceChatRaTeXFormula(displayList: normalizedDisplayList, fontSize: fontSize)
    }

    private static func normalizedDefaultFrameColorIfNeeded(
        in displayList: RaTeXDisplayList,
        latex: String,
        color: VoiceChatRaTeXColor
    ) -> RaTeXDisplayList {
        guard latex.contains(#"\boxed"#) || latex.contains(#"\fbox"#) else {
            return displayList
        }

        let replacementColor = color.displayListColor
        var didChange = false
        let items = displayList.items.map { item -> RaTeXDisplayItem in
            guard case let .rect(rect) = item,
                  rect.isLikelyDefaultFrameStroke else {
                return item
            }

            didChange = true
            return .rect(
                RaTeXRect(
                    x: rect.x,
                    y: rect.y,
                    width: rect.width,
                    height: rect.height,
                    color: replacementColor
                )
            )
        }

        guard didChange else { return displayList }
        return RaTeXDisplayList(
            version: displayList.version,
            width: displayList.width,
            height: displayList.height,
            depth: displayList.depth,
            items: items
        )
    }

    private func parseDisplayList(
        latex: String,
        displayMode: Bool,
        color: VoiceChatRaTeXColor
    ) -> RaTeXDisplayList? {
        #if os(iOS) && canImport(RaTeXFFI)
        if let displayList = try? parseNativeDisplayList(
            latex: latex,
            displayMode: displayMode,
            color: color
        ) {
            return displayList
        }
        #endif

        #if canImport(JavaScriptCore)
        let wasmLatex = displayMode ? latex : #"\textstyle{\#(latex)}"#
        return try? RaTeXWasmRuntime.shared.parseDisplayList(
            latex: wasmLatex,
            color: color
        )
        #else
        return nil
        #endif
    }

    #if os(iOS) && canImport(RaTeXFFI)
    private func parseNativeDisplayList(
        latex: String,
        displayMode: Bool,
        color: VoiceChatRaTeXColor
    ) throws -> RaTeXDisplayList {
        nativeLock.lock()
        defer { nativeLock.unlock() }

        var ffiColor = RatexColor(
            r: Float(color.red),
            g: Float(color.green),
            b: Float(color.blue),
            a: Float(color.alpha)
        )
        let result = withUnsafePointer(to: &ffiColor) { colorPointer in
            var options = RatexOptions(
                struct_size: MemoryLayout<RatexOptions>.size,
                display_mode: displayMode ? 1 : 0,
                color: colorPointer
            )
            return ratex_parse_and_layout(latex, &options)
        }

        guard result.error_code == 0, let pointer = result.data else {
            if let errorPointer = ratex_get_last_error() {
                throw VoiceChatRaTeXError.parse(String(cString: errorPointer))
            }
            throw VoiceChatRaTeXError.parse("RaTeX returned no display list")
        }
        defer { ratex_free_display_list(pointer) }

        return try Self.decodeDisplayList(fromCString: pointer)
    }
    #endif

    fileprivate static func decodeDisplayList(from json: String) throws -> RaTeXDisplayList {
        try decodeDisplayList(from: Data(json.utf8))
    }

    private static func decodeDisplayList(fromCString pointer: UnsafePointer<CChar>) throws -> RaTeXDisplayList {
        guard let byteCount = boundedCStringUTF8ByteCount(
            pointer,
            maxBytes: VoiceChatRaTeXRenderLimits.maxDisplayListJSONBytes
        ) else {
            throw VoiceChatRaTeXError.parse("RaTeX display list exceeded the maximum allowed size")
        }
        return try decodeDisplayList(from: Data(bytes: pointer, count: byteCount))
    }

    private static func decodeDisplayList(from data: Data) throws -> RaTeXDisplayList {
        guard data.count <= VoiceChatRaTeXRenderLimits.maxDisplayListJSONBytes else {
            throw VoiceChatRaTeXError.parse("RaTeX display list exceeded the maximum allowed size")
        }
        return try JSONDecoder().decode(RaTeXDisplayList.self, from: data)
    }

    private static func boundedCStringUTF8ByteCount(_ pointer: UnsafePointer<CChar>, maxBytes: Int) -> Int? {
        var count = 0
        while count <= maxBytes {
            if pointer[count] == 0 {
                return count
            }
            count += 1
        }
        return nil
    }

    private static func isSafeDisplayList(_ displayList: RaTeXDisplayList, fontSize: CGFloat) -> Bool {
        guard displayList.items.count <= VoiceChatRaTeXRenderLimits.maxDisplayListItems else {
            return false
        }
        guard displayList.pathCommandCount <= VoiceChatRaTeXRenderLimits.maxPathCommands else {
            return false
        }
        guard displayList.width.isFinite,
              displayList.height.isFinite,
              displayList.depth.isFinite,
              displayList.width >= 0,
              displayList.height >= 0,
              displayList.depth >= 0 else {
            return false
        }

        let width = CGFloat(displayList.width) * fontSize
        let height = CGFloat(displayList.height) * fontSize
        let depth = CGFloat(displayList.depth) * fontSize
        let totalHeight = height + depth
        return width.isFinite &&
            height.isFinite &&
            depth.isFinite &&
            totalHeight.isFinite &&
            width <= VoiceChatRaTeXRenderLimits.maxRenderedWidth &&
            totalHeight <= VoiceChatRaTeXRenderLimits.maxRenderedHeight
    }
}

public enum VoiceChatRaTeXRenderLimits {
    public static let maxLatexLength = 4_096
    public static let maxDisplayListJSONBytes = 1_048_576
    public static let maxDisplayListItems = 4_096
    public static let maxPathCommands = 65_536
    public static let maxRenderedWidth: CGFloat = 8_192
    public static let maxRenderedHeight: CGFloat = 4_096
}

private extension RaTeXRect {
    var isLikelyDefaultFrameStroke: Bool {
        guard color.isOpaqueBlack else { return false }
        let thinDimension = min(abs(width), abs(height))
        let longDimension = max(abs(width), abs(height))
        return thinDimension > 0
            && thinDimension <= 0.08
            && longDimension >= 0.08
    }
}

private extension RaTeXDisplayColor {
    var isOpaqueBlack: Bool {
        let epsilon: Float = 0.002
        return a > 0.01
            && abs(r) <= epsilon
            && abs(g) <= epsilon
            && abs(b) <= epsilon
    }
}

private enum VoiceChatRaTeXError: Error {
    case missingResource(String)
    case parse(String)
    case javascript(String)
}

#if canImport(JavaScriptCore)
private final class RaTeXWasmRuntime: @unchecked Sendable {
    static let shared = RaTeXWasmRuntime()

    private let lock = NSLock()
    private var context: JSContext?
    private var renderFunction: JSValue?
    private var lastException: String?

    private init() {}

    func parseDisplayList(latex: String, color: VoiceChatRaTeXColor) throws -> RaTeXDisplayList {
        lock.lock()
        defer { lock.unlock() }

        let function = try initializedRenderFunction()
        lastException = nil
        let value = function.call(withArguments: [latex, color.cssHex])
        if let lastException {
            throw VoiceChatRaTeXError.javascript(lastException)
        }
        guard let json = value?.toString(), !json.isEmpty else {
            throw VoiceChatRaTeXError.parse("RaTeX WASM returned an empty display list")
        }
        return try VoiceChatRaTeXEngine.decodeDisplayList(from: json)
    }

    private func initializedRenderFunction() throws -> JSValue {
        if let renderFunction {
            return renderFunction
        }

        let context = JSContext()
        guard let context else {
            throw VoiceChatRaTeXError.javascript("JavaScriptCore context could not be created")
        }
        context.exceptionHandler = { [weak self] _, exception in
            self?.lastException = exception?.toString()
        }

        try evaluate(Self.javascriptPrelude, in: context)
        try evaluate(Self.ratexJavaScriptSource(), in: context)
        try initializeWasm(in: context)

        guard let function = context.objectForKeyedSubscript("__ratexRenderLatex"),
              !function.isUndefined else {
            throw VoiceChatRaTeXError.javascript("RaTeX WASM render function was not installed")
        }

        self.context = context
        renderFunction = function
        return function
    }

    private func evaluate(_ script: String, in context: JSContext) throws {
        lastException = nil
        _ = context.evaluateScript(script)
        if let lastException {
            throw VoiceChatRaTeXError.javascript(lastException)
        }
    }

    private func initializeWasm(in context: JSContext) throws {
        guard let wasmURL = Bundle.module.url(
            forResource: "ratex_wasm_bg",
            withExtension: "wasm",
            subdirectory: "Resources/wasm"
        ) ?? Bundle.module.url(
            forResource: "ratex_wasm_bg",
            withExtension: "wasm",
            subdirectory: "wasm"
        ) ?? Bundle.module.url(
            forResource: "ratex_wasm_bg",
            withExtension: "wasm"
        ) else {
            throw VoiceChatRaTeXError.missingResource("ratex_wasm_bg.wasm")
        }

        let base64 = try Data(contentsOf: wasmURL).base64EncodedString()
        context.setObject(base64, forKeyedSubscript: "__ratexWasmBase64" as NSString)
        try evaluate(
            """
            var __ratexBytes = __decodeBase64(__ratexWasmBase64);
            var __ratexModule = new WebAssembly.Module(__ratexBytes.buffer);
            __ratexInitSync({ module: __ratexModule });
            """,
            in: context
        )
    }

    private static func ratexJavaScriptSource() throws -> String {
        guard let jsURL = Bundle.module.url(
            forResource: "ratex_wasm",
            withExtension: "js",
            subdirectory: "Resources/wasm"
        ) ?? Bundle.module.url(
            forResource: "ratex_wasm",
            withExtension: "js",
            subdirectory: "wasm"
        ) ?? Bundle.module.url(
            forResource: "ratex_wasm",
            withExtension: "js"
        ) else {
            throw VoiceChatRaTeXError.missingResource("ratex_wasm.js")
        }

        var source = try String(contentsOf: jsURL, encoding: .utf8)
        source = source.replacingOccurrences(
            of: "export function renderLatex",
            with: "function renderLatex"
        )
        source = source.replacingOccurrences(
            of: "module_or_path = new URL('ratex_wasm_bg.wasm', import.meta.url);",
            with: "throw new Error('async init disabled');"
        )
        source = source.replacingOccurrences(
            of: "export { initSync, __wbg_init as default };",
            with: "globalThis.__ratexInitSync = initSync; globalThis.__ratexRenderLatex = renderLatex;"
        )
        let jsonReturn = "return getStringFromWasm0(ptr3, len3);"
        guard source.contains(jsonReturn) else {
            throw VoiceChatRaTeXError.javascript("RaTeX WASM glue did not expose the expected display-list return boundary")
        }
        source = source.replacingOccurrences(
            of: jsonReturn,
            with: """
            if (len3 > \(VoiceChatRaTeXRenderLimits.maxDisplayListJSONBytes)) {
                throw new Error('RaTeX display list exceeded the maximum allowed size');
            }
            return getStringFromWasm0(ptr3, len3);
            """
        )
        if source.contains("import.meta") {
            throw VoiceChatRaTeXError.javascript("RaTeX WASM glue still contains module-only import.meta syntax")
        }
        return source
    }

    private static let javascriptPrelude = """
    var console = { warn: function(){}, log: function(){}, error: function(){} };
    function TextEncoder(){ }
    TextEncoder.prototype.encode = function(str) {
      var out = [];
      for (var i = 0; i < str.length; i++) {
        var c = str.charCodeAt(i);
        if (c < 128) {
          out.push(c);
        } else if (c < 2048) {
          out.push((c >> 6) | 192);
          out.push((c & 63) | 128);
        } else if ((c & 0xFC00) === 0xD800 && i + 1 < str.length && (str.charCodeAt(i + 1) & 0xFC00) === 0xDC00) {
          var code = 0x10000 + ((c & 0x3FF) << 10) + (str.charCodeAt(++i) & 0x3FF);
          out.push((code >> 18) | 240);
          out.push(((code >> 12) & 63) | 128);
          out.push(((code >> 6) & 63) | 128);
          out.push((code & 63) | 128);
        } else {
          out.push((c >> 12) | 224);
          out.push(((c >> 6) & 63) | 128);
          out.push((c & 63) | 128);
        }
      }
      return new Uint8Array(out);
    };
    TextEncoder.prototype.encodeInto = function(str, view) {
      var bytes = this.encode(str);
      view.set(bytes);
      return { read: str.length, written: bytes.length };
    };
    function TextDecoder(){ }
    TextDecoder.prototype.decode = function(input) {
      if (!input) return '';
      var bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
      var out = '';
      var i = 0;
      while (i < bytes.length) {
        var c = bytes[i++];
        if (c < 128) {
          out += String.fromCharCode(c);
        } else if (c < 224) {
          out += String.fromCharCode(((c & 31) << 6) | (bytes[i++] & 63));
        } else if (c < 240) {
          out += String.fromCharCode(((c & 15) << 12) | ((bytes[i++] & 63) << 6) | (bytes[i++] & 63));
        } else {
          var code = ((c & 7) << 18) | ((bytes[i++] & 63) << 12) | ((bytes[i++] & 63) << 6) | (bytes[i++] & 63);
          code -= 0x10000;
          out += String.fromCharCode(0xD800 + (code >> 10), 0xDC00 + (code & 1023));
        }
      }
      return out;
    };
    function __decodeBase64(input) {
      var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      var out = [];
      var buffer = 0;
      var bits = 0;
      for (var i = 0; i < input.length; i++) {
        var ch = input.charAt(i);
        if (ch === '=') break;
        var value = chars.indexOf(ch);
        if (value < 0) continue;
        buffer = (buffer << 6) | value;
        bits += 6;
        if (bits >= 8) {
          bits -= 8;
          out.push((buffer >> bits) & 255);
        }
      }
      return new Uint8Array(out);
    }
    """
}
#endif
