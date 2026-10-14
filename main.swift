import Cocoa
import ServiceManagement
import UserNotifications

/// The two reminders the app sends. The raw value is also the notification identifier.
enum Reminder: String {
    case stand, water

    var minutes: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: defaultsKey)
            return value > 0 ? value : (self == .stand ? 40 : 60)
        }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    var presets: [Int] { self == .stand ? [20, 30, 40, 45, 60, 90] : [30, 45, 60, 90, 120] }
    var title: String { self == .stand ? "Time to stand up 🧍" : "Time to drink water 💧" }
    var body: String {
        self == .stand
            ? "You've been sitting for \(minutes) minutes. Stand up and walk around for a few minutes."
            : "Have a glass of water."
    }
    var sound: NSSound? { NSSound(named: self == .stand ? "Glass" : "Bottle") }

    private var defaultsKey: String { self == .stand ? "intervalMinutes" : "waterIntervalMinutes" }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var timer: Timer?
    private var sittingSeconds: TimeInterval = 0
    private var waterSeconds: TimeInterval = 0
    private var lastTick = Date()
    private var paused = false
    /// The reminder for the current sitting session was sent; keep counting until the user stands up.
    private var reminded = false

    /// No keyboard/mouse input for this long (or the Mac slept) = you got up, so the counter resets.
    private let awayResetSeconds: TimeInterval = 5 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        statusItem.button?.image = NSImage(systemSymbolName: "figure.stand", accessibilityDescription: "Sit Reminder")
        statusItem.button?.imagePosition = .imageLeading
        menu.delegate = self
        statusItem.menu = menu

        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
        updateTitle()
    }

    // MARK: - Tracking

    private func tick() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        lastTick = now
        guard !paused else { return }

        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle >= awayResetSeconds || elapsed >= awayResetSeconds {
            if sittingSeconds > 0 { standUp() }
        } else {
            sittingSeconds += elapsed
        }
        // Water is due on a fixed period of awake time, whether or not you are at the keyboard.
        if elapsed < awayResetSeconds {
            waterSeconds += elapsed
        }

        if sittingSeconds < TimeInterval(Reminder.stand.minutes * 60) {
            reminded = false
        } else if !reminded {
            reminded = true
            send(.stand)
        }
        if waterSeconds >= TimeInterval(Reminder.water.minutes * 60) {
            waterSeconds = 0
            send(.water)
        }
        updateTitle()
    }

    /// The user got up: start a new sitting session and clear the reminder that is still on screen.
    private func standUp() {
        sittingSeconds = 0
        reminded = false
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Reminder.stand.rawValue])
        updateTitle()
    }

    private func updateTitle() {
        let remaining = Reminder.stand.minutes - Int(sittingSeconds / 60)
        // Past the interval it shows how long you are overdue, e.g. "+7m".
        statusItem.button?.title = paused ? " paused" : remaining > 0 ? " \(remaining)m" : " +\(-remaining)m"
    }

    private func send(_ reminder: Reminder) {
        // Played by the app itself so it is heard even when Focus/Do Not Disturb hides the banner.
        reminder.sound?.play()
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                guard settings.authorizationStatus == .authorized else {
                    self.showAlert(for: reminder)
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = reminder.body
                center.add(UNNotificationRequest(identifier: reminder.rawValue, content: content, trigger: nil))
            }
        }
    }

    /// Fallback when notifications are not allowed in System Settings.
    private func showAlert(for reminder: Reminder) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = reminder.title
        alert.informativeText = reminder.body
        alert.runModal()
        if reminder == .stand { standUp() }
    }

    /// Clicking the stand-up notification means "OK, I'm standing up".
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier == Reminder.stand.rawValue {
            DispatchQueue.main.async { self.standUp() }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let sat = Int(sittingSeconds / 60)
        let waterLeft = max(0, Reminder.water.minutes - Int(waterSeconds / 60))
        menu.addItem(NSMenuItem(title: "Sitting for \(sat) min (reminder every \(Reminder.stand.minutes) min)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Next water in \(waterLeft) min", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        addIntervalMenu("Stand up every", for: .stand)
        addIntervalMenu("Drink water every", for: .water)
        addItem("Test reminders now", #selector(testReminders), key: "t")
        addItem("I just stood up (reset)", #selector(resetCounter), key: "r")
        addItem(paused ? "Resume" : "Pause", #selector(togglePause), key: "p")
        menu.addItem(.separator())
        addItem("Launch at login", #selector(toggleLaunchAtLogin), key: "")
        menu.items.last?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        addItem("Quit", #selector(quit), key: "q")
    }

    private func addItem(_ title: String, _ action: Selector, key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func addIntervalMenu(_ title: String, for reminder: Reminder) {
        let current = reminder.minutes
        let submenu = NSMenu()
        for minutes in reminder.presets {
            let item = NSMenuItem(title: "\(minutes) min", action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            item.representedObject = reminder.rawValue
            item.state = minutes == current ? .on : .off
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let isCustom = !reminder.presets.contains(current)
        let custom = NSMenuItem(title: isCustom ? "Custom (\(current) min)…" : "Custom…",
                                action: #selector(selectCustom(_:)), keyEquivalent: "")
        custom.target = self
        custom.representedObject = reminder.rawValue
        custom.state = isCustom ? .on : .off
        submenu.addItem(custom)

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let reminder = (sender.representedObject as? String).flatMap(Reminder.init(rawValue:)) else { return }
        reminder.minutes = sender.tag
        updateTitle()
    }

    @objc private func selectCustom(_ sender: NSMenuItem) {
        guard let reminder = (sender.representedObject as? String).flatMap(Reminder.init(rawValue:)) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = reminder == .stand ? "Remind me to stand up every … minutes" : "Remind me to drink water every … minutes"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = String(reminder.minutes)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if let minutes = Int(field.stringValue.trimmingCharacters(in: .whitespaces)), (1...480).contains(minutes) {
            reminder.minutes = minutes
            updateTitle()
        } else {
            let error = NSAlert()
            error.messageText = "Please enter a whole number between 1 and 480."
            error.runModal()
        }
    }

    @objc private func testReminders() {
        send(.stand)
        send(.water)
    }

    @objc private func resetCounter() {
        standUp()
    }

    @objc private func togglePause() {
        paused.toggle()
        lastTick = Date()
        updateTitle()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
