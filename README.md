# AppCleaner (Native SwiftUI)

Native macOS cleaner built with **SwiftUI** for **Xcode 27**.

## Open in Xcode 27 beta 5

### Option A — Create project and add sources (recommended)

1. Open **Xcode 27**
2. **File → New → Project…**
3. Choose **macOS → App**
4. Product Name: `AppCleaner`
5. Interface: **SwiftUI**
6. Language: **Swift**
7. Uncheck "Include Tests" if you want a minimal project
8. Save the project (e.g. replace this folder or create next to it)
9. Delete the default `ContentView.swift` / `AppCleanerApp.swift` that Xcode generated
10. Drag the contents of the `AppCleaner/` folder from this package into the Xcode project navigator (check **Copy items if needed**)
11. Target → **Signing & Capabilities**: select your Team
12. **Info** / capabilities: enable **App Sandbox** only if you want it — for full cleanup you typically **disable App Sandbox** or add temporary exception entitlements for user-selected and absolute paths
13. Run (⌘R)

### Option B — Use the included sources as a folder reference

The Swift sources under `AppCleaner/` are ready to drop into any macOS SwiftUI target.

## Features

- Dashboard with disk health (Excellent / Good / Poor / Really Bad)
- Smart Scan, System Junk, Applications, Leftovers
- Disk Map (sunburst canvas)
- Large & Old files, Privacy caches
- Maintenance: Reduce RAM, Empty Trash, Flush DNS, Dock, Finder
- Native menu bar status item (🧹)
- App / Clean / View menu commands

## Permissions

For best results grant **Full Disk Access**:

**System Settings → Privacy & Security → Full Disk Access → add AppCleaner**

## Requirements

- macOS 14+ (Sonoma or later recommended)
- Xcode 27 beta 5
- Apple Silicon or Intel

## Notes

- Moving items uses `FileManager.trashItem` (recoverable from Trash)
- `purge` (Reduce RAM) prompts for admin
- Not a malware scanner
