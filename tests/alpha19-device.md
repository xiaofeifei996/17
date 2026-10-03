# alpha19 device acceptance (iOS 15 / RootHide)

Static scope checks and a successful build do not validate private UIKit lifecycle behavior.

- Cold app: choose a terminated app; time from selection to first interactive frame. Compare alpha18 on the same device/app. No fixed speedup is assumed.
- Lock: float an app, move/resize it, lock and unlock twice, including once with keyboard open. Content and gestures must recover at the same position/size; no content may appear above the lock screen.
- Existing keyboard: open keyboard full screen, then float that same app. Keyboard must be full-width outside the float and above it; type and dismiss.
- New keyboard: open/close keyboard five times in the float, including after full-screen app switching. No embedded/duplicate keyboard or stale touch region.
- Cleanup: close float while keyboard is visible, then swipe Home pages and tap the former keyboard area. Repeat after lock/unlock. All touches must work without respring.
- Scope: test at least Notes and another unrelated app; no application-process injection.

Lock notification reference: https://github.com/julioverne/LockDroid/blob/master/lockdroidhook/Tweak.xm
