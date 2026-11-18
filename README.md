# BeverageDirector

A tiny menu bar manager that switches your Mac's menu bar between collapsed and expanded with a single click.

Click the **…** item and the clutter is gone. Click it again and everything is back.

## What it's good for

Menu bars fill up fast: VPNs, clipboard managers, battery tools, sync clients, little utilities you need once a week. Most of the time you only want a handful of them; occasionally you want all of them.

BeverageDirector gives you two states:

- **Collapsed**: only the icons you really need.
- **Expanded**: everything else, too.

Hit **…** to switch between them. 

### Why not Bartender, Ice or Thaw?

Classic menu bar managers work by moving or covering other apps' menu bar windows. On current macOS, the system **MenuBarAgent** draws the menu bar itself, and those tricks have become unreliable. 

BeverageDirector doesn't fight the system and doesn't try to reorder the icons. It flips the same **System Settings › Menu Bar › Allow in the Menu Bar** switches you could flip by hand, just a whole set at a time and instantly. MenuBarAgent does the actual hiding, so icons appear and disappear exactly as if you had toggled them in System Settings.

## Using it

| Action | Result |
|---|---|
| Left-click **…** | Switch between Collapsed and Expanded |
| Right-click (or Control-click) **…** | Menu with **Launch at Login**, **Automatically Collapse**, **Settings…** and **Quit BeverageDirector** |

### Settings

The settings window shows both states side by side: **Collapsed** on the left, **Expanded** on the right. Each list contains a checkbox to decide whether that app can put an icon in the menu bar when the state is active
