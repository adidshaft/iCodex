/// icodex_keystroke — tiny native helper for posting keyboard events.
///
/// Lives inside iCodex-Connect.app/Contents/MacOS/ so macOS associates
/// it with the app for Accessibility/TCC. Python calls it via subprocess.
///
/// Usage:
///   icodex_keystroke check          → prints "granted" or "denied"
///   icodex_keystroke request        → triggers macOS Accessibility prompt
///   icodex_keystroke key ACTION     → send a single key action
///   icodex_keystroke paste_enter    → Cmd+V then Enter
///   icodex_keystroke escape         → Escape key
///   icodex_keystroke ctrl_c         → Ctrl+C
///   icodex_keystroke activate BUNDLEID → bring app to front

import Cocoa
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Keystroke helpers

func bundleURL(for executablePath: String) -> URL {
    URL(fileURLWithPath: executablePath)
        .deletingLastPathComponent()  // MacOS
        .deletingLastPathComponent()  // Contents
        .deletingLastPathComponent()  // .app
}

func isInstalledInApplications(_ appURL: URL) -> Bool {
    let normalizedPath = appURL.resolvingSymlinksInPath().path
    let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true).path + "/"
    let userApplications = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Applications", isDirectory: true).path + "/"

    return normalizedPath.hasPrefix(systemApplications) || normalizedPath.hasPrefix(userApplications)
}

func preferredInstallURL(for appURL: URL) -> URL {
    let fileManager = FileManager.default
    let appName = appURL.lastPathComponent
    let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
    if fileManager.isWritableFile(atPath: systemApplications.path) {
        return systemApplications.appendingPathComponent(appName, isDirectory: true)
    }

    let userApplications = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Applications", isDirectory: true)
    try? fileManager.createDirectory(at: userApplications, withIntermediateDirectories: true)
    return userApplications.appendingPathComponent(appName, isDirectory: true)
}

func appVolumeURL(for appURL: URL) -> URL? {
    try? appURL.resourceValues(forKeys: [.volumeURLKey]).volume
}

func installerVolumes(appNamed appName: String, excluding currentAppURL: URL? = nil) -> [URL] {
    let fileManager = FileManager.default
    let mounted = fileManager.mountedVolumeURLs(
        includingResourceValuesForKeys: [.volumeURLKey],
        options: []
    ) ?? []

    return mounted.filter { volumeURL in
        if let currentAppURL,
           let currentVolume = appVolumeURL(for: currentAppURL),
           currentVolume.resolvingSymlinksInPath() == volumeURL.resolvingSymlinksInPath() {
            return false
        }

        let bundledApp = volumeURL.appendingPathComponent("\(appName).app", isDirectory: true)
        let installNote = volumeURL.appendingPathComponent("Install \(appName).txt")
        let applicationsAlias = volumeURL.appendingPathComponent("Applications")
        return fileManager.fileExists(atPath: bundledApp.path)
            && fileManager.fileExists(atPath: installNote.path)
            && fileManager.fileExists(atPath: applicationsAlias.path)
    }
}

@discardableResult
func ejectVolume(_ volumeURL: URL) -> Bool {
    func detach(arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = arguments
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    return detach(arguments: ["detach", volumeURL.path, "-quiet"])
        || detach(arguments: ["detach", volumeURL.path, "-force", "-quiet"])
}

func shellQuoted(_ string: String) -> String {
    "'" + string.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}

func scheduleEjectVolume(_ volumeURL: URL, after delaySeconds: Int = 2) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    let quotedPath = shellQuoted(volumeURL.path)
    task.arguments = [
        "-c",
        "sleep \(delaySeconds); /usr/bin/hdiutil detach \(quotedPath) -quiet || /usr/bin/hdiutil detach \(quotedPath) -force -quiet"
    ]
    try? task.run()
}

func cleanupMountedInstallerVolumes(appNamed appName: String, excluding currentAppURL: URL? = nil) {
    for volumeURL in installerVolumes(appNamed: appName, excluding: currentAppURL) {
        _ = ejectVolume(volumeURL)
    }
}

func relaunchInstalledApp(at installedAppURL: URL) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    task.arguments = [installedAppURL.path]
    try? task.run()
}

func installAppBundle(from sourceAppURL: URL, to destinationAppURL: URL) throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: destinationAppURL.path) {
        try fileManager.removeItem(at: destinationAppURL)
    }
    try fileManager.copyItem(at: sourceAppURL, to: destinationAppURL)
}

func promptToInstallInApplications(appURL: URL) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.activate(ignoringOtherApps: true)

    let destinationURL = preferredInstallURL(for: appURL)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Install iCodex-Connect to Applications"
    alert.informativeText = """
    iCodex-Connect works best when launched from Applications.

    Running it from the DMG or another folder can prevent Accessibility permission from sticking correctly.
    Install location:
    \(destinationURL.path)
    """
    alert.addButton(withTitle: "Install and Open")
    alert.addButton(withTitle: "Show Me")
    alert.addButton(withTitle: "Quit")

    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
        do {
            try installAppBundle(from: appURL, to: destinationURL)
            relaunchInstalledApp(at: destinationURL)
            if let sourceVolume = appVolumeURL(for: appURL) {
                scheduleEjectVolume(sourceVolume)
            }
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .critical
            failure.messageText = "Could Not Install iCodex-Connect"
            failure.informativeText = """
            \(error.localizedDescription)

            Try dragging the app into Applications manually, then open it from there.
            """
            failure.addButton(withTitle: "OK")
            failure.runModal()
        }
    } else if response == .alertSecondButtonReturn {
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
        NSWorkspace.shared.open(destinationURL.deletingLastPathComponent())
    }

    exit(0)
}

func openAccessibilitySettings() {
    guard let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    ) else {
        return
    }
    NSWorkspace.shared.open(settingsURL)
}

@discardableResult
func requestAccessibilityIfNeeded() -> Bool {
    guard !CGPreflightPostEventAccess() else {
        return false
    }

    CGRequestPostEventAccess()
    openAccessibilitySettings()
    return true
}

func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags = []) {
    guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    else {
        fputs("error: could not create keyboard event\n", stderr)
        exit(1)
    }
    if !flags.isEmpty {
        keyDown.flags = flags
        keyUp.flags = flags
    }
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
    usleep(100_000)  // 0.1s between events
}

func activateApp(bundleID: String) -> Bool {
    guard let app = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleID
    ).first else {
        return false
    }
    if #available(macOS 14.0, *) {
        app.activate()
    } else {
        app.activate(options: .activateIgnoringOtherApps)
    }
    usleep(500_000)  // 0.5s for activation
    return true
}

func setClipboard(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
    usleep(100_000)
}

func postNamedAction(_ action: String) -> Bool {
    switch action {
    case "enter":
        postKeystroke(keyCode: 36)
    case "tab":
        postKeystroke(keyCode: 48)
    case "shift_tab":
        postKeystroke(keyCode: 48, flags: .maskShift)
    case "space":
        postKeystroke(keyCode: 49)
    case "escape":
        postKeystroke(keyCode: 53)
    case "up":
        postKeystroke(keyCode: 126)
    case "down":
        postKeystroke(keyCode: 125)
    case "left":
        postKeystroke(keyCode: 123)
    case "right":
        postKeystroke(keyCode: 124)
    case "page_up":
        postKeystroke(keyCode: 116)
    case "page_down":
        postKeystroke(keyCode: 121)
    case "jump_top":
        postKeystroke(keyCode: 126, flags: .maskCommand)
    case "jump_bottom":
        postKeystroke(keyCode: 125, flags: .maskCommand)
    default:
        return false
    }
    return true
}

// MARK: - Accessibility helpers

struct SessionStateSnapshot: Codable {
    let locked: Bool
    let onConsole: Bool
    let loginDone: Bool
    let screensaverRunning: Bool
}

struct ActionableControlSnapshot: Codable {
    let id: String
    let title: String
    let role: String
    let enabled: Bool
    let selected: Bool
    let focused: Bool
}

struct DiscoveredControl {
    let snapshot: ActionableControlSnapshot
    let element: AXUIElement
}

private let actionableRoles: Set<String> = [
    kAXButtonRole as String,
    kAXRadioButtonRole as String,
    kAXCheckBoxRole as String,
    kAXMenuButtonRole as String,
    kAXPopUpButtonRole as String,
    kAXDisclosureTriangleRole as String,
]

private let chromeControlTitles: Set<String> = [
    "close",
    "minimize",
    "zoom",
]

func axCopyValue(_ element: AXUIElement, _ attribute: CFString) -> AnyObject? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard error == .success else {
        return nil
    }
    return value
}

func axStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
    axCopyValue(element, attribute) as? String
}

func axBoolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
    if let value = axCopyValue(element, attribute) as? Bool {
        return value
    }
    if let number = axCopyValue(element, attribute) as? NSNumber {
        return number.boolValue
    }
    return nil
}

func axElementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
    guard let value = axCopyValue(element, attribute) else {
        return nil
    }
    let cfValue = value as CFTypeRef
    guard CFGetTypeID(cfValue) == AXUIElementGetTypeID() else {
        return nil
    }
    return unsafeBitCast(cfValue, to: AXUIElement.self)
}

func axElementArrayAttribute(_ element: AXUIElement, _ attribute: CFString) -> [AXUIElement] {
    axCopyValue(element, attribute) as? [AXUIElement] ?? []
}

func codexRunningApplication(bundleID: String) -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
}

func codexAppElement(bundleID: String) -> AXUIElement? {
    guard let app = codexRunningApplication(bundleID: bundleID) else {
        return nil
    }
    return AXUIElementCreateApplication(app.processIdentifier)
}

func focusedWindowElement(bundleID: String) -> AXUIElement? {
    guard let appElement = codexAppElement(bundleID: bundleID) else {
        return nil
    }
    if let focusedWindow = axElementAttribute(appElement, kAXFocusedWindowAttribute as CFString) {
        return focusedWindow
    }
    return axElementArrayAttribute(appElement, kAXWindowsAttribute as CFString).first
}

func focusedUIElement(bundleID: String) -> AXUIElement? {
    guard let appElement = codexAppElement(bundleID: bundleID) else {
        return nil
    }
    return axElementAttribute(appElement, kAXFocusedUIElementAttribute as CFString)
}

func normalizedControlTitle(_ element: AXUIElement) -> String {
    let candidates = [
        axStringAttribute(element, kAXTitleAttribute as CFString),
        axStringAttribute(element, kAXDescriptionAttribute as CFString),
        axStringAttribute(element, kAXValueAttribute as CFString),
        axStringAttribute(element, kAXHelpAttribute as CFString),
    ]
    for candidate in candidates {
        let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
    }
    return ""
}

func collectActionableControls(
    root: AXUIElement,
    maxDepth: Int,
    depth: Int = 0,
    controls: inout [(element: AXUIElement, title: String, role: String, enabled: Bool, selected: Bool, focused: Bool)]
) {
    if depth > maxDepth {
        return
    }

    let role = axStringAttribute(root, kAXRoleAttribute as CFString) ?? ""
    let title = normalizedControlTitle(root)
    let enabled = axBoolAttribute(root, kAXEnabledAttribute as CFString) ?? true
    let selected = axBoolAttribute(root, kAXSelectedAttribute as CFString) ?? false
    let focused = axBoolAttribute(root, kAXFocusedAttribute as CFString) ?? false

    if actionableRoles.contains(role), !title.isEmpty {
        controls.append((root, title, role, enabled, selected, focused))
    }

    let childAttributes: [CFString] = [
        kAXChildrenAttribute as CFString,
        kAXContentsAttribute as CFString,
    ]

    for attribute in childAttributes {
        let children = axElementArrayAttribute(root, attribute)
        if children.isEmpty {
            continue
        }
        for child in children {
            collectActionableControls(root: child, maxDepth: maxDepth, depth: depth + 1, controls: &controls)
        }
    }
}

func filterMirroredControls(
    _ controls: [(element: AXUIElement, title: String, role: String, enabled: Bool, selected: Bool, focused: Bool)]
) -> [(element: AXUIElement, title: String, role: String, enabled: Bool, selected: Bool, focused: Bool)] {
    var seen = Set<String>()
    return controls.filter { control in
        let normalized = control.title.lowercased()
        guard !chromeControlTitles.contains(normalized),
              !normalized.contains("stop"),
              !normalized.contains("interrupt")
        else {
            return false
        }
        let key = "\(control.role)|\(normalized)"
        if seen.contains(key) {
            return false
        }
        seen.insert(key)
        return true
    }
}

func enumerateControls(
    _ controls: [(element: AXUIElement, title: String, role: String, enabled: Bool, selected: Bool, focused: Bool)]
) -> [DiscoveredControl] {
    controls.enumerated().map { index, control in
        let id = "control-\(index + 1)"
        let snapshot = ActionableControlSnapshot(
            id: id,
            title: control.title,
            role: control.role,
            enabled: control.enabled,
            selected: control.selected,
            focused: control.focused
        )
        return DiscoveredControl(snapshot: snapshot, element: control.element)
    }
}

func discoverMirroredControls(bundleID: String) -> [DiscoveredControl] {
    if let focused = focusedUIElement(bundleID: bundleID) {
        var ancestor: AXUIElement? = focused
        for _ in 0..<2 {
            guard let current = ancestor else {
                break
            }
            if let parent = axElementAttribute(current, kAXParentAttribute as CFString) {
                var grouped: [(element: AXUIElement, title: String, role: String, enabled: Bool, selected: Bool, focused: Bool)] = []
                for child in axElementArrayAttribute(parent, kAXChildrenAttribute as CFString) {
                    collectActionableControls(root: child, maxDepth: 2, controls: &grouped)
                }
                let filtered = filterMirroredControls(grouped)
                if filtered.count >= 2, filtered.count <= 12 {
                    return enumerateControls(filtered)
                }
                ancestor = parent
            } else {
                break
            }
        }
    }

    guard let window = focusedWindowElement(bundleID: bundleID) else {
        return []
    }
    var controls: [(element: AXUIElement, title: String, role: String, enabled: Bool, selected: Bool, focused: Bool)] = []
    collectActionableControls(root: window, maxDepth: 8, controls: &controls)
    return enumerateControls(filterMirroredControls(controls))
}

func discoverAllControls(bundleID: String) -> [DiscoveredControl] {
    guard let window = focusedWindowElement(bundleID: bundleID) else {
        return []
    }
    var controls: [(element: AXUIElement, title: String, role: String, enabled: Bool, selected: Bool, focused: Bool)] = []
    collectActionableControls(root: window, maxDepth: 8, controls: &controls)

    var seen = Set<String>()
    let unique = controls.filter { control in
        let key = "\(control.role)|\(control.title.lowercased())"
        if seen.contains(key) {
            return false
        }
        seen.insert(key)
        return true
    }
    return enumerateControls(unique)
}

func pressControl(_ control: DiscoveredControl) -> Bool {
    guard control.snapshot.enabled else {
        return false
    }
    let result = AXUIElementPerformAction(control.element, kAXPressAction as CFString)
    if result == .success {
        usleep(200_000)
        return true
    }
    return false
}

func pressMirroredControl(bundleID: String, controlID: String) -> Bool {
    discoverMirroredControls(bundleID: bundleID)
        .first(where: { $0.snapshot.id == controlID })
        .map(pressControl) ?? false
}

func pressMatchingControl(bundleID: String, keywords: [String]) -> Bool {
    let normalizedKeywords = keywords.map { $0.lowercased() }
    for control in discoverAllControls(bundleID: bundleID) {
        let title = control.snapshot.title.lowercased()
        if normalizedKeywords.contains(where: { title.contains($0) }) {
            return pressControl(control)
        }
    }
    return false
}

func sessionStateSnapshot() -> SessionStateSnapshot {
    let session = (CGSessionCopyCurrentDictionary() as? [String: Any]) ?? [:]
    let onConsole = (session["kCGSSessionOnConsoleKey"] as? NSNumber)?.boolValue ?? true
    let loginDone = (session["kCGSessionLoginDoneKey"] as? NSNumber)?.boolValue ?? true
    let locked = (session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
    let screensaverRunning = !NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.apple.ScreenSaver.Engine"
    ).isEmpty

    return SessionStateSnapshot(
        locked: locked || !onConsole || !loginDone,
        onConsole: onConsole,
        loginDone: loginDone,
        screensaverRunning: screensaverRunning
    )
}

func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    guard let data = try? encoder.encode(value),
          let string = String(data: data, encoding: .utf8) else {
        fputs("error: could not encode JSON\n", stderr)
        exit(1)
    }
    print(string)
}

// MARK: - App launcher mode

func launchBackend() {
    // When invoked with no args, we're the CFBundleExecutable being launched
    // by macOS. Spawn the bash launcher script to set up Python + start server.
    let execPath = CommandLine.arguments[0]
    let appURL = bundleURL(for: execPath)
    let appName = appURL.deletingPathExtension().lastPathComponent
    if !isInstalledInApplications(appURL) {
        promptToInstallInApplications(appURL: appURL)
    }
    cleanupMountedInstallerVolumes(appNamed: appName, excluding: appURL)

    let macosDir = (execPath as NSString).deletingLastPathComponent
    let contentsDir = (macosDir as NSString).deletingLastPathComponent
    let resourcesDir = (contentsDir as NSString).appendingPathComponent("Resources")
    let launcher = (resourcesDir as NSString).appendingPathComponent("icodex_launcher.sh")
    let requestedAccessibility = requestAccessibilityIfNeeded()

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/bash")
    task.arguments = [launcher]
    task.currentDirectoryURL = URL(fileURLWithPath: macosDir)
    var environment = ProcessInfo.processInfo.environment
    if requestedAccessibility {
        environment["ICODEX_SHOW_A11Y_GUIDANCE"] = "1"
    }
    task.environment = environment
    // Detach: launcher runs in background, we exit so macOS is happy
    do {
        try task.run()
    } catch {
        fputs("error: could not launch backend: \(error)\n", stderr)
        exit(1)
    }
    // Exit immediately — the bash launcher → Python will keep running
    exit(0)
}

// MARK: - Main

let args = CommandLine.arguments
if args.count < 2 {
    // No arguments = launched as the app → start the backend
    launchBackend()
}

switch args[1] {
case "check":
    // Check if we have Accessibility (post-event) permission
    let granted = CGPreflightPostEventAccess()
    print(granted ? "granted" : "denied")

case "request":
    // Trigger macOS native Accessibility permission prompt
    CGRequestPostEventAccess()
    print("requested")

case "paste_enter":
    // Cmd+V (paste), wait, then Enter
    postKeystroke(keyCode: 9, flags: .maskCommand)   // Cmd+V
    usleep(300_000)                                   // 0.3s
    postKeystroke(keyCode: 36)                        // Enter
    print("ok")

case "key":
    guard args.count >= 3 else {
        fputs("usage: icodex_keystroke key <enter|tab|shift_tab|space|escape|up|down|left|right|page_up|page_down|jump_top|jump_bottom>\n", stderr)
        exit(1)
    }
    if postNamedAction(args[2]) {
        print("ok")
    } else {
        fputs("unknown key action: \(args[2])\n", stderr)
        exit(1)
    }

case "escape":
    postKeystroke(keyCode: 53)
    print("ok")

case "ctrl_c":
    postKeystroke(keyCode: 8, flags: .maskControl)
    print("ok")

case "activate":
    guard args.count >= 3 else {
        fputs("usage: icodex_keystroke activate <bundle_id>\n", stderr)
        exit(1)
    }
    if activateApp(bundleID: args[2]) {
        print("ok")
    } else {
        print("not_found")
        exit(1)
    }

case "session_state":
    printJSON(sessionStateSnapshot())

case "list_controls":
    guard args.count >= 3 else {
        fputs("usage: icodex_keystroke list_controls <bundle_id>\n", stderr)
        exit(1)
    }
    let controls = discoverMirroredControls(bundleID: args[2]).map(\.snapshot)
    printJSON(controls)

case "press_control":
    guard args.count >= 4 else {
        fputs("usage: icodex_keystroke press_control <bundle_id> <control_id>\n", stderr)
        exit(1)
    }
    if pressMirroredControl(bundleID: args[2], controlID: args[3]) {
        print("ok")
    } else {
        fputs("error: could not press control\n", stderr)
        exit(1)
    }

case "press_matching":
    guard args.count >= 4 else {
        fputs("usage: icodex_keystroke press_matching <bundle_id> <keyword> [keyword...]\n", stderr)
        exit(1)
    }
    if pressMatchingControl(bundleID: args[2], keywords: Array(args.dropFirst(3))) {
        print("ok")
    } else {
        fputs("error: no matching control found\n", stderr)
        exit(1)
    }

case "clipboard":
    // Set clipboard text (read from stdin or arg)
    let text: String
    if args.count >= 3 {
        text = args[2]
    } else {
        text = (readLine(strippingNewline: false) ?? "")
    }
    setClipboard(text)
    print("ok")

case "send":
    // Full sequence: activate app, set clipboard, paste, enter
    guard args.count >= 3 else {
        fputs("usage: icodex_keystroke send <bundle_id> [message]\n", stderr)
        exit(1)
    }
    let bundleID = args[2]
    let message: String
    if args.count >= 4 {
        message = args[3]
    } else {
        // Read from stdin
        message = (readLine(strippingNewline: false) ?? "")
    }

    guard activateApp(bundleID: bundleID) else {
        fputs("error: could not activate \(bundleID)\n", stderr)
        print("activate_failed")
        exit(1)
    }

    setClipboard(message)
    postKeystroke(keyCode: 9, flags: .maskCommand)   // Cmd+V
    usleep(300_000)
    postKeystroke(keyCode: 36)                        // Enter
    print("ok")

default:
    fputs("unknown command: \(args[1])\n", stderr)
    exit(1)
}
