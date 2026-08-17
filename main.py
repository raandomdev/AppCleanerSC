#!/usr/bin/env python3
"""
AppCleaner – macOS leftover file finder & remover
Requires: Full Disk Access (System Settings → Privacy & Security)
"""

from __future__ import annotations

import base64
import os
import shutil
import subprocess
import sys
import tempfile
import threading
from pathlib import Path
from typing import Any, Dict, List, Optional

import webview
from webview.dom import DOMEventHandler

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
HOME = Path.home()
USER_LIBRARY = HOME / "Library"
SYSTEM_LIBRARY = Path("/Library")

SCAN_ROOTS = [
    USER_LIBRARY / "Application Support",
    USER_LIBRARY / "Caches",
    USER_LIBRARY / "Preferences",
    USER_LIBRARY / "Containers",
    USER_LIBRARY / "Group Containers",
    USER_LIBRARY / "Saved Application State",
    USER_LIBRARY / "Logs",
    USER_LIBRARY / "LaunchAgents",
    USER_LIBRARY / "HTTPStorages",
    USER_LIBRARY / "WebKit",
    USER_LIBRARY / "Cookies",
    SYSTEM_LIBRARY / "Application Support",
    SYSTEM_LIBRARY / "Caches",
    SYSTEM_LIBRARY / "LaunchAgents",
    SYSTEM_LIBRARY / "LaunchDaemons",
    SYSTEM_LIBRARY / "PrivilegedHelperTools",
]

APP_DIRS = [
    Path("/Applications"),
    HOME / "Applications",
]

PROTECTED_PREFIXES = ("com.apple.",)

# Icon cache: app path -> data URL
_ICON_CACHE: Dict[str, Optional[str]] = {}


# ---------------------------------------------------------------------------
# Icon extraction (macOS)
# ---------------------------------------------------------------------------
def _icon_via_appkit(app_path: str, size: int = 64) -> Optional[str]:
    """Best quality: NSWorkspace icon → PNG data URL."""
    try:
        from AppKit import NSBitmapImageFileTypePNG, NSBitmapImageRep, NSWorkspace
        from Cocoa import NSMakeSize

        icon = NSWorkspace.sharedWorkspace().iconForFile_(app_path)
        if icon is None:
            return None
        icon.setSize_(NSMakeSize(size, size))
        tiff = icon.TIFFRepresentation()
        if tiff is None:
            return None
        rep = NSBitmapImageRep.imageRepWithData_(tiff)
        if rep is None:
            return None
        png_data = rep.representationUsingType_properties_(
            NSBitmapImageFileTypePNG, None
        )
        if png_data is None:
            return None
        b64 = base64.b64encode(bytes(png_data)).decode("ascii")
        return f"data:image/png;base64,{b64}"
    except Exception:
        return None


def _icon_via_sips(app_path: Path, size: int = 64) -> Optional[str]:
    """Fallback: locate .icns in Contents/Resources and convert with sips."""
    try:
        import plistlib

        info_plist = app_path / "Contents" / "Info.plist"
        icon_name = None
        if info_plist.exists():
            with open(info_plist, "rb") as f:
                plist = plistlib.load(f)
            icon_name = plist.get("CFBundleIconFile") or plist.get("CFBundleIconName")

        resources = app_path / "Contents" / "Resources"
        candidates: List[Path] = []
        if icon_name:
            base = icon_name if icon_name.endswith(".icns") else f"{icon_name}.icns"
            candidates.append(resources / base)
            candidates.append(resources / icon_name)
        # Common fallbacks
        candidates.extend(resources.glob("*.icns"))

        icns = next((c for c in candidates if c.is_file()), None)
        if not icns:
            return None

        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
            out = tmp.name
        try:
            r = subprocess.run(
                [
                    "sips",
                    "-s",
                    "format",
                    "png",
                    "-z",
                    str(size),
                    str(size),
                    str(icns),
                    "--out",
                    out,
                ],
                capture_output=True,
                timeout=10,
            )
            if r.returncode != 0 or not Path(out).exists():
                return None
            data = Path(out).read_bytes()
            b64 = base64.b64encode(data).decode("ascii")
            return f"data:image/png;base64,{b64}"
        finally:
            try:
                os.unlink(out)
            except OSError:
                pass
    except Exception:
        return None


def get_app_icon_data_url(app_path: str, size: int = 64) -> Optional[str]:
    key = f"{app_path}:{size}"
    if key in _ICON_CACHE:
        return _ICON_CACHE[key]

    path = Path(app_path)
    if not path.exists():
        _ICON_CACHE[key] = None
        return None

    icon = _icon_via_appkit(app_path, size) or _icon_via_sips(path, size)
    _ICON_CACHE[key] = icon
    return icon


class Api:
    def __init__(self) -> None:
        self._cancel = threading.Event()
        self.window: Any = None

    # ------------------------------------------------------------------
    # Permissions
    # ------------------------------------------------------------------
    def check_full_disk_access(self) -> Dict[str, Any]:
        can_list = False
        try:
            list((USER_LIBRARY / "Containers").iterdir())
            can_list = True
        except (PermissionError, OSError):
            pass
        return {
            "has_full_disk_access": can_list,
            "can_list_containers": can_list,
            "message": (
                "Full Disk Access looks OK."
                if can_list
                else "Full Disk Access is required. Open System Settings → Privacy & Security → Full Disk Access and enable Terminal (or this app)."
            ),
        }

    def open_full_disk_access_settings(self) -> bool:
        try:
            subprocess.run(
                [
                    "open",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
                ],
                check=False,
            )
            return True
        except Exception:
            return False

    # ------------------------------------------------------------------
    # App discovery + icons
    # ------------------------------------------------------------------
    def _read_plist(self, app_path: Path) -> Optional[dict]:
        info = app_path / "Contents" / "Info.plist"
        if not info.exists():
            return None
        try:
            import plistlib

            with open(info, "rb") as f:
                return plistlib.load(f)
        except Exception:
            return None

    def _app_info(self, item: Path, with_icon: bool = True) -> Dict[str, Any]:
        plist = self._read_plist(item)
        name = (
            (plist or {}).get("CFBundleDisplayName")
            or (plist or {}).get("CFBundleName")
            or item.stem
        )
        bundle_id = (plist or {}).get("CFBundleIdentifier", "") or ""
        version = (plist or {}).get("CFBundleShortVersionString") or (
            plist or {}
        ).get("CFBundleVersion", "")
        protected = any(bundle_id.startswith(p) for p in PROTECTED_PREFIXES)
        icon = get_app_icon_data_url(str(item)) if with_icon else None
        return {
            "name": name,
            "path": str(item),
            "bundle_id": bundle_id,
            "version": version or "",
            "protected": protected,
            "icon": icon,
        }

    def list_installed_apps(self) -> List[Dict[str, Any]]:
        apps: List[Dict[str, Any]] = []
        seen = set()
        for root in APP_DIRS:
            if not root.exists():
                continue
            try:
                for item in sorted(root.iterdir(), key=lambda p: p.name.lower()):
                    if not item.is_dir() or item.suffix != ".app":
                        continue
                    if item.name in seen:
                        continue
                    seen.add(item.name)
                    apps.append(self._app_info(item, with_icon=True))
            except (PermissionError, OSError):
                continue
        apps.sort(key=lambda a: a["name"].lower())
        return apps

    def get_app_icon(self, app_path: str) -> Optional[str]:
        """Return data-URL icon for a single app (used after drop / choose)."""
        return get_app_icon_data_url(app_path)

    def inspect_app(self, app_path: str) -> Optional[Dict[str, Any]]:
        """Build full app info from an arbitrary path (drop / choose)."""
        path = Path(app_path)
        # Normalize if user dropped something inside the bundle
        if path.suffix != ".app":
            parts = path.parts
            for i, part in enumerate(parts):
                if part.endswith(".app"):
                    path = Path(*parts[: i + 1])
                    break
        if not path.is_dir() or path.suffix != ".app":
            return None
        return self._app_info(path, with_icon=True)

    def choose_application(self) -> Optional[Dict[str, Any]]:
        """
        Native macOS open panel that can select .app bundles
        (they are packages/directories, so a normal file dialog often fails).
        """
        path = self._native_choose_app()
        if not path:
            return None
        return self.inspect_app(path)

    def _native_choose_app(self) -> Optional[str]:
        # 1) Preferred: AppKit NSOpenPanel configured for application packages
        try:
            from AppKit import NSOpenPanel, NSURL
            from Foundation import NSURL as FNSURL  # noqa: F401 – available via AppKit

            panel = NSOpenPanel.openPanel()
            panel.setCanChooseFiles_(True)
            panel.setCanChooseDirectories_(True)  # .app is a directory package
            panel.setAllowsMultipleSelection_(False)
            panel.setResolvesAliases_(True)
            panel.setTitle_("Choose Application")
            panel.setPrompt_("Choose")
            panel.setMessage_("Select a macOS application (.app)")
            # Restrict to .app when possible
            try:
                panel.setAllowedFileTypes_(["app"])
            except Exception:
                pass
            try:
                apps_url = NSURL.fileURLWithPath_("/Applications")
                panel.setDirectoryURL_(apps_url)
            except Exception:
                pass

            # runModal must run on main thread – pywebview API calls usually are
            if panel.runModal() != 1:  # NSModalResponseOK == 1
                return None
            urls = panel.URLs()
            if not urls or len(urls) == 0:
                return None
            chosen = str(urls[0].path())
            return chosen
        except Exception:
            pass

        # 2) Fallback: AppleScript choose file of type app
        try:
            script = (
                'set theApp to choose file of type {"app"} '
                'with prompt "Choose Application" '
                'default location (path to applications folder)\n'
                "return POSIX path of theApp"
            )
            r = subprocess.run(
                ["osascript", "-e", script],
                capture_output=True,
                text=True,
                timeout=120,
            )
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout.strip()
        except Exception:
            pass

        # 3) Last resort: pywebview folder dialog
        try:
            dialog_type = getattr(webview, "FOLDER_DIALOG", None)
            if dialog_type is None:
                fd = getattr(webview, "FileDialog", None)
                if fd is not None:
                    dialog_type = getattr(fd, "FOLDER", getattr(fd, "OPEN", None))
            if dialog_type is None:
                dialog_type = getattr(webview, "OPEN_DIALOG", 10)
            result = self.window.create_file_dialog(
                dialog_type,
                allow_multiple=False,
                directory="/Applications",
            )
            if result:
                return str(result[0] if isinstance(result, (list, tuple)) else result)
        except Exception:
            pass
        return None

    # ------------------------------------------------------------------
    # Scanning
    # ------------------------------------------------------------------
    def _get_size(self, path: Path) -> int:
        total = 0
        try:
            if path.is_file():
                return path.stat().st_size
            for root, _dirs, files in os.walk(path, onerror=lambda _e: None):
                for f in files:
                    try:
                        total += (Path(root) / f).stat().st_size
                    except (OSError, PermissionError):
                        pass
        except (OSError, PermissionError):
            pass
        return total

    def _human_size(self, n: int) -> str:
        for unit in ("B", "KB", "MB", "GB", "TB"):
            if n < 1024:
                return f"{n:.1f} {unit}" if unit != "B" else f"{n} B"
            n /= 1024.0
        return f"{n:.1f} PB"

    def scan_app(self, app_path: str, bundle_id: str, app_name: str) -> Dict[str, Any]:
        self._cancel.clear()
        results: List[Dict[str, Any]] = []
        app_path_p = Path(app_path)

        name_variants = {
            app_name,
            app_name.replace(" ", ""),
            app_name.lower(),
            app_name.replace(" ", "").lower(),
            app_path_p.stem,
        }
        if bundle_id:
            name_variants.add(bundle_id)
            name_variants.add(bundle_id.split(".")[-1])
        name_variants = {v for v in name_variants if v}

        def matches(entry_name: str) -> Optional[str]:
            en = entry_name.lower()
            for v in name_variants:
                vl = v.lower()
                if en == vl or en.startswith(vl + ".") or en.startswith(vl + "-"):
                    return "exact / prefix"
                if vl in en:
                    return "contains name"
            return None

        for root in SCAN_ROOTS:
            if self._cancel.is_set():
                break
            if not root.exists():
                continue
            try:
                entries = list(root.iterdir())
            except (PermissionError, OSError):
                continue

            for entry in entries:
                if self._cancel.is_set():
                    break
                reason = matches(entry.name)
                if not reason:
                    continue
                try:
                    if entry.resolve() == app_path_p.resolve():
                        continue
                except OSError:
                    pass

                confidence = "medium"
                if bundle_id and (
                    entry.name == bundle_id
                    or entry.name.startswith(bundle_id + ".")
                    or entry.name == f"{bundle_id}.plist"
                    or entry.name == f"{bundle_id}.savedState"
                ):
                    confidence = "high"
                elif reason == "exact / prefix":
                    confidence = "high"
                elif reason == "contains name":
                    confidence = "low"

                protected = any(
                    bundle_id.startswith(p) for p in PROTECTED_PREFIXES
                ) if bundle_id else False
                if protected:
                    confidence = "protected"

                size = self._get_size(entry)
                results.append(
                    {
                        "path": str(entry),
                        "size": size,
                        "size_human": self._human_size(size),
                        "confidence": confidence,
                        "reason": reason,
                        "protected": protected,
                        "selected": confidence in ("high", "medium") and not protected,
                    }
                )

        if app_path_p.exists():
            size = self._get_size(app_path_p)
            results.insert(
                0,
                {
                    "path": str(app_path_p),
                    "size": size,
                    "size_human": self._human_size(size),
                    "confidence": "high",
                    "reason": "application bundle",
                    "protected": any(
                        bundle_id.startswith(p) for p in PROTECTED_PREFIXES
                    )
                    if bundle_id
                    else False,
                    "selected": True,
                },
            )

        results.sort(key=lambda r: (-r["size"], r["path"].lower()))
        total_size = sum(r["size"] for r in results if not r["protected"])
        return {
            "items": results,
            "total_size": total_size,
            "total_size_human": self._human_size(total_size),
            "count": len(results),
            "cancelled": self._cancel.is_set(),
        }

    def cancel_scan(self) -> bool:
        self._cancel.set()
        return True

    # ------------------------------------------------------------------
    # Removal
    # ------------------------------------------------------------------
    def remove_items(self, paths: List[str]) -> Dict[str, Any]:
        removed: List[str] = []
        errors: List[Dict[str, str]] = []
        for p in paths:
            path = Path(p)
            if not path.exists():
                errors.append({"path": p, "error": "does not exist"})
                continue
            if any(
                str(path).startswith(s)
                for s in ("/System", "/usr", "/bin", "/sbin", "/private/var/db")
            ):
                errors.append({"path": p, "error": "protected system path"})
                continue
            try:
                subprocess.run(
                    [
                        "osascript",
                        "-e",
                        f'tell application "Finder" to delete POSIX file "{path}"',
                    ],
                    check=True,
                    capture_output=True,
                )
                removed.append(p)
            except subprocess.CalledProcessError:
                try:
                    trash = HOME / ".Trash"
                    trash.mkdir(exist_ok=True)
                    dest = trash / path.name
                    counter = 1
                    while dest.exists():
                        dest = trash / f"{path.stem} {counter}{path.suffix}"
                        counter += 1
                    shutil.move(str(path), str(dest))
                    removed.append(p)
                except Exception as e:
                    errors.append({"path": p, "error": str(e)})
            except Exception as e:
                errors.append({"path": p, "error": str(e)})
        return {
            "removed": removed,
            "errors": errors,
            "removed_count": len(removed),
        }

    def reveal_in_finder(self, path: str) -> bool:
        try:
            subprocess.run(["open", "-R", path], check=False)
            return True
        except Exception:
            return False


def _bind_drag_drop(window: Any) -> None:
    """Enable full-path drag & drop via Python-side DOM events, then notify JS."""

    def on_drag(_e: dict) -> None:
        pass

    def on_drop(e: dict) -> None:
        files = (e.get("dataTransfer") or {}).get("files") or []
        paths: List[str] = []
        for f in files:
            if isinstance(f, dict):
                p = f.get("pywebviewFullPath") or f.get("name")
            else:
                p = None
            if p:
                paths.append(str(p))
        if not paths:
            return
        import json

        payload = json.dumps(paths)
        try:
            window.evaluate_js(
                f"window.__appCleanerHandleDrop && window.__appCleanerHandleDrop({payload})"
            )
        except Exception:
            pass

    # preventDefault=True is required so the webview accepts the drop
    try:
        window.dom.document.events.dragenter += DOMEventHandler(on_drag, True, True)
        window.dom.document.events.dragover += DOMEventHandler(
            on_drag, True, True, debounce=200
        )
        window.dom.document.events.drop += DOMEventHandler(on_drop, True, True)
    except Exception as exc:
        print(f"Warning: could not bind drag-drop handlers: {exc}")


def main() -> None:
    if sys.platform != "darwin":
        print("AppCleaner is macOS-only.")
        sys.exit(1)

    api = Api()
    # Support PyInstaller bundles (sys._MEIPASS holds extracted data files)
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        base = Path(sys._MEIPASS)
    else:
        base = Path(__file__).resolve().parent
    html_path = base / "index.html"
    if not html_path.exists():
        alt = Path(sys.executable).resolve().parent / "index.html"
        if alt.exists():
            html_path = alt
            base = alt.parent
        else:
            print(f"Missing {html_path}")
            sys.exit(1)

    window = webview.create_window(
        "AppCleaner",
        url=html_path.as_uri(),
        js_api=api,
        width=900,
        height=620,
        min_size=(700, 480),
        frameless=False,
        easy_drag=False,
        background_color="#1E1E20",
        text_select=False,
    )
    api.window = window

    def on_start() -> None:
        # Bind after the window/DOM is ready
        try:
            _bind_drag_drop(window)
        except Exception as exc:
            print(f"Drag-drop bind failed: {exc}")

    webview.start(on_start, debug=False)


if __name__ == "__main__":
    main()
