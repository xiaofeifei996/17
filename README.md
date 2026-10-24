# GanJi v93 - Opaque search area fix

This revision fixes the search-area surroundings becoming transparent when the location search TextField receives focus.

Changes in `GanJi/ContentView.swift`:
- The outer search capsule uses solid white instead of system background opacity.
- The search/suggestions container uses solid white.
- The whole search-and-dock region always paints an opaque white backing extending through the bottom safe area; it no longer switches to a clear background when focus changes.
- Existing search, suggestion, nearby market panel, favorites, and region selection logic is preserved.

Compile with the project's existing GitHub Actions workflow. Xcode compilation was not run in this environment.
