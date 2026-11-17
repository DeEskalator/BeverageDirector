//
//  Logging.swift
//  BeverageDirector
//

import os

/// Unified log categories. Stream them with:
/// `log stream --level debug --predicate 'subsystem == "net.dog-cow.BeverageDirector"'`
extension Logger {
    nonisolated private static let subsystem = "net.dog-cow.BeverageDirector"

    nonisolated static let allowList = Logger(subsystem: subsystem, category: "MenuBarAllowList")
    nonisolated static let profiles = Logger(subsystem: subsystem, category: "MenuBarProfiles")
    nonisolated static let configuration = Logger(subsystem: subsystem, category: "Configuration")
    nonisolated static let launchAtLogin = Logger(subsystem: subsystem, category: "LaunchAtLogin")
}
