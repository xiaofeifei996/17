# GanJi v113 — Remove Bundled 108 Markets

Removed `Shared/markets.json`, the bundled dataset containing 108 built-in market records. Market lists now rely on live API results and per-area cached results instead of the bundled sample data. If the network fails and no cache exists for the selected area, the app will show its existing network/error empty state rather than displaying the built-in 108 markets.

The region/place search and existing `api.ganjirili.com/gathers` request flow are retained. ZIP integrity checked; Xcode compilation and iPhone runtime validation have not been performed in this environment.
