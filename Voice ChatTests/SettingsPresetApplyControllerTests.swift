import XCTest
@testable import Voice_Chat

@MainActor
final class SettingsPresetApplyControllerTests: XCTestCase {
    func testApplyPublishesStatusesFromInjectedOperation() async {
        let request = makeRequest()
        let finishedAt = TestDate.reference
        var appliedRequests: [TTSPresetApplyRequest] = []
        let controller = SettingsPresetApplyController(applyOperation: { request, publish in
            appliedRequests.append(request)
            publish(.idle.starting())
            publish(.idle.starting().recordingSuccess(at: finishedAt))
        })
        var emissions: [TTSPresetApplyStatus] = []
        controller.onStatusChange = { emissions.append($0) }

        await controller.apply(request)

        XCTAssertEqual(appliedRequests, [request])
        XCTAssertEqual(emissions.count, 2)
        XCTAssertTrue(emissions[0].isApplying)
        XCTAssertEqual(emissions[1].lastAppliedAt, finishedAt)
        XCTAssertTrue(emissions[1].lastSucceeded)
        XCTAssertEqual(controller.status, emissions[1])
    }

    func testApplyOnLaunchOnlyRunsOnce() async {
        let request = makeRequest()
        var requestBuildCount = 0
        var applyCount = 0
        let controller = SettingsPresetApplyController(applyOperation: { _, publish in
            applyCount += 1
            publish(.idle.starting())
        })

        await controller.applyOnLaunchIfNeeded {
            requestBuildCount += 1
            return request
        }
        await controller.applyOnLaunchIfNeeded {
            requestBuildCount += 1
            return request
        }

        XCTAssertEqual(requestBuildCount, 1)
        XCTAssertEqual(applyCount, 1)
    }

    func testNilRequestDoesNotApplyButStillConsumesLaunchGate() async {
        var applyCount = 0
        let controller = SettingsPresetApplyController(applyOperation: { _, _ in
            applyCount += 1
        })

        await controller.apply(nil)
        await controller.applyOnLaunchIfNeeded { nil }
        await controller.applyOnLaunchIfNeeded { makeRequest() }

        XCTAssertEqual(applyCount, 0)
        XCTAssertEqual(controller.status, .idle)
    }

    private func makeRequest() -> TTSPresetApplyRequest {
        TTSPresetApplyRequest(
            serverAddress: "http://localhost:9880",
            gptWeightsPath: "/tmp/gpt.ckpt",
            sovitsWeightsPath: "/tmp/sovits.pth"
        )
    }
}
