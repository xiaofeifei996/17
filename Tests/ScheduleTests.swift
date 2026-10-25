import Foundation

@main struct ScheduleTests {
    static func main() throws {
        let chinaTZ = TimeZone(identifier: "Asia/Shanghai")!
        NSTimeZone.default = chinaTZ
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = chinaTZ

        // Bundled markets.json was intentionally removed. Keep schedule regression
        // tests independent of production/API data by using small in-memory fixtures.
        let markets = [
            Market(id: "fixture-rat", name: "测试甲集", province: "测试省", city: "测试市", area: "测试区",
                   provinceCode: 1, cityCode: 2, areaCode: 3, sourceAreaCode: 3,
                   lat: 23.0, lon: 113.0, marketType: 1, repeatType: 6,
                   repeatValue: ["鼠"], remark: "", place: "", address: "", status: 1),
            Market(id: "fixture-lunar", name: "测试乙集", province: "测试省", city: "测试市", area: "测试区",
                   provinceCode: 1, cityCode: 2, areaCode: 3, sourceAreaCode: 3,
                   lat: 23.1, lon: 113.1, marketType: 0, repeatType: 1,
                   repeatValue: ["初一", "十五"], remark: "", place: "", address: "", status: 1)
        ]
        precondition(!markets.isEmpty, "Schedule fixtures must not be empty")
        precondition(Set(markets.map(\.id)).count == markets.count, "Fixture market IDs must be unique")

        // Test schedule invariants against fixtures, never a removed bundled dataset.
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
        print("PASS: fixture IDs, 72 local-day/time consistency checks, and lunar calendar regression check.")
    }
}
