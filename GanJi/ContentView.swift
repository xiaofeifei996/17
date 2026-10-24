import SwiftUI
import MapKit

private enum GatherTab: String, CaseIterable {
    case discover = "赶集", saved = "收藏"
}

struct ContentView: View {
    @State private var markets = MarketStore.load()
    @State private var selectedAreaCode = MarketStore.availableAreas.first?.code ?? 450881
    @State private var query = ""
    @State private var selectedDay = 0
    @State private var showDatePicker = false
    @State private var chosenDate = Calendar.current.startOfDay(for: Date())
    @State private var tab: GatherTab = .discover
    @State private var savedIDs = Set(UserDefaults.standard.stringArray(forKey: "GanJiFavoriteMarketIDs") ?? [])
    @State private var savedMarkets = (try? JSONDecoder().decode([Market].self, from: UserDefaults.standard.data(forKey: "GanJiFavoriteMarketsData") ?? Data())) ?? []
    @State private var selectedMarket: Market?
    @State private var loading = false
    @State private var message: String?

    private var areas: [(code: Int, name: String, city: String, province: String, lat: Double, lon: Double)] {
        MarketStore.availableAreas
    }
    private var currentArea: String {
        areas.first(where: { $0.code == selectedAreaCode }).map { "\($0.city) · \($0.name)" } ?? "选择地区"
    }
    private var baseMarkets: [Market] { tab == .saved ? savedMarkets.filter { savedIDs.contains($0.id) } : markets }
    private var rows: [MarketDay] {
        MarketStore.upcoming(from: chosenDate, markets: baseMarkets)
            .filter { $0.market.areaCode == selectedAreaCode || tab == .saved }
            .filter { selectedDay == 3 || $0.daysAhead == selectedDay }
            .filter {
                query.isEmpty || $0.market.name.localizedCaseInsensitiveContains(query)
                || $0.market.area.localizedCaseInsensitiveContains(query)
                || $0.market.address.localizedCaseInsensitiveContains(query)
            }
    }

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.95, blue: 0.91).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        introPanel
                        searchField
                        daySelector
                        if loading {
                            ProgressView("正在更新集市…").frame(maxWidth: .infinity).padding(28)
                        }
                        if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                        if rows.isEmpty && !loading {
                            emptyState
                        } else {
                            HStack(alignment: .firstTextBaseline) {
                                Text(tab == .saved ? "我的赶集清单" : "附近的集日")
                                    .font(.system(size: 21, weight: .bold, design: .rounded))
                                Spacer()
                                Text("\(rows.count) 个集市").font(.caption).foregroundStyle(.secondary)
                            }
                            LazyVStack(spacing: 12) {
                                ForEach(rows) { row in
                                    marketCard(row)
                                }
                            }
                        }
                        Text("集期信息仅供参考，出发前建议向当地确认。")
                            .font(.caption2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
                bottomBar
            }
        }
        .preferredColorScheme(.light)
        .task { await refreshMarkets() }
        .sheet(isPresented: $showDatePicker) {
            NavigationView {
                VStack {
                    DatePicker("选择日期", selection: $chosenDate, displayedComponents: .date)
                        .datePickerStyle(.graphical).padding()
                    Button("使用这一天") { showDatePicker = false }
                        .font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color(red: 0.82, green: 0.29, blue: 0.16), in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    Spacer()
                }
                .navigationTitle("赶集日期")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showDatePicker = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedMarket) { market in
            marketDetail(market)
                .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("赶集日记").font(.system(size: 27, weight: .black, design: .rounded))
                Text("把乡间好日子，装进口袋").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(areas, id: \.code) { area in
                    Button("\(area.province) · \(area.city) · \(area.name)") {
                        selectedAreaCode = area.code
                        tab = .discover
                        Task { await refreshMarkets() }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(currentArea).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.30, green: 0.34, blue: 0.27))
                .padding(.horizontal, 11).padding(.vertical, 10)
                .background(.white.opacity(0.85), in: Capsule())
            }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 14)
    }

    private var introPanel: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 26).fill(Color(red: 0.19, green: 0.27, blue: 0.20))
            Circle().fill(Color(red: 0.89, green: 0.53, blue: 0.28).opacity(0.9))
                .frame(width: 130, height: 130).offset(x: 245, y: -30)
            Circle().stroke(.white.opacity(0.17), lineWidth: 1).frame(width: 150, height: 150).offset(x: 225, y: 35)
            VStack(alignment: .leading, spacing: 10) {
                Text("LOCAL MARKET GUIDE").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(2).foregroundStyle(Color(red: 0.94, green: 0.73, blue: 0.49))
                Text("今天去哪儿赶集？").font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text("查集期 · 找好物 · 收藏常去的集市").font(.system(size: 12)).foregroundStyle(.white.opacity(0.78))
                Button { showDatePicker = true } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "calendar")
                        Text(chosenDate.formatted(.dateTime.month(.abbreviated).day()))
                        Text("更改日期")
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.20, green: 0.27, blue: 0.20))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color(red: 0.96, green: 0.84, blue: 0.63), in: Capsule())
                }.padding(.top, 4)
            }.padding(20)
        }
        .frame(height: 176).clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color(red: 0.78, green: 0.31, blue: 0.18))
            TextField("搜集市名称、乡镇或地址", text: $query)
                .font(.system(size: 14))
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
        }
        .padding(.horizontal, 15).frame(height: 50)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.04), lineWidth: 1))
    }

    private var daySelector: some View {
        HStack(spacing: 8) {
            ForEach([(0, "今天"), (1, "明天"), (2, "后天"), (3, "全部")], id: \.0) { item in
                Button { selectedDay = item.0 } label: {
                    Text(item.1)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedDay == item.0 ? .white : Color(red: 0.34, green: 0.36, blue: 0.31))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(selectedDay == item.0 ? Color(red: 0.82, green: 0.29, blue: 0.16) : .white, in: RoundedRectangle(cornerRadius: 13))
                }.buttonStyle(.plain)
            }
        }
    }

    private func marketCard(_ row: MarketDay) -> some View {
        Button { selectedMarket = row.market } label: {
            HStack(alignment: .top, spacing: 13) {
                VStack(spacing: 3) {
                    Text(row.dayLabel).font(.system(size: 12, weight: .bold))
                    Text(row.date.formatted(.dateTime.day())).font(.system(size: 27, weight: .black, design: .rounded))
                    Text(row.date.formatted(.dateTime.weekday(.wide))).font(.system(size: 10))
                }
                .foregroundStyle(Color(red: 0.72, green: 0.29, blue: 0.17))
                .frame(width: 58, height: 76)
                .background(Color(red: 0.98, green: 0.92, blue: 0.85), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(row.market.name).font(.system(size: 16, weight: .bold)).foregroundStyle(.primary).lineLimit(1)
                        if row.market.marketType == 1 {
                            Text("大集").font(.system(size: 9, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 3).background(Color(red: 0.24, green: 0.39, blue: 0.27), in: Capsule())
                        }
                        Spacer(minLength: 0)
                    }
                    Text([row.market.province, row.market.city, row.market.area].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: "clock").font(.system(size: 10))
                        Text(row.market.displaySchedule).lineLimit(1)
                    }.font(.system(size: 11)).foregroundStyle(Color(red: 0.40, green: 0.43, blue: 0.36))
                    if !row.market.address.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin").font(.system(size: 10))
                            Text(row.market.address).lineLimit(1)
                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button { toggleSaved(row.market) } label: {
                    Image(systemName: savedIDs.contains(row.market.id) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(savedIDs.contains(row.market.id) ? Color(red: 0.82, green: 0.29, blue: 0.16) : .secondary)
                        .frame(width: 28, height: 30)
                }.buttonStyle(.plain)
            }
            .padding(13)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.black.opacity(0.035), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: tab == .saved ? "bookmark" : "basket")
                .font(.system(size: 32, weight: .light)).foregroundStyle(Color(red: 0.77, green: 0.39, blue: 0.25))
            Text(tab == .saved ? "还没有收藏集市" : "这组条件下暂时没有集市")
                .font(.system(size: 16, weight: .bold))
            Text(tab == .saved ? "遇到常去的集市，点一下书签就能保存。" : "试试切换日期、地区，或搜索其他关键词。")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 38)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            tabButton(.discover, icon: "sun.max.fill")
            tabButton(.saved, icon: "bookmark.fill")
        }
        .padding(.top, 10).padding(.bottom, 22)
        .background(.white.shadow(.drop(color: .black.opacity(0.05), radius: 12, y: -4)))
    }

    private func tabButton(_ value: GatherTab, icon: String) -> some View {
        Button { tab = value } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(value.rawValue).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(tab == value ? Color(red: 0.82, green: 0.29, blue: 0.16) : .secondary)
            .frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }

    private func marketDetail(_ market: Market) -> some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(market.name).font(.system(size: 26, weight: .bold, design: .rounded))
                        Spacer()
                        Button { toggleSaved(market) } label: {
                            Image(systemName: savedIDs.contains(market.id) ? "bookmark.fill" : "bookmark")
                                .font(.title2).foregroundStyle(Color(red: 0.82, green: 0.29, blue: 0.16))
                        }
                    }
                    Text(market.displaySchedule).font(.headline).foregroundStyle(Color(red: 0.72, green: 0.29, blue: 0.17))
                    detailLine("地区", [market.province, market.city, market.area].filter { !$0.isEmpty }.joined(separator: " · "))
                    detailLine("地址", market.address.isEmpty ? "暂无详细地址" : market.address)
                    detailLine("集市类型", market.size)
                    detailLine("赶集规律", market.displaySchedule)
                    if !market.remark.isEmpty { detailLine("备注", market.remark) }
                    Text("提示：集期和地址可能随当地安排变化，出发前请再次核实。")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 6)
                }.padding(22)
            }
            .navigationTitle("集市详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { selectedMarket = nil } } }
        }
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15))
            Divider()
        }
    }

    private func toggleSaved(_ market: Market) {
        if savedIDs.contains(market.id) {
            savedIDs.remove(market.id)
        } else {
            savedIDs.insert(market.id)
            if !savedMarkets.contains(where: { $0.id == market.id }) { savedMarkets.append(market) }
        }
        UserDefaults.standard.set(Array(savedIDs), forKey: "GanJiFavoriteMarketIDs")
        if let data = try? JSONEncoder().encode(savedMarkets) {
            UserDefaults.standard.set(data, forKey: "GanJiFavoriteMarketsData")
        }
    }

    @MainActor
    private func refreshMarkets() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let fetched = try await MarketAPI.fetch(areaCode: selectedAreaCode)
            if !fetched.isEmpty {
                markets = fetched
                MarketCache.save(fetched, areaCode: selectedAreaCode)
            } else {
                message = "线上暂无更多数据，当前显示本地集市资料。"
            }
        } catch {
            if let cached = MarketCache.load(areaCode: selectedAreaCode), !cached.isEmpty { markets = cached }
            message = markets.isEmpty ? "暂时无法连接集市服务，请检查网络。" : "已显示本地资料，网络恢复后可更新。"
        }
    }
}
