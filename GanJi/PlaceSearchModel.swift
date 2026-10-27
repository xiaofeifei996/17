import Foundation
import MapKit
import Combine

/// Shared MapKit place search for the Home and Region screens.
/// It debounces fast typing, ignores stale callbacks, and retries one empty/failed request.
@MainActor
final class PlaceSearchModel: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

    private let completer = MKLocalSearchCompleter()
    private var pendingQuery = ""
    private var requestTask: Task<Void, Never>?
    private var didRetryCurrentQuery = false

    override init() {
        super.init()
        completer.delegate = self
        // Include general query suggestions as well as addresses and POIs. This helps
        // when users search Chinese administrative names (cities/counties/towns).
        completer.resultTypes = [.address, .pointOfInterest, .query]
        // Bias results toward China while retaining nationwide search coverage.
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.8617, longitude: 104.1954),
            span: MKCoordinateSpan(latitudeDelta: 35, longitudeDelta: 60)
        )
    }

    func clearResults() {
        requestTask?.cancel()
        requestTask = nil
        pendingQuery = ""
        didRetryCurrentQuery = false
        results = []
        isSearching = false
        errorMessage = nil
        completer.queryFragment = ""
    }

    func query(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        requestTask?.cancel()
        pendingQuery = trimmed
        didRetryCurrentQuery = false
        errorMessage = nil
        results = []

        guard trimmed.count >= 2 else {
            isSearching = false
            completer.queryFragment = ""
            return
        }

        isSearching = true
        // Debounce keystrokes so older MapKit responses are less likely to race the
        // newest query, especially on slower mobile connections.
        requestTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard let self, !Task.isCancelled, self.pendingQuery == trimmed else { return }
            self.completer.queryFragment = trimmed
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard completer.queryFragment == pendingQuery, pendingQuery.count >= 2 else { return }
        let currentResults = Array(completer.results.prefix(12))
        guard !currentResults.isEmpty else {
            if retryCurrentQueryOnce() { return }
            results = []
            isSearching = false
            errorMessage = "暂未找到地点，请尝试输入更完整的名称。"
            return
        }
        results = currentResults
        isSearching = false
        errorMessage = nil
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Ignore failure callbacks belonging to an old query.
        guard completer.queryFragment == pendingQuery, pendingQuery.count >= 2 else { return }
        if retryCurrentQueryOnce() { return }
        results = []
        isSearching = false
        errorMessage = "地点搜索暂不可用，请检查网络后重试。"
    }

    @discardableResult
    private func retryCurrentQueryOnce() -> Bool {
        guard !didRetryCurrentQuery, pendingQuery.count >= 2 else { return false }
        didRetryCurrentQuery = true
        let query = pendingQuery
        requestTask?.cancel()
        isSearching = true
        requestTask = Task { [weak self] in
            guard let self else { return }
            self.completer.queryFragment = ""
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, self.pendingQuery == query else { return }
            self.completer.queryFragment = query
        }
        return true
    }
}
