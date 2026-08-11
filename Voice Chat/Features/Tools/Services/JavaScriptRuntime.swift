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
    let value: JSONValue?
    let resultType: String
    let resultDisplay: String?
    let output: String
    let truncated: Bool
}

private struct JavaScriptConsoleSnapshot: Decodable, Sendable {
    let output: String
    let truncated: Bool
}

private struct JavaScriptResultSnapshot: Decodable, Sendable {
    let result: JSONValue?
    let resultType: String?
    let resultDisplay: String?
    let exception: JavaScriptExceptionSnapshot?
    let truncated: Bool
}

private struct JavaScriptExceptionSnapshot: Decodable, Sendable {
    let message: String
    let line: Int?
    let column: Int?
    let source: String?
    let stack: String?
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

}

#if canImport(WebKit)
@MainActor
private final class JavaScriptWebSession: NSObject, WKNavigationDelegate {
    private let contentWorld = WKContentWorld.world(name: "VoiceChatJavaScriptRuntime")
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<JavaScriptExecutionResult, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var executionScript = ""
    private var didStartEvaluation = false

    func execute(
        code: String,
        inputJSON: String,
        timeoutSeconds: TimeInterval
    ) async throws -> JavaScriptExecutionResult {
        executionScript = try Self.executionScript(code: code, inputJSON: inputJSON)

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
        evaluateUserCode(in: webView)
    }

    private func evaluateUserCode(in webView: WKWebView) {
        webView.evaluateJavaScript(
            executionScript,
            in: nil,
            in: contentWorld
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(snapshotJSON as String):
                completeEvaluation(snapshotJSON: snapshotJSON)
            case .success:
                finish(.failure(ChatToolError.failed(
                    "The bounded JavaScript result snapshot could not be decoded."
                )))
            case let .failure(error):
                completeException(error)
            }
        }
    }

    private func completeEvaluation(snapshotJSON: String) {
        let snapshot: JavaScriptResultSnapshot
        do {
            guard let data = snapshotJSON.data(using: .utf8) else {
                throw ChatToolError.failed("The bounded JavaScript result snapshot could not be decoded.")
            }
            snapshot = try JSONDecoder().decode(JavaScriptResultSnapshot.self, from: data)
        } catch {
            finish(.failure(error))
            return
        }

        readConsoleSnapshot { [weak self] snapshotResult in
            guard let self else { return }
            switch snapshotResult {
            case let .success(console):
                if let exception = snapshot.exception {
                    finish(.failure(Self.scriptError(from: exception, console: console)))
                    return
                }
                guard let resultType = snapshot.resultType else {
                    finish(.failure(ChatToolError.failed(
                        "The bounded JavaScript result snapshot could not be decoded."
                    )))
                    return
                }
                finish(.success(JavaScriptExecutionResult(
                    value: snapshot.result,
                    resultType: resultType,
                    resultDisplay: snapshot.resultDisplay,
                    output: console.output,
                    truncated: snapshot.truncated || console.truncated
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

    private static func scriptError(
        from exception: JavaScriptExceptionSnapshot,
        console: JavaScriptConsoleSnapshot
    ) -> ChatToolError {
        var details = [exception.message]
        if let line = exception.line, let column = exception.column {
            details.append("Line \(line), column \(column)")
        } else if let line = exception.line {
            details.append("Line \(line)")
        }
        if let source = exception.source, !source.isEmpty, source != "about:blank" {
            details.append("Source: \(source)")
        }
        if let stack = exception.stack,
           !stack.isEmpty,
           stack != exception.message {
            details.append("Stack:\n\(stack)")
        }
        if exception.truncated {
            details.append("Exception details were truncated.")
        }
        if !console.output.isEmpty {
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

    private static func executionScript(code: String, inputJSON: String) throws -> String {
        let encodedInputData = try JSONEncoder().encode(inputJSON)
        let encodedCodeData = try JSONEncoder().encode(code)
        guard let encodedInput = String(data: encodedInputData, encoding: .utf8),
              let encodedCode = String(data: encodedCodeData, encoding: .utf8) else {
            throw ChatToolError.failed("The JavaScript execution request could not be encoded.")
        }
        return #"""
    {
    const input = JSON.parse(\#(encodedInput));
    const __voiceChatNativeEval = eval;
    const __voiceChatNativeJSONStringify = JSON.stringify.bind(JSON);
    const __voiceChatNativeString = String;
    const __voiceChatNativeArrayIsArray = Array.isArray.bind(Array);
    const __voiceChatNativeArrayPush = Function.call.bind(Array.prototype.push);
    const __voiceChatNativeArraySort = Function.call.bind(Array.prototype.sort);
    const __voiceChatNativeNumberIsFinite = Number.isFinite.bind(Number);
    const __voiceChatNativeNumberIsInteger = Number.isInteger.bind(Number);
    const __voiceChatNativeMinimum = Math.min.bind(Math);
    const __voiceChatNativeObjectKeys = Object.keys.bind(Object);
    const __voiceChatNativeObjectCreate = Object.create.bind(Object);
    const __voiceChatNativeObjectDefineProperty = Object.defineProperty.bind(Object);
    const __voiceChatNativeStringCharCodeAt = Function.call.bind(String.prototype.charCodeAt);
    const __voiceChatNativeStringSlice = Function.call.bind(String.prototype.slice);
    const __voiceChatNativeDate = Date;
    const __voiceChatNativeDateToISOString = Function.call.bind(Date.prototype.toISOString);
    const __voiceChatNativeWeakSet = WeakSet;
    const __voiceChatNativeWeakSetAdd = Function.call.bind(WeakSet.prototype.add);
    const __voiceChatNativeWeakSetDelete = Function.call.bind(WeakSet.prototype.delete);
    const __voiceChatNativeWeakSetHas = Function.call.bind(WeakSet.prototype.has);
    const __voiceChatNativeError = Error;
    const __voiceChatNativeTypeError = TypeError;
    const __voiceChatConsoleLines = [];
    let __voiceChatConsoleUnits = 0;
    let __voiceChatConsoleTruncated = false;
    const __voiceChatFormatConsoleValue = value => {
      if (typeof value === "string") return value;
      if (typeof value === "undefined") return "undefined";
      if (typeof value === "function") return `[Function${value.name ? `: ${value.name}` : ""}]`;
      if (typeof value === "symbol" || typeof value === "bigint") return __voiceChatNativeString(value);
      if (value instanceof __voiceChatNativeError) return `${value.name}: ${value.message}`;
      const seen = new __voiceChatNativeWeakSet();
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
    const __voiceChatCreateResultSnapshot = rawValue => {
      let remainingNodes = 4000;
      let remainingStringUnits = 64000;
      let truncated = false;
      const omitted = {};
      const ancestors = new __voiceChatNativeWeakSet();
      const captureString = value => {
        const maximumUnits = __voiceChatNativeMinimum(4000, remainingStringUnits);
        let end = __voiceChatNativeMinimum(value.length, maximumUnits);
        if (end > 0 && end < value.length) {
          const lastUnit = __voiceChatNativeStringCharCodeAt(value, end - 1);
          const nextUnit = __voiceChatNativeStringCharCodeAt(value, end);
          if (lastUnit >= 0xD800 && lastUnit <= 0xDBFF && nextUnit >= 0xDC00 && nextUnit <= 0xDFFF) {
            end -= 1;
          }
        }
        const visible = __voiceChatNativeStringSlice(value, 0, end);
        remainingStringUnits -= visible.length;
        if (visible.length < value.length) truncated = true;
        return visible;
      };
      const capture = (value, depth = 0) => {
        if (remainingNodes <= 0) {
          truncated = true;
          return omitted;
        }
        remainingNodes -= 1;
        if (value === null) return null;
        switch (typeof value) {
        case "boolean":
          return value;
        case "number":
          if (!__voiceChatNativeNumberIsFinite(value)) throw new __voiceChatNativeTypeError("Non-finite number");
          return value;
        case "string":
          return captureString(value);
        case "undefined":
        case "function":
        case "symbol":
        case "bigint":
          throw new __voiceChatNativeTypeError("Unsupported value");
        }
        if (value instanceof __voiceChatNativeDate) {
          return captureString(__voiceChatNativeDateToISOString(value));
        }
        if (depth >= 32) {
          truncated = true;
          return null;
        }
        if (__voiceChatNativeWeakSetHas(ancestors, value)) {
          throw new __voiceChatNativeTypeError("Cyclic value");
        }
        __voiceChatNativeWeakSetAdd(ancestors, value);
        try {
          if (__voiceChatNativeArrayIsArray(value)) {
            if (value.length > 200) truncated = true;
            const output = [];
            const count = __voiceChatNativeMinimum(value.length, 200);
            for (let index = 0; index < count; index += 1) {
              const captured = capture(value[index], depth + 1);
              if (captured === omitted) break;
              __voiceChatNativeArrayPush(output, captured);
            }
            return output;
          }
          const keys = __voiceChatNativeObjectKeys(value);
          __voiceChatNativeArraySort(keys);
          if (keys.length > 200) truncated = true;
          const output = __voiceChatNativeObjectCreate(null);
          const count = __voiceChatNativeMinimum(keys.length, 200);
          for (let index = 0; index < count; index += 1) {
            const key = keys[index];
            if (key.length > remainingStringUnits) {
              truncated = true;
              break;
            }
            remainingStringUnits -= key.length;
            const captured = capture(value[key], depth + 1);
            if (captured === omitted) break;
            __voiceChatNativeObjectDefineProperty(output, key, {
              value: captured,
              enumerable: true,
              writable: true,
              configurable: true
            });
          }
          return output;
        } finally {
          __voiceChatNativeWeakSetDelete(ancestors, value);
        }
      };
      if (typeof rawValue === "undefined") {
        return __voiceChatNativeJSONStringify({ resultType: "undefined", truncated: false });
      }
      if (typeof rawValue === "number" && !__voiceChatNativeNumberIsFinite(rawValue)) {
        return __voiceChatNativeJSONStringify({
          resultType: "number",
          resultDisplay: __voiceChatNativeString(rawValue),
          truncated: false
        });
      }
      const resultType = rawValue === null
        ? "null"
        : __voiceChatNativeArrayIsArray(rawValue)
          ? "array"
          : rawValue instanceof __voiceChatNativeDate
            ? "string"
            : typeof rawValue;
      try {
        const result = capture(rawValue);
        return __voiceChatNativeJSONStringify({ result, resultType, truncated });
      } catch (_) {
        let resultDisplay;
        try {
          resultDisplay = captureString(__voiceChatNativeString(rawValue));
        } catch (_) {}
        return __voiceChatNativeJSONStringify({
          resultType: "unavailable",
          ...(resultDisplay === undefined ? {} : { resultDisplay }),
          truncated
        });
      }
    };
    const __voiceChatCreateExceptionSnapshot = error => {
      let truncated = false;
      const readProperty = name => {
        try {
          return error === null || typeof error === "undefined" ? undefined : error[name];
        } catch (_) {
          return undefined;
        }
      };
      const captureString = (value, maximumUnits) => {
        let string;
        try {
          string = typeof value === "string" ? value : __voiceChatNativeString(value);
        } catch (_) {
          return undefined;
        }
        let end = __voiceChatNativeMinimum(string.length, maximumUnits);
        if (end > 0 && end < string.length) {
          const lastUnit = __voiceChatNativeStringCharCodeAt(string, end - 1);
          const nextUnit = __voiceChatNativeStringCharCodeAt(string, end);
          if (lastUnit >= 0xD800 && lastUnit <= 0xDBFF && nextUnit >= 0xDC00 && nextUnit <= 0xDFFF) {
            end -= 1;
          }
        }
        const visible = __voiceChatNativeStringSlice(string, 0, end);
        if (visible.length < string.length) truncated = true;
        return visible;
      };
      const name = captureString(readProperty("name"), 256);
      const rawMessage = readProperty("message");
      const separator = name && typeof rawMessage !== "undefined" ? ": " : "";
      const messageBudget = __voiceChatNativeMinimum(4000 - (name?.length ?? 0) - separator.length, 4000);
      let message = captureString(rawMessage, messageBudget);
      if (!name && typeof message === "undefined") {
        message = captureString(error, 4000);
      }
      const formattedMessage = `${name ?? ""}${separator}${message ?? "JavaScript exception"}`;
      const firstInteger = (first, second) => {
        if (__voiceChatNativeNumberIsInteger(first)) return first;
        return __voiceChatNativeNumberIsInteger(second) ? second : undefined;
      };
      const line = firstInteger(readProperty("line"), readProperty("lineNumber"));
      const column = firstInteger(readProperty("column"), readProperty("columnNumber"));
      const source = captureString(readProperty("sourceURL"), 1000);
      const stack = typeof line === "undefined" || typeof column === "undefined"
        ? captureString(readProperty("stack"), 4000)
        : undefined;
      return __voiceChatNativeJSONStringify({
        exception: {
          message: formattedMessage,
          ...(typeof line === "undefined" ? {} : { line }),
          ...(typeof column === "undefined" ? {} : { column }),
          ...(typeof source === "undefined" ? {} : { source }),
          ...(typeof stack === "undefined" ? {} : { stack }),
          truncated
        },
        truncated
      });
    };
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
    let __voiceChatCompletionSnapshot;
    try {
      const __voiceChatRawResult = (0, __voiceChatNativeEval)(\#(encodedCode));
      __voiceChatCompletionSnapshot = __voiceChatCreateResultSnapshot(__voiceChatRawResult);
    } catch (error) {
      __voiceChatCompletionSnapshot = __voiceChatCreateExceptionSnapshot(error);
    }
    __voiceChatCompletionSnapshot;
    }
    """#
    }
}
#endif

private func invalidScript(_ message: String) -> ChatToolError {
    ChatToolError.invalidArguments(message)
}
