import AVKit
import SwiftUI

struct CaptureTutorialView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var player = AVPlayer()
    @State private var elapsed = 0.0
    @State private var isPlaying = false
    private let posterImage = CaptureTutorialStep.resourceURL(extension: "png").flatMap { NSImage(contentsOf: $0) }
    let dismiss: () -> Void

    private var step: CaptureTutorialStep { CaptureTutorialStep.at(elapsed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            demonstration

            HStack {
                if !reduceMotion {
                    Button(isPlaying ? AppText.pause : AppText.play,
                           systemImage: isPlaying ? "pause.fill" : "play.fill") {
                        if isPlaying {
                            player.pause()
                            isPlaying = false
                        } else {
                            if elapsed >= CaptureTutorialStep.duration { restart() }
                            else { play() }
                        }
                    }
                    Button(AppText.replay, systemImage: "arrow.counterclockwise", action: restart)
                }
                Spacer()
                Button(AppText.captureTutorialDone, action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 700)
        .onExitCommand(perform: dismiss)
        .onAppear {
            guard let url = CaptureTutorialStep.resourceURL(extension: "mp4") else { return }
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            if !reduceMotion { play() }
        }
        .onDisappear {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled {
                player.pause()
                isPlaying = false
            } else {
                restart()
            }
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            guard isPlaying else { return }
            let time = player.currentTime().seconds
            if time.isFinite { elapsed = time }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard note.object as? AVPlayerItem === player.currentItem else { return }
            elapsed = CaptureTutorialStep.duration
            isPlaying = false
        }
    }

    private var demonstration: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                poster
                if !reduceMotion {
                    TutorialVideo(player: player)
                        .allowsHitTesting(false)
                        .opacity(elapsed > 0 ? 1 : 0)
                    caption(step)
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                        .background(.regularMaterial)
                }
            }
            .aspectRatio(800.0 / 520, contentMode: .fit)
            .accessibilityHidden(true)

            if reduceMotion {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(CaptureTutorialStep.allCases) { caption($0) }
                }
                .padding(16)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CaptureTutorialStep.allCases.map(\.caption).joined(separator: "\n"))
    }

    private var poster: some View {
        Group {
            if let image = posterImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
    }

    private func caption(_ step: CaptureTutorialStep) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text((step.rawValue + 1).formatted())
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            Text(step.caption)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func play() {
        player.play()
        isPlaying = true
    }

    private func restart() {
        elapsed = 0
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        play()
    }
}

enum CaptureTutorialStep: Int, CaseIterable, Identifiable {
    case selection, scroll, save
    static let duration = 14.0
    var id: Self { self }

    static func at(_ seconds: Double) -> Self {
        if seconds < 4.5 { return .selection }
        if seconds < 10 { return .scroll }
        return .save
    }

    var caption: String {
        switch self {
        case .selection: return AppText.captureTutorialSelection
        case .scroll: return AppText.captureTutorialScroll
        case .save: return AppText.captureTutorialSave
        }
    }

    static func resourceURL(extension fileExtension: String, localization: String = LocalizationResolver.localization) -> URL? {
        Bundle.main.url(forResource: localization, withExtension: fileExtension, subdirectory: "TutorialDemo")
    }
}

private struct TutorialVideo: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.updatesNowPlayingInfoCenter = false
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player = nil
    }
}
