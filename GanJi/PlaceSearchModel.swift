import Foundation
import MapKit
import Combine

/// Uses Apple's MapKit place suggestions. Results are global suggestions, not a guaranteed
/// exhaustive national gazetteer; users should verify the province/city/county shown.
@MainActor
final class PlaceSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

    private let completer = MKLocalSearchCompleter()
    private var pendingQuery = ""

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        // Bias results toward China while still allowing the query to find other matches.
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.8617, longitude: 104.1954),
            span: MKCoordinateSpan(latitudeDelta: 35, longitudeDelta: 60)
        )
    }

    func query(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingQuery = trimmed
        errorMessage = nil
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            completer.queryFragment = ""
            return
        }
        isSearching = true
        completer.queryFragment = trimmed
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard completer.queryFragment == pendingQuery else { return }
        results = Array(completer.results.prefix(8))
        isSearching = false
        errorMessage = results.isEmpty ? "暂未找到地点，请尝试输入更完整的名称。" : nil
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
        isSearching = false
        errorMessage = "地点搜索暂不可用，请检查网络后重试。"
    }
}
