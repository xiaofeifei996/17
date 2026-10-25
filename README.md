# GanJi v116 — Direct County Name Matching

Fixes place search for queries that are already county/district names (for example, 青秀区). Matching now checks the search title/subtitle against loaded county records before relying on MapKit placemark administrative fields. Unique exact county names can resolve even when MapKit only returns a province; duplicate names still require city/province context to avoid false matches.

The existing county selection and market API flow are unchanged. Bundled `Shared/markets.json` remains absent.

Validation: source-level patch and ZIP integrity check only; Xcode/iPhone runtime not verified.
