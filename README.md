# BeverageDirector

A tiny menu bar app that switches your Mac's menu bar between two sets of icons with a single click.

Click the **…** item and the clutter is gone. Click it again and everything is back.

## What it's good for

Menu bars fill up fast: VPNs, clipboard managers, battery tools, sync clients, little utilities you need once a week. Most of the time you only want a handful of them; occasionally you want all of them.

BeverageDirector gives you two states:

- **Collapsed**: only the icons you really need.
- **Expanded**: everything else, too.

Left-click **…** to switch between them. Hidden apps keep running; macOS just leaves their icons out of the menu bar.

### Why not Bartender, Ice or Thaw?

Classic menu bar managers work by moving or covering other apps' menu bar windows. On current macOS, the system **MenuBarAgent** draws the right side of the menu bar itself, and those tricks have become unreliable.

BeverageDirector doesn't fight the system. It flips the same **System Settings › Menu Bar › Allow in the Menu Bar** switches you could flip by hand, just a whole set at a time and instantly. MenuBarAgent does the actual hiding, so icons appear and disappear exactly as if you had toggled them in System Settings.

## Using it

| Action | Result |
|---|---|
| Left-click **…** | Switch between Collapsed and Expanded |
| Right-click (or Control-click) **…** | Menu with **Launch at Login**, **Automatically Collapse**, **Settings…** and **Quit BeverageDirector** |

The **…** icon shows the current state: `ellipsis.circle` while collapsed, `ellipsis.circle.fill` while expanded.

**Automatically Collapse** switches back to Collapsed a while after you expand: never (the default), or after 15 seconds up to 30 minutes. The countdown starts each time you switch to Expanded.

### Settings

The settings window shows both states side by side: **Collapsed** on the left, **Expanded** on the right. Each list contains every app that can put an icon in the menu bar; a checkmark means "show this icon in this state".

- **Make Active** switches to that state right away.
- **Show All / Hide All** in each list's bottom bar change every listed app at once, after a confirmation.
- The **search field** and the **filter menu** in the toolbar narrow the lists: all items, items that are always hidden, hidden when collapsed, or hidden when expanded. The filter button turns blue while a filter is active.
- Changes to the active state apply immediately.

While the settings window is open, BeverageDirector gets a Dock icon and a regular menu bar; when you close it, it goes back to living only in the menu bar.

### Saving and sharing a setup

**File › Save Configuration to File… (⌘S)** writes both states to a `.bdconfig` file: plain, readable JSON with the active state and the hidden apps of each state.
**File › Import Configuration… (⌘O)** loads such a file and applies it immediately. Handy for a second Mac or as a backup before experimenting.

### Good to know

- **First launch changes nothing.** Both states start as a copy of what System Settings currently allows, so nothing in your menu bar changes until you change something.
- **New apps are visible in both states** until you uncheck them.
- **BeverageDirector owns the switches.** If you turn an app off in System Settings, the next click on **…** applies BeverageDirector's lists again. Do your hiding in BeverageDirector.
- **BeverageDirector never hides itself**, so you can't lose your way back.

## Requirements

- **macOS 27.** This has only been verified on macOS 27.0.1.
- **Full Disk Access** for BeverageDirector: *System Settings › Privacy & Security › Full Disk Access*. The menu bar switches live in a protected system container, which macOS only lets apps with Full Disk Access read and write. Without it, the settings window explains what's missing and links to the right pane.
- The app runs **without App Sandbox**; a sandboxed app can't reach these settings at all.

## How it works

The "Allow in the Menu Bar" switches are stored in the `trackedApplications` key of the `group.com.apple.controlcenter` preferences. MenuBarAgent observes that key and shows or hides an app's icon as soon as its `isAllowed` value changes.

BeverageDirector keeps a list of hidden apps for each state. Switching states rewrites `isAllowed` for every tracked app in a single write, through the same preferences domain MenuBarAgent observes. The change takes effect within a few milliseconds, without restarting anything.

| File | Role |
|---|---|
| `MenuBarAllowList.swift` | Reads and writes the system allow list |
| `MenuBarProfiles.swift` | The two states, persisted in UserDefaults |
| `MenuBarConfiguration.swift` | The `.bdconfig` file format |
| `BeverageDirectorApp.swift` | App entry point, **…** status item, right-click menu |
| `Logging.swift` | Unified log categories |
| `Settings/` | The SwiftUI settings window and its menu commands |

### ⚠️ Private API

This relies on undocumented macOS internals: the structure of `trackedApplications`, MenuBarAgent observing it, and the private `_CFPreferences…WithContainer` functions. A macOS update can break any of them. If something stops working, the `MenuBarAllowList` log category (see below) shows whether reading, decoding or writing failed. Not suitable for the Mac App Store.

### Logs

BeverageDirector writes to the unified log under the subsystem `net.dog-cow.BeverageDirector`, with the categories `MenuBarAllowList`, `MenuBarProfiles`, `Configuration` and `LaunchAtLogin`. Filter for the subsystem in Console.app, or watch it live in Terminal:

```sh
log stream --level debug --predicate 'subsystem == "net.dog-cow.BeverageDirector"'
```

Errors and state changes are stored and can be read back later with `log show --last 1h --info --predicate 'subsystem == "net.dog-cow.BeverageDirector"'`. Debug messages only appear while you are streaming.

## Building

Open `BeverageDirector.xcodeproj` in Xcode 27 and run the **BeverageDirector** scheme.

Sign it with your development team rather than "Sign to Run Locally". macOS ties the Full Disk Access permission to the app's signature, and an ad-hoc signature changes with every build, so you would have to grant access again after each rebuild.
