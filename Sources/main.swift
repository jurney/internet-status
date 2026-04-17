import AppKit

// Ensure only one instance runs at a time
let bundleID = Bundle.main.bundleIdentifier ?? "com.chrisjurney.internet-status"
let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
if running.count > 1 {
    // Another instance is already running — activate it and exit
    running.first { $0 != NSRunningApplication.current }?.activate()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
