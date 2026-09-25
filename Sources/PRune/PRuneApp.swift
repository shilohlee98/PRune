import AppKit
import SwiftUI

@main
struct PRuneApp: App {
    @NSApplicationDelegateAdaptor(PRuneAppDelegate.self) private var appDelegate
    @State private var store = PullRequestStore()

    init() {
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        for application in NSWorkspace.shared.runningApplications {
            guard application.processIdentifier != currentProcessID else { continue }
            let executableName = application.executableURL?.lastPathComponent ?? ""
            let isPRune = application.bundleIdentifier == "dev.shiloh.prune"
                || executableName == "PRune"
                || executableName.hasPrefix("PRune-")
                || application.bundleIdentifier == "dev.shiloh.pull-lens"
                || executableName == "PullLens"
                || executableName.hasPrefix("PullLens-")
            if isPRune {
                application.terminate()
            }
        }
    }

    var body: some Scene {
        WindowGroup("PRune") {
            ContentView()
                .environment(store)
                .frame(minWidth: 900, minHeight: 620)
                .preferredColorScheme(.dark)
                .background(WindowConfigurator())
        }
        .defaultSize(width: 1240, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh Pull Requests") {
                    Task { await store.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Find in Page") {
                    DetailFindCommand.send(.open)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find Next") {
                    DetailFindCommand.send(.next)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Find Previous") {
                    DetailFindCommand.send(.previous)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }
    }
}

private final class PRuneAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            NSApp.windows.forEach(WindowChrome.configure)
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowConfigurationView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            WindowChrome.configure(view.window)
        }
    }
}

@MainActor
private enum WindowChrome {
    static func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        removeTitleBarSafeArea(from: window)
        restoreWindowToVisibleScreen(window)
        DispatchQueue.main.async {
            positionWindowButtons(in: window)
        }
    }

    private static func positionWindowButtons(in window: NSWindow) {
        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (index, type) in buttonTypes.enumerated() {
            guard let button = window.standardWindowButton(type),
                  let container = button.superview
            else { continue }

            var frame = button.frame
            frame.origin.x = 18 + CGFloat(index) * 23
            frame.origin.y = max(0, container.bounds.height - 22 - frame.height / 2)
            button.setFrameOrigin(frame.origin)
        }
    }

    private static func removeTitleBarSafeArea(from window: NSWindow) {
        guard let contentView = window.contentView else { return }
        let nativeTopInset = contentView.safeAreaInsets.top
            - contentView.additionalSafeAreaInsets.top
        guard nativeTopInset > 0 else { return }

        contentView.additionalSafeAreaInsets = NSEdgeInsets(
            top: -nativeTopInset,
            left: 0,
            bottom: 0,
            right: 0
        )
        contentView.needsLayout = true
    }

    private static func restoreWindowToVisibleScreen(_ window: NSWindow) {
        guard let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let frame = window.frame
        let visibleIntersection = frame.intersection(visibleFrame)
        guard visibleIntersection.width < min(320, frame.width) || visibleIntersection.height < 80 else {
            return
        }

        var restoredFrame = frame
        if restoredFrame.width <= visibleFrame.width {
            restoredFrame.origin.x = min(
                max(restoredFrame.origin.x, visibleFrame.minX),
                visibleFrame.maxX - restoredFrame.width
            )
        } else {
            restoredFrame.origin.x = visibleFrame.minX
        }
        if restoredFrame.height <= visibleFrame.height {
            restoredFrame.origin.y = min(
                max(restoredFrame.origin.y, visibleFrame.minY),
                visibleFrame.maxY - restoredFrame.height
            )
        } else {
            restoredFrame.origin.y = visibleFrame.minY
        }
        window.setFrame(restoredFrame, display: false)
    }
}

private final class WindowConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            WindowChrome.configure(window)
        }
    }
}

struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DraggableTitleBarView()
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

private final class DraggableTitleBarView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}
