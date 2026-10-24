# GanJi v96 - market panel and opaque search lane

This package is based on the supplied GanJi v94 project archive, with `GanJi/ContentView.swift` updated for v96.

Changes:
- Removed the keyboard-visible 150pt bottom reservation from the nearby-market panel so it can use more of the available height.
- Increased the collapsed panel share to 52%, expanded share to 86%, and keyboard-visible share to 94% of available geometry (bounded to preserve the bottom control lane).
- Removed the 44pt vertical offset when the keyboard appears.
- Extended the opaque search-lane background while the keyboard is visible to cover the map strip below the search control.

Please run the repository's GitHub Actions workflow and test on device; this package has not been built with Xcode in this environment.


## v102 layout fix
- Reserved a 96pt bottom lane for the persistent Dock when the keyboard is closed, so the unified market/search sheet no longer places its search control behind the Dock.
- Keyboard-visible layout does not receive this additional fixed offset.


## UI redesign
This revision replaces the original map-led interface with an editorial, card-based market discovery experience: warm paper background, dark green feature panel, date chips, searchable market cards, saved list, and a dedicated market detail sheet. Existing market data models, API, location support, assets, and widget sources are retained.
