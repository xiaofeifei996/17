import Foundation

/// 农历 / 干支日换算
///
/// 关键设计：干支日不依赖任何系统历法 API 的“序日”，而是以一个经双重核实的
/// 锚点日（2026-10-20 为丁卯日）为基准，按本地日历日的天数差逐日推算。
///
/// 之前的实现用 `ordinality(of: .day, in: .era)`，在 iOS 上它按 UTC 计日：
/// 列表/小组件全部基于本地零点（startOfDay），UTC+8 下被算成前一日，
/// 导致所有相位整体偏移一档；而界面头部用下午的 Date() 恰好仍是同一 UTC 日，
/// 显示正确 —— 头对、表错的“精神分裂”状态就是这么来的。
enum LunarCalendar {
    static let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    static let zodiac = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]
    static let monthNames = ["正月", "二月", "三月", "四月", "五月", "六月",
                             "七月", "八月", "九月", "十月", "冬月", "腊月"]
    static let dayNames = ["初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                           "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                           "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]

    /// 锚点：2026-10-20 是丁卯日（六十甲子序号 3）。
    /// 经两处独立核实：圩日表页面标注 10月20日 丁卯[兔] / 10月03日 庚戌[狗]，
    /// 用户权威排期（卯日→大妙/登明）也与此一致。
    static let anchorYMD = (2026, 10, 20)
    static let anchorIndex = 3

    /// 当日六十甲子序号（0 = 甲子）。纯“本地日历日差值”推算，
    /// 不使用 ordinality/儒略日等任何会按 UTC 取整的 API。
    static func index60(_ date: Date) -> Int {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = anchorYMD.0
        comps.month = anchorYMD.1
        comps.day = anchorYMD.2
        comps.hour = 12          // 正午锚点，避免任何日界含糊
        guard let anchor = cal.date(from: comps) else { return anchorIndex }
        let n = cal.dateComponents([.day],
                                   from: cal.startOfDay(for: anchor),
                                   to: cal.startOfDay(for: date)).day ?? 0
        return ((anchorIndex + n) % 60 + 60) % 60
    }

    /// 当日地支序号（0 = 子）
    static func branchIndexForDate(_ date: Date) -> Int {
        index60(date) % 12
    }

    /// 当日生肖序号（0 = 鼠）—— 与地支天然对齐
    static func zodiacIndex(_ date: Date) -> Int {
        branchIndexForDate(date)
    }

    static func branchName(_ date: Date) -> String {
        branches[branchIndexForDate(date)]
    }

    static func zodiacName(_ date: Date) -> String {
        zodiac[branchIndexForDate(date)]
    }

    /// 当日干支名，如 “丁卯”
    static func ganzhiName(_ date: Date) -> String {
        stems[index60(date) % 10] + branches[branchIndexForDate(date)]
    }

    static func branchIndex(_ b: String) -> Int? {
        branches.firstIndex(of: b)
    }

    static func zodiacOfBranch(_ b: String) -> String {
        guard let i = branches.firstIndex(of: b) else { return "" }
        return zodiac[i]
    }

    /// 农历月日文字，如 “九月十一”（用系统农历换算，仅做显示，不参与排期。
    /// 排期只依赖上面逐日推干的锚点法，农历月的长短与排日无关。）
    static func lunarText(_ date: Date) -> String {
        var cal = Calendar(identifier: .chinese)
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.month, .day], from: date)
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        let mn = monthNames[min(max(m, 1), 12) - 1]
        let dn = dayNames[min(max(d, 1), 30) - 1]
        return mn + dn
    }

    static func shortDate(_ date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.month, .day], from: date)
        return "\(comps.month ?? 1)月\(comps.day ?? 1)日"
    }

    static func weekdayText(_ date: Date) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let idx = Calendar.current.component(.weekday, from: date) - 1
        return names[min(max(idx, 0), 6)]
    }
}
