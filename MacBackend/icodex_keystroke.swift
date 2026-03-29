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
import Darwin
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

// MARK: - Native menu bar app

private let backendPort = 8642
private let latestDmgURL = "https://github.com/adidshaft/iCodex/releases/download/main-build/iCodex-Connect.dmg"
private let autoOpenInterval: TimeInterval = 24 * 60 * 60

struct InternalDeviceSnapshot: Codable {
    let id: String
    let ip: String
    let name: String
}

struct PairingStatusSnapshot: Codable {
    let running: Bool
    let local_ip: String
    let port: Int
    let passcode: String
    let devices: [InternalDeviceSnapshot]
}

struct MenuState: Codable {
    var lastPairingMenuOpenedAt: TimeInterval = 0
}

func appSupportDirectory() -> URL {
    let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    return root.appendingPathComponent("Library/Application Support/iCodex-Connect", isDirectory: true)
}

func menuStateURL() -> URL {
    appSupportDirectory().appendingPathComponent("menu_state.json")
}

func instanceLockURL() -> URL {
    appSupportDirectory().appendingPathComponent("menu.lock")
}

func authFileURL() -> URL {
    URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent(".codex/icodex_auth.json")
}

func internalRequestData(path: String, method: String = "GET") -> Data? {
    guard let url = URL(string: "http://127.0.0.1:\(backendPort)\(path)") else {
        return nil
    }

    var request = URLRequest(url: url, timeoutInterval: 1.5)
    request.httpMethod = method
    request.setValue("menubar", forHTTPHeaderField: "X-Internal")
    if method != "GET" {
        request.httpBody = Data()
    }

    let semaphore = DispatchSemaphore(value: 0)
    var output: Data?
    URLSession.shared.dataTask(with: request) { data, response, _ in
        if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
            output = data
        }
        semaphore.signal()
    }.resume()
    _ = semaphore.wait(timeout: .now() + 2.0)
    return output
}

func fetchPairingStatus() -> PairingStatusSnapshot? {
    guard let data = internalRequestData(path: "/internal/pairing-status") else {
        return nil
    }
    return try? JSONDecoder().decode(PairingStatusSnapshot.self, from: data)
}

func disconnectDevice(_ deviceID: String) -> Bool {
    internalRequestData(path: "/internal/devices/\(deviceID)/disconnect", method: "POST") != nil
}

func disconnectAllDevices() -> Bool {
    internalRequestData(path: "/internal/devices/disconnect-all", method: "POST") != nil
}

func readMenuState() -> MenuState {
    let url = menuStateURL()
    guard let data = try? Data(contentsOf: url),
          let state = try? JSONDecoder().decode(MenuState.self, from: data) else {
        return MenuState()
    }
    return state
}

func writeMenuState(_ state: MenuState) {
    let dir = appSupportDirectory()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(state) {
        try? data.write(to: menuStateURL(), options: [.atomic])
    }
}

func fallbackPasscode() -> String {
    guard let data = try? Data(contentsOf: authFileURL()),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let passcode = object["setup_passcode"] as? String else {
        return "------"
    }
    return passcode
}

func generateQRCodeImage(payload: String, size: CGFloat = 120) -> NSImage? {
    guard let data = payload.data(using: .utf8),
          let filter = CIFilter(name: "CIQRCodeGenerator") else {
        return nil
    }

    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let outputImage = filter.outputImage else {
        return nil
    }

    let scaleX = size / outputImage.extent.size.width
    let scaleY = size / outputImage.extent.size.height
    let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    let rep = NSCIImageRep(ciImage: transformed)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(rep)
    return image
}

func openAccessibilitySettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
        return
    }
    NSWorkspace.shared.open(url)
}

func shell(_ launchPath: String, _ arguments: [String]) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: launchPath)
    task.arguments = arguments
    try? task.run()
}

func freeBackendPort() {
    shell("/bin/sh", ["-c", "lsof -ti:\(backendPort) 2>/dev/null | xargs kill -9 2>/dev/null || true"])
}

final class NativeMenuBarController: NSObject, NSApplicationDelegate {
    private let execPath = CommandLine.arguments[0]
    private lazy var appURL = bundleURL(for: execPath)
    private lazy var appName = appURL.deletingPathExtension().lastPathComponent
    private lazy var resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
    private lazy var launcherURL = resourcesURL.appendingPathComponent("icodex_launcher.sh")

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Server: Starting…", action: nil, keyEquivalent: "")
    private let startStopItem = NSMenuItem(title: "Start Server", action: #selector(toggleServer(_:)), keyEquivalent: "")
    private let urlItem = NSMenuItem(title: "Server URL unavailable", action: #selector(copyURL(_:)), keyEquivalent: "")
    private let passcodeItem = NSMenuItem(title: "Passcode: ------", action: #selector(copyPasscode(_:)), keyEquivalent: "")
    private let qrPreviewItem = NSMenuItem()
    private let pairingLinkItem = NSMenuItem(title: "Copy Pairing Link", action: #selector(copyPairingLink(_:)), keyEquivalent: "")
    private let updateItem = NSMenuItem(title: "Download Latest Build", action: #selector(downloadLatestBuild(_:)), keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "Accessibility: Checking…", action: #selector(openAccessibility(_:)), keyEquivalent: "")
    private let devicesRootItem = NSMenuItem(title: "Devices (0)", action: nil, keyEquivalent: "")
    private let devicesMenu = NSMenu()
    private let quitItem = NSMenuItem(title: "Quit iCodex", action: #selector(quitApp(_:)), keyEquivalent: "q")

    private var qrImageView: NSImageView?
    private var qrSubtitleField: NSTextField?
    private var qrHostField: NSTextField?
    private var qrPasscodeField: NSTextField?
    private var qrHintField: NSTextField?

    private var refreshTimer: Timer?
    private var serverProcess: Process?
    private var wantsServerRunning = true
    private var lastStatus: PairingStatusSnapshot?
    private var menuState = readMenuState()
    private var instanceLockDescriptor: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !isInstalledInApplications(appURL) {
            promptToInstallInApplications(appURL: appURL)
        }

        guard acquireInstanceLock() else {
            NSApp.terminate(nil)
            return
        }

        cleanupMountedInstallerVolumes(appNamed: appName, excluding: appURL)
        setupStatusItem()
        setupMenu()
        ensureServerRunningIfNeeded()
        refreshStatus()

        refreshTimer = Timer.scheduledTimer(
            timeInterval: 5.0,
            target: self,
            selector: #selector(refreshTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )

        if shouldAutoOpenPairingMenu() {
            markPairingMenuAutoOpened()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.statusItem.button?.performClick(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        stopServer()
        cleanupMountedInstallerVolumes(appNamed: appName, excluding: appURL)
        releaseInstanceLock()
    }

    private func acquireInstanceLock() -> Bool {
        let supportDirectory = appSupportDirectory()
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)

        let descriptor = open(instanceLockURL().path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor != -1 else {
            return false
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }
        instanceLockDescriptor = descriptor
        return true
    }

    private func releaseInstanceLock() {
        guard instanceLockDescriptor != -1 else {
            return
        }
        flock(instanceLockDescriptor, LOCK_UN)
        close(instanceLockDescriptor)
        instanceLockDescriptor = -1
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(
                systemSymbolName: "qrcode.viewfinder",
                accessibilityDescription: "iCodex-Connect"
            ) {
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageLeading
            }
            button.title = " iC"
        }
        statusItem.button?.toolTip = "iCodex-Connect"
        statusItem.menu = menu
    }

    private func setupMenu() {
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        startStopItem.target = self
        menu.addItem(startStopItem)

        urlItem.target = self
        menu.addItem(urlItem)

        passcodeItem.target = self
        menu.addItem(passcodeItem)

        qrPreviewItem.view = makeQRPreviewView()
        qrPreviewItem.isEnabled = false
        menu.addItem(qrPreviewItem)

        pairingLinkItem.target = self
        menu.addItem(pairingLinkItem)

        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())

        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        devicesRootItem.submenu = devicesMenu
        menu.addItem(devicesRootItem)

        menu.addItem(.separator())

        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func makeLabel(_ text: String, frame: NSRect, font: NSFont, alpha: CGFloat = 1.0) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.alignment = .center
        label.font = font
        label.textColor = NSColor.labelColor.withAlphaComponent(alpha)
        return label
    }

    private func makeQRPreviewView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 296, height: 260))

        let title = makeLabel(
            "Pair iPhone with this Mac",
            frame: NSRect(x: 18, y: 228, width: 260, height: 20),
            font: .boldSystemFont(ofSize: 14)
        )
        view.addSubview(title)

        let subtitle = makeLabel(
            "Scan with Camera or the in-app QR scanner.",
            frame: NSRect(x: 18, y: 204, width: 260, height: 18),
            font: .systemFont(ofSize: 12),
            alpha: 0.78
        )
        view.addSubview(subtitle)
        qrSubtitleField = subtitle

        let imageView = NSImageView(frame: NSRect(x: 88, y: 74, width: 120, height: 120))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        view.addSubview(imageView)
        qrImageView = imageView

        let host = makeLabel(
            "",
            frame: NSRect(x: 18, y: 44, width: 260, height: 18),
            font: .systemFont(ofSize: 12)
        )
        view.addSubview(host)
        qrHostField = host

        let passcode = makeLabel(
            "",
            frame: NSRect(x: 18, y: 24, width: 260, height: 18),
            font: .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        )
        view.addSubview(passcode)
        qrPasscodeField = passcode

        let hint = makeLabel(
            "",
            frame: NSRect(x: 18, y: 6, width: 260, height: 14),
            font: .systemFont(ofSize: 11),
            alpha: 0.72
        )
        view.addSubview(hint)
        qrHintField = hint

        return view
    }

    private func shouldAutoOpenPairingMenu() -> Bool {
        Date().timeIntervalSince1970 - menuState.lastPairingMenuOpenedAt >= autoOpenInterval
    }

    private func markPairingMenuAutoOpened() {
        menuState.lastPairingMenuOpenedAt = Date().timeIntervalSince1970
        writeMenuState(menuState)
    }

    private func ensureServerRunningIfNeeded() {
        guard wantsServerRunning else {
            return
        }
        if fetchPairingStatus() != nil {
            return
        }
        startServer()
    }

    private func startServer() {
        guard serverProcess?.isRunning != true else {
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [launcherURL.path]
        task.currentDirectoryURL = resourcesURL
        task.environment = ProcessInfo.processInfo.environment
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.serverProcess = nil
                self?.refreshStatus()
            }
        }

        do {
            try task.run()
            serverProcess = task
        } catch {
            NSSound.beep()
            fputs("error: could not start local backend: \(error)\n", stderr)
        }
    }

    private func stopServer() {
        serverProcess?.terminate()
        serverProcess = nil
        freeBackendPort()
    }

    private func updateTooltip(running: Bool, devicesCount: Int) {
        if running {
            statusItem.button?.toolTip = devicesCount > 0
                ? "iCodex-Connect running · \(devicesCount) device\(devicesCount == 1 ? "" : "s") connected"
                : "iCodex-Connect running"
        } else {
            statusItem.button?.toolTip = "iCodex-Connect stopped"
        }
    }

    private func updateQRPreview(with status: PairingStatusSnapshot?) {
        guard let subtitle = qrSubtitleField,
              let host = qrHostField,
              let passcode = qrPasscodeField,
              let hint = qrHintField,
              let imageView = qrImageView else {
            return
        }

        guard let status else {
            imageView.image = nil
            subtitle.stringValue = "Start the server to generate the pairing QR."
            host.stringValue = "Open iCodex-Connect from the menu bar any time."
            passcode.stringValue = ""
            hint.stringValue = ""
            return
        }

        guard !status.local_ip.isEmpty, status.local_ip != "127.0.0.1" else {
            imageView.image = nil
            subtitle.stringValue = "Join Wi-Fi to generate the pairing QR."
            host.stringValue = "The iPhone app can still pair manually later."
            passcode.stringValue = ""
            hint.stringValue = ""
            return
        }

        guard status.passcode.count == 6 else {
            imageView.image = nil
            subtitle.stringValue = "Pairing passcode is still loading."
            host.stringValue = "Mac: \(status.local_ip):\(status.port)"
            passcode.stringValue = ""
            hint.stringValue = "Retry in a moment."
            return
        }

        let pairingURL = "icodex://pair?host=\(status.local_ip)&port=\(status.port)&passcode=\(status.passcode)"
        imageView.image = generateQRCodeImage(payload: pairingURL)
        subtitle.stringValue = "Scan to pair instantly. The pairing code refreshes every 24 hours."
        host.stringValue = "Mac: \(status.local_ip):\(status.port)"
        passcode.stringValue = "Passcode: \(status.passcode)"
        hint.stringValue = "Tip: Camera scan jumps straight into iCodex."
    }

    private func rebuildDevicesMenu(with devices: [InternalDeviceSnapshot]) {
        devicesMenu.removeAllItems()
        devicesRootItem.title = "Devices (\(devices.count))"

        if devices.isEmpty {
            let empty = NSMenuItem(title: "No devices connected", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            devicesMenu.addItem(empty)
            return
        }

        for device in devices {
            let item = NSMenuItem(
                title: "\(device.name) (\(device.ip))",
                action: #selector(disconnectDeviceAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device.id
            devicesMenu.addItem(item)
        }

        devicesMenu.addItem(.separator())
        let disconnectAll = NSMenuItem(title: "Disconnect All", action: #selector(disconnectAllDevicesAction(_:)), keyEquivalent: "")
        disconnectAll.target = self
        devicesMenu.addItem(disconnectAll)
    }

    @objc private func refreshTimerFired(_ timer: Timer) {
        refreshStatus()
    }

    private func refreshStatus() {
        let status = fetchPairingStatus()
        if status == nil, wantsServerRunning, serverProcess?.isRunning != true {
            startServer()
        }
        lastStatus = status

        let running = status?.running == true
        let host = status?.local_ip ?? ""
        let passcode = status?.passcode ?? fallbackPasscode()
        let devices = status?.devices ?? []

        statusMenuItem.title = running ? "Server: Running" : "Server: Stopped"
        startStopItem.title = running ? "Stop Server" : "Start Server"
        urlItem.title = running && !host.isEmpty ? "http://\(host):\(backendPort)  ⧉" : "Server URL unavailable"
        passcodeItem.title = passcode.count == 6 ? "Passcode: \(passcode)  ⧉" : "Passcode: ------"

        let granted = CGPreflightPostEventAccess()
        accessibilityItem.title = granted
            ? "Accessibility: Granted"
            : "Accessibility: Not granted (click to fix)"

        updateTooltip(running: running, devicesCount: devices.count)
        updateQRPreview(with: status)
        rebuildDevicesMenu(with: devices)
    }

    @objc private func toggleServer(_ sender: Any?) {
        if lastStatus?.running == true {
            wantsServerRunning = false
            stopServer()
        } else {
            wantsServerRunning = true
            startServer()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.refreshStatus()
        }
    }

    @objc private func copyURL(_ sender: Any?) {
        guard let status = lastStatus else {
            NSSound.beep()
            return
        }
        setClipboard("http://\(status.local_ip):\(status.port)")
    }

    @objc private func copyPasscode(_ sender: Any?) {
        let passcode = lastStatus?.passcode ?? fallbackPasscode()
        guard passcode.count == 6 else {
            NSSound.beep()
            return
        }
        setClipboard(passcode)
    }

    @objc private func copyPairingLink(_ sender: Any?) {
        guard let status = lastStatus, status.passcode.count == 6 else {
            NSSound.beep()
            return
        }
        let pairingURL = "icodex://pair?host=\(status.local_ip)&port=\(status.port)&passcode=\(status.passcode)"
        setClipboard(pairingURL)
    }

    @objc private func downloadLatestBuild(_ sender: Any?) {
        guard let url = URL(string: latestDmgURL) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func openAccessibility(_ sender: Any?) {
        if CGPreflightPostEventAccess() {
            refreshStatus()
            return
        }
        CGRequestPostEventAccess()
        openAccessibilitySettings()
        refreshStatus()
    }

    @objc private func disconnectDeviceAction(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else {
            return
        }
        _ = disconnectDevice(deviceID)
        refreshStatus()
    }

    @objc private func disconnectAllDevicesAction(_ sender: Any?) {
        _ = disconnectAllDevices()
        refreshStatus()
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

// MARK: - Main

let args = CommandLine.arguments
if args.count < 2 {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = NativeMenuBarController()
    app.delegate = delegate
    app.run()
    exit(0)
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
