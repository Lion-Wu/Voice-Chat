import XCTest
@testable import Voice_Chat
#if canImport(CoreLocation) && canImport(Contacts) && canImport(MapKit)
import Contacts
import CoreLocation
import MapKit
#endif

final class CodeInterpreterToolTests: XCTestCase {
    func testRunsStandardJavaScriptLoopsAndFunctions() async throws {
        let result = try await run("""
        function fibonacci(count) {
            const values = [0, 1];
            for (let index = 2; index < count; index += 1) {
                values.push(values[index - 1] + values[index - 2]);
            }
            return values;
        }
        let index = 0;
        let total = 0;
        while (index < 5) {
            total += index;
            index += 1;
        }
        return { total, values: fibonacci(7) };
        """)

        XCTAssertEqual(result.payload["result"], .object([
            "total": .number(10),
            "values": .array([0, 1, 1, 2, 3, 5, 8].map { .number(Double($0)) })
        ]))
        XCTAssertEqual(result.payload["result_type"], .string("object"))
        XCTAssertEqual(result.payload["truncated"], .bool(false))
    }

    func testRunsInputTransformsAndCalculationHelpers() async throws {
        let result = try await run(
            """
            const selected = input.values.filter(value => value >= input.minimum);
            const weighted = selected.map((value, index) => value * (index + 1));
            return {
                average: round(mean(selected), 2),
                median: median(selected),
                sum: sum(weighted),
                range: range(1, 4)
            };
            """,
            input: ["values": [1, 3, 5, 7], "minimum": 3]
        )

        XCTAssertEqual(result.payload["result"], .object([
            "average": .number(5),
            "median": .number(5),
            "sum": .number(34),
            "range": .array([1, 2, 3, 4].map { .number(Double($0)) })
        ]))
    }

    func testKeepsJSONNumbersAndBooleansDistinct() async throws {
        let result = try await run("return { zero: input.zero, one: input.one, enabled: input.enabled };", input: [
            "zero": 0,
            "one": 1,
            "enabled": true
        ])

        XCTAssertEqual(result.payload["result"], .object([
            "zero": .number(0),
            "one": .number(1),
            "enabled": .bool(true)
        ]))
    }

    func testBoundsLargeResultsAndReportsTruncation() async throws {
        let result = try await run("return [range(1, 250), \"x\".repeat(70000)];")

        guard case let .array(values) = result.payload["result"],
              case let .array(numbers) = values.first,
              case let .string(text) = values.last else {
            return XCTFail("Expected bounded array and string output")
        }
        XCTAssertEqual(numbers.count, 200)
        XCTAssertEqual(text.count, 4_000)
        XCTAssertEqual(result.payload["truncated"], .bool(true))
    }

    func testBoundsExponentiallySharedOutput() async throws {
        let result = try await run("return range(1, 40).reduce((value) => [value, value], 0);")

        XCTAssertEqual(result.payload["truncated"], .bool(true))
        XCTAssertLessThanOrEqual(jsonNodeCount(result.payload["result"]), 4_000)
    }

    func testMedianOfLargeFiniteValuesRemainsFinite() async throws {
        let result = try await run("return median([1e308, 1e308]);")

        XCTAssertEqual(result.payload["result"], .number(1e308))
    }

    func testDoesNotExposeNetworkFilesystemOrWebPageGlobals() async throws {
        let result = try await run("""
        return [
            typeof fetch,
            typeof XMLHttpRequest,
            typeof WebSocket,
            typeof window,
            typeof document,
            typeof require,
            typeof process
        ];
        """)

        XCTAssertEqual(result.payload["result"], .array(Array(repeating: .string("undefined"), count: 7)))
    }

    func testRejectsDynamicCodeGeneration() async {
        await assertInvalidScript(#"return (() => {})["constructor"]("return 7")();"#)
    }

    func testRejectsSyntaxErrorsAsyncResultsAndNonFiniteResults() async {
        await assertInvalidScript("this is not valid JavaScript")
        await assertInvalidScript("return Promise.resolve(1);")
        await assertInvalidScript("return Math.log(-1);")
    }

    func testInfiniteLoopTimesOutAndNextExecutionStillWorks() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await CodeInterpreterRuntime.evaluate(
                code: "while (true) {}",
                input: [:],
                timeoutSeconds: 0.2
            )
            XCTFail("Expected timeout")
        } catch let error as ChatToolError {
            XCTAssertEqual(error.resultStatus, .failed)
            XCTAssertTrue(error.localizedDescription.contains("timed out"))
        }
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(3))

        let recovery = try await run("return 7;")
        XCTAssertEqual(recovery.payload["result"], .number(7))
    }

    func testRejectsOversizedOrNonObjectInput() async throws {
        let oversized = String(repeating: "x", count: 1_000_001)
        do {
            _ = try await run("return input.value.length;", input: ["value": oversized])
            XCTFail("Expected oversized input error")
        } catch let error as ChatToolError {
            XCTAssertEqual(error.resultStatus, .invalidArguments)
        }

        do {
            let reader = try ChatToolArgumentReader(argumentsJSON: #"{"code":"return 1;","input":[]}"#)
            _ = try await SandboxedCodeInterpreterTool().run(arguments: reader)
            XCTFail("Expected object input error")
        } catch let error as ChatToolError {
            XCTAssertEqual(error.resultStatus, .invalidArguments)
        }
    }

    #if canImport(CoreLocation) && canImport(Contacts) && canImport(MapKit)
    func testPlacemarkMapsSystemAddressAndAdministrativeFields() throws {
        let address = CNMutablePostalAddress()
        address.street = "1 Infinite Loop"
        address.subLocality = "Cupertino"
        address.city = "Cupertino"
        address.subAdministrativeArea = "Santa Clara County"
        address.state = "California"
        address.postalCode = "95014"
        address.country = "United States"
        address.isoCountryCode = "US"

        let placemark = MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: 37.3317, longitude: -122.0301),
            postalAddress: address
        )
        let place = LocationPlaceDescription(placemark: placemark)

        guard case let .object(fields) = place.jsonValue else {
            return XCTFail("Expected place object")
        }
        XCTAssertEqual(fields["country"], .string("United States"))
        XCTAssertEqual(fields["country_code"], .string("US"))
        XCTAssertEqual(fields["administrative_area"], .string("California"))
        XCTAssertEqual(fields["sub_administrative_area"], .string("Santa Clara County"))
        XCTAssertEqual(fields["locality"], .string("Cupertino"))
        XCTAssertEqual(fields["sub_locality"], .string("Cupertino"))
        XCTAssertEqual(fields["postal_code"], .string("95014"))
        guard case let .string(formattedAddress)? = fields["formatted_address"] else {
            return XCTFail("Expected formatted address")
        }
        XCTAssertFalse(formattedAddress.isEmpty)
    }
    #endif

    private func run(
        _ code: String,
        input: [String: Any] = [:]
    ) async throws -> ChatToolExecutionPayload {
        let arguments: [String: Any] = ["code": code, "input": input]
        let data = try JSONSerialization.data(withJSONObject: arguments)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let reader = try ChatToolArgumentReader(argumentsJSON: json)
        return try await SandboxedCodeInterpreterTool().run(arguments: reader)
    }

    private func assertInvalidScript(_ code: String) async {
        do {
            _ = try await run(code)
            XCTFail("Expected invalid arguments")
        } catch let error as ChatToolError {
            XCTAssertEqual(error.resultStatus, .invalidArguments)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func jsonNodeCount(_ value: JSONValue?) -> Int {
        guard let value else { return 0 }
        switch value {
        case .string, .number, .bool, .null:
            return 1
        case let .array(values):
            return 1 + values.reduce(0) { $0 + jsonNodeCount($1) }
        case let .object(values):
            return 1 + values.values.reduce(0) { $0 + jsonNodeCount($1) }
        }
    }
}
