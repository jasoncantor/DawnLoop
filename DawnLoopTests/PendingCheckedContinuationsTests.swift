import XCTest
@testable import DawnLoop

@MainActor
final class PendingCheckedContinuationsTests: XCTestCase {
    func testResumeAllResumesEveryPendingWaiter() async {
        let pending = PendingCheckedContinuations<Int?>()
        var firstShouldStart = false
        var secondShouldStart = true

        let first = Task { @MainActor in
            await withCheckedContinuation { continuation in
                firstShouldStart = pending.add(continuation)
            }
        }
        await Task.yield()

        let second = Task { @MainActor in
            await withCheckedContinuation { continuation in
                secondShouldStart = pending.add(continuation)
            }
        }
        await Task.yield()

        pending.resumeAll(returning: 42)

        let firstResult = await first.value
        let secondResult = await second.value

        XCTAssertEqual(firstResult, 42)
        XCTAssertEqual(secondResult, 42)
        XCTAssertTrue(firstShouldStart)
        XCTAssertFalse(secondShouldStart)
    }

    func testResumeAllClearsPendingWaitersForNextWave() async {
        let pending = PendingCheckedContinuations<Int>()
        var firstWaveShouldStart = false

        let firstWave = Task { @MainActor in
            await withCheckedContinuation { continuation in
                firstWaveShouldStart = pending.add(continuation)
            }
        }
        await Task.yield()

        pending.resumeAll(returning: 1)

        XCTAssertEqual(await firstWave.value, 1)
        XCTAssertTrue(firstWaveShouldStart)

        var secondWaveShouldStart = false
        let secondWave = Task { @MainActor in
            await withCheckedContinuation { continuation in
                secondWaveShouldStart = pending.add(continuation)
            }
        }
        await Task.yield()

        pending.resumeAll(returning: 2)

        XCTAssertEqual(await secondWave.value, 2)
        XCTAssertTrue(secondWaveShouldStart)
    }
}
