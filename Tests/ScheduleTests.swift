import Foundation

@main struct ScheduleTests {
    static func main() throws {
        let chinaTZ = TimeZone(identifier: "Asia/Shanghai")!
        NSTimeZone.default = chinaTZ
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = chinaTZ

        // The app intentionally ships without bundled market records.
        let markets = MarketStore.load()
        precondition(markets.isEmpty, "Bundled market dataset should be empty")

        for day in 20...31 {
            for hour in [0, 1, 8, 16, 18, 23] {
                let d = cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
                let start = cal.startOfDay(for: d)
                let ids = markets.filter { MarketStore.daysUntilNext($0, from: d) == 0 }.map(\.id)
                let idsAtStart = markets.filter { MarketStore.daysUntilNext($0, from: start) == 0 }.map(\.id)
                precondition(ids == idsAtStart, "Schedule must be stable throughout local day: \(d)")
                precondition(LunarCalendar.branchName(d) == LunarCalendar.branchName(start),
                             "Lunar branch must be stable throughout local day: \(d)")
                precondition(Set(ids).count == ids.count, "Today's market IDs must not duplicate: \(d)")
            }
        }

        let d = cal.date(from: DateComponents(year: 2026, month: 10, day: 20))!
        precondition(LunarCalendar.ganzhiName(d) == "丁卯", "Lunar ganzhi regression check failed")
        print("PASS: dataset decode, unique IDs, 72 local-day/time consistency checks, and lunar calendar regression check.")
    }
}
