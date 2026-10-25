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


## v110 — distinctive visual redesign
- Reworked the home page into an editorial market-calendar layout with a dark olive / harvest-gold palette, numbered day sections, and a date-led hero.
- Rebranded map discovery as “圩场探索” and refined the market sheet and market rows into rounded, warm-paper cards.
- Rebuilt the persistent bottom Dock as a dark navigation strip with harvest-gold active state.
- Preserved the existing data models, market schedule calculations, location and search flows, favorites, region picker, MapKit map, and widget source.
- Source archive edited in this environment; an Xcode build/device validation has not been run.

## v111 — map page redesign, not a reference-screen copy
- Replaced the map page's warm light sheet with a midnight blue/charcoal surface and mint-green highlights.
- Changed market rows to dark individual cards, with teal distance labels, amber size tags, and arrow-style affordances.
- Changed location/search controls to dark floating capsules and updated the bottom Dock to match the new night-map theme.
- This intentionally departs from the supplied screenshot's ivory sheet, blue-gray distances, bright pink hearts, and white/blue search capsule.
- Existing functionality is preserved in source; compile and device testing are still required.


## v112 — Region page rebuilt
- Reworked the Region tab's identity and selected-area control into a location-exploration panel with English micro-label, mint location glyph, dark gradient card, and a distinct expanded picker surface.
- Updated the region selector and confirm/collapse actions to match the night-map theme. This is a structural component redesign rather than a recolor of the reference screenshot.
- Existing region data selection and chooseRegion flow retained. Build and device verification remain necessary.


## v113 — Region page structural redesign
- Rebuilt the map region sheet from a plain vertical market list into a discovery dashboard with a title/region/count header, filter chips, and a two-column market-card grid.
- Each market card has a storefront glyph, market name, animal/schedule detail, size/day chips, distance, and a favorite action.
- Reworked the region search capsule and suggestions to use the same dark navy / mint visual system.
- Kept the existing map, region selection, search model, market filtering, distance calculations, and favorites state.
- Xcode is not available in this environment, so the archive has not been compiled or validated on-device.


## v113.1 — place recognition fix (based on v113)
- Base archive: GanJi-v113-Region-Redesigned.zip. The v113 redesigned region-page UI is retained.
- Improved MapKit place-to-county matching using completion title/subtitle and placemark fields, with normalized names and ranked candidate scoring.
- Added offline fallback entries for 港北区、港南区、覃塘区 in 贵港市.
- UI redesign from later versions was not copied into this archive.
- iOS build and device validation remain required.
