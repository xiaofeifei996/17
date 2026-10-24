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


## UI redesign (v103)
- Reworked home header and added a warm green daily hero panel.
- Shifted accent colors to a natural market-inspired palette.
- Updated market row typography, selection fills, and panel surfaces.
- Preserved MarketAPI endpoint, MapKit place suggestions, lunar market schedule logic, filters, favorites, region lookup, and widget targets.


## v106 — remove bundled market records
- Deleted `Shared/markets.json` containing the bundled market list.
- `MarketStore.load()` now returns an empty list; runtime market data should come from the existing API fetch or per-area cache.
- `MarketAPI` endpoint and response parsing remain unchanged.
- The API used bundled records only as optional region-name metadata; without the dataset, that metadata falls back to empty strings.
- Updated schedule test to assert there is no bundled market dataset.
- Not built with Xcode in this environment; verify API loading and region labels on device.
