import AppKit

final class PinholeOverlayController {
    private var dimmingWindows: [NSWindow] = []
    private var borderWindow: NSWindow?
    private var closeWindow: NSWindow?
    private var screenObserver: NSObjectProtocol?
    private var focusRect: NSRect?

    var backgroundTransparency: CGFloat = 0.15 {
        didSet {
            backgroundTransparency = min(max(backgroundTransparency, 0), 1)
            updateDimmingWindowBackgrounds()
        }
    }

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let focusRect = self.focusRect else { return }
            self.show(focusRect: focusRect)
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func show(focusRect: NSRect) {
        hide()
        self.focusRect = focusRect

        for screen in NSScreen.screens {
            let screenFrame = screen.frame
            let visiblePart = screenFrame.intersection(focusRect)

            if visiblePart.isEmpty {
                dimmingWindows.append(makeDimmingWindow(frame: screenFrame))
                continue
            }

            rectanglesAroundHole(in: screenFrame, hole: visiblePart)
                .filter { !$0.isEmpty && $0.width > 0 && $0.height > 0 }
                .forEach { dimmingWindows.append(makeDimmingWindow(frame: $0)) }
        }

        dimmingWindows.forEach { $0.orderFrontRegardless() }
        borderWindow = makeBorderWindow(around: focusRect)
        closeWindow = makeCloseWindow(near: focusRect)
        borderWindow?.orderFrontRegardless()
        closeWindow?.orderFrontRegardless()
    }

    func hide() {
        dimmingWindows.forEach { $0.close() }
        dimmingWindows.removeAll()
        borderWindow?.close()
        borderWindow = nil
        closeWindow?.close()
        closeWindow = nil
        focusRect = nil
    }

    private func rectanglesAroundHole(in frame: NSRect, hole: NSRect) -> [NSRect] {
        [
            NSRect(
                x: frame.minX,
                y: hole.maxY,
                width: frame.width,
                height: frame.maxY - hole.maxY
            ),
            NSRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width,
                height: hole.minY - frame.minY
            ),
            NSRect(
                x: frame.minX,
                y: hole.minY,
                width: hole.minX - frame.minX,
                height: hole.height
            ),
            NSRect(
                x: hole.maxX,
                y: hole.minY,
                width: frame.maxX - hole.maxX,
                height: hole.height
            )
        ]
    }

    private func makeDimmingWindow(frame: NSRect) -> NSWindow {
        let window = OverlayWindow(frame: frame)
        window.backgroundColor = dimmingBackgroundColor
        window.ignoresMouseEvents = true
        return window
    }

    private var dimmingBackgroundColor: NSColor {
        NSColor.black.withAlphaComponent(1 - backgroundTransparency)
    }

    private func updateDimmingWindowBackgrounds() {
        dimmingWindows.forEach { $0.backgroundColor = dimmingBackgroundColor }
    }

    private func makeBorderWindow(around rectangle: NSRect) -> NSWindow {
        let borderWidth: CGFloat = 3
        let frame = rectangle.insetBy(dx: -borderWidth, dy: -borderWidth)
        let window = OverlayWindow(frame: frame)
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.contentView = BorderView()
        return window
    }

    private func makeCloseWindow(near rectangle: NSRect) -> NSWindow {
        let size = NSSize(width: 32, height: 32)
        let spacing: CGFloat = 6
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(rectangle) })
        let availableFrame = screen?.frame ?? NSScreen.main?.frame ?? rectangle

        var origin = NSPoint(
            x: rectangle.maxX - size.width,
            y: rectangle.maxY + spacing
        )
        if origin.y + size.height > availableFrame.maxY {
            origin.y = rectangle.maxY - size.height - spacing
        }
        origin.x = min(max(origin.x, availableFrame.minX + 8), availableFrame.maxX - size.width - 8)
        origin.y = min(max(origin.y, availableFrame.minY + 8), availableFrame.maxY - size.height - 8)

        let window = OverlayWindow(frame: NSRect(origin: origin, size: size))
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.contentView = CloseControlView { [weak self] in
            self?.hide()
        }
        return window
    }
}

private final class OverlayWindow: NSPanel {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class BorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let border = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        border.lineWidth = 3
        NSColor.white.withAlphaComponent(0.9).setStroke()
        border.stroke()
    }
}

private final class CloseControlView: NSView {
    private let onClose: () -> Void
    private var isHovering = false
    private var trackingAreaReference: NSTrackingArea?
    private var acceptsClicks = false
    private var hasArmedClick = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        waitForSelectionGestureToEnd()
    }

    override var isOpaque: Bool { false }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard acceptsClicks else { return }
        hasArmedClick = true
    }

    override func mouseUp(with event: NSEvent) {
        guard hasArmedClick else { return }
        hasArmedClick = false

        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            // Let AppKit finish dispatching mouseUp before the callback closes
            // and releases the window containing this responder.
            DispatchQueue.main.async { [self] in
                onClose()
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .regular),
            .foregroundColor: isHovering
                ? NSColor.white
                : NSColor.white.withAlphaComponent(0.55),
            .paragraphStyle: paragraph
        ]
        "×".draw(
            in: NSRect(x: 0, y: 3, width: bounds.width, height: 26),
            withAttributes: attributes
        )
    }

    private func waitForSelectionGestureToEnd() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }

            if NSEvent.pressedMouseButtons == 0 {
                self.acceptsClicks = true
            } else {
                self.waitForSelectionGestureToEnd()
            }
        }
    }
}
