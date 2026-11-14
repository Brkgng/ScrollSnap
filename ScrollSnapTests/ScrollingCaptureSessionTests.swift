import AppKit
import XCTest
@testable import ScrollSnap

@MainActor
final class ScrollingCaptureSessionTests: XCTestCase {
    func testFinishWaitsForSuspendedInitialFrameBeforeTerminalFrame() async {
        let initial = makeImage(color: .red)
        let terminal = makeImage(color: .blue)
        let gate = CaptureGate()
        let provider = CaptureScript([
            .suspended(gate),
            .immediate(terminal),
        ])
        let stitcher = RecordingStitcher()
        let session = ScrollingCaptureSession(capture: provider.capture, stitcher: stitcher)

        let startTask = Task { @MainActor in await session.start() }
        await gate.waitUntilStarted()
        let finishTask = Task { @MainActor in await session.finish() }
        await Task.yield()

        XCTAssertEqual(provider.captureCount, 1, "Terminal capture must not overlap the initial capture")
        gate.resume(returning: initial)

        let didStart = await startTask.value
        XCTAssertTrue(didStart)
        let result = await finishTask.value
        XCTAssertTrue(result === terminal)
        XCTAssertEqual(provider.captureCount, 2)
        XCTAssertEqual(stitcher.startedImages.count, 1)
        XCTAssertTrue(stitcher.startedImages[0] === initial)
        XCTAssertEqual(stitcher.addedImages.count, 1)
        XCTAssertTrue(stitcher.addedImages[0] === terminal)
    }

    func testFinishDuringSuspendedSetupFailureStillFinalizes() async {
        let gate = CaptureGate()
        let provider = CaptureScript([
            .suspended(gate),
            .immediate(nil),
        ])
        let stitcher = RecordingStitcher()
        let session = ScrollingCaptureSession(capture: provider.capture, stitcher: stitcher)

        let startTask = Task { @MainActor in await session.start() }
        await gate.waitUntilStarted()
        let finishTask = Task { @MainActor in await session.finish() }
        await Task.yield()

        XCTAssertEqual(provider.captureCount, 1)
        gate.resume(returning: nil)

        let didStart = await startTask.value
        let result = await finishTask.value
        XCTAssertFalse(didStart)
        XCTAssertNil(result)
        XCTAssertEqual(provider.captureCount, 2)
        XCTAssertEqual(stitcher.stopCount, 1)
    }

    func testFinishWaitsForInFlightFrameThenCapturesTerminalFrame() async {
        let initial = makeImage(color: .red)
        let inFlight = makeImage(color: .green)
        let terminal = makeImage(color: .blue)
        let gate = CaptureGate()
        let provider = CaptureScript([
            .immediate(initial),
            .suspended(gate),
            .immediate(terminal),
        ])
        let stitcher = RecordingStitcher()
        let session = ScrollingCaptureSession(capture: provider.capture, stitcher: stitcher)

        let didStart = await session.start()
        XCTAssertTrue(didStart)
        XCTAssertTrue(session.requestFrame())
        XCTAssertFalse(session.requestFrame(), "Only one screenshot request may be active")
        await gate.waitUntilStarted()

        let finishTask = Task { @MainActor in await session.finish() }
        await Task.yield()
        gate.resume(returning: inFlight)

        let result = await finishTask.value
        XCTAssertTrue(result === terminal)
        XCTAssertEqual(provider.captureCount, 3)
        XCTAssertEqual(stitcher.addedImages.count, 2)
        XCTAssertTrue(stitcher.addedImages[0] === inFlight)
        XCTAssertTrue(stitcher.addedImages[1] === terminal)
        XCTAssertEqual(stitcher.stopCount, 1)
    }

    func testFinishWithoutInFlightFrameAddsTerminalFrame() async {
        let initial = makeImage(color: .red)
        let terminal = makeImage(color: .blue)
        let provider = CaptureScript([.immediate(initial), .immediate(terminal)])
        let stitcher = RecordingStitcher()
        let session = ScrollingCaptureSession(capture: provider.capture, stitcher: stitcher)

        let didStart = await session.start()
        XCTAssertTrue(didStart)
        let result = await session.finish()

        XCTAssertTrue(result === terminal)
        XCTAssertEqual(provider.captureCount, 2)
        XCTAssertEqual(stitcher.addedImages.count, 1)
        XCTAssertTrue(stitcher.addedImages[0] === terminal)
    }

    func testTerminalCaptureFailureReturnsLastStitchedImage() async {
        let initial = makeImage(color: .red)
        let provider = CaptureScript([.immediate(initial), .immediate(nil)])
        let stitcher = RecordingStitcher()
        let session = ScrollingCaptureSession(capture: provider.capture, stitcher: stitcher)

        let didStart = await session.start()
        XCTAssertTrue(didStart)
        let result = await session.finish()

        XCTAssertTrue(result === initial)
        XCTAssertTrue(session.isIncomplete)
        XCTAssertEqual(stitcher.addedImages.count, 0)
        XCTAssertEqual(stitcher.stopCount, 1)
    }

    func testCancelDiscardsSuspendedFrameAndDoesNotCaptureTerminalFrame() async {
        let initial = makeImage(color: .red)
        let lateFrame = makeImage(color: .green)
        let gate = CaptureGate()
        let provider = CaptureScript([
            .immediate(initial),
            .suspended(gate),
            .immediate(makeImage(color: .blue)),
        ])
        let stitcher = RecordingStitcher()
        let session = ScrollingCaptureSession(capture: provider.capture, stitcher: stitcher)

        let didStart = await session.start()
        XCTAssertTrue(didStart)
        XCTAssertTrue(session.requestFrame())
        await gate.waitUntilStarted()

        let cancelTask = Task { @MainActor in await session.cancel() }
        await Task.yield()
        gate.resume(returning: lateFrame)
        await cancelTask.value

        XCTAssertEqual(provider.captureCount, 2)
        XCTAssertEqual(stitcher.addedImages.count, 0)
        XCTAssertEqual(stitcher.stopCount, 1)
        let resultAfterCancellation = await session.finish()
        XCTAssertNil(resultAfterCancellation)
    }

    func testRepeatedFinishDoesNotFinalizeTwice() async {
        let initial = makeImage(color: .red)
        let terminal = makeImage(color: .blue)
        let provider = CaptureScript([.immediate(initial), .immediate(terminal)])
        let stitcher = RecordingStitcher()
        let session = ScrollingCaptureSession(capture: provider.capture, stitcher: stitcher)

        let didStart = await session.start()
        XCTAssertTrue(didStart)
        let firstResult = await session.finish()
        let secondResult = await session.finish()
        XCTAssertNotNil(firstResult)
        XCTAssertNil(secondResult)

        XCTAssertEqual(provider.captureCount, 2)
        XCTAssertEqual(stitcher.stopCount, 1)
    }

    func testFrameRequestRemainsBusyUntilStitchingCompletes() async {
        let gate = CaptureGate()
        let image = makeImage(color: .blue)
        let provider = CaptureScript([.immediate(image), .immediate(image), .immediate(image)])
        let stitcher = RecordingStitcher(processingGate: gate)
        let session = ScrollingCaptureSession(capture: provider.capture, stitcher: stitcher)
        let started = await session.start()
        XCTAssertTrue(started)
        XCTAssertTrue(session.requestFrame())
        await gate.waitUntilStarted()
        XCTAssertFalse(session.requestFrame(), "Processing must not accumulate screenshots")
        XCTAssertEqual(provider.captureCount, 2)
        let finish = Task { @MainActor in await session.finish() }
        gate.resume(returning: nil)
        _ = await finish.value
        XCTAssertEqual(provider.captureCount, 3)
    }

    private func makeImage(color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        return image
    }
}

@MainActor
private final class RecordingStitcher: ImageStitching {
    var isIncomplete = false
    private(set) var startedImages: [NSImage] = []
    private(set) var addedImages: [NSImage] = []
    private(set) var stopCount = 0
    private var currentImage: NSImage?
    private let processingGate: CaptureGate?

    init(processingGate: CaptureGate? = nil) { self.processingGate = processingGate }

    func waitForPendingImages() async {
        if !addedImages.isEmpty, let processingGate { _ = await processingGate.capture() }
    }

    func startStitching(with initialImage: NSImage) {
        startedImages.append(initialImage)
        currentImage = initialImage
    }

    func addImage(_ image: NSImage) {
        addedImages.append(image)
        currentImage = image
    }

    func stopStitching() async -> NSImage? {
        stopCount += 1
        return currentImage
    }
}

@MainActor
private final class CaptureScript {
    enum Step {
        case immediate(NSImage?)
        case suspended(CaptureGate)
    }

    private var steps: [Step]
    private(set) var captureCount = 0

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func capture() async -> NSImage? {
        captureCount += 1
        guard !steps.isEmpty else {
            XCTFail("Unexpected screenshot request")
            return nil
        }

        switch steps.removeFirst() {
        case .immediate(let image):
            return image
        case .suspended(let gate):
            return await gate.capture()
        }
    }
}

@MainActor
private final class CaptureGate {
    private var didStart = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var imageContinuation: CheckedContinuation<NSImage?, Never>?

    func capture() async -> NSImage? {
        didStart = true
        startContinuation?.resume()
        startContinuation = nil
        return await withCheckedContinuation { continuation in
            imageContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func resume(returning image: NSImage?) {
        imageContinuation?.resume(returning: image)
        imageContinuation = nil
    }
}
