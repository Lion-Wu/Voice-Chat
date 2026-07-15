//
//  CodeInterpreterRuntime.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.24.
//

import Foundation
#if canImport(WebKit)
@preconcurrency import WebKit
#endif

struct CodeInterpreterExecutionResult: Sendable {
    let value: CodeInterpreterValue
    let truncated: Bool
}

enum CodeInterpreterRuntime {
    static let executionTimeoutSeconds: TimeInterval = 60

    private static let maximumCodeCharacters = 64_000
    private static let maximumInputBytes = 1_000_000

    static func evaluate(
        code: String,
        input: [String: Any],
        timeoutSeconds: TimeInterval = executionTimeoutSeconds
    ) async throws -> CodeInterpreterExecutionResult {
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalidScript("Interpreter code must not be empty.")
        }
        guard code.count <= maximumCodeCharacters else {
            throw invalidScript("Interpreter code is too long.")
        }
        guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
            throw ChatToolError.failed("Code execution timed out.")
        }

        let inputJSON = try normalizedInputJSON(input)

        #if canImport(WebKit)
        let session = await CodeInterpreterWebSession()
        let envelopeJSON = try await session.execute(
            code: code,
            inputJSON: inputJSON,
            timeoutSeconds: timeoutSeconds
        )
        return try decodeEnvelope(envelopeJSON)
        #else
        throw ChatToolError.unsupported("JavaScript execution is not available on this platform.")
        #endif
    }

    private static func normalizedInputJSON(_ input: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(input),
              let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
              data.count <= maximumInputBytes,
              let json = String(data: data, encoding: .utf8) else {
            throw invalidScript("Interpreter input must be a JSON object no larger than 1000000 bytes.")
        }
        return json
    }

    private static func decodeEnvelope(_ json: String) throws -> CodeInterpreterExecutionResult {
        guard let data = json.data(using: .utf8),
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChatToolError.failed("The JavaScript result could not be decoded.")
        }
        if let error = envelope["error"] as? [String: Any] {
            let name = (error["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = (error["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = [name, message]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ": ")
            throw invalidScript(description.isEmpty ? "JavaScript execution failed." : description)
        }
        guard let rawResult = envelope["result"],
              let truncated = envelope["truncated"] as? Bool else {
            throw ChatToolError.failed("The JavaScript result could not be decoded.")
        }

        return CodeInterpreterExecutionResult(
            value: try CodeInterpreterValue(jsonObject: rawResult),
            truncated: truncated
        )
    }
}

enum CodeInterpreterValue: Equatable, Sendable {
    case number(Double)
    case bool(Bool)
    case string(String)
    case array([CodeInterpreterValue])
    case object([String: CodeInterpreterValue])
    case null
}

extension CodeInterpreterValue {
    fileprivate init(jsonObject: Any, depth: Int = 0) throws {
        guard depth <= 32 else {
            throw ChatToolError.failed("The JavaScript result is nested too deeply.")
        }

        if jsonObject is NSNull {
            self = .null
        } else if let value = jsonObject as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                let number = value.doubleValue
                guard number.isFinite else {
                    throw ChatToolError.failed("The JavaScript result contains a non-finite number.")
                }
                self = .number(number)
            }
        } else if let value = jsonObject as? String {
            self = .string(value)
        } else if let values = jsonObject as? [Any] {
            self = .array(try values.map { try Self(jsonObject: $0, depth: depth + 1) })
        } else if let object = jsonObject as? [String: Any] {
            self = .object(try object.reduce(into: [:]) { output, item in
                output[item.key] = try Self(jsonObject: item.value, depth: depth + 1)
            })
        } else {
            throw ChatToolError.failed("The JavaScript result contains an unsupported value.")
        }
    }

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

#if canImport(WebKit)
@MainActor
private final class CodeInterpreterWebSession: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var code = ""
    private var inputJSON = "{}"
    private var didStartEvaluation = false

    func execute(
        code: String,
        inputJSON: String,
        timeoutSeconds: TimeInterval
    ) async throws -> String {
        self.code = code
        self.inputJSON = inputJSON

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                startWebView()
                timeoutTask = Task { @MainActor [weak self] in
                    let nanoseconds = UInt64(min(timeoutSeconds, 86_400) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    guard !Task.isCancelled else { return }
                    self?.finish(.failure(ChatToolError.failed(
                        String(format: "Code execution timed out after %.0f seconds.", timeoutSeconds)
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

        webView.callAsyncJavaScript(
            Self.executionBody,
            arguments: ["code": code, "inputJSON": inputJSON],
            in: nil,
            in: .world(name: "VoiceChatCodeInterpreter")
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(value as String):
                finish(.success(value))
            case .success:
                finish(.failure(ChatToolError.failed("The JavaScript result was not serializable.")))
            case let .failure(error):
                finish(.failure(Self.scriptError(from: error)))
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

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        continuation.resume(with: result)
    }

    private static func scriptError(from error: Error) -> ChatToolError {
        let nsError = error as NSError
        if nsError.domain == WKError.errorDomain,
           nsError.code == WKError.javaScriptExceptionOccurred.rawValue {
            return invalidScript(nsError.localizedDescription)
        }
        return .failed(nsError.localizedDescription)
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

    private static let executionBody = #"""
    const nativeFunction = Function;
    const nativeString = String;
    const nativeJSONParse = JSON.parse.bind(JSON);
    const nativeJSONStringify = JSON.stringify.bind(JSON);
    try {
    const functionParameters = [
      "input", "sum", "product", "mean", "median", "stdev", "percentile", "range", "round",
      "abs", "sqrt", "floor", "ceil", "sin", "cos", "tan", "asin", "acos", "atan",
      "log", "log10", "exp", "pow", "min", "max", "pi", "e",
      "globalThis", "window", "self", "top", "parent", "frames", "document", "location", "navigator",
      "fetch", "XMLHttpRequest", "WebSocket", "EventSource", "Worker", "SharedWorker",
      "indexedDB", "caches", "localStorage", "sessionStorage", "webkit", "FileReader",
      "Image", "Audio", "open", "alert", "confirm", "prompt", "setTimeout", "setInterval",
      "requestAnimationFrame", "require", "module", "process", "Deno", "Function"
    ];

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

    const runner = nativeFunction(...functionParameters, `"use strict";\n${code}`);

    const functionPrototypes = [
      nativeFunction.prototype,
      Object.getPrototypeOf(async function () {}),
      Object.getPrototypeOf(function* () {}),
      Object.getPrototypeOf(async function* () {})
    ];
    for (const prototype of functionPrototypes) {
      try {
        Object.defineProperty(prototype, "constructor", { value: undefined, writable: false, configurable: false });
      } catch (_) {}
    }
    try { Object.defineProperty(globalThis, "eval", { value: undefined, writable: false, configurable: false }); } catch (_) {}
    try { Object.defineProperty(globalThis, "Function", { value: undefined, writable: false, configurable: false }); } catch (_) {}
    try { Object.defineProperty(globalThis, "WebAssembly", { value: undefined, writable: false, configurable: false }); } catch (_) {}

    const input = nativeJSONParse(inputJSON);
    const helpers = [
      input, sum, product, mean, median, stdev, percentile, range, round,
      abs, sqrt, floor, ceil, sin, cos, tan, asin, acos, atan,
      log, log10, exp, pow, min, max, pi, e
    ];
    while (helpers.length < functionParameters.length) helpers.push(undefined);
    const result = runner(...helpers);

    let truncated = false;
    let remainingNodes = 4000;
    let remainingStringUnits = 64000;
    const ancestors = new WeakSet();
    const nodeLimitReached = Symbol("nodeLimitReached");
    const snapshot = (value, depth = 0) => {
      if (remainingNodes <= 0) {
        truncated = true;
        return nodeLimitReached;
      }
      remainingNodes -= 1;
      if (depth >= 32 && value !== null && typeof value === "object") {
        truncated = true;
        return null;
      }
      if (value === null || typeof value === "boolean") return value;
      if (typeof value === "number") {
        if (!Number.isFinite(value)) throw new RangeError("The result contains a non-finite number.");
        return value;
      }
      if (typeof value === "string") {
        const visibleLength = Math.min(value.length, 4000, remainingStringUnits);
        const visible = value.slice(0, visibleLength);
        remainingStringUnits -= visibleLength;
        if (visibleLength < value.length) truncated = true;
        return visible;
      }
      if (["undefined", "function", "symbol", "bigint"].includes(typeof value)) {
        throw new TypeError("The result must contain only JSON-compatible values.");
      }
      if (value instanceof Promise || (value && typeof value.then === "function")) {
        throw new TypeError("Asynchronous JavaScript results are not supported.");
      }
      if (value instanceof Date) {
        if (!Number.isFinite(value.getTime())) throw new RangeError("The result contains an invalid date.");
        return value.toISOString();
      }
      if (ancestors.has(value)) throw new TypeError("The result contains a circular reference.");
      ancestors.add(value);
      try {
        if (Array.isArray(value) || ArrayBuffer.isView(value)) {
          const count = Math.min(value.length, 200);
          if (count < value.length) truncated = true;
          const output = [];
          for (let index = 0; index < count; index += 1) {
            const nested = snapshot(value[index], depth + 1);
            if (nested === nodeLimitReached) break;
            output.push(nested);
          }
          return output;
        }
        if (value instanceof Map) return snapshot(Array.from(value.entries()), depth + 1);
        if (value instanceof Set) return snapshot(Array.from(value.values()), depth + 1);

        const prototype = Object.getPrototypeOf(value);
        if (prototype !== Object.prototype && prototype !== null) {
          throw new TypeError("The result contains a non-JSON object.");
        }
        const keys = Object.keys(value).sort();
        const count = Math.min(keys.length, 200);
        if (count < keys.length) truncated = true;
        const output = {};
        for (let index = 0; index < count; index += 1) {
          const key = keys[index];
          if (key.length > remainingStringUnits) {
            truncated = true;
            break;
          }
          remainingStringUnits -= key.length;
          const nested = snapshot(value[key], depth + 1);
          if (nested === nodeLimitReached) break;
          output[key] = nested;
        }
        return output;
      } finally {
        ancestors.delete(value);
      }
    };

    const boundedResult = snapshot(result);
    return nativeJSONStringify({ result: boundedResult === nodeLimitReached ? null : boundedResult, truncated });
    } catch (error) {
      const name = error && typeof error.name === "string" ? error.name : "Error";
      const message = error && typeof error.message === "string" ? error.message : nativeString(error);
      return nativeJSONStringify({ error: { name, message } });
    }
    """#
}
#endif

private func invalidScript(_ message: String) -> ChatToolError {
    ChatToolError.invalidArguments(message)
}
