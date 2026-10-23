import WidgetKit
import SwiftUI

struct DayItem: Identifiable {
    let id: String
    let name: String
    var short: String { name.replacingOccurrences(of: "圩", with: "") }
}

struct GanJiEntry: TimelineEntry {
    let date: Date
    let days: [Date]
    let sections: [[DayItem]]
}

struct MarketProvider: TimelineProvider {
    private func build(_ date: Date) -> GanJiEntry {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let days = (0..<3).compactMap { cal.date(byAdding: .day, value: $0, to: day) }
        return GanJiEntry(date: date, days: days, sections: days.map { d in
            MarketStore.markets(on: d).map { DayItem(id: $0.id, name: $0.name) }
        })
    }

    func placeholder(in context: Context) -> GanJiEntry { build(Date()) }
    func getSnapshot(in context: Context, completion: @escaping (GanJiEntry) -> Void) {
        completion(build(Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<GanJiEntry>) -> Void) {
        let now = Date()
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var entries = [build(now)]
        for offset in 1..<8 {
            if let day = cal.date(byAdding: .day, value: offset, to: today) { entries.append(build(day)) }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// Explicitly draw the asset as the widget's full-bleed background.
// Avoid GeometryReader-based image selection in containerBackground: WidgetKit may
// provide a constrained proposal, which can leave the fallback paper color visible.
private struct WidgetCanvas: View {
    let dark: Bool

    private var paper: Color {
        dark
            ? Color(red: 0.035, green: 0.12, blue: 0.13)
            : Color(red: 0.98, green: 0.96, blue: 0.88)
    }

    var body: some View {
        ZStack {
            paper

            Image("VillageWatercolor", bundle: .main)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .opacity(dark ? 0.88 : 1.0)
                .overlay {
                    // Keep text readable without washing out the entire illustration.
                    LinearGradient(
                        stops: [
                            .init(color: paper.opacity(dark ? 0.48 : 0.30), location: 0.0),
                            .init(color: paper.opacity(dark ? 0.24 : 0.10), location: 0.38),
                            .init(color: paper.opacity(dark ? 0.05 : 0.0), location: 0.72),
                            .init(color: paper.opacity(dark ? 0.12 : 0.0), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct PaperCard<Content: View>: View {
    let dark: Bool
    let content: Content
    init(dark: Bool, @ViewBuilder content: () -> Content) {
        self.dark = dark
        self.content = content()
    }
    var body: some View {
        content
            .padding(10)
            .background(dark ? Color(red: 0.12, green: 0.20, blue: 0.18) : Color(red: 1.0, green: 0.99, blue: 0.95), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(dark ? Color.white.opacity(0.08) : Color(red: 0.83, green: 0.82, blue: 0.74), lineWidth: 0.7))
    }
}

struct GanJiWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: GanJiEntry
    private var dark: Bool { colorScheme == .dark }
    private var small: Bool { family == .systemSmall }
    private var large: Bool { family == .systemLarge }
    private let ink = Color(red: 0.12, green: 0.22, blue: 0.18)
    private let vermilion = Color(red: 0.72, green: 0.24, blue: 0.16)
    private var primaryInk: Color { dark ? Color(red: 0.97, green: 0.94, blue: 0.84) : ink }
    private var secondaryInk: Color { dark ? Color.white.opacity(0.76) : ink.opacity(0.72) }

    var body: some View {
        Group {
            if #available(iOS 17.0, *) {
                content.containerBackground(for: .widget) { WidgetCanvas(dark: dark) }
            } else {
                content.background(WidgetCanvas(dark: dark))
            }
        }
    }

    private func names(_ offset: Int, short: Bool = false) -> String {
        guard entry.sections.indices.contains(offset) else { return "—" }
        let items = entry.sections[offset]
        return items.isEmpty ? (offset == 0 ? "今日无圩" : "暂无圩日") : items.map { short ? $0.short : $0.name }.joined(separator: " · ")
    }
    private func numericDate(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 1)/\(c.day ?? 1)"
    }

    @ViewBuilder private var content: some View {
        if small { smallLayout }
        else if family == .systemMedium { mediumLayout }
        else { largeLayout }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "basket.fill").font(.system(size: 10, weight: .bold)).foregroundColor(dark ? Color(red: 0.98, green: 0.79, blue: 0.53) : vermilion)
            Text("赶集日记").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(primaryInk)
            Spacer(minLength: 2)
            Text("本地圩日历").font(.system(size: 9, weight: .medium)).foregroundColor(secondaryInk)
        }
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Text(LunarCalendar.shortDate(entry.date))
                .font(.system(size: 25, weight: .heavy, design: .serif))
                .foregroundColor(primaryInk).lineLimit(1).minimumScaleFactor(0.68)
            Text("\(LunarCalendar.weekdayText(entry.date)) · 农历\(LunarCalendar.lunarText(entry.date))")
                .font(.system(size: 9, weight: .medium)).foregroundColor(secondaryInk)
                .lineLimit(1).minimumScaleFactor(0.68)
            Text("\(LunarCalendar.ganzhiName(entry.date))日")
                .font(.system(size: 9, weight: .medium, design: .serif)).foregroundColor(secondaryInk)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text("今日赶集").font(.system(size: 9, weight: .semibold)).foregroundColor(secondaryInk)
                Text(names(0, short: true))
                    .font(.system(size: 17, weight: .heavy, design: .serif))
                    .foregroundColor(vermilion).lineLimit(2).minimumScaleFactor(0.62)
                Text("（赶集）").font(.system(size: 9, weight: .medium)).foregroundColor(secondaryInk)
            }
            .padding(.bottom, 2)
        }
        .padding(10)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Full-width header, matching the reference image.
            header
                .padding(.horizontal, 2)

            HStack(alignment: .top, spacing: 8) {
                // Left column: date and today's market. Do not insert a Spacer
                // between the lunar details and market name; that caused overlap
                // in the constrained medium widget.
                VStack(alignment: .leading, spacing: 3) {
                    Text(LunarCalendar.shortDate(entry.date))
                        .font(.system(size: 25, weight: .heavy, design: .serif))
                        .foregroundColor(primaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(LunarCalendar.weekdayText(entry.date)) · 农历\(LunarCalendar.lunarText(entry.date))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    Text("\(LunarCalendar.ganzhiName(entry.date))日")
                        .font(.system(size: 9, weight: .medium, design: .serif))
                        .foregroundColor(secondaryInk)
                        .lineLimit(1)

                    HStack(alignment: .center, spacing: 7) {
                        // Use two explicit text views so Dynamic Type / widget
                        // compression can never turn the stamp into “今…” horizontally.
                        VStack(spacing: 0) {
                            Text("今")
                            Text("日")
                        }
                        .font(.system(size: 11, weight: .heavy, design: .serif))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: true)
                        .frame(width: 25, height: 40, alignment: .center)
                        .background(vermilion, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .fixedSize(horizontal: true, vertical: true)
                        .layoutPriority(2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(names(0, short: false))
                                .font(.system(size: 15, weight: .heavy, design: .serif))
                                .foregroundColor(vermilion)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .minimumScaleFactor(0.72)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("（赶集）")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(secondaryInk)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 7)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Right column: one translucent card with equal-width forecast columns.
                HStack(alignment: .top, spacing: 0) {
                    forecastColumn(1)

                    Rectangle()
                        .fill(dark ? Color.white.opacity(0.22) : Color(red: 0.80, green: 0.79, blue: 0.70))
                        .frame(width: 1)
                        .padding(.vertical, 3)

                    forecastColumn(2)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    dark
                        ? Color(red: 0.08, green: 0.17, blue: 0.16).opacity(0.82)
                        : Color(red: 0.99, green: 0.97, blue: 0.88).opacity(0.84),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(dark ? Color.white.opacity(0.16) : Color.white.opacity(0.72), lineWidth: 0.8)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(9)
    }

    private func forecastColumn(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(index == 1 ? "明日" : "后日")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(secondaryInk)
                .lineLimit(1)

            Text(names(index, short: false))
                .font(.system(size: 15, weight: .heavy, design: .serif))
                .foregroundColor(primaryInk)
                .lineLimit(2)
                .minimumScaleFactor(0.66)
                .fixedSize(horizontal: false, vertical: true)

            Text("（赶集）")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(secondaryInk)
                .lineLimit(1)

            Spacer(minLength: 3)

            Text("农历\(LunarCalendar.lunarText(entry.days[index]))")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func dayCard(_ index: Int, compact: Bool = false) -> some View {
        let accent = index == 0 ? vermilion : Color(red: 0.24, green: 0.43, blue: 0.32)
        return VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            Text(["今天", "明天", "后天"][index])
                .font(.system(size: compact ? 8 : 9, weight: .bold))
                .foregroundColor(index == 0 ? .white : primaryInk)
                .padding(.horizontal, compact ? 6 : 7)
                .padding(.vertical, compact ? 2 : 3)
                .background(index == 0 ? vermilion : (dark ? Color.white.opacity(0.10) : Color(red: 0.88, green: 0.91, blue: 0.79)), in: Capsule())
                .lineLimit(1)
            Text(numericDate(entry.days[index]))
                .font(.system(size: compact ? 12 : 15, weight: .heavy, design: .serif))
                .foregroundColor(primaryInk).lineLimit(1).minimumScaleFactor(0.65)
            Text(LunarCalendar.weekdayText(entry.days[index]))
                .font(.system(size: compact ? 8 : 9, weight: .medium)).foregroundColor(secondaryInk).lineLimit(1)
            if !compact { Spacer(minLength: 1) }
            Text(names(index, short: true))
                .font(.system(size: compact ? 9 : 13, weight: .heavy, design: .serif))
                .foregroundColor(accent).lineLimit(compact ? 2 : 1).minimumScaleFactor(0.55)
            if !compact {
                HStack(spacing: 3) {
                    Image(systemName: "basket.fill").font(.system(size: 8))
                    Text(index == 0 ? "今日开圩" : "圩日预告").font(.system(size: 8, weight: .medium))
                }.foregroundColor(secondaryInk).lineLimit(1)
            }
        }
        .padding(compact ? 6 : 8)
        .frame(maxWidth: .infinity, minHeight: compact ? 76 : 92, maxHeight: compact ? 82 : nil, alignment: .leading)
        .background(index == 0
            ? (dark ? Color(red: 0.35, green: 0.16, blue: 0.12).opacity(0.82) : Color(red: 1.0, green: 0.91, blue: 0.84).opacity(0.96))
            : (dark ? Color(red: 0.04, green: 0.17, blue: 0.19).opacity(0.86) : Color(red: 0.98, green: 0.98, blue: 0.90).opacity(0.91)),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .stroke(index == 0 ? vermilion.opacity(dark ? 0.65 : 0.55) : (dark ? Color.white.opacity(0.20) : Color.white.opacity(0.92)), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 7) {
            header

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(LunarCalendar.shortDate(entry.date))
                    .font(.system(size: 29, weight: .heavy, design: .serif))
                    .foregroundColor(primaryInk)
                    .lineLimit(1).minimumScaleFactor(0.68)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LunarCalendar.weekdayText(entry.date))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(vermilion)
                    Text("农历\(LunarCalendar.lunarText(entry.date)) · \(LunarCalendar.ganzhiName(entry.date))日")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(secondaryInk)
                        .lineLimit(1).minimumScaleFactor(0.72)
                }
                Spacer(minLength: 0)
                Text("今日圩日")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(vermilion, in: Capsule())
            }

            // 今日重点区：保留透出背景插画的空间，避免整张组件被不透明卡片盖住。
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "basket.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(vermilion)
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日赶集")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(secondaryInk)
                    Text(names(0, short: true))
                        .font(.system(size: 21, weight: .heavy, design: .serif))
                        .foregroundColor(vermilion)
                        .lineLimit(1).minimumScaleFactor(0.58)
                    Text("\(numericDate(entry.days.first ?? entry.date)) · \(LunarCalendar.weekdayText(entry.days.first ?? entry.date))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(dark ? Color.black.opacity(0.16) : Color.white.opacity(0.34),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            // 参考布局要求大尺寸也显示今日、明日、后日三张卡片。
            HStack(alignment: .top, spacing: 7) {
                dayCard(0, compact: true)
                dayCard(1, compact: true)
                dayCard(2, compact: true)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(9)
    }


}

struct GanJiWidget: Widget {
    let kind = "GanJiWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MarketProvider()) { entry in
            GanJiWidgetView(entry: entry)
        }
        .configurationDisplayName("赶集日记 · 田园集市")
        .description("岭南乡土插画风，查看今日、明日与后日圩日及农历干支")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main struct GanJiWidgetBundle: WidgetBundle {
    var body: some Widget { GanJiWidget() }
}
