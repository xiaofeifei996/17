import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches the same public market-list endpoint observed in the user's HAR.
/// Availability and response shape for other area codes must be verified at runtime.
enum MarketAPI {
    private struct Envelope: Decodable {
        let total: Int?
        let data: [Record]
    }

    private struct Record: Decodable {
        let id: Int
        let name: String
        let marketType: Int?
        let repeatType: Int?
        let repeatValue: [String]?
        let remark: String?
        let place: String?
        let address: String?
        let gps: [Double]?
        let cityCode: Int?
        let areaCode: Int?
        let status: Int?

        enum CodingKeys: String, CodingKey {
            case id, name, remark, place, address, gps, status
            case marketType = "market_type"
            case repeatType = "repeat_type"
            case repeatValue = "repeat_value"
            case cityCode = "citycode"
            case areaCode = "areacode"
        }
    }

    static func fetch(areaCode: Int) async throws -> [Market] {
        var components = URLComponents(string: "https://api.ganjirili.com/gathers")!
        components.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pageSize", value: "199"),
            URLQueryItem(name: "areacode", value: String(areaCode))
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (rawData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // HAR exports can mark JSON response bodies as base64. Live HTTP usually returns JSON directly;
        // accept either representation without assuming the server always uses one format.
        let data: Data
        if (try? JSONSerialization.jsonObject(with: rawData)) != nil {
            data = rawData
        } else if let text = String(data: rawData, encoding: .utf8),
                  let decoded = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (try? JSONSerialization.jsonObject(with: decoded)) != nil {
            data = decoded
        } else {
            throw URLError(.cannotParseResponse)
        }

        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        let known = MarketStore.load().first(where: { $0.areaCode == areaCode })
        return envelope.data.compactMap { item in
            guard let gps = item.gps, gps.count >= 2 else { return nil }
            return Market(
                id: String(item.id),
                name: item.name,
                province: known?.province ?? "",
                city: known?.city ?? "",
                area: known?.area ?? "",
                provinceCode: known?.provinceCode,
                cityCode: item.cityCode,
                areaCode: item.areaCode ?? areaCode,
                sourceAreaCode: item.areaCode ?? areaCode,
                lat: gps[1],
                lon: gps[0],
                marketType: item.marketType,
                repeatType: item.repeatType,
                repeatValue: item.repeatValue ?? [],
                remark: item.remark ?? "",
                place: item.place ?? "",
                address: item.address ?? "",
                status: item.status
            )
        }.filter { $0.status == nil || $0.status == 1 }
    }
}

enum MarketCache {
    private static func url(for areaCode: Int) -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("markets-\(areaCode).json")
    }

    static func save(_ markets: [Market], areaCode: Int) {
        guard let url = url(for: areaCode), let data = try? JSONEncoder().encode(Wrapper(markets: markets)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load(areaCode: Int) -> [Market]? {
        guard let url = url(for: areaCode), let data = try? Data(contentsOf: url),
              let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data) else { return nil }
        return wrapper.markets
    }

    private struct Wrapper: Codable { let markets: [Market] }
}
