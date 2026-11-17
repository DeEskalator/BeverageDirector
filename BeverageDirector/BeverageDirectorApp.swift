//
//  BeverageDirectorApp.swift
//  BeverageDirector
//
//  Created by Jakob  on 17.11.2026.
//

import os
import ServiceManagement
import SwiftUI

@main
struct BeverageDirectorApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // MenuBarExtra can't tell a left from a right click, so the "…" item stays AppKit. Hand it SwiftUI's window opener.
        let _ = appDelegate.openSettings = { [openWindow] in
            NSApp.activate()
            openWindow(id: SettingsView.windowID)
        }

        Window("BeverageDirector", id: SettingsView.windowID) {
            SettingsView()
                .environment(appDelegate.profiles)
                // A regular app (Dock icon + menu bar) only while settings are open; menu bar only otherwise.
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate()
                }
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
        }
        .defaultSize(width: 680, height: 620)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(needsSetup ? .presented : .suppressed)
        .commands {
            ConfigurationCommands()
        }
    }

    /// Show settings on first launch, and whenever System Settings is unreadable (access not granted yet).
    private var needsSetup: Bool {
        appDelegate.profiles.isFirstLaunch || !appDelegate.profiles.isSeeded
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let profiles = MenuBarProfiles()
    var openSettings: () -> Void = {}
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(profiles: profiles) { [weak self] in
            self?.openSettings()
        }
        profiles.apply()
    }

    /// SwiftUI quits a single-`Window` app when that window closes; we live in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// The "…" item: left click toggles the state, right click (or control-click) shows a small menu.
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let profiles: MenuBarProfiles
    private let openSettings: () -> Void
    private var observation: Task<Void, Never>?

    init(profiles: MenuBarProfiles, openSettings: @escaping () -> Void) {
        self.profiles = profiles
        self.openSettings = openSettings
        super.init()

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Open Settings") { [weak self] in
                self?.openSettings()
                return true
            },
        ])

        observation = Task { [weak self, profiles] in
            for await mode in Observations({ profiles.current }) {
                self?.render(mode)
            }
        }
    }

    deinit {
        observation?.cancel()
    }

    private func render(_ mode: MenuBarProfiles.Mode) {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: mode.statusItemSymbol, accessibilityDescription: "BeverageDirector: \(mode.title)")
        button.toolTip = "\(mode.title) — click to switch to \(mode.toggled.title), right-click for options"
    }

    @objc private func clicked() {
        // No event means an accessibility press, which counts as a primary click.
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            profiles.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let launchAtLogin = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLogin)

        let autoCollapse = NSMenuItem(title: "Automatically Collapse", action: nil, keyEquivalent: "")
        let delays = NSMenu()
        for (title, seconds) in Self.autoCollapseDelays {
            let item = NSMenuItem(title: title, action: #selector(autoCollapseDelayChosen), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            item.state = profiles.autoCollapseDelay == seconds ? .on : .off
            delays.addItem(item)
            if seconds == 0 { delays.addItem(.separator()) }
        }
        autoCollapse.submenu = delays
        menu.addItem(autoCollapse)

        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsChosen), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit BeverageDirector", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Attach the menu for this one click only, so a left click keeps toggling.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func settingsChosen() {
        openSettings()
    }

    /// Titles and seconds for the "Automatically Collapse" submenu; 0 means never.
    private static let autoCollapseDelays = [
        ("Never", 0),
        ("After 15 Seconds", 15),
        ("After 30 Seconds", 30),
        ("After 1 Minute", 60),
        ("After 2 Minutes", 120),
        ("After 5 Minutes", 300),
        ("After 10 Minutes", 600),
        ("After 30 Minutes", 1800),
    ]

    @objc private func autoCollapseDelayChosen(_ sender: NSMenuItem) {
        profiles.autoCollapseDelay = sender.tag
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
            Logger.launchAtLogin.error("Changing login item failed: \(String(describing: error), privacy: .public)")
        }
        Logger.launchAtLogin.notice("Status: \(service.status.rawValue)")
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
