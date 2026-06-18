import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum DefaultsKey {
        static let backgroundTransparency = "backgroundTransparency"
    }

    private let overlayController = FocusOverlayController()
    private var selectionController: SelectionController?
    private var statusItem: NSStatusItem?
    private var preferencesMenuView: PreferencesMenuView?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate

        // NSApplication.delegate is weak. Keep the delegate and all window
        // controllers alive for the full duration of the application.
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureDefaults()
        configureStatusItem()

        DispatchQueue.main.async { [weak self] in
            self?.beginSelection()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        DispatchQueue.main.async { [weak self] in
            self?.beginSelection()
        }
        return true
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "viewfinder",
            accessibilityDescription: "FocusC"
        )

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Select Window or Focus Area...",
            action: #selector(beginSelection),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Remove Overlay",
            action: #selector(removeOverlay),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(makePreferencesMenuItem())
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit FocusC",
            action: #selector(quit),
            keyEquivalent: ""
        )
        menu.items.forEach { $0.target = self }

        item.menu = menu
        statusItem = item
    }

    private func configureDefaults() {
        UserDefaults.standard.register(defaults: [
            DefaultsKey.backgroundTransparency: 0.15
        ])
        overlayController.backgroundTransparency = UserDefaults.standard.double(
            forKey: DefaultsKey.backgroundTransparency
        )
    }

    private func makePreferencesMenuItem() -> NSMenuItem {
        let preferencesItem = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: "")
        let preferencesMenu = NSMenu()
        let controlItem = NSMenuItem()
        let controlView = PreferencesMenuView(
            transparency: overlayController.backgroundTransparency
        ) { [weak self] transparency in
            guard let self else { return }
            self.overlayController.backgroundTransparency = transparency
            UserDefaults.standard.set(
                Double(transparency),
                forKey: DefaultsKey.backgroundTransparency
            )
        }
        controlItem.view = controlView
        preferencesMenu.addItem(controlItem)
        preferencesItem.submenu = preferencesMenu
        preferencesMenuView = controlView
        return preferencesItem
    }

    @objc private func beginSelection() {
        selectionController?.cancel()
        overlayController.hide()

        let controller = SelectionController()
        controller.onSelection = { [weak self] rectangle in
            self?.selectionController = nil
            // Present on the next event-loop turn so the mouse gesture that
            // completed selection cannot interact with the new close panel.
            DispatchQueue.main.async {
                self?.overlayController.show(focusRect: rectangle)
            }
        }
        controller.onCancel = { [weak self] in
            self?.selectionController = nil
        }

        selectionController = controller
        controller.begin()
    }

    @objc private func removeOverlay() {
        overlayController.hide()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private final class PreferencesMenuView: NSView {
    private let valueLabel = NSTextField(labelWithString: "")
    private let onChange: (CGFloat) -> Void

    init(transparency: CGFloat, onChange: @escaping (CGFloat) -> Void) {
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 68))

        let titleLabel = NSTextField(labelWithString: "Background opacity")
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.frame = NSRect(x: 14, y: 39, width: 190, height: 18)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: 205, y: 39, width: 40, height: 18)

        let slider = NSSlider(
            value: Double(1 - transparency),
            minValue: 0,
            maxValue: 1,
            target: self,
            action: #selector(sliderChanged(_:))
        )
        slider.isContinuous = true
        slider.numberOfTickMarks = 11
        slider.allowsTickMarkValuesOnly = false
        slider.frame = NSRect(x: 14, y: 9, width: 232, height: 24)

        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(slider)
        updateValueLabel(1 - transparency)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let opacity = CGFloat(sender.doubleValue)
        updateValueLabel(opacity)
        onChange(1 - opacity)
    }

    private func updateValueLabel(_ opacity: CGFloat) {
        valueLabel.stringValue = String(format: "%.2f", Double(opacity))
    }
}
