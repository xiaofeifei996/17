import Foundation

/// 圩点记录。repeatType / repeatValue 保留原始接口字段，不把未知编码猜成固定圩期。
struct Market: Codable, Identifiable {
    let id: String
    let name: String
    let province: String
    let city: String
    let area: String
    let provinceCode: Int?
    let cityCode: Int?
    let areaCode: Int?
    let sourceAreaCode: Int?
    let lat: Double
    let lon: Double
    let marketType: Int?
    let repeatType: Int?
    let repeatValue: [String]
    let remark: String
    let place: String
    let address: String
    let status: Int?

    var size: String { marketType == 1 ? "大集" : "集市" }

    /// type 6 的生肖值转换为对应地支，供旧 UI 显示；其它规则不伪造生肖。
    var branches: String {
        guard repeatType == 6 else { return "" }
        let map = ["鼠":"子", "牛":"丑", "虎":"寅", "兔":"卯", "龙":"辰", "蛇":"巳", "马":"午", "羊":"未", "猴":"申", "鸡":"酉", "狗":"戌", "猪":"亥"]
        return repeatValue.compactMap { map[$0] }.joined()
    }

    var displaySchedule: String {
        if repeatType == 6 { return repeatValue.joined(separator: "、") }
        if repeatType == 1 || repeatType == 4 { return "农历" + repeatValue.joined(separator: "、") }
        return "圩期待核实"
    }
}

private struct MarketFile: Decodable {
    let markets: [Market]
}

struct MarketDay: Identifiable {
    let market: Market
    let date: Date
    let daysAhead: Int
    var id: String { market.id + "-\(daysAhead)" }
    var branches: String { market.branches.map(String.init).joined(separator: "·") }
    var animals: String {
        if market.repeatType == 6 { return market.repeatValue.joined(separator: "、") }
        return market.displaySchedule
    }
    var dayLabel: String {
        switch daysAhead { case 0: return "今天"; case 1: return "明天"; case 2: return "后天"; default: return "\(daysAhead)天后" }
    }
}

enum MarketStore {
    static func load() -> [Market] {
        guard let url = Bundle.main.url(forResource: "markets", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(MarketFile.self, from: data) else { return [] }
        return file.markets.filter { $0.status == nil || $0.status == 1 }
    }

    private static let phaseTable: [Character: Int] = ["子":0,"卯":0,"午":0,"酉":0,"辰":1,"戌":1,"丑":1,"未":1,"寅":2,"申":2,"巳":2,"亥":2]
    static func phase(ofBranches branches: String) -> Int? { guard let first = branches.first else { return nil }; return phaseTable[first] }
    static func dayPhase(_ date: Date) -> Int? { guard let first = LunarCalendar.branchName(date).first else { return nil }; return phaseTable[first] }

    private static func lunarDay(_ date: Date) -> Int {
        var cal = Calendar(identifier: .chinese); cal.timeZone = TimeZone.current
        return cal.component(.day, from: date)
    }
    private static func lunarDayNumber(_ value: String) -> Int? {
        if let n = Int(value), (1...30).contains(n) { return n }
        let map = ["一":1,"二":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9,"十":10]
        if value == "十一" { return 11 }; if value == "十二" { return 12 }; if value == "十三" { return 13 }; if value == "十四" { return 14 }; if value == "十五" { return 15 }; if value == "十六" { return 16 }; if value == "十七" { return 17 }; if value == "十八" { return 18 }; if value == "十九" { return 19 }; if value == "二十" { return 20 }; if value == "廿一" { return 21 }; if value == "廿二" { return 22 }; if value == "廿三" { return 23 }; if value == "廿四" { return 24 }; if value == "廿五" { return 25 }; if value == "廿六" { return 26 }; if value == "廿七" { return 27 }; if value == "廿八" { return 28 }; if value == "廿九" { return 29 }; if value == "三十" { return 30 }
        return map[value]
    }

    static func daysUntilNext(_ market: Market, from fromDate: Date) -> Int {
        let cal = Calendar.current
        for offset in 0..<40 {
            guard let d = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: fromDate)) else { continue }
            switch market.repeatType {
            case 6:
                guard let p = phase(ofBranches: market.branches), dayPhase(d) == p else { continue }
                return offset
            case 1, 4:
                let wanted = market.repeatValue.compactMap(lunarDayNumber)
                if wanted.contains(lunarDay(d)) { return offset }
            default: continue
            }
        }
        return -1
    }

    static func nextDate(_ market: Market, from fromDate: Date) -> Date {
        let n = max(daysUntilNext(market, from: fromDate), 0)
        return Calendar.current.date(byAdding: .day, value: n, to: Calendar.current.startOfDay(for: fromDate)) ?? fromDate
    }

    static func upcoming(from date: Date, markets source: [Market]? = nil) -> [MarketDay] {
        let today = Calendar.current.startOfDay(for: date)
        return (source ?? load()).enumerated().compactMap { index, market -> (Int, MarketDay)? in
            let n = daysUntilNext(market, from: today)
            guard n >= 0 else { return nil }
            let d = Calendar.current.date(byAdding: .day, value: n, to: today) ?? today
            return (index, MarketDay(market: market, date: d, daysAhead: n))
        }.sorted { a, b in a.1.daysAhead == b.1.daysAhead ? a.0 < b.0 : a.1.daysAhead < b.1.daysAhead }.map(\.1)
    }

    static func markets(on date: Date) -> [Market] {
        let day = Calendar.current.startOfDay(for: date)
        return load().filter { daysUntilNext($0, from: day) == 0 }
    }

    static var availableAreas: [(code: Int, name: String, city: String, province: String, lat: Double, lon: Double)] {
        let grouped = Dictionary(grouping: load(), by: { $0.areaCode ?? 0 })
        return grouped.compactMap { code, markets in
            guard code > 0, let first = markets.first else { return nil }
            let coords = markets.compactMap { m -> (Double, Double)? in m.lat.isFinite && m.lon.isFinite ? (m.lat, m.lon) : nil }
            guard !coords.isEmpty else { return nil }
            return (code, first.area, first.city, first.province,
                    coords.map(\.0).reduce(0, +) / Double(coords.count),
                    coords.map(\.1).reduce(0, +) / Double(coords.count))
        }.sorted { $0.name < $1.name }
    }

    static func distanceKm(_ market: Market, from lat: Double, lon: Double) -> Double {
        let rad = Double.pi / 180
        let dLat = (market.lat - lat) * rad, dLon = (market.lon - lon) * rad
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat * rad) * cos(market.lat * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 6371 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

func kmText(_ km: Double) -> String { km < 1 ? String(format: "%.0f米", km * 1000) : String(format: "%.1f公里", km) }
