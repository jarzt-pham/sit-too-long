import Cocoa
import ServiceManagement
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var timer: Timer?
    private var sittingSeconds: TimeInterval = 0
    private var lastTick = Date()
    private var paused = false
    /// The reminder for the current sitting session was sent; keep counting until the user stands up.
    private var reminded = false

    /// No keyboard/mouse input for this long (or the Mac slept) = you got up, so the counter resets.
    private let awayResetSeconds: TimeInterval = 5 * 60
    private let presetMinutes = [20, 30, 40, 45, 60, 90]
    private let reminderSound = NSSound(named: "Glass")

    private var intervalMinutes: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: "intervalMinutes")
            return value > 0 ? value : 40
        }
        set { UserDefaults.standard.set(newValue, forKey: "intervalMinutes") }
    }

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

        if sittingSeconds < TimeInterval(intervalMinutes * 60) {
            reminded = false
        } else if !reminded {
            reminded = true
            sendReminder()
        }
        updateTitle()
    }

    /// The user got up: start a new sitting session and clear the reminder that is still on screen.
    private func standUp() {
        sittingSeconds = 0
        reminded = false
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        updateTitle()
    }

    private func updateTitle() {
        let remaining = intervalMinutes - Int(sittingSeconds / 60)
        // Past the interval it shows how long you are overdue, e.g. "+7m".
        statusItem.button?.title = paused ? " paused" : remaining > 0 ? " \(remaining)m" : " +\(-remaining)m"
    }

    private func sendReminder() {
        // Played by the app itself so it is heard even when Focus/Do Not Disturb hides the banner.
        reminderSound?.play()
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                guard settings.authorizationStatus == .authorized else {
                    self.showReminderAlert()
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = "Time to stand up 🧍"
                content.body = "You've been sitting for \(self.intervalMinutes) minutes. Stand up and walk around for a few minutes."
                center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
        }
    }

    /// Fallback when notifications are not allowed in System Settings.
    private func showReminderAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Time to stand up 🧍"
        alert.informativeText = "You've been sitting for \(intervalMinutes) minutes. Stand up and walk around for a few minutes."
        alert.runModal()
        standUp()
    }

    /// Clicking the reminder notification means "OK, I'm standing up".
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { self.standUp() }
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
        menu.addItem(NSMenuItem(title: "Sitting for \(sat) min (reminder every \(intervalMinutes) min)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let intervalItem = NSMenuItem(title: "Remind every", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        for minutes in presetMinutes {
            let item = NSMenuItem(title: "\(minutes) min", action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            item.state = minutes == intervalMinutes ? .on : .off
            intervalMenu.addItem(item)
        }
        intervalMenu.addItem(.separator())
        let custom = NSMenuItem(title: presetMinutes.contains(intervalMinutes) ? "Custom…" : "Custom (\(intervalMinutes) min)…",
                                action: #selector(selectCustom), keyEquivalent: "")
        custom.target = self
        custom.state = presetMinutes.contains(intervalMinutes) ? .off : .on
        intervalMenu.addItem(custom)
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        addItem("Test reminder now", #selector(testReminder), key: "t")
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

    @objc private func selectPreset(_ sender: NSMenuItem) {
        intervalMinutes = sender.tag
        updateTitle()
    }

    @objc private func selectCustom() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Remind me every … minutes"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = String(intervalMinutes)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if let minutes = Int(field.stringValue.trimmingCharacters(in: .whitespaces)), (1...480).contains(minutes) {
            intervalMinutes = minutes
            updateTitle()
        } else {
            let error = NSAlert()
            error.messageText = "Please enter a whole number between 1 and 480."
            error.runModal()
        }
    }

    @objc private func testReminder() {
        sendReminder()
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
