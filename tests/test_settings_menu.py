from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
resources = root / "prefs/Resources"
pages = {name: (resources / f"{name}.plist").read_text(encoding="utf-8")
         for name in ("Root", "Window", "Keyboard", "External", "System")}

assert "PSSwitchCell" not in pages["Root"] and "PSSliderCell" not in pages["Root"]
assert all(f"id = {name.lower()}" in pages["Root"]
           for name in ("Window", "Keyboard", "External", "System"))

keys = re.findall(r'key = "([^"]+)"', "\n".join(pages.values()))
assert len(keys) == len(set(keys))
assert set(keys) == {
    "showSplitAppIdentity", "portraitExternalKeyboard", "landscapeExternalKeyboard",
    "externalKeyboardHorizontalPercent", "closeOutsideWithKeyboard", "keyboardDimOpacity",
    "internalKeyboardZoomPercent",
    "notificationSplitEnabled", "urlSplitEnabled", "clearOnLock", "hideForScreenshot", "hostedCameraEnabled",
}
panel = (root / "PXPanel.swift").read_text(encoding="utf-8")
assert 'forKey: "internalKeyboardZoomPercent"' in panel
assert 'min(requestedZoom, room)' in panel
assert 'key = "internalKeyboardZoomPercent"; default = 160; min = 100; max = 200;' in pages["Keyboard"]

backup = (root / "prefs/PXBackupController.swift").read_text(encoding="utf-8")
assert all(text in backup for text in (
    "persistentDomain(forName: domain)", "PropertyListSerialization.data",
    "PropertyListSerialization.propertyList", "formatVersion", "backup[\"domain\"]",
    "setPersistentDomain(settings, forName: domain)", "UIAlertAction(title: \"恢复\"",
))
