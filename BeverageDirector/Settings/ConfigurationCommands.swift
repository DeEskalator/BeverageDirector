//
//  ConfigurationCommands.swift
//  BeverageDirector
//

import SwiftUI

/// Published by the settings window, which owns the save and open panels.
struct ConfigurationFileActions {
    let save: () -> Void
    let open: () -> Void
}

extension FocusedValues {
    @Entry var configurationFileActions: ConfigurationFileActions?
}

/// File menu items; disabled unless the settings window is the focused scene.
struct ConfigurationCommands: Commands {
    @FocusedValue(\.configurationFileActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save Configuration to File…") { actions?.save() }
                .keyboardShortcut("s")
                .disabled(actions == nil)
        }
        CommandGroup(replacing: .importExport) {
            Button("Import Configuration…") { actions?.open() }
                .keyboardShortcut("o")
                .disabled(actions == nil)
        }
    }
}
