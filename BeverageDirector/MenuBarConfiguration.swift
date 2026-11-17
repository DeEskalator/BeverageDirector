//
//  MenuBarConfiguration.swift
//  BeverageDirector
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// `.bdconfig`, declared under `UTExportedTypeDeclarations` in Info.plist.
    nonisolated static let menuBarConfiguration = UTType(exportedAs: "net.dog-cow.BeverageDirector.configuration", conformingTo: .json)
}

/// Everything needed to recreate both states on another Mac, stored as readable JSON in a `.bdconfig` file.
nonisolated struct MenuBarConfiguration: Codable, Transferable {
    var version = 1
    /// `"collapsed"` or `"expanded"`.
    var activeState: String
    var hiddenWhenCollapsed: [String]
    var hiddenWhenExpanded: [String]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .menuBarConfiguration) { configuration in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(configuration)
        } importing: { data in
            try JSONDecoder().decode(MenuBarConfiguration.self, from: data)
        }
    }
}
