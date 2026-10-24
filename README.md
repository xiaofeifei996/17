# GanJi v109 — Vertical Nearby Market List

Based on v108 unified search + nearby market panel.

Changes:
- Replaced the collapsed nearby-market horizontal carousel with a vertical scrolling list.
- Reuses the existing `MarketListRow` component, preserving schedule, distance, selection and favorite UI.
- Selecting a row in the compact list centers the map on that market.
- Keeps the expanded vertical list and place search flow intact.
- Does not introduce iOS 16-only APIs.

Validation: ZIP integrity checked. An Xcode/macOS build was not available in this environment.
