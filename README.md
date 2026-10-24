# GanJi v112 — Homepage Place Search

Homepage search now follows the Region map's place-search workflow:

1. Search a place name using MapKit autocomplete.
2. Show each result's title and smaller address subtitle so users can distinguish city/county/town context.
3. Resolve the selected suggestion to a placemark, match its administrative county against the region data, and use the matched area code for the existing `api.ganjirili.com/gathers` request (`areacode`).
4. Town-level places use the matched parent county's area code when the placemark provides that administrative hierarchy.

The existing Region map search remains available. ZIP integrity checked; Xcode compilation and iPhone runtime validation have not been performed in this environment.
