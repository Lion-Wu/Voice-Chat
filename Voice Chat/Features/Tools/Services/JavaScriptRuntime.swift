//
//  JavaScriptRuntime.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.24.
//

import Foundation
#if canImport(WebKit)
@preconcurrency import WebKit
#endif

struct JavaScriptExecutionResult: Sendable {
    let value: JavaScriptValue?
    let resultType: String
    let resultDisplay: String?
    let output: String
    let truncated: Bool
}

private struct JavaScriptConsoleSnapshot: Decodable, Sendable {
    let output: String
    let truncated: Bool
}

enum JavaScriptRuntime {
    static let executionTimeoutSeconds: TimeInterval = 60

    private static let maximumCodeCharacters = 256_000
    private static let maximumInputBytes = 4_000_000

    static func evaluate(
        code: String,
        input: [String: Any],
        timeoutSeconds: TimeInterval = executionTimeoutSeconds
    ) async throws -> JavaScriptExecutionResult {
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalidScript("JavaScript code must not be empty.")
        }
        guard code.count <= maximumCodeCharacters else {
            throw invalidScript("JavaScript code must not exceed \(maximumCodeCharacters) characters.")
        }
        guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
            throw ChatToolError.failed("JavaScript execution timed out.")
        }

        let inputJSON = try normalizedInputJSON(input)

        #if canImport(WebKit)
        let session = await JavaScriptWebSession()
        return try await session.execute(
            code: code,
            inputJSON: inputJSON,
            timeoutSeconds: timeoutSeconds
        )
        #else
        throw ChatToolError.unsupported("JavaScript execution is not available on this platform.")
        #endif
    }

    private static func normalizedInputJSON(_ input: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(input),
              let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
              data.count <= maximumInputBytes,
              let json = String(data: data, encoding: .utf8) else {
            throw invalidScript("JavaScript input must be a JSON object no larger than \(maximumInputBytes) bytes.")
        }
        return json
    }

    fileprivate static func executionResult(
        rawResult: Any?,
        console: JavaScriptConsoleSnapshot,
        resultIsUnbridgeable: Bool = false
    ) -> JavaScriptExecutionResult {
        if resultIsUnbridgeable {
            return JavaScriptExecutionResult(
                value: nil,
                resultType: "unavailable",
                resultDisplay: nil,
                output: console.output,
                truncated: console.truncated
            )
        }
        guard let rawResult else {
            return JavaScriptExecutionResult(
                value: nil,
                resultType: "undefined",
                resultDisplay: nil,
                output: console.output,
                truncated: console.truncated
            )
        }
        if String(describing: type(of: rawResult)).localizedCaseInsensitiveContains("undefined") {
            return JavaScriptExecutionResult(
                value: nil,
                resultType: "undefined",
                resultDisplay: nil,
                output: console.output,
                truncated: console.truncated
            )
        }
        if let number = rawResult as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID(),
           !number.doubleValue.isFinite {
            return JavaScriptExecutionResult(
                value: nil,
                resultType: "number",
                resultDisplay: String(describing: number),
                output: console.output,
                truncated: console.truncated
            )
        }
        var snapshot = JavaScriptResultSnapshot()
        do {
            let value = try snapshot.capture(rawResult) ?? .null
            return JavaScriptExecutionResult(
                value: value,
                resultType: value.typeName,
                resultDisplay: nil,
                output: console.output,
                truncated: snapshot.truncated || console.truncated
            )
        } catch {
            return JavaScriptExecutionResult(
                value: nil,
                resultType: "unavailable",
                resultDisplay: String(describing: rawResult),
                output: console.output,
                truncated: console.truncated
            )
        }
    }
}

enum JavaScriptValue: Equatable, Sendable {
    case number(Double)
    case bool(Bool)
    case string(String)
    case array([JavaScriptValue])
    case object([String: JavaScriptValue])
    case null
}

extension JavaScriptValue {
    var typeName: String {
        switch self {
        case .number: return "number"
        case .bool: return "boolean"
        case .string: return "string"
        case .array: return "array"
        case .object: return "object"
        case .null: return "null"
        }
    }

    var jsonValue: JSONValue {
        switch self {
        case let .number(value): return .number(value)
        case let .bool(value): return .bool(value)
        case let .string(value): return .string(value)
        case let .array(values): return .array(values.map(\.jsonValue))
        case let .object(values): return .object(values.mapValues(\.jsonValue))
        case .null: return .null
        }
    }
}

private struct JavaScriptResultSnapshot {
    private var remainingNodes = 4_000
    private var remainingStringUnits = 64_000
    private(set) var truncated = false

    mutating func capture(_ value: Any, depth: Int = 0) throws -> JavaScriptValue? {
        guard remainingNodes > 0 else {
            truncated = true
            return nil
        }
        remainingNodes -= 1

        if value is NSNull {
            return .null
        }
        if let value = value as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            let number = value.doubleValue
            guard number.isFinite else {
                throw invalidScript("The JavaScript result contains a non-finite number.")
            }
            return .number(number)
        }
        if let value = value as? String {
            return .string(captureString(value))
        }
        if let values = value as? [Any] {
            guard depth < 32 else {
                truncated = true
                return .null
            }
            if values.count > 200 {
                truncated = true
            }
            var output: [JavaScriptValue] = []
            output.reserveCapacity(min(values.count, 200))
            for value in values.prefix(200) {
                guard let captured = try capture(value, depth: depth + 1) else { break }
                output.append(captured)
            }
            return .array(output)
        }
        if let values = value as? [String: Any] {
            guard depth < 32 else {
                truncated = true
                return .null
            }
            let keys = values.keys.sorted()
            if keys.count > 200 {
                truncated = true
            }
            var output: [String: JavaScriptValue] = [:]
            output.reserveCapacity(min(keys.count, 200))
            for key in keys.prefix(200) {
                let keyLength = key.utf16.count
                guard keyLength <= remainingStringUnits else {
                    truncated = true
                    break
                }
                remainingStringUnits -= keyLength
                guard let rawValue = values[key],
                      let captured = try capture(rawValue, depth: depth + 1) else { break }
                output[key] = captured
            }
            return .object(output)
        }
        if let value = value as? Date {
            return .string(captureString(ISO8601DateFormatter().string(from: value)))
        }
        throw invalidScript("The JavaScript result contains an unsupported value.")
    }

    private mutating func captureString(_ value: String) -> String {
        let maximumUnits = min(4_000, remainingStringUnits)
        var usedUnits = 0
        var endIndex = value.unicodeScalars.startIndex
        while endIndex < value.unicodeScalars.endIndex {
            let scalar = value.unicodeScalars[endIndex]
            let scalarUnits = scalar.value > 0xFFFF ? 2 : 1
            guard usedUnits + scalarUnits <= maximumUnits else { break }
            usedUnits += scalarUnits
            endIndex = value.unicodeScalars.index(after: endIndex)
        }
        remainingStringUnits -= usedUnits
        if endIndex < value.unicodeScalars.endIndex {
            truncated = true
        }
        return String(value.unicodeScalars[..<endIndex])
    }
}

#if canImport(WebKit)
@MainActor
private final class JavaScriptWebSession: NSObject, WKNavigationDelegate {
    private let contentWorld = WKContentWorld.world(name: "VoiceChatJavaScriptRuntime")
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<JavaScriptExecutionResult, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var setupScript = ""
    private var userCode = ""
    private var didStartEvaluation = false

    func execute(
        code: String,
        inputJSON: String,
        timeoutSeconds: TimeInterval
    ) async throws -> JavaScriptExecutionResult {
        setupScript = try Self.setupScript(inputJSON: inputJSON)
        userCode = code

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                startWebView()
                timeoutTask = Task { @MainActor [weak self] in
                    let nanoseconds = UInt64(min(timeoutSeconds, 86_400) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    guard !Task.isCancelled else { return }
                    self?.finish(.failure(ChatToolError.failed(
                        String(format: "JavaScript execution timed out after %.0f seconds.", timeoutSeconds)
                    )))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    private func startWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        webView.loadHTMLString(Self.sandboxDocument, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !didStartEvaluation else { return }
        didStartEvaluation = true

        webView.evaluateJavaScript(
            setupScript,
            in: nil,
            in: contentWorld
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                evaluateUserCode(in: webView)
            case let .failure(error):
                completeException(error)
            }
        }
    }

    private func evaluateUserCode(in webView: WKWebView) {
        webView.evaluateJavaScript(
            userCode,
            in: nil,
            in: contentWorld
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(value):
                completeEvaluation(rawResult: value)
            case let .failure(error):
                if Self.isUnsupportedResultError(error) {
                    completeEvaluation(rawResult: nil, resultIsUnbridgeable: true)
                } else {
                    completeException(error)
                }
            }
        }
    }

    private func completeEvaluation(rawResult: Any?, resultIsUnbridgeable: Bool = false) {
        readConsoleSnapshot { [weak self] snapshotResult in
            guard let self else { return }
            switch snapshotResult {
            case let .success(snapshot):
                finish(.success(JavaScriptRuntime.executionResult(
                    rawResult: rawResult,
                    console: snapshot,
                    resultIsUnbridgeable: resultIsUnbridgeable
                )))
            case let .failure(error):
                finish(.failure(error))
            }
        }
    }

    private func completeException(_ error: Error) {
        readConsoleSnapshot { [weak self] snapshotResult in
            guard let self else { return }
            let console = try? snapshotResult.get()
            finish(.failure(Self.scriptError(from: error, console: console)))
        }
    }

    private func readConsoleSnapshot(
        completion: @escaping (Result<JavaScriptConsoleSnapshot, Error>) -> Void
    ) {
        guard let webView else {
            completion(.failure(ChatToolError.failed("The JavaScript console output is unavailable.")))
            return
        }
        webView.evaluateJavaScript(
            Self.consoleSnapshotScript,
            in: nil,
            in: contentWorld
        ) { result in
            switch result {
            case let .success(value as String):
                do {
                    guard let data = value.data(using: .utf8) else {
                        throw ChatToolError.failed("The JavaScript console output could not be decoded.")
                    }
                    completion(.success(try JSONDecoder().decode(JavaScriptConsoleSnapshot.self, from: data)))
                } catch {
                    completion(.failure(error))
                }
            case .success:
                completion(.failure(ChatToolError.failed("The JavaScript console output could not be decoded.")))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(ChatToolError.failed(error.localizedDescription)))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(ChatToolError.failed(error.localizedDescription)))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure(ChatToolError.failed("The isolated JavaScript process terminated.")))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        decisionHandler(url == nil || url?.scheme == "about" ? .allow : .cancel)
    }

    private func finish(_ result: Result<JavaScriptExecutionResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        continuation.resume(with: result)
    }

    private static func isUnsupportedResultError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == WKError.errorDomain
            && nsError.code == WKError.javaScriptResultTypeIsUnsupported.rawValue
    }

    private static func scriptError(
        from error: Error,
        console: JavaScriptConsoleSnapshot?
    ) -> ChatToolError {
        let nsError = error as NSError
        guard nsError.domain == WKError.errorDomain,
              nsError.code == WKError.javaScriptExceptionOccurred.rawValue else {
            return .failed(nsError.localizedDescription)
        }

        let rawMessage = nsError.userInfo["WKJavaScriptExceptionMessage"] as? String
        let line = (nsError.userInfo["WKJavaScriptExceptionLineNumber"] as? NSNumber)?.intValue
        let column = (nsError.userInfo["WKJavaScriptExceptionColumnNumber"] as? NSNumber)?.intValue
        let source = nsError.userInfo["WKJavaScriptExceptionSourceURL"]
            .map { String(describing: $0) }
            .flatMap { $0 == "about:blank" ? nil : $0 }

        var details = [rawMessage ?? nsError.localizedDescription]
        if let line, let column {
            details.append("Line \(line), column \(column)")
        } else if let line {
            details.append("Line \(line)")
        }
        if let source, !source.isEmpty {
            details.append("Source: \(source)")
        }
        if let console, !console.output.isEmpty {
            details.append("Console output before the exception:\n\(console.output)")
        }
        return invalidScript(details.joined(separator: "\n"))
    }

    private static let sandboxDocument = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; connect-src 'none'; img-src 'none'; media-src 'none'; font-src 'none'; style-src 'none'; object-src 'none'; frame-src 'none'; child-src 'none'; worker-src 'none'; manifest-src 'none'; base-uri 'none'; form-action 'none'">
    </head>
    <body></body>
    </html>
    """

    private static let consoleSnapshotScript = """
    this.__voiceChatJavaScriptConsoleSnapshot__()
    """

    private static func setupScript(inputJSON: String) throws -> String {
        let encodedInputData = try JSONEncoder().encode(inputJSON)
        guard let encodedInput = String(data: encodedInputData, encoding: .utf8) else {
            throw ChatToolError.failed("The JavaScript input could not be encoded.")
        }
        return #"""
    {
    const input = JSON.parse(\#(encodedInput));
    const __voiceChatNativeJSONStringify = JSON.stringify.bind(JSON);
    const __voiceChatNativeString = String;
    const __voiceChatConsoleLines = [];
    let __voiceChatConsoleUnits = 0;
    let __voiceChatConsoleTruncated = false;
    const __voiceChatFormatConsoleValue = value => {
      if (typeof value === "string") return value;
      if (typeof value === "undefined") return "undefined";
      if (typeof value === "function") return `[Function${value.name ? `: ${value.name}` : ""}]`;
      if (typeof value === "symbol" || typeof value === "bigint") return __voiceChatNativeString(value);
      if (value instanceof Error) return `${value.name}: ${value.message}`;
      const seen = new WeakSet();
      try {
        const encoded = __voiceChatNativeJSONStringify(value, (_, nested) => {
          if (typeof nested === "bigint" || typeof nested === "symbol") return __voiceChatNativeString(nested);
          if (typeof nested === "function") return `[Function${nested.name ? `: ${nested.name}` : ""}]`;
          if (typeof nested === "undefined") return "undefined";
          if (nested !== null && typeof nested === "object") {
            if (seen.has(nested)) return "[Circular]";
            seen.add(nested);
          }
          return nested;
        });
        return encoded === undefined ? __voiceChatNativeString(value) : encoded;
      } catch (_) {
        try {
          return __voiceChatNativeString(value);
        } catch (_) {
          return "[Unprintable]";
        }
      }
    };
    const __voiceChatWriteConsole = (level, values) => {
      if (__voiceChatConsoleLines.length >= 200 || __voiceChatConsoleUnits >= 64000) {
        __voiceChatConsoleTruncated = true;
        return;
      }
      const prefix = level === "log" ? "" : `[${level}] `;
      const line = prefix + values.map(__voiceChatFormatConsoleValue).join(" ");
      const available = Math.min(4000, 64000 - __voiceChatConsoleUnits);
      const visible = line.slice(0, available);
      __voiceChatConsoleLines.push(visible);
      __voiceChatConsoleUnits += visible.length;
      if (visible.length < line.length) __voiceChatConsoleTruncated = true;
    };
    const __voiceChatConsole = Object.freeze({
      log: (...values) => __voiceChatWriteConsole("log", values),
      info: (...values) => __voiceChatWriteConsole("info", values),
      warn: (...values) => __voiceChatWriteConsole("warn", values),
      error: (...values) => __voiceChatWriteConsole("error", values)
    });
    Object.defineProperty(this, "console", {
      value: __voiceChatConsole,
      writable: false,
      configurable: false
    });
    Object.defineProperty(this, "print", {
      value: (...values) => __voiceChatWriteConsole("log", values),
      writable: false,
      configurable: false
    });
    Object.defineProperty(this, "__voiceChatJavaScriptConsoleSnapshot__", {
      value: () => __voiceChatNativeJSONStringify({
        output: __voiceChatConsoleLines.join("\n"),
        truncated: __voiceChatConsoleTruncated
      }),
      writable: false,
      configurable: false
    });
    const numbers = (values, name) => {
      if (!Array.isArray(values) || values.some(value => typeof value !== "number" || !Number.isFinite(value))) {
        throw new TypeError(`${name} requires an array of finite numbers.`);
      }
      return values;
    };
    const finite = (value, name) => {
      if (typeof value !== "number" || !Number.isFinite(value)) {
        throw new RangeError(`${name} produced a non-finite number.`);
      }
      return value;
    };
    const sum = values => finite(numbers(values, "sum").reduce((total, value) => total + value, 0), "sum");
    const product = values => finite(numbers(values, "product").reduce((total, value) => total * value, 1), "product");
    const mean = values => {
      const checked = numbers(values, "mean");
      if (checked.length === 0) throw new RangeError("mean requires a nonempty array.");
      return finite(sum(checked) / checked.length, "mean");
    };
    const median = values => {
      const checked = [...numbers(values, "median")].sort((left, right) => left - right);
      if (checked.length === 0) throw new RangeError("median requires a nonempty array.");
      const middle = Math.floor(checked.length / 2);
      if (checked.length % 2 !== 0) return checked[middle];
      const lower = checked[middle - 1];
      const upper = checked[middle];
      return finite(Math.sign(lower) === Math.sign(upper) ? lower + (upper - lower) / 2 : (lower + upper) / 2, "median");
    };
    const stdev = values => {
      const checked = numbers(values, "stdev");
      if (checked.length === 0) throw new RangeError("stdev requires a nonempty array.");
      const average = mean(checked);
      return finite(Math.sqrt(checked.reduce((total, value) => total + (value - average) ** 2, 0) / checked.length), "stdev");
    };
    const percentile = (values, requestedPercentile) => {
      const checked = [...numbers(values, "percentile")].sort((left, right) => left - right);
      if (checked.length === 0 || !Number.isFinite(requestedPercentile) || requestedPercentile < 0 || requestedPercentile > 100) {
        throw new RangeError("percentile requires a nonempty array and a percentile from 0 to 100.");
      }
      const rank = requestedPercentile / 100 * (checked.length - 1);
      const lower = Math.floor(rank);
      const upper = Math.ceil(rank);
      return finite(lower === upper ? checked[lower] : checked[lower] + (checked[upper] - checked[lower]) * (rank - lower), "percentile");
    };
    const range = (start, end, step = start <= end ? 1 : -1) => {
      if (![start, end, step].every(Number.isFinite) || step === 0) {
        throw new RangeError("range requires finite start/end values and a nonzero step.");
      }
      const output = [];
      for (let value = start; step > 0 ? value <= end : value >= end; value += step) {
        output.push(finite(value, "range"));
      }
      return output;
    };
    const round = (value, digits = 0) => {
      if (!Number.isInteger(digits) || digits < -15 || digits > 15) {
        throw new RangeError("round digits must be an integer from -15 to 15.");
      }
      const scale = 10 ** digits;
      return finite(Math.round(value * scale) / scale, "round");
    };
    const abs = Math.abs;
    const sqrt = Math.sqrt;
    const floor = Math.floor;
    const ceil = Math.ceil;
    const sin = Math.sin;
    const cos = Math.cos;
    const tan = Math.tan;
    const asin = Math.asin;
    const acos = Math.acos;
    const atan = Math.atan;
    const log = Math.log;
    const log10 = Math.log10;
    const exp = Math.exp;
    const pow = Math.pow;
    const min = Math.min;
    const max = Math.max;
    const pi = Math.PI;
    const e = Math.E;

    const functionPrototypes = [
      Function.prototype,
      Object.getPrototypeOf(async function () {}),
      Object.getPrototypeOf(function* () {}),
      Object.getPrototypeOf(async function* () {})
    ];
    for (const prototype of functionPrototypes) {
      try {
        Object.defineProperty(prototype, "constructor", { value: undefined, writable: false, configurable: false });
      } catch (_) {}
    }
    const unavailableGlobals = [
      "eval", "Function", "WebAssembly", "fetch", "XMLHttpRequest", "WebSocket", "EventSource",
      "Worker", "SharedWorker", "indexedDB", "caches", "localStorage", "sessionStorage", "webkit",
      "FileReader", "Image", "Audio", "open", "alert", "confirm", "prompt", "setTimeout", "setInterval",
      "requestAnimationFrame", "require", "module", "process", "Deno", "globalThis", "window", "self",
      "top", "parent", "frames", "document", "location", "navigator"
    ];
    for (const name of unavailableGlobals) {
      try {
        Object.defineProperty(this, name, { value: undefined, writable: false, configurable: false });
      } catch (_) {}
    }
    const publicBindings = {
      input, sum, product, mean, median, stdev, percentile, range, round,
      abs, sqrt, floor, ceil, sin, cos, tan, asin, acos, atan, log, log10,
      exp, pow, min, max, pi, e
    };
    for (const [name, value] of Object.entries(publicBindings)) {
      Object.defineProperty(this, name, { value, writable: false, configurable: false });
    }
    }
    true;
    """#
    }
}
#endif

private func invalidScript(_ message: String) -> ChatToolError {
    ChatToolError.invalidArguments(message)
}
