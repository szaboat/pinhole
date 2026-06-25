import AppKit

final class SelectionController {
    var onSelection: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var windows: [SelectionWindow] = []
    private var selectableWindows: [SelectableWindow] = []
    private var isFinishing = false

    func begin() {
        NSApp.activate(ignoringOtherApps: true)
        selectableWindows = SelectableWindow.visibleWindows()

        windows = NSScreen.screens.map { screen in
            let window = SelectionWindow(screen: screen)
            window.selectionView.onSelection = { [weak self, weak window] localRect in
                guard let self, let window else { return }
                let globalRect = localRect.offsetBy(
                    dx: window.frame.minX,
                    dy: window.frame.minY
                )
                self.finish(with: globalRect)
            }
            window.selectionView.onWindowSelection = { [weak self, weak window] localPoint in
                guard let self, let window else { return false }
                let globalPoint = NSPoint(
                    x: localPoint.x + window.frame.minX,
                    y: localPoint.y + window.frame.minY
                )
                guard let selectedWindow = self.window(at: globalPoint) else { return false }
                self.finish(with: selectedWindow.frame)
                return true
            }
            window.selectionView.onCancel = { [weak self] in
                self?.cancel()
            }
            window.orderFrontRegardless()
            return window
        }

        windows.first?.makeKey()
        windows.first?.makeFirstResponder(windows.first?.selectionView)
    }

    func cancel() {
        guard !isFinishing else { return }
        isFinishing = true

        // Releasing the key window from inside its responder's keyDown or
        // mouseUp handler causes an NSResponder over-release on macOS 12.
        DispatchQueue.main.async { [self] in
            closeWindows()
            onCancel?()
        }
    }

    private func finish(with rectangle: NSRect) {
        guard !isFinishing else { return }
        isFinishing = true

        let selection = rectangle.standardized.integral
        DispatchQueue.main.async { [self] in
            closeWindows()
            onSelection?(selection)
        }
    }

    private func closeWindows() {
        windows.forEach { $0.close() }
        windows.removeAll()
        selectableWindows.removeAll()
    }

    private func window(at point: NSPoint) -> SelectableWindow? {
        selectableWindows.first { $0.frame.contains(point) }
    }
}

final class SelectionWindow: NSWindow {
    let selectionView = SelectionView()

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }
}

final class SelectionView: NSView {
    var onSelection: ((NSRect) -> Void)?
    var onWindowSelection: ((NSPoint) -> Bool)?
    var onCancel: (() -> Void)?

    private var dragStart: NSPoint?
    private var selectionRect = NSRect.zero
    private let minimumSelectionSize: CGFloat = 24
    private let clickSelectionTolerance: CGFloat = 4

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.58).setFill()
        bounds.fill()

        if !selectionRect.isEmpty {
            NSColor.clear.setFill()
            selectionRect.fill(using: .copy)

            let border = NSBezierPath(rect: selectionRect.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 2
            NSColor.white.withAlphaComponent(0.95).setStroke()
            border.stroke()

            drawSizeLabel()
        } else {
            drawInstructions()
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        selectionRect = NSRect(origin: dragStart!, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let current = convert(event.locationInWindow, from: nil)
        selectionRect = rectangle(from: dragStart, to: current)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        mouseDragged(with: event)
        let clickPoint = dragStart
        dragStart = nil

        guard selectionRect.width >= minimumSelectionSize,
              selectionRect.height >= minimumSelectionSize else {
            if selectionRect.width <= clickSelectionTolerance,
               selectionRect.height <= clickSelectionTolerance,
               let clickPoint,
               onWindowSelection?(clickPoint) == true {
                return
            }

            selectionRect = .zero
            needsDisplay = true
            return
        }

        onSelection?(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    private func rectangle(from start: NSPoint, to end: NSPoint) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).intersection(bounds)
    }

    private func drawInstructions() {
        let title = "Click a window or drag a pinhole"
        let subtitle = "Press Escape to cancel"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.75),
            .paragraphStyle: paragraph
        ]

        let centerY = bounds.midY
        title.draw(
            in: NSRect(x: 0, y: centerY + 4, width: bounds.width, height: 34),
            withAttributes: titleAttributes
        )
        subtitle.draw(
            in: NSRect(x: 0, y: centerY - 26, width: bounds.width, height: 24),
            withAttributes: subtitleAttributes
        )
    }

    private func drawSizeLabel() {
        let text = "\(Int(selectionRect.width)) x \(Int(selectionRect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let padding = NSSize(width: 12, height: 7)
        let labelSize = NSSize(
            width: size.width + padding.width * 2,
            height: size.height + padding.height * 2
        )
        var origin = NSPoint(
            x: selectionRect.midX - labelSize.width / 2,
            y: selectionRect.minY - labelSize.height - 8
        )
        if origin.y < 8 {
            origin.y = selectionRect.minY + 8
        }

        let labelRect = NSRect(origin: origin, size: labelSize)
        let background = NSBezierPath(roundedRect: labelRect, xRadius: 7, yRadius: 7)
        NSColor.black.withAlphaComponent(0.8).setFill()
        background.fill()

        text.draw(
            at: NSPoint(
                x: labelRect.minX + padding.width,
                y: labelRect.minY + padding.height
            ),
            withAttributes: attributes
        )
    }
}

private struct SelectableWindow {
    let frame: NSRect

    static func visibleWindows() -> [SelectableWindow] {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let currentProcessID = Int(ProcessInfo.processInfo.processIdentifier)

        return windowInfo.compactMap { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                  ownerPID != currentProcessID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let alpha = info[kCGWindowAlpha as String] as? Double,
                  alpha > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = NSRect(cgWindowBounds: bounds),
                  frame.width >= 24,
                  frame.height >= 24 else {
                return nil
            }

            return SelectableWindow(frame: frame.integral)
        }
    }
}

private extension NSRect {
    init?(cgWindowBounds bounds: [String: Any]) {
        guard let x = bounds["X"] as? CGFloat,
              let y = bounds["Y"] as? CGFloat,
              let width = bounds["Width"] as? CGFloat,
              let height = bounds["Height"] as? CGFloat,
              width > 0,
              height > 0 else {
            return nil
        }

        let cgRect = NSRect(x: x, y: y, width: width, height: height)
        guard let screen = NSScreen.screens.first(where: { screen in
            guard let displayBounds = screen.displayBounds else { return false }
            return displayBounds.intersects(cgRect)
        }) else {
            return nil
        }

        guard let displayBounds = screen.displayBounds else { return nil }
        self.init(
            x: screen.frame.minX + (cgRect.minX - displayBounds.minX),
            y: screen.frame.maxY - (cgRect.maxY - displayBounds.minY),
            width: cgRect.width,
            height: cgRect.height
        )
    }
}

private extension NSScreen {
    var displayBounds: NSRect? {
        guard let displayID = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? CGDirectDisplayID else {
            return nil
        }

        return NSRectFromCGRect(CGDisplayBounds(displayID))
    }
}
