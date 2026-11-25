//
//  SettingsView.swift
//  BeverageDirector
//

import os
import SwiftUI
import UniformTypeIdentifiers

/// Both states side by side: Collapsed on the left, Expanded on the right.
struct SettingsView: View {
    static let windowID = "settings"
    private static let filterItemID = "filter"
    
    @Environment(MenuBarProfiles.self) private var profiles
    
    /// `nil` while loading or when System Settings can't be read.
    @State private var apps: [MenuBarAllowList.App]?
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var filter = AppFilter.all
    /// Apps that matched `filter` when it was chosen. They stay listed (dimmed) after an edit makes them
    /// stop matching, so a stray click doesn't make a row vanish before you can see what changed.
    @State private var filterMatches: Set<String> = []
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isGrantingAccess = false
    @State private var fileError: String?
    
    var body: some View {
        content
            .frame(minWidth: 600, minHeight: 460)
            .searchable(text: $searchText, placement: .toolbar, prompt: "Filter Apps")
            .toolbar(id: "settings") {
                ToolbarItem(id: Self.filterItemID) {
                    filterMenu
                }
            }
            .task { reload() }
            .focusedSceneValue(\.configurationFileActions, ConfigurationFileActions(
                save: { isExporting = true },
                open: { isImporting = true }
            ))
            .fileExporter(
                isPresented: $isExporting,
                item: profiles.configuration,
                contentTypes: [.menuBarConfiguration],
                defaultFilename: "BeverageDirector Configuration"
            ) { result in
                switch result {
                case .success(let url):
                    Logger.configuration.notice("Saved to \(url.path, privacy: .public)")
                case .failure(let error):
                    Logger.configuration.error("Save failed: \(String(describing: error), privacy: .public)")
                    fileError = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.menuBarConfiguration]) { result in
                do {
                    let url = try result.get()
                    let isAccessing = url.startAccessingSecurityScopedResource()
                    defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
                    let configuration = try JSONDecoder().decode(MenuBarConfiguration.self, from: Data(contentsOf: url))
                    try profiles.load(configuration)
                    Logger.configuration.notice("Imported \(url.path, privacy: .public)")
                } catch {
                    Logger.configuration.error("Import failed: \(String(describing: error), privacy: .public)")
                    fileError = error.localizedDescription
                }
            }
            // Otherwise both panels reopen Control Center's folder from Grant Access.
            .fileDialogDefaultDirectory(URL.userHomeDirectory.appending(path: "Documents", directoryHint: .isDirectory))
            .alert("Couldn’t Use Configuration File", item: $fileError) { _ in
                Button("OK") {}
            } message: { message in
                Text(message)
            }
    }
    
    @ViewBuilder
    private var content: some View {
        if let apps {
            let visibleApps = filtered(apps)
            let dimmedIDs = Set(visibleApps.map(\.id).filter { !filter.includes($0, in: profiles) })
            HStack(alignment: .top, spacing: 20) {
                ModeColumn(mode: .collapsed, apps: visibleApps, dimmedIDs: dimmedIDs)
                ModeColumn(mode: .expanded, apps: visibleApps, dimmedIDs: dimmedIDs)
            }
            .padding(20)
        } else if hasLoaded {
            ContentUnavailableView {
                Label("Can’t Read Menu Bar Settings", systemImage: "lock")
            } description: {
                Text("BeverageDirector needs access to Control Center’s folder to see and change which apps may show icons in the menu bar. Click Grant Access, then confirm the folder that opens.")
            } actions: {
                Button("Grant Access") { isGrantingAccess = true }
                Button("Try Again", action: reload)
            }
            .fileImporter(isPresented: $isGrantingAccess, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    Logger.allowList.notice("Picked \(url.path, privacy: .public), expected \(MenuBarAllowList.containerURL.path, privacy: .public)")
                    MenuBarAllowList.grantAccess(to: url)
                    reload()
                case .failure(let error):
                    Logger.allowList.error("Grant Access panel failed: \(String(describing: error), privacy: .public)")
                }
            }
            .fileDialogDefaultDirectory(MenuBarAllowList.containerURL)
            .fileDialogConfirmationLabel("Grant Access")
            .fileDialogMessage("Click “Grant Access” to let BeverageDirector change your menu bar.")
        } else {
            ProgressView()
        }
    }
    
    private var filterMenu: some View {
        Menu {
            Picker("Filter", selection: $filter) {
                Text(AppFilter.all.title).tag(AppFilter.all)
                Divider()
                ForEach(AppFilter.allCases.filter { $0 != .all }) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease")
                .foregroundStyle(filter == .all ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
        }
        .menuIndicator(.hidden)
        .help(filter.title)
        .onChange(of: filter) { _, filter in
            setFilterItemProminent(filter != .all)
            captureFilterMatches()
        }
    }

    /// SwiftUI has no toolbar API for the accent-tinted glass that marks an active filter (and `.buttonStyle`
    /// doesn't reach a toolbar `Menu`), so set AppKit's `NSToolbarItem.style` on the item SwiftUI created.
    private func setFilterItemProminent(_ isProminent: Bool) {
        let items = NSApp.windows.compactMap(\.toolbar).flatMap(\.items)
        for item in items where item.itemIdentifier.rawValue == Self.filterItemID {
            item.style = isProminent ? .prominent : .plain
        }
    }
    
    private func captureFilterMatches() {
        filterMatches = Set((apps ?? []).map(\.id).filter { filter.includes($0, in: profiles) })
    }
    
    private func filtered(_ apps: [MenuBarAllowList.App]) -> [MenuBarAllowList.App] {
        apps.filter { app in
            (filterMatches.contains(app.id) || filter.includes(app.id, in: profiles))
            && (searchText.isEmpty
                || app.name.localizedCaseInsensitiveContains(searchText)
                || app.id.localizedCaseInsensitiveContains(searchText))
        }
    }
    
    private func reload() {
        let ownIdentifier = Bundle.main.bundleIdentifier
        apps = MenuBarAllowList.installedApps()?.filter { $0.id != ownIdentifier }
        hasLoaded = true
        profiles.seedIfNeeded()
        captureFilterMatches()
    }
}


private enum AppFilter: CaseIterable, Identifiable {
    case all, alwaysHidden, hiddenWhenCollapsed, hiddenWhenExpanded
    
    var id: Self { self }
    
    var title: String {
        switch self {
        case .all: "Show All Items"
        case .alwaysHidden: "Show Always Hidden Items"
        case .hiddenWhenCollapsed: "Show Hidden When Collapsed"
        case .hiddenWhenExpanded: "Show Hidden When Expanded"
        }
    }
    
    func includes(_ id: String, in profiles: MenuBarProfiles) -> Bool {
        switch self {
        case .all: true
        case .alwaysHidden: !profiles.isVisible(id, in: .collapsed) && !profiles.isVisible(id, in: .expanded)
        case .hiddenWhenCollapsed: !profiles.isVisible(id, in: .collapsed)
        case .hiddenWhenExpanded: !profiles.isVisible(id, in: .expanded)
        }
    }
}

private struct ModeColumn: View {
    let mode: MenuBarProfiles.Mode
    let apps: [MenuBarAllowList.App]
    /// Listed apps that no longer match the active filter.
    let dimmedIDs: Set<String>
    
    @Environment(MenuBarProfiles.self) private var profiles

    /// The Show All / Hide All choice waiting for confirmation.
    @State private var pendingVisibility: Bool?

    private var isActive: Bool { profiles.current == mode }
    
    private var summary: String {
        let hidden = profiles.hiddenCount(in: mode, among: apps.map(\.id))
        return hidden == 0 ? "All \(apps.count) shown" : "\(hidden) of \(apps.count) hidden"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(apps) { app in
                        AppRow(app: app, mode: mode, isDimmed: dimmedIDs.contains(app.id))
                    }
                } header: {
                    HStack {
                        Text(mode.title)
                        Spacer()
                        Button("Make Active") { profiles.activate(mode) }
                            .controlSize(.small)
                            .disabled(isActive)
                    }
                }
            }
            .listStyle(.plain)
            .alternatingRowBackgrounds()
            Divider()
            bottomBar
        }
        .clipShape(.rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator) }
    }
    
    private var bottomBar: some View {
        HStack {
            Text(summary)
                .foregroundStyle(.secondary)
            Spacer()
            ControlGroup {
                Button("Show All") { pendingVisibility = true }
                Button("Hide All") { pendingVisibility = false }
            }
            .fixedSize()
        }
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background { Rectangle().fill(.bar) }
        .alert(confirmationTitle, item: $pendingVisibility) { visible in
            Button(visible ? "Show All" : "Hide All") {
                profiles.setVisible(visible, for: apps.map(\.id), in: mode)
            }
            Button("Cancel", role: .cancel) {}
        } message: { visible in
            Text(confirmationMessage(visible))
        }
    }

    private var confirmationTitle: String {
        "\(pendingVisibility == true ? "Show" : "Hide") All Icons When \(mode.title)?"
    }

    private func confirmationMessage(_ visible: Bool) -> String {
        let apps = apps.count == 1 ? "1 app" : "\(apps.count) apps"
        let change = visible ? "show its icon" : "hide its icon"
        let timing = isActive ? " This applies to your menu bar right away." : ""
        return "Every listed app (\(apps)) will \(change) in the \(mode.title) state.\(timing)"
    }
}

private struct AppRow: View {
    let app: MenuBarAllowList.App
    let mode: MenuBarProfiles.Mode
    let isDimmed: Bool
    
    @Environment(MenuBarProfiles.self) private var profiles
    
    var body: some View {
        Toggle(isOn: isVisible) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(app.name)
                    .lineLimit(1)
            }
        }
        .toggleStyle(.checkbox)
        // Looks disabled but stays clickable, so an accidental change can be undone right here.
        .opacity(isDimmed ? 0.4 : 1)
        .help(app.id)
    }
    
    private var isVisible: Binding<Bool> {
        Binding {
            profiles.isVisible(app.id, in: mode)
        } set: { visible in
            profiles.setVisible(visible, for: [app.id], in: mode)
        }
    }
}

#Preview {
    SettingsView()
        .environment(MenuBarProfiles())
}
