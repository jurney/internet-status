import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let pingMonitor = PingMonitor()
    private var pingEnabled = true
    private var lastStats: PingStats?
    private lazy var statusMenu: NSMenu = { buildMenu() }()

    private let targets = [
        "google.com",
        "1.1.1.1",
        "8.8.8.8",
        "9.9.9.9",
        "208.67.222.222"
    ]

    private let pingRangePresets: [(label: String, min: Double, max: Double)] = [
        ("20 – 500 ms (LAN / fast broadband)", 20, 500),
        ("50 – 2000 ms (default)", 50, 2000),
        ("100 – 5000 ms (satellite / slow link)", 100, 5000),
    ]

    private let windowPresets: [(label: String, packets: Int)] = [
        ("5 packets", 5),
        ("10 packets", 10),
        ("30 packets", 30),
        ("60 packets", 60),
        ("300 packets", 300),
    ]

    private var selectedTarget: String {
        get { UserDefaults.standard.string(forKey: "target") ?? targets[0] }
        set { UserDefaults.standard.set(newValue, forKey: "target") }
    }

    private var pingMin: Double {
        get {
            let v = UserDefaults.standard.double(forKey: "pingMin")
            return v > 0 ? v : 50
        }
        set { UserDefaults.standard.set(newValue, forKey: "pingMin") }
    }

    private var pingMax: Double {
        get {
            let v = UserDefaults.standard.double(forKey: "pingMax")
            return v > 0 ? v : 2000
        }
        set { UserDefaults.standard.set(newValue, forKey: "pingMax") }
    }

    private var windowPackets: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "windowPackets")
            return v > 0 ? v : 10
        }
        set { UserDefaults.standard.set(newValue, forKey: "windowPackets") }
    }

    private var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !UserDefaults.standard.bool(forKey: "launchAtLoginConfigured") {
            UserDefaults.standard.set(true, forKey: "launchAtLoginConfigured")
            try? SMAppService.mainApp.register()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateIcon(stats: nil)
        statusMenu = buildMenu()

        pingMonitor.target = selectedTarget
        pingMonitor.windowPackets = windowPackets
        pingMonitor.onChange = { [weak self] stats in
            self?.lastStats = stats
            self?.updateIcon(stats: stats)
        }
        pingMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pingMonitor.stop()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            statusMenu = buildMenu()
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            DispatchQueue.main.async { self.statusItem.menu = nil }
        } else {
            togglePing()
        }
    }

    private func togglePing() {
        pingEnabled.toggle()
        if pingEnabled {
            pingMonitor.start()
        } else {
            pingMonitor.stop()
            lastStats = nil
            updateIcon(stats: nil)
        }
    }

    private func updateIcon(stats: PingStats?) {
        let image: NSImage
        if pingEnabled {
            let packetLoss = stats?.packetLossPercent ?? 0
            let avgLatency = stats?.avgMs ?? 0
            image = IconRenderer.render(packetLoss: packetLoss,
                                         avgLatencyMs: avgLatency,
                                         pingMin: pingMin,
                                         pingMax: pingMax)
            if let s = stats {
                statusItem.button?.toolTip = String(format:
                    "Loss: %.1f%% (%d samples)\nAvg: %.1f ms\nMin: %.1f ms\nMax: %.1f ms",
                    s.packetLossPercent, s.sampleCount,
                    s.avgMs, s.minMs, s.maxMs)
            } else {
                statusItem.button?.toolTip = "Internet Status — starting..."
            }
        } else {
            image = IconRenderer.renderDisabled()
            statusItem.button?.toolTip = "Internet Status — paused"
        }
        statusItem.button?.image = image
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // --- Target ---
        let targetHeader = NSMenuItem(title: "Ping Target", action: nil, keyEquivalent: "")
        targetHeader.isEnabled = false
        menu.addItem(targetHeader)

        for target in targets {
            let item = NSMenuItem(title: target, action: #selector(selectTarget(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = target
            if target == selectedTarget {
                item.state = .on
            }
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // --- Ping Range ---
        let rangeHeader = NSMenuItem(title: "Ping Range (icon size)", action: nil, keyEquivalent: "")
        rangeHeader.isEnabled = false
        menu.addItem(rangeHeader)

        for preset in pingRangePresets {
            let item = NSMenuItem(title: preset.label, action: #selector(selectRange(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [preset.min, preset.max]
            if preset.min == pingMin && preset.max == pingMax {
                item.state = .on
            }
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // --- Window ---
        let windowHeader = NSMenuItem(title: "Sample Window", action: nil, keyEquivalent: "")
        windowHeader.isEnabled = false
        menu.addItem(windowHeader)

        for preset in windowPresets {
            let item = NSMenuItem(title: preset.label, action: #selector(selectWindow(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.packets
            if preset.packets == windowPackets {
                item.state = .on
            }
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // --- Launch at Login ---
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Internet Status", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    @objc private func selectTarget(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? String else { return }
        selectedTarget = target
        pingMonitor.target = target
        pingMonitor.start()
        statusMenu = buildMenu()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if launchAtLogin {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
        statusMenu = buildMenu()
    }

    @objc private func selectRange(_ sender: NSMenuItem) {
        guard let values = sender.representedObject as? [Double],
              values.count == 2 else { return }
        pingMin = values[0]
        pingMax = values[1]
        statusMenu = buildMenu()
    }

    @objc private func selectWindow(_ sender: NSMenuItem) {
        guard let packets = sender.representedObject as? Int else { return }
        windowPackets = packets
        pingMonitor.windowPackets = packets
        statusMenu = buildMenu()
    }
}
