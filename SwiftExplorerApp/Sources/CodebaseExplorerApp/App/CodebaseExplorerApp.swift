import AppKit
import SwiftUI

@main
struct CodebaseExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller: AppController
    private let initialWindowSize: CGSize

    init() {
        let dependencies = AppDependencies()
        _controller = StateObject(wrappedValue: AppController.live(dependencies: dependencies))
        initialWindowSize = dependencies.initialWindowSize ?? CGSize(width: 1180, height: 760)
    }

    var body: some Scene {
        WindowGroup("Codebase Combiner") {
            ContentView(controller: controller)
        }
        .defaultSize(width: initialWindowSize.width, height: initialWindowSize.height)
        .commands {
            AppCommands(controller: controller)
        }

        Settings {
            SettingsView(preferences: controller.preferences)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = AppDependencies().defaults
    private let e2eWindowSize = AppDependencies().initialWindowSize
    private var didConfigureE2EWindow = false

    func applicationWillFinishLaunching(_: Notification) {
        defaults.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        false
    }

    func application(_: NSApplication, shouldSaveSecureApplicationState _: NSCoder) -> Bool {
        false
    }

    func application(_: NSApplication, shouldRestoreSecureApplicationState _: NSCoder) -> Bool {
        false
    }

    func application(_: NSApplication, shouldSaveApplicationState _: NSCoder) -> Bool {
        false
    }

    func application(_: NSApplication, shouldRestoreApplicationState _: NSCoder) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_: Notification) {
        if e2eWindowSize != nil {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidBecomeKey(_:)),
                name: NSWindow.didBecomeKeyNotification,
                object: nil
            )
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppLog.lifecycle.info("Application finished launching")
        DispatchQueue.main.async { self.disableWindowRestoration() }
        DispatchQueue.main.async { self.recenterOffscreenWindowsIfNeeded() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.disableWindowRestoration() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.recenterOffscreenWindowsIfNeeded() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.configureE2EWindowFrameIfNeeded() }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        configureE2EWindowFrameIfNeeded(window: notification.object as? NSWindow)
    }

    @MainActor
    private func disableWindowRestoration() {
        for window in NSApp.windows {
            window.isRestorable = false
            window.restorationClass = nil
            window.disableSnapshotRestoration()
        }
    }

    @MainActor
    private func recenterOffscreenWindowsIfNeeded() {
        for window in NSApp.windows where window.isVisible {
            guard !window.frame.isEmpty else { continue }
            let isVisible = NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
            if !isVisible, let screen = NSScreen.main {
                window.setFrameOrigin(CGPoint(
                    x: screen.visibleFrame.midX - window.frame.width / 2,
                    y: screen.visibleFrame.midY - window.frame.height / 2
                ))
            }
        }
    }

    @MainActor
    private func configureE2EWindowFrameIfNeeded(window providedWindow: NSWindow? = nil) {
        guard !didConfigureE2EWindow,
              let e2eWindowSize,
              let window = providedWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
              let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
        else { return }

        window.setFrame(
            E2EWindowFramePolicy.frame(size: e2eWindowSize, visibleFrame: visibleFrame),
            display: true,
            animate: false
        )
        didConfigureE2EWindow = true
        AppLog.lifecycle.info(
            "Configured E2E window frame width=\(Int(window.frame.width), privacy: .public) height=\(Int(window.frame.height), privacy: .public)"
        )
    }
}

enum E2EWindowFramePolicy {
    static func frame(size: CGSize, visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
