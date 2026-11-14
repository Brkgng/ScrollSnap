import AppKit

@main
final class FixtureApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let scrollView = NSScrollView()
    private let status = NSTextField(labelWithString: "Ready: 0")
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var document: DocumentView!
    private let detailPattern = VerticalDetailFixture(rawValue: UserDefaults.standard.string(forKey: "FixturePattern") ?? "")
    private var conversation: CGImage?
    private var documentWidth: Int { conversation?.width ?? FixtureDocument.width }
    private var viewportHeight: Int {
        if conversation != nil { return ConversationFixture.viewportHeight }
        return detailPattern == nil ? FixtureDocument.viewportHeight : VerticalDetailFixture.viewportHeight
    }
    private var documentHeight: Int { conversation?.height ?? detailPattern?.height ?? FixtureDocument.height }

    static func main() {
        let app = NSApplication.shared
        let delegate = FixtureApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.string(forKey: "FixturePattern") == "conversation" {
            conversation = ConversationFixture.image()
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: documentWidth + 40, height: max(520, viewportHeight + 120)),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ScrollSnap Capture Fixture"
        let content = window.contentView!
        scrollView.frame = NSRect(x: 20, y: 100, width: documentWidth, height: viewportHeight)
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = detailPattern == nil && conversation == nil
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.setAccessibilityIdentifier("baseline.viewport")
        scrollView.setAccessibilityLabel("Numbered document")
        document = DocumentView(frame: NSRect(x: 0, y: 0, width: documentWidth, height: documentHeight),
                                image: conversation ?? detailPattern?.image() ?? FixtureDocument.image(),
                                usesNearestNeighbor: conversation != nil)
        scrollView.documentView = document
        content.addSubview(scrollView)
        if detailPattern != nil {
            let header = NSImageView(frame: NSRect(x: scrollView.frame.minX,
                                                  y: scrollView.frame.maxY - CGFloat(VerticalDetailFixture.headerHeight),
                                                  width: CGFloat(FixtureDocument.width), height: CGFloat(VerticalDetailFixture.headerHeight)))
            header.image = NSImage(cgImage: VerticalDetailFixture.headerImage(),
                                   size: NSSize(width: FixtureDocument.width, height: VerticalDetailFixture.headerHeight))
            header.imageScaling = .scaleAxesIndependently
            content.addSubview(header)
        }
        for (index, title) in ["Reset", "Slow", "Normal", "Fast"].enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(performAction(_:)))
            button.frame = NSRect(x: 20 + index * 120, y: 52, width: 110, height: 32)
            button.tag = index
            content.addSubview(button)
        }
        status.frame = NSRect(x: 20, y: 15, width: 480, height: 25)
        status.setAccessibilityIdentifier("baseline.status")
        content.addSubview(status)
        let replace = NSButton(title: "Unrelated", target: self, action: #selector(performAction(_:)))
        replace.frame = NSRect(x: 420, y: 12, width: 80, height: 28)
        replace.tag = 4
        content.addSubview(replace)
        observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                          object: scrollView.contentView, queue: .main) { [weak self] _ in
            guard let self else { return }
            if timer == nil { updateStatus("Ready") }
        }
        // Keep the controlled fixture on the primary display for stable XCTest coordinates.
        let screenIndex = UserDefaults.standard.integer(forKey: "FixtureScreenIndex")
        if let screen = NSScreen.screens.dropFirst(screenIndex).first {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - window.frame.width / 2,
                                          y: screen.visibleFrame.midY - window.frame.height / 2))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        move(to: 0)
    }

    @objc private func performAction(_ sender: NSButton) {
        timer?.invalidate()
        timer = nil
        if sender.tag == 4 {
            document.isUnrelated = true
            document.needsDisplay = true
            updateStatus("Replaced")
            return
        }
        if sender.tag == 0 {
            document.isUnrelated = false
            document.needsDisplay = true
            move(to: 0); updateStatus("Ready"); return
        }
        let speed = [0.0, 160.0, 640.0, 1600.0][sender.tag]
        let initial = scrollView.contentView.bounds.minY
        let started = ProcessInfo.processInfo.systemUptime
        updateStatus("Scrolling")
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let top = min(CGFloat(documentHeight - viewportHeight),
                          initial + (ProcessInfo.processInfo.systemUptime - started) * speed)
            move(to: top)
            updateStatus("Scrolling")
            if top >= CGFloat(documentHeight - viewportHeight) {
                timer.invalidate()
                self.timer = nil
                updateStatus("Done")
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func move(to top: CGFloat) {
        // The conversation bitmap has one pixel per point; keep its display sampling stable.
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: conversation == nil ? top : top.rounded()))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func updateStatus(_ state: String) {
        status.stringValue = "\(state): \(Int(scrollView.contentView.bounds.minY.rounded()))"
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

private final class DocumentView: NSView {
    var isUnrelated = false
    private let image: NSImage
    private let usesNearestNeighbor: Bool
    init(frame: NSRect, image: CGImage, usesNearestNeighbor: Bool = false) {
        self.image = NSImage(cgImage: image, size: frame.size)
        self.usesNearestNeighbor = usesNearestNeighbor
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:image:) for the test fixture") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        if isUnrelated { NSColor.systemPurple.setFill(); bounds.fill(); return }
        if usesNearestNeighbor { NSGraphicsContext.current?.imageInterpolation = .none }
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    }
}
