# AppCleaner (macOS)

Lightweight leftover-file finder for macOS applications.  
Built with **Python + pywebview**.

## What’s new

- **Real app icons** – extracted via `NSWorkspace` (PyObjC) with `sips` fallback
- **Working drag-and-drop** – full paths via pywebview `DOMEventHandler` + `pywebviewFullPath`

## Requirements

- macOS 12+
- Python 3.9+
- Full Disk Access (recommended)

## Install & Run

```bash
cd AppCleaner
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py
```

## Permissions

1. Open **System Settings → Privacy & Security → Full Disk Access**
2. Add **Terminal** (or your packaged app / Python binary)
3. Restart AppCleaner

## Usage

1. Drop a `.app` onto the window, or click **Choose Application…**, or open the list (☰)
2. Select an app → **Scan**
3. Review leftovers (High / Medium / Low confidence)
4. **Remove Selected…** moves items to Trash (safe)

## Icons

Icons are loaded as PNG data-URLs:

1. Preferred: `NSWorkspace.sharedWorkspace().iconForFile_()` (needs `pyobjc-framework-Cocoa`)
2. Fallback: read `CFBundleIconFile` from Info.plist → convert `.icns` with `sips`

## Drag & drop

pywebview only exposes full paths on the **Python** side.  
`main.py` binds `drop` / `dragover` with `DOMEventHandler(prevent_default=True)` and calls:

```js
window.__appCleanerHandleDrop(paths)
```

so the frontend can `inspect_app` and show the real icon.
