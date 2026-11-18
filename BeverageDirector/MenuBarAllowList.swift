//
//  MenuBarAllowList.swift
//  BeverageDirector
//

import AppKit
import os

/// Reads and writes the System Settings › Menu Bar › "Allow in the Menu Bar" switches.
///
/// ⚠️ Private, reverse engineered on macOS 27.0.1 (26A434):
/// - The switches live in the `trackedApplications` key of the `group.com.apple.controlcenter` defaults suite,
///   a binary plist holding a Swift-Codable dictionary encoded as a flat `[key, value, key, value, …]` array.
/// - MenuBarAgent (`MenuBarClientCore.TrackedApplicationsPreferences`) KVO-observes that suite. Writing through the
///   container-aware CFPreferences SPI hits the same cfprefsd domain, so changes apply immediately.
///   A plain `defaults write <path>` lands in a different domain and is only picked up after MenuBarAgent restarts.
enum MenuBarAllowList {
    struct App: Identifiable, Hashable {
        /// Bundle identifier, or the file URL string for ad-hoc binaries.
        let id: String
        let name: String
        let url: URL
        let isAllowed: Bool
    }

    /// All tracked apps that are still installed, sorted by name. `nil` when the settings can't be read.
    static func installedApps() -> [App]? {
        guard let entries = read() else { return nil }
        let apps = pairs(of: entries).compactMap { key, value -> App? in
            guard let id = identifier(of: key), let url = applicationURL(for: key, id: id) else { return nil }
            return App(id: id, name: displayName(of: url), url: url, isAllowed: value["isAllowed"] as? Bool ?? true)
        }
        Logger.allowList.info("\(entries.count / 2) tracked, \(apps.count) installed")
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Whether the switches can be read right now, i.e. access has been granted.
    static var isAccessible: Bool {
        read() != nil
    }

    /// Identifiers of every tracked app (installed or not) that is currently switched off. `nil` when the settings can't be read.
    static func disallowedIdentifiers() -> Set<String>? {
        guard let entries = read() else { return nil }
        return Set(pairs(of: entries).compactMap { key, value in
            value["isAllowed"] as? Bool == false ? identifier(of: key) : nil
        })
    }

    /// Sets `isAllowed` for every tracked app. Writes only when something actually changed.
    static func setAllowed(_ isAllowed: (String) -> Bool) {
        guard var entries = read() else { return }
        var changes: [String] = []
        for index in stride(from: 0, to: entries.count - 1, by: 2) {
            guard let id = identifier(of: entries[index]) else { continue }
            let allowed = isAllowed(id)
            if entries[index + 1]["isAllowed"] as? Bool != allowed {
                entries[index + 1]["isAllowed"] = allowed
                changes.append("\(allowed ? "+" : "-")\(id)")
            }
        }
        guard !changes.isEmpty else {
            Logger.allowList.debug("Nothing to change")
            return
        }
        Logger.allowList.notice("Writing \(changes.count) change(s): \(changes.joined(separator: " "), privacy: .public)")
        write(entries)
    }

    // MARK: - Entry decoding

    private static func pairs(of entries: [[String: Any]]) -> [([String: Any], [String: Any])] {
        stride(from: 0, to: entries.count - 1, by: 2).map { (entries[$0], entries[$0 + 1]) }
    }

    /// `{bundle: {_0: "com.example"}}` or `{adhocBinary: {_0: {relative: "file:///…"}}}`
    private static func identifier(of key: [String: Any]) -> String? {
        if let bundle = key["bundle"] as? [String: Any] {
            return bundle["_0"] as? String
        }
        if let binary = key["adhocBinary"] as? [String: Any], let location = binary["_0"] as? [String: Any] {
            return location["relative"] as? String
        }
        Logger.allowList.error("Unknown key shape: \(String(describing: key), privacy: .public)")
        return nil
    }

    private static func applicationURL(for key: [String: Any], id: String) -> URL? {
        if key["bundle"] != nil {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        }
        guard let url = URL(string: id), FileManager.default.fileExists(atPath: url.path) else { return nil }
        // Prefer the enclosing .app so the row gets a proper name and icon.
        var candidate = url
        while candidate.pathComponents.count > 1 {
            if candidate.pathExtension == "app" { return candidate }
            candidate.deleteLastPathComponent()
        }
        return url
    }

    private static func displayName(of url: URL) -> String {
        let info = Bundle(url: url)?.localizedInfoDictionary ?? Bundle(url: url)?.infoDictionary
        return info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
    }

    // MARK: - Sandbox access

    private static let bookmarkKey = "controlCenterContainerBookmark"

    /// Keeps the access the open panel granted for `url` and stores it as a security-scoped bookmark for later launches.
    static func grantAccess(to url: URL) {
        Logger.allowList.notice("Granting access to \(url.path, privacy: .public), startAccessing: \(url.startAccessingSecurityScopedResource())")
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            Logger.allowList.notice("Saved security-scoped bookmark (\(bookmark.count) bytes)")
        } catch {
            Logger.allowList.error("Creating bookmark failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Resolves the stored bookmark once per launch, before the first read or write.
    private static let restoredAccess: Void = {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            Logger.allowList.notice("No stored bookmark")
            return
        }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            Logger.allowList.notice("Resolved bookmark to \(url.path, privacy: .public), stale: \(isStale), startAccessing: \(url.startAccessingSecurityScopedResource())")
            if isStale {
                grantAccess(to: url)
            }
        } catch {
            Logger.allowList.error("Resolving bookmark failed: \(String(describing: error), privacy: .public)")
        }
    }()

    // MARK: - Private CFPreferences SPI

    private typealias CopyAppValue = @convention(c) (CFString, CFString, CFString) -> Unmanaged<CFPropertyList>?
    private typealias SetAppValue = @convention(c) (CFString, CFPropertyList?, CFString, CFString) -> Void
    private typealias AppSynchronize = @convention(c) (CFString, CFString) -> DarwinBoolean

    /// Control Center's group container, which holds the switches.
    static let containerURL = URL.userHomeDirectory.appending(path: "Library/Group Containers/group.com.apple.controlcenter", directoryHint: .isDirectory)

    private static let suite = "group.com.apple.controlcenter" as CFString
    private static let key = "trackedApplications" as CFString
    private static let container = containerURL.path as CFString

    private static let coreFoundation = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOW)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let pointer = dlsym(coreFoundation, name) else {
            Logger.allowList.error("Missing symbol \(name, privacy: .public)")
            return nil
        }
        return unsafeBitCast(pointer, to: type)
    }

    private static func read() -> [[String: Any]]? {
        _ = restoredAccess
        guard let copy = symbol("_CFPreferencesCopyAppValueWithContainer", as: CopyAppValue.self) else { return nil }
        guard let data = copy(key, suite, container)?.takeRetainedValue() as? Data else {
            Logger.allowList.error("Could not read \(key as String, privacy: .public) from \(container as String, privacy: .public). Has access been granted?")
            return nil
        }
        do {
            guard let entries = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
                Logger.allowList.error("Unexpected root type in \(data.count) bytes")
                return nil
            }
            return entries
        } catch {
            Logger.allowList.error("Decode failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func write(_ entries: [[String: Any]]) {
        guard let set = symbol("_CFPreferencesSetAppValueWithContainer", as: SetAppValue.self),
              let synchronize = symbol("_CFPreferencesAppSynchronizeWithContainer", as: AppSynchronize.self) else { return }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: entries, format: .binary, options: 0)
            set(key, data as CFData, suite, container)
            Logger.allowList.info("Wrote \(data.count) bytes, synchronize: \(synchronize(suite, container).boolValue)")
        } catch {
            Logger.allowList.error("Encode failed: \(String(describing: error), privacy: .public)")
        }
    }
}

extension URL {
    /// The user's real home folder. `NSHomeDirectory()` and `homeDirectory` point into our own container when sandboxed.
    static let userHomeDirectory: URL = {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } } ?? NSHomeDirectory()
        return URL(filePath: home, directoryHint: .isDirectory)
    }()
}
