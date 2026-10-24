# GanJi v110 — Homepage Uses Region Search

Based on v109 vertical nearby-market list.

Changes:
- Homepage search now searches the same administrative-region dataset used by the Region picker.
- Results include province, city and county/district entries, with county matches ranked first.
- Selecting a result reuses `chooseRegion(_:)`, then opens the Region/map experience for that area.
- Homepage search no longer uses MapKit place autocomplete; the map destination search keeps its existing place-search behavior.
- Preserves existing region loading, region selection, market refresh, routing, favorites and the vertical nearby-market list.
- Uses APIs compatible with the iOS 15 deployment target.

Validation: ZIP integrity and source-level checks completed. An Xcode/macOS build and iPhone runtime test were not available in this environment.
