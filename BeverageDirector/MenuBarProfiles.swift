//
//  MenuBarProfiles.swift
//  BeverageDirector
//

import AppKit
import Observation
import os

/// The two menu bar states and which app icons each one hides.
@Observable
final class MenuBarProfiles {
    enum Mode: String, CaseIterable {
        case expanded, collapsed

        var title: String {
            switch self {
            case .expanded: "Expanded"
            case .collapsed: "Collapsed"
            }
        }

        var statusItemSymbol: String {
            switch self {
            case .expanded: "ellipsis.circle.fill"
            case .collapsed: "ellipsis.circle"
            }
        }

        var toggled: Mode { self == .expanded ? .collapsed : .expanded }
    }

    private(set) var current: Mode
    private var hidden: [Mode: Set<String>]

    /// False until both states have been seeded from System Settings. Nothing is applied before that,
    /// so a launch without access to Control Center's settings can't switch every disabled icon back on.
    private(set) var isSeeded: Bool

    /// True when there was nothing saved at launch.
    @ObservationIgnored let isFirstLaunch: Bool

    /// Seconds after switching to Expanded before going back to Collapsed on its own; 0 means never.
    var autoCollapseDelay: Int {
        didSet {
            defaults.set(autoCollapseDelay, forKey: "autoCollapseDelay")
            Logger.profiles.notice("Auto-collapse delay: \(self.autoCollapseDelay)s")
            scheduleAutoCollapse()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let ownIdentifier = Bundle.main.bundleIdentifier ?? ""
    @ObservationIgnored private var autoCollapseTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        current = defaults.string(forKey: "currentMode").flatMap(Mode.init) ?? .expanded
        autoCollapseDelay = defaults.integer(forKey: "autoCollapseDelay")
        let hasSavedState = defaults.object(forKey: Self.hiddenKey(.expanded)) != nil
        isSeeded = hasSavedState
        isFirstLaunch = !hasSavedState
        hidden = Dictionary(uniqueKeysWithValues: Mode.allCases.map { mode in
            (mode, Set(defaults.stringArray(forKey: Self.hiddenKey(mode)) ?? []))
        })
        seedIfNeeded()
        scheduleAutoCollapse()
    }

    /// Starts both states from whatever System Settings currently has, so nothing changes until the user edits.
    func seedIfNeeded() {
        guard !isSeeded else { return }
        guard let disallowed = MenuBarAllowList.disallowedIdentifiers() else {
            Logger.profiles.error("Can't seed yet, System Settings unreadable")
            return
        }
        hidden = [.expanded: disallowed, .collapsed: disallowed]
        isSeeded = true
        save()
        Logger.profiles.notice("Seeded with \(disallowed.count) hidden app(s)")
    }

    func isVisible(_ id: String, in mode: Mode) -> Bool {
        !hidden[mode, default: []].contains(id)
    }

    func hiddenCount(in mode: Mode, among ids: some Sequence<String>) -> Int {
        ids.filter { !isVisible($0, in: mode) }.count
    }

    func setVisible(_ visible: Bool, for ids: some Sequence<String>, in mode: Mode) {
        if visible {
            hidden[mode, default: []].subtract(ids)
        } else {
            hidden[mode, default: []].formUnion(ids)
        }
        save()
        if mode == current { apply() }
    }

    func activate(_ mode: Mode) {
        current = mode
        save()
        apply()
        scheduleAutoCollapse()
    }

    func toggle() {
        activate(current.toggled)
    }

    /// Restarts the countdown back to Collapsed while expanded, and cancels it otherwise.
    private func scheduleAutoCollapse() {
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
        guard current == .expanded, autoCollapseDelay > 0 else { return }
        let delay = autoCollapseDelay
        autoCollapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            Logger.profiles.notice("Collapsing automatically after \(delay)s")
            activate(.collapsed)
        }
    }

    // MARK: Configuration files

    enum ConfigurationError: LocalizedError {
        case unknownState(String)
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unknownState(let state): "The file names an unknown state, “\(state)”."
            case .unsupportedVersion(let version): "The file was written by a newer version of BeverageDirector (format \(version))."
            }
        }
    }

    var configuration: MenuBarConfiguration {
        MenuBarConfiguration(
            activeState: current.rawValue,
            hiddenWhenCollapsed: hidden[.collapsed, default: []].sorted(),
            hiddenWhenExpanded: hidden[.expanded, default: []].sorted()
        )
    }

    /// Replaces both states with the file's contents and applies the active one right away.
    func load(_ configuration: MenuBarConfiguration) throws {
        guard configuration.version <= 1 else { throw ConfigurationError.unsupportedVersion(configuration.version) }
        guard let mode = Mode(rawValue: configuration.activeState) else { throw ConfigurationError.unknownState(configuration.activeState) }
        hidden = [.collapsed: Set(configuration.hiddenWhenCollapsed), .expanded: Set(configuration.hiddenWhenExpanded)]
        isSeeded = true
        Logger.profiles.notice("Loaded configuration: \(mode.title, privacy: .public) active, \(configuration.hiddenWhenCollapsed.count) hidden collapsed, \(configuration.hiddenWhenExpanded.count) hidden expanded")
        activate(mode)
    }

    /// Pushes the current state into System Settings. Our own item is never hidden.
    func apply() {
        seedIfNeeded()
        guard isSeeded else { return }
        Logger.profiles.info("Applying \(self.current.title, privacy: .public)")
        let hiddenNow = hidden[current, default: []]
        MenuBarAllowList.setAllowed { id in
            id == ownIdentifier || !hiddenNow.contains(id)
        }
    }

    private func save() {
        defaults.set(current.rawValue, forKey: "currentMode")
        guard isSeeded else { return }
        for mode in Mode.allCases {
            defaults.set(hidden[mode, default: []].sorted(), forKey: Self.hiddenKey(mode))
        }
    }

    private static func hiddenKey(_ mode: Mode) -> String {
        "hiddenApps.\(mode.rawValue)"
    }
}
