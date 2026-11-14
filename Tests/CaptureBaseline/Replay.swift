import AppKit
import Darwin
import Vision

private struct Scenario {
    let name: String
    let positions: [Int]
    var pinnedHeader = false
    var animated = false
    var expectedHeight: Int { FixtureDocument.viewportHeight + (positions.max() ?? 0) }
}

private struct Observation: Codable {
    let scenario: String
    let scale: Int
    let iteration: Int
    let expectedHeight: Int
    let actualHeight: Double
    let expectedRows: [Int]
    let actualRows: [Int]
    let pixelMismatchFraction: Double?
    let maximumBandMismatchFraction: Double?
    let expectedIncomplete: Bool
    let actualIncomplete: Bool
    let accurate: Bool
    let processingMilliseconds: Double
    let cpuMilliseconds: Double
}

@main
private struct Replay {
    @MainActor
    static func main() async {
        do { try await record() }
        catch {
            fputs("Baseline could not be measured: \(error)\n", stderr)
            exit(2)
        }
    }

    @MainActor
    private static func record() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let scenarios = [
            Scenario(name: "static", positions: [0, 0, 0]),
            Scenario(name: "tiny-movements", positions: Array(stride(from: 0, through: 60, by: 3))),
            Scenario(name: "slow", positions: Array(stride(from: 0, through: 400, by: 20))),
            Scenario(name: "normal", positions: Array(stride(from: 0, through: 2000, by: 80))),
            Scenario(name: "fast", positions: Array(stride(from: 0, through: 1920, by: 320)) + [2000]),
            Scenario(name: "reverse", positions: [0, 40, 80, 60, 40]),
            Scenario(name: "reverse-and-resume", positions: [0, 40, 80, 60, 40, 80, 120]),
            Scenario(name: "pinned-header", positions: Array(stride(from: 0, through: 800, by: 80)), pinnedHeader: true),
            Scenario(name: "animation", positions: Array(stride(from: 0, through: 800, by: 80)), animated: true)
        ]
        var observations: [Observation] = []
        for scale in [1, 2] {
            let document = FixtureDocument.image(scale: scale)
            let initial = FixtureDocument.viewport(document: document, top: 0, scale: scale)
            // Check the fixture reader independently before judging production output.
            guard FixtureDocument.rows(in: initial) == Array(1...10) else {
                throw NSError(domain: "CaptureBaseline", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Fixture marker self-check failed"])
            }
            // Fail visibly on a blocked Vision environment rather than record fabricated regressions.
            let initialCG = initial.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            let request = VNTranslationalImageRegistrationRequest(targetedCGImage: initialCG)
            try VNImageRequestHandler(cgImage: initialCG, options: [:]).perform([request])
            try FixtureDocument.save(NSImage(cgImage: document, size: NSSize(width: FixtureDocument.width,
                                                                          height: FixtureDocument.height)),
                                     to: output.appendingPathComponent("document-\(scale)x.png"))
            for scenario in scenarios {
                let expected = FixtureDocument.expected(document: document, height: scenario.expectedHeight,
                                                        scale: scale, pinnedHeader: scenario.pinnedHeader)
                let expectedRows = FixtureDocument.rows(in: expected)
                try FixtureDocument.save(expected, to: output.appendingPathComponent("\(scenario.name)-\(scale)x-expected.png"))
                for iteration in 1...3 {
                    let frames = scenario.positions.map {
                        FixtureDocument.viewport(document: document, top: $0, scale: scale,
                                                 pinnedHeader: scenario.pinnedHeader, animated: scenario.animated)
                    }
                    let manager = StitchingManager()
                    let wallStart = ProcessInfo.processInfo.systemUptime
                    let cpuStart = clock()
                    manager.startStitching(with: frames[0])
                    for frame in frames.dropFirst() { manager.addImage(frame) }
                    let result = await manager.stopStitching()
                    let elapsed = (ProcessInfo.processInfo.systemUptime - wallStart) * 1000
                    let cpu = Double(clock() - cpuStart) / Double(CLOCKS_PER_SEC) * 1000
                    let actualRows = result.map(FixtureDocument.rows) ?? []
                    let actualHeight = result.map { Double($0.size.height) } ?? 0
                    let mismatch = result.flatMap { FixtureDocument.mismatchFraction($0, expected, animated: scenario.animated) }
                    observations.append(Observation(scenario: scenario.name, scale: scale, iteration: iteration,
                                                    expectedHeight: scenario.expectedHeight, actualHeight: actualHeight,
                                                    expectedRows: expectedRows, actualRows: actualRows,
                                                    pixelMismatchFraction: mismatch,
                                                    maximumBandMismatchFraction: nil,
                                                    expectedIncomplete: false, actualIncomplete: manager.isIncomplete,
                                                    accurate: abs(actualHeight - Double(scenario.expectedHeight)) <= 1
                                                        && actualRows == expectedRows && (mismatch.map { $0 <= 0.02 } ?? false)
                                                        && !manager.isIncomplete,
                                                    processingMilliseconds: elapsed, cpuMilliseconds: cpu))
                    if let result {
                        try FixtureDocument.save(result, to: output.appendingPathComponent("\(scenario.name)-\(scale)x-\(iteration)-actual.png"))
                    }
                    print("\(scenario.name) \(scale)x #\(iteration): \(Int(actualHeight))/\(scenario.expectedHeight) points, rows \(actualRows.count)/\(expectedRows.count)")
                }
            }
        }
        observations += try await recordConversation(output: output)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(observations).write(to: output.appendingPathComponent("observations.json"))
        let failures = observations.filter { !$0.accurate }.count
        print("Recorded \(observations.count) observations; \(failures) failed image checks. This is a baseline, not a green test result.")
        if CommandLine.arguments.contains("--check"), failures > 0 { exit(1) }
    }

    @MainActor
    private static func recordConversation(output: URL) async throws -> [Observation] {
        let source = ConversationFixture.image()
        let movement = source.height - ConversationFixture.viewportHeight
        let scenarios = [
            (name: "conversation-normal", positions: Array(stride(from: 0, to: movement, by: 80)) + [movement], incomplete: false),
            (name: "conversation-fast", positions: Array(stride(from: 0, to: movement, by: 400)) + [movement], incomplete: false),
            (name: "conversation-gap", positions: [0, ConversationFixture.viewportHeight + 100], incomplete: true)
        ]
        var observations: [Observation] = []
        for scale in [1, 2] {
            let context = CGContext(data: nil, width: source.width * scale, height: source.height * scale,
                                    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.interpolationQuality = .none
            context.draw(source, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
            let document = context.makeImage()!
            for scenario in scenarios {
                let expectedHeight = scenario.incomplete ? ConversationFixture.viewportHeight : source.height
                let crop = document.cropping(to: CGRect(x: 0, y: 0, width: document.width, height: expectedHeight * scale))!
                let expected = NSImage(cgImage: crop, size: NSSize(width: source.width, height: expectedHeight))
                let frames = scenario.positions.map { ConversationFixture.viewport(document: document, top: $0, scale: scale) }
                let manager = StitchingManager()
                let wallStart = ProcessInfo.processInfo.systemUptime
                let cpuStart = clock()
                manager.startStitching(with: frames[0])
                for frame in frames.dropFirst() { manager.addImage(frame) }
                let result = await manager.stopStitching()
                let elapsed = (ProcessInfo.processInfo.systemUptime - wallStart) * 1000
                let cpu = Double(clock() - cpuStart) / Double(CLOCKS_PER_SEC) * 1000
                let mismatch = result.flatMap { FixtureDocument.mismatchFraction($0, expected, width: source.width) }
                let bandMismatch = result.flatMap { ConversationFixture.maximumBandMismatch($0, expected: expected) }
                observations.append(Observation(scenario: scenario.name, scale: scale, iteration: 1,
                                                expectedHeight: expectedHeight, actualHeight: result.map { Double($0.size.height) } ?? 0,
                                                expectedRows: [], actualRows: [], pixelMismatchFraction: mismatch,
                                                maximumBandMismatchFraction: bandMismatch,
                                                expectedIncomplete: scenario.incomplete, actualIncomplete: manager.isIncomplete,
                                                accurate: (bandMismatch.map { $0 <= 0.02 } ?? false)
                                                    && manager.isIncomplete == scenario.incomplete,
                                                processingMilliseconds: elapsed, cpuMilliseconds: cpu))
                try FixtureDocument.save(expected, to: output.appendingPathComponent("\(scenario.name)-\(scale)x-expected.png"))
                if let result {
                    try FixtureDocument.save(result, to: output.appendingPathComponent("\(scenario.name)-\(scale)x-actual.png"))
                }
                print("\(scenario.name) \(scale)x: incomplete=\(manager.isIncomplete), maximum band mismatch=\(bandMismatch.map(String.init(describing:)) ?? "unavailable")")
            }
        }
        return observations
    }
}
