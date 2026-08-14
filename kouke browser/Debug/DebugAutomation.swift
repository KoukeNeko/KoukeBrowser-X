//
//  DebugAutomation.swift
//  kouke browser
//
//  DEBUG-only automation harness. Lets external scripts drive the app through
//  a JSON command file in the sandbox tmp directory, and dump window snapshots
//  and view hierarchies for automated visual verification (no screen-recording
//  permission needed because the app renders its own views).
//
//  Protocol: write {"seq": N, "cmd": "..."} to <container tmp>/kouke-debug/command.json.
//  The harness executes each new seq once and writes result-N.json next to it.
//

#if DEBUG

import AppKit
import SwiftUI

@MainActor
final class DebugAutomation {
    static let shared = DebugAutomation()

    private static let pollInterval: TimeInterval = 0.25
    private static let directoryName = "kouke-debug"
    private static let commandFileName = "command.json"
    private static let writeProbeFileName = ".write-probe"

    private var pollTimer: Timer?
    private var lastExecutedSeq: Int = 0

    private init() {}

    /// Environment override for the harness directory.
    ///
    /// Several unsandboxed debug builds can be running at once, and they would
    /// otherwise all poll the same path under NSTemporaryDirectory() and race to
    /// answer each other's commands. A test run sets this to a private directory.
    private static let directoryEnvironmentKey = "KOUKE_DEBUG_DIR"

    var workingDirectory: URL {
        if let override = ProcessInfo.processInfo.environment[Self.directoryEnvironmentKey],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(Self.directoryName)
    }

    func start() {
        guard prepareWorkingDirectory() else { return }

        NSLog("🧪 DebugAutomation: watching %@", workingDirectory.path)

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { _ in
            Task { @MainActor in
                DebugAutomation.shared.pollCommandFile()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// Creates the command directory and proves the app can write into it.
    ///
    /// Both halves are load-bearing. Creation can fail outright, and a directory
    /// that already exists is not necessarily writable — a sandboxed build is
    /// refused access to anything outside its container. Neither failure is
    /// visible from the outside: the harness simply waits for result files that
    /// will never appear, which reads as the app having hung. Probing here turns
    /// a silent stall into a named error at launch.
    private func prepareWorkingDirectory() -> Bool {
        do {
            try FileManager.default.createDirectory(at: workingDirectory,
                                                    withIntermediateDirectories: true)
        } catch {
            NSLog("🧪 DebugAutomation: cannot create %@ — %@ — harness disabled",
                  workingDirectory.path, String(describing: error))
            return false
        }

        let probeURL = workingDirectory.appendingPathComponent(Self.writeProbeFileName)
        do {
            try Data().write(to: probeURL, options: .atomic)
            try FileManager.default.removeItem(at: probeURL)
        } catch {
            NSLog("🧪 DebugAutomation: %@ is not writable — %@ — harness disabled",
                  workingDirectory.path, String(describing: error))
            return false
        }

        return true
    }

    // MARK: - Command Loop

    private func pollCommandFile() {
        let commandURL = workingDirectory.appendingPathComponent(Self.commandFileName)
        guard let data = try? Data(contentsOf: commandURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let seq = json["seq"] as? Int,
              let command = json["cmd"] as? String,
              seq > lastExecutedSeq else {
            return
        }

        lastExecutedSeq = seq

        // Some commands (extension loading, page loads) are inherently async.
        // Their result file simply appears later; the polling client already
        // waits for result-<seq>.json, so no protocol change is needed.
        if let asyncCommand = AsyncCommand(rawValue: command) {
            Task { @MainActor in
                let outcome = await self.executeAsync(asyncCommand, arguments: json)
                self.writeResult(seq: seq, outcome: outcome)
            }
            return
        }

        if let passwordCommand = PasswordCommand(rawValue: command) {
            writeResult(seq: seq, outcome: executePasswordCommand(passwordCommand, arguments: json))
            return
        }

        if let probeCommand = KeychainProbeCommand(rawValue: command) {
            writeResult(seq: seq, outcome: executeKeychainProbeCommand(probeCommand, arguments: json))
            return
        }

        let outcome = execute(command: command, arguments: json)
        writeResult(seq: seq, outcome: outcome)
    }

    private func execute(command: String, arguments: [String: Any]) -> Result<String, Error> {
        switch command {
        case "snapshot":
            return snapshotAllWindows()
        case "state":
            return dumpState()
        case "set_style":
            return setTabBarStyle(arguments)
        case "set_appearance":
            return setChromeAppearance(arguments)
        case "set_address_bar_style":
            return setAddressBarFollowsChromeStyle(arguments)
        case "add_tab":
            return addTab(arguments)
        case "switch_tab":
            return switchTab(arguments)
        case "detach_active":
            return detachActiveTab(arguments)
        case "transfer":
            return transferTab(arguments)
        case "hittest":
            return hitTestPoints(arguments)
        case "configure_chrome":
            return configureChrome(arguments)
        case "traffic_lights":
            return reportTrafficLights(arguments)
        case "gestures":
            return reportGestureRecognizers(arguments)
        case "window_frame":
            return setWindowFrame(arguments)
        default:
            return .failure(DebugAutomationError.unknownCommand(command))
        }
    }

    func writeResult(seq: Int, outcome: Result<String, Error>) {
        var payload: [String: Any] = ["seq": seq]
        switch outcome {
        case .success(let message):
            payload["ok"] = true
            payload["message"] = message
        case .failure(let error):
            payload["ok"] = false
            payload["message"] = String(describing: error)
        }
        let resultURL = workingDirectory.appendingPathComponent("result-\(seq).json")
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: resultURL)
        }
    }

    // MARK: - Snapshot & Hierarchy

    private func snapshotAllWindows() -> Result<String, Error> {
        var captured: [Int] = []
        for window in NSApp.windows where window.isVisible {
            guard let frameView = window.contentView?.superview else { continue }
            let bounds = frameView.bounds
            guard bounds.width > 0, bounds.height > 0,
                  let bitmap = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { continue }
            frameView.cacheDisplay(in: bounds, to: bitmap)
            guard let pngData = bitmap.representation(using: .png, properties: [:]) else { continue }

            let number = window.windowNumber
            let snapshotURL = workingDirectory.appendingPathComponent("snapshot-\(number).png")
            try? pngData.write(to: snapshotURL)

            var hierarchyText = "window #\(number) frame=\(window.frame) styleMask=\(window.styleMask.rawValue) toolbar=\(window.toolbar != nil) titlebarTransparent=\(window.titlebarAppearsTransparent)\n"
            dumpHierarchy(of: frameView, indent: 0, into: &hierarchyText)
            let hierarchyURL = workingDirectory.appendingPathComponent("hierarchy-\(number).txt")
            try? hierarchyText.write(to: hierarchyURL, atomically: true, encoding: .utf8)

            captured.append(number)
        }
        _ = dumpState()
        return .success("captured windows: \(captured)")
    }

    private func dumpHierarchy(of view: NSView, indent: Int, into text: inout String) {
        let padding = String(repeating: "  ", count: indent)
        let className = String(describing: type(of: view))
        let windowRect = view.convert(view.bounds, to: nil)
        var line = "\(padding)\(className) frame=\(view.frame) inWindow=\(windowRect) hidden=\(view.isHidden) alpha=\(view.alphaValue) flipped=\(view.isFlipped)"
        if let identifier = view.identifier?.rawValue, !identifier.isEmpty {
            line += " id=\(identifier)"
        }
        if let clipView = view as? NSClipView {
            line += " clipBoundsOrigin=\(clipView.bounds.origin)"
        }
        if let backgroundColor = view.layer?.backgroundColor {
            line += " layerBg=\(String(describing: backgroundColor))"
        }
        line += " appearance=\(view.effectiveAppearance.name.rawValue)"
        text += line + "\n"
        for subview in view.subviews {
            dumpHierarchy(of: subview, indent: indent + 1, into: &text)
        }
    }

    // MARK: - State

    private func dumpState() -> Result<String, Error> {
        var windowsInfo: [[String: Any]] = []
        for window in NSApp.windows where window.isVisible {
            let number = window.windowNumber
            var info: [String: Any] = [
                "windowNumber": number,
                "title": window.title,
                "isKeyWindow": window.isKeyWindow,
                "frame": NSStringFromRect(window.frame),
                "hasToolbar": window.toolbar != nil,
                // Translucent chrome only works when the window stops painting
                // an opaque background, so both are part of the assertion.
                "isOpaque": window.isOpaque,
                "backgroundAlpha": window.backgroundColor.alphaComponent
            ]
            if let viewModel = WindowManager.shared.debugViewModel(forWindowNumber: number) {
                info["activeTabId"] = viewModel.activeTabId?.uuidString ?? ""
                info["tabs"] = viewModel.tabs.map { tab in
                    ["id": tab.id.uuidString, "title": tab.title, "url": tab.url]
                }
            }
            windowsInfo.append(info)
        }
        let payload: [String: Any] = [
            "tabBarStyle": BrowserSettings.shared.tabBarStyle.rawValue,
            "chromeAppearance": BrowserSettings.shared.chromeAppearance.rawValue,
            "addressBarFollowsChromeStyle": BrowserSettings.shared.addressBarFollowsChromeStyle,
            "glassAvailable": ChromeAppearance.isGlassAvailable,
            "windows": windowsInfo
        ]
        let stateURL = workingDirectory.appendingPathComponent("state.json")
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: stateURL)
            return .success("state written (\(windowsInfo.count) windows)")
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Actions

    private func setTabBarStyle(_ arguments: [String: Any]) -> Result<String, Error> {
        guard let rawValue = arguments["value"] as? String,
              let style = TabBarStyle(rawValue: rawValue) else {
            return .failure(DebugAutomationError.badArguments("value must be normal|compact"))
        }
        BrowserSettings.shared.tabBarStyle = style
        return .success("tabBarStyle = \(rawValue)")
    }

    private func setChromeAppearance(_ arguments: [String: Any]) -> Result<String, Error> {
        guard let rawValue = arguments["value"] as? String,
              let appearance = ChromeAppearance(rawValue: rawValue) else {
            return .failure(DebugAutomationError.badArguments("value must be normal|solid|liquid_glass"))
        }
        BrowserSettings.shared.chromeAppearance = appearance
        return .success("chromeAppearance = \(rawValue)")
    }

    private func setAddressBarFollowsChromeStyle(_ arguments: [String: Any]) -> Result<String, Error> {
        guard let enabled = arguments["value"] as? Bool else {
            return .failure(DebugAutomationError.badArguments("value must be a bool"))
        }
        BrowserSettings.shared.addressBarFollowsChromeStyle = enabled
        return .success("addressBarFollowsChromeStyle = \(enabled)")
    }

    private func resolveViewModel(_ arguments: [String: Any]) -> (Int, BrowserViewModel)? {
        if let windowNumber = arguments["window"] as? Int {
            guard let viewModel = WindowManager.shared.debugViewModel(forWindowNumber: windowNumber) else { return nil }
            return (windowNumber, viewModel)
        }
        for window in NSApp.orderedWindows where window.isVisible {
            if let viewModel = WindowManager.shared.debugViewModel(forWindowNumber: window.windowNumber) {
                return (window.windowNumber, viewModel)
            }
        }
        return nil
    }

    private func addTab(_ arguments: [String: Any]) -> Result<String, Error> {
        guard let (windowNumber, viewModel) = resolveViewModel(arguments) else {
            return .failure(DebugAutomationError.windowNotFound)
        }
        if let url = arguments["url"] as? String {
            viewModel.addTabWithURL(url)
        } else {
            viewModel.addTab()
        }
        return .success("added tab in window #\(windowNumber); tabs=\(viewModel.tabs.count)")
    }

    private func switchTab(_ arguments: [String: Any]) -> Result<String, Error> {
        guard let (windowNumber, viewModel) = resolveViewModel(arguments) else {
            return .failure(DebugAutomationError.windowNotFound)
        }
        guard let tabString = arguments["tab"] as? String, let tabId = UUID(uuidString: tabString) else {
            return .failure(DebugAutomationError.badArguments("tab must be a UUID"))
        }
        viewModel.switchToTab(tabId)
        return .success("switched to \(tabString) in window #\(windowNumber)")
    }

    /// Mirrors TabBar.detachTabToNewWindow — the same path a drag-out uses.
    private func detachActiveTab(_ arguments: [String: Any]) -> Result<String, Error> {
        guard let (windowNumber, viewModel) = resolveViewModel(arguments) else {
            return .failure(DebugAutomationError.windowNotFound)
        }
        guard let activeTabId = viewModel.activeTabId else {
            return .failure(DebugAutomationError.badArguments("window #\(windowNumber) has no active tab"))
        }
        WindowManager.shared.detachTabToNewWindow(activeTabId, from: viewModel, at: nil)
        return .success("detached \(activeTabId.uuidString) from window #\(windowNumber)")
    }

    /// Mirrors TabBar.receiveTabAtEnd for a cross-window drop.
    private func transferTab(_ arguments: [String: Any]) -> Result<String, Error> {
        guard let fromWindow = arguments["from"] as? Int,
              let toWindow = arguments["to"] as? Int,
              let tabString = arguments["tab"] as? String,
              let tabId = UUID(uuidString: tabString) else {
            return .failure(DebugAutomationError.badArguments("need from, to, tab"))
        }
        guard let destinationViewModel = WindowManager.shared.debugViewModel(forWindowNumber: toWindow) else {
            return .failure(DebugAutomationError.windowNotFound)
        }
        // The real drop path reorders instead of transferring in this case; the
        // harness must not drive WindowManager into a same-window transfer.
        guard !destinationViewModel.tabs.contains(where: { $0.id == tabId }) else {
            return .failure(DebugAutomationError.badArguments("tab already lives in destination window"))
        }
        WindowManager.shared.transferTab(from: fromWindow, tabId: tabId, to: destinationViewModel, position: .atEnd)
        return .success("transfer requested \(tabString): #\(fromWindow) -> #\(toWindow)")
    }
}

// MARK: - Chrome Probes

extension DebugAutomation {
    private func window(fromArguments arguments: [String: Any]) -> NSWindow? {
        if let windowNumber = arguments["window"] as? Int {
            return NSApp.windows.first { $0.windowNumber == windowNumber }
        }
        return NSApp.windows.first { $0.isVisible && $0.contentView != nil }
    }

    /// For each point (in points, top-left origin of the window), report which
    /// view AppKit hit-testing would deliver a click to.
    func hitTestPoints(_ arguments: [String: Any]) -> Result<String, Error> {
        guard let window = window(fromArguments: arguments),
              let frameView = window.contentView?.superview else {
            return .failure(DebugAutomationError.windowNotFound)
        }
        guard let points = arguments["points"] as? [[Double]] else {
            return .failure(DebugAutomationError.badArguments("points must be [[x, y], ...]"))
        }
        var report: [String] = []
        let frameHeight = frameView.bounds.height
        for point in points where point.count == 2 {
            // Convert top-left window coordinates to the frame view's bottom-up space
            let appKitPoint = NSPoint(x: point[0], y: frameHeight - point[1])
            let hitView = frameView.hitTest(appKitPoint)
            let chain = sequence(first: hitView, next: { $0?.superview })
                .prefix(6)
                .compactMap { view -> String? in
                    guard let view = view else { return nil }
                    let canMove = view.mouseDownCanMoveWindow ? "MOVES" : "blocks"
                    return "\(String(describing: type(of: view)))[\(canMove)]"
                }
                .joined(separator: " < ")
            report.append("(\(point[0]), \(point[1])) -> \(chain)")
        }
        return .success(report.joined(separator: " | "))
    }

    /// Reconfigure the window's titlebar/toolbar at runtime to compare options.
    func configureChrome(_ arguments: [String: Any]) -> Result<String, Error> {
        guard let window = window(fromArguments: arguments) else {
            return .failure(DebugAutomationError.windowNotFound)
        }
        if let wantsToolbar = arguments["toolbar"] as? Bool {
            if wantsToolbar {
                window.toolbar = NSToolbar(identifier: "DebugProbeToolbar")
            } else {
                window.toolbar = nil
            }
        }
        if let styleName = arguments["toolbarStyle"] as? String {
            switch styleName {
            case "unified": window.toolbarStyle = .unified
            case "unifiedCompact": window.toolbarStyle = .unifiedCompact
            case "expanded": window.toolbarStyle = .expanded
            case "automatic": window.toolbarStyle = .automatic
            default: return .failure(DebugAutomationError.badArguments("unknown toolbarStyle"))
            }
        }
        if let transparent = arguments["titlebarTransparent"] as? Bool {
            window.titlebarAppearsTransparent = transparent
        }
        return .success("chrome updated: toolbar=\(window.toolbar != nil) style=\(window.toolbarStyle.rawValue) transparent=\(window.titlebarAppearsTransparent)")
    }
}

// MARK: - Traffic Light Probes

extension DebugAutomation {
    /// Report each traffic light's position, expressed as distance from the
    /// window's top edge to the button's vertical center (in points).
    func reportTrafficLights(_ arguments: [String: Any]) -> Result<String, Error> {
        guard let window = window(fromArguments: arguments) else {
            return .failure(DebugAutomationError.windowNotFound)
        }
        let buttonTypes: [(String, NSWindow.ButtonType)] = [
            ("close", .closeButton), ("min", .miniaturizeButton), ("zoom", .zoomButton)
        ]
        var report: [String] = []
        for (label, type) in buttonTypes {
            guard let button = window.standardWindowButton(type),
                  let titlebarView = button.superview else { continue }
            if report.isEmpty {
                report.append("titlebarHeight=\(titlebarView.bounds.height)")
            }
            let centerFromTop = titlebarView.bounds.height - button.frame.midY
            let identity = UInt(bitPattern: ObjectIdentifier(button).hashValue) % 100000
            report.append("\(label): x=\(button.frame.origin.x) centerFromTop=\(centerFromTop) id=\(identity) posts=\(button.postsFrameChangedNotifications)")
        }
        return .success(report.joined(separator: " | "))
    }

    /// List every gesture recognizer in the window's view tree (class names),
    /// to find recognizers that could steal drags from the tab views.
    func reportGestureRecognizers(_ arguments: [String: Any]) -> Result<String, Error> {
        guard let window = window(fromArguments: arguments),
              let frameView = window.contentView?.superview else {
            return .failure(DebugAutomationError.windowNotFound)
        }
        var report: [String] = []
        collectGestureRecognizers(of: frameView, into: &report)
        return .success(report.isEmpty ? "none" : report.joined(separator: " | "))
    }

    private func collectGestureRecognizers(of view: NSView, into report: inout [String]) {
        if !view.gestureRecognizers.isEmpty {
            let names = view.gestureRecognizers.map { String(describing: type(of: $0)) }
            report.append("\(String(describing: type(of: view))): \(names.joined(separator: ", "))")
        }
        for subview in view.subviews {
            collectGestureRecognizers(of: subview, into: &report)
        }
    }

    func setWindowFrame(_ arguments: [String: Any]) -> Result<String, Error> {
        guard let window = window(fromArguments: arguments) else {
            return .failure(DebugAutomationError.windowNotFound)
        }
        var frame = window.frame
        if let width = arguments["w"] as? Double, let height = arguments["h"] as? Double {
            frame.size = NSSize(width: width, height: height)
            window.setFrame(frame, display: true)
        }
        // Exercises the same call WindowDragRegionView uses to move the window,
        // verifying it still works while `isMovable` is false.
        if let x = arguments["x"] as? Double, let y = arguments["y"] as? Double {
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        return .success("frame = \(NSStringFromRect(window.frame)) isMovable=\(window.isMovable)")
    }
}

enum DebugAutomationError: Error {
    case unknownCommand(String)
    case badArguments(String)
    case windowNotFound
}

#endif
