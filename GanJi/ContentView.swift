import SwiftUI
import UIKit
import MapKit
import CoreLocation

private enum MarketFilter: String, CaseIterable, Identifiable {
    case all = "全部", today = "今天", tomorrow = "明天", dayAfter = "后天"
    var id: String { rawValue }
    var offset: Int? {
        switch self { case .all: return nil; case .today: return 0; case .tomorrow: return 1; case .dayAfter: return 2 }
    }
}

private struct TopRoundedShape: Shape {
    var radius: CGFloat = 25

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width / 2, rect.height / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct ContentView: View {
    @StateObject private var locator = LocationModel()
    @State private var selectedFilter: MarketFilter = .all
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var searchText = ""
    @FocusState private var isPlaceSearchFocused: Bool
    @State private var isMarketSheetVisible = true
    @State private var isKeyboardVisible = false
    @StateObject private var placeSearch = PlaceSearchModel()
    @State private var placeSearchMessage: String?
    @State private var selectedAreaCode: Int = 450881
    @State private var showRegionPicker = false
    @State private var homeRegionExpanded = false
    @State private var selectedPickerProvinceCode: Int = 450000
    @State private var selectedPickerCityCode: Int = 450800
    @State private var selectedPickerCountyCode: Int = 450881
    @State private var nationalRegionOptions: [RegionOption] = []
    @State private var loadingRegionOptions = false
    @State private var regionLoadMessage = "正在加载全国省、市、县区数据…"
    @State private var selectedAreaDisplayName: String?
    @State private var displayedMarkets: [Market] = MarketStore.load()
    @State private var loadingMarkets = false
    @State private var marketLoadError: String?
    @State private var selectedMarketID: String?
    @State private var showDatePicker = false
    @State private var sheetExpanded = false
    @State private var showMainPage = false
    @State private var favorites: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "GanJiFavoriteMarketIDs") ?? [])
    @State private var favoriteMarkets: [Market] = (try? JSONDecoder().decode([Market].self, from: UserDefaults.standard.data(forKey: "GanJiFavoriteMarketsData") ?? Data())) ?? []
    @State private var homeTab: HomeTab = .home
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 23.12, longitude: 110.31),
        span: MKCoordinateSpan(latitudeDelta: 0.32, longitudeDelta: 0.34)
    )

    private var allMarkets: [Market] { displayedMarkets }
    private var currentDateHeaderText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: Date())
    }
    private var offsetFromToday: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: selectedDate).day ?? 0
    }
    private var filteredMarkets: [MarketDay] {
        let base = MarketStore.upcoming(from: selectedDate, markets: displayedMarkets).filter { $0.market.areaCode == selectedAreaCode }
        return base.filter { row in
            let filterMatch = selectedFilter.offset == nil || row.daysAhead == selectedFilter.offset
            let searchMatch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                row.market.name.localizedCaseInsensitiveContains(searchText) ||
                row.market.area.localizedCaseInsensitiveContains(searchText)
            return filterMatch && searchMatch
        }.sorted { a, b in
            let da = distanceValue(for: a.market), db = distanceValue(for: b.market)
            if let da = da, let db = db { return da < db }
            return a.daysAhead < b.daysAhead
        }
    }
    private var mapMarkets: [Market] {
        var markets = filteredMarkets.map { $0.market }
        // A saved favorite may not be present in the currently loaded/filtered API list.
        // Keep the selected saved market on the map so tapping a favorite can move to it.
        if let selectedID = selectedMarketID,
           !markets.contains(where: { $0.id == selectedID }),
           let saved = favoriteMarkets.first(where: { $0.id == selectedID }) {
            markets.append(saved)
        }
        return markets
    }

    /// Home groups only the markets opening today, tomorrow, and the day after tomorrow.
    /// Sorting is performed inside each date group, so a closer market never jumps ahead of today's group.
    private func homeMarkets(for offset: Int) -> [MarketDay] {
        let today = Calendar.current.startOfDay(for: Date())
        // The home page shows only favorited markets, grouped by their next opening day.
        // Use the persisted favorite market records so favorites remain available even when
        // the currently loaded API list does not contain them.
        let savedFavorites = favoriteMarkets.filter { favorites.contains($0.id) }
        let upcoming = MarketStore.upcoming(from: today, markets: savedFavorites)
            .filter { $0.daysAhead == offset }
            .filter { row in
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                return query.isEmpty || row.market.name.localizedCaseInsensitiveContains(query) || row.market.area.localizedCaseInsensitiveContains(query)
            }
        return upcoming.sorted { a, b in
            let da = distanceValue(for: a.market), db = distanceValue(for: b.market)
            if let da = da, let db = db, da != db { return da < db }
            return a.market.name.localizedCompare(b.market.name) == .orderedAscending
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // Draw the map behind both the top status-bar safe area and the bottom edge.
                mapLayer
                    .ignoresSafeArea()
                // Keep the map visible when searching. Do not place a tall white
                // background behind the whole bottom lane: when SwiftUI resizes for
                // the keyboard, that layer expands upward and creates the huge blank
                // white area seen in v97. The search capsule and suggestions each have
                // their own opaque backgrounds below.
                // While the place-search field is active, hide the market list visually
                // so no market rows appear in the narrow strip above the keyboard.
                // Keep isMarketSheetVisible unchanged: when search focus ends, the panel
                // returns to its previous expanded/collapsed state automatically.
                if isMarketSheetVisible && showMainPage {
                    marketSheet(screenHeight: geo.size.height)
                        .frame(maxHeight: isKeyboardVisible ? geo.size.height * 0.78 : .infinity, alignment: .bottom)
                        // Search and nearby market browsing share one panel above the persistent Dock.
                        .padding(.bottom, isKeyboardVisible ? 0 : 66)
                        .zIndex(3)
                }
                if !showMainPage {
                    homePage
                        .padding(.bottom, 58)
                        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
                        .zIndex(10)
                }
                // One persistent Dock shared by every top-level page. Keeping the
                // same SwiftUI view alive avoids the Dock flashing when switching to Map.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    sharedDock
                }
                .ignoresSafeArea(edges: .bottom)
                .zIndex(11)
            }
            .background(Color.clear)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
            .onAppear {
                locator.start()
                Task { await refreshMarkets(for: selectedAreaCode) }
                if let first = allMarkets.first {
                    region.center = CLLocationCoordinate2D(latitude: first.lat, longitude: first.lon)
                }
            }
            .onChange(of: selectedMarketID) { newValue in
                guard let id = newValue,
                      let market = allMarkets.first(where: { $0.id == id })
                        ?? favoriteMarkets.first(where: { $0.id == id }) else { return }
                // Selecting a row should expose the map area above the bottom sheet.
                // Collapse the sheet and place the selected annotation in the visible
                // map area's center rather than the physical screen's center.
                withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                    sheetExpanded = false
                    let span = 0.09
                    let latitudeOffset = span * 0.5
                    region.center = CLLocationCoordinate2D(
                        latitude: market.lat - latitudeOffset,
                        longitude: market.lon
                    )
                    region.span = MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                }
            }
            .sheet(isPresented: $showDatePicker) {
                NavigationView {
                    VStack(spacing: 18) {
                        DatePicker("选择赶集日期", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(GraphicalDatePickerStyle())
                            .padding()
                        Button("完成") { showDatePicker = false }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.ganjiBlue, in: RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal)
                        Spacer()
                    }
                    .navigationTitle("选择日期")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showDatePicker = false } } }
                }
            }
            .sheet(isPresented: $showRegionPicker) {
                VStack(spacing: 0) {
                    Capsule().fill(Color.gray.opacity(0.28)).frame(width: 38, height: 5).padding(.top, 10)
                    HStack(spacing: 12) {
                        Button {
                            showRegionPicker = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 23))
                                .foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("关闭地区选择")
                        Spacer(minLength: 0)
                        Text("选择地区")
                            .font(.system(size: 19, weight: .semibold))
                        Spacer(minLength: 0)
                        Button {
                            // The sheet blocks the underlying Dock, so provide a direct
                            // route to Home while the region picker is open.
                            showRegionPicker = false
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showMainPage = false
                                homeTab = .home
                            }
                        } label: {
                            Text("主页")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color.ganjiBlue)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("关闭地区选择并返回主页")
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    HStack(spacing: 0) {
                        pickerColumn(title: "省份", selection: $selectedPickerProvinceCode, options: pickerProvinces)
                        pickerColumn(title: "城市", selection: $selectedPickerCityCode, options: pickerCities)
                        pickerColumn(title: "区县", selection: $selectedPickerCountyCode, options: pickerCounties)
                    }
                    .frame(height: 238)
                    .padding(.horizontal, 8)
                    Text(regionLoadMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                    HStack(spacing: 14) {
                        Button {
                            showRegionPicker = false
                        } label: {
                            Text("取消")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(Color(red: 0.0, green: 0.62, blue: 0.31))
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 9))
                        }
                        Button {
                            if let option = pickerCounties.first(where: { $0.code == selectedPickerCountyCode })
                                ?? pickerCities.first(where: { $0.code == selectedPickerCityCode })
                                ?? pickerProvinces.first(where: { $0.code == selectedPickerProvinceCode }) {
                                chooseRegion(option)
                            } else {
                                showRegionPicker = false
                            }
                        } label: {
                            Text("确定")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(Color(red: 0.0, green: 0.69, blue: 0.34), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 22)
                }
                .background(Color(.systemBackground))
                .modifier(RegionPickerSheetSizing())
                .onChange(of: selectedPickerProvinceCode) { _ in
                    if let firstCity = pickerCities.first {
                        selectedPickerCityCode = firstCity.code
                    } else {
                        selectedPickerCityCode = 0
                        selectedPickerCountyCode = 0
                    }
                }
                .onChange(of: selectedPickerCityCode) { _ in
                    selectedPickerCountyCode = pickerCounties.first?.code ?? 0
                }
                .onAppear {
                    alignPickerToSelectedRegion()
                    Task {
                        await loadNationalRegions()
                        alignPickerToSelectedRegion()
                    }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private enum HomeTab { case home, favorites, region, map }

    private func homeCalendarInfo(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.78))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
    }

    private var homePage: some View {
        VStack(spacing: 0) {
            // Editorial header: a different information hierarchy from the original card/list screen.
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(currentDateHeaderText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(1.1)
                        .foregroundColor(Color(red: 0.56, green: 0.31, blue: 0.19))
                    Text(homeTab == .favorites ? "收藏簿" : (homeTab == .region ? "探索地区" : "趁圩睇靓女"))
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(Color(red: 0.15, green: 0.19, blue: 0.17))
                    Text(homeTab == .favorites ? "把常去的圩日收进来" : (homeTab == .region ? "选择你的趁圩目的地" : "把圩日的热闹记下来"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(red: 0.43, green: 0.45, blue: 0.40))
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().fill(Color(red: 0.87, green: 0.34, blue: 0.19)).frame(width: 48, height: 48)
                    Image(systemName: homeTab == .favorites ? "bookmark.fill" : "sun.max.fill")
                        .font(.system(size: 19, weight: .bold)).foregroundColor(.white)
                }.padding(.top, 7)
            }
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 18)

            if homeTab == .home {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("圩日记事").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1.8).foregroundColor(.white.opacity(0.82))
                                Text("今天去哪趁圩？").font(.system(size: 21, weight: .bold, design: .rounded)).foregroundColor(.white)
                                Text("按开圩日期整理你的行程").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.88))
                                HStack(alignment: .top, spacing: 8) {
                                    homeCalendarInfo(title: "生肖", value: LunarCalendar.zodiacName(Date()))
                                    homeCalendarInfo(title: "日干支", value: LunarCalendar.ganzhiName(Date()))
                                    homeCalendarInfo(title: "农历", value: LunarCalendar.lunarText(Date()))
                                }
                                .padding(.top, 7)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "basket.fill").font(.system(size: 36, weight: .medium)).foregroundColor(Color(red: 0.00, green: 0.48, blue: 1.00))
                        }
                        .padding(20).background(Color(red: 0.00, green: 0.48, blue: 1.00), in: RoundedRectangle(cornerRadius: 22))

                        // Homepage place search removed; region selection remains available in the Region tab.
                        ForEach(0..<3, id: \.self) { offset in
                            let rows = homeMarkets(for: offset)
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(["今日趁圩", "明日趁圩", "后日趁圩"][offset])
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundColor(Color.primary)
                                    Spacer()
                                }
                                if rows.isEmpty {
                                    HStack(spacing: 12) {
                                        Image(systemName: "sun.horizon").font(.system(size: 21)).foregroundColor(Color(red: 0.00, green: 0.48, blue: 1.00))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("暂时没有安排").font(.system(size: 14, weight: .semibold))
                                            Text("收藏圩日后，会在这里按日期出现").font(.system(size: 12)).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }.padding(15).background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
                                } else {
                                    VStack(spacing: 0) {
                                        ForEach(rows) { row in
                                            Button {
                                                selectedMarketID = row.market.id
                                                withAnimation { showMainPage = true; homeTab = .region }
                                            } label: {
                                                HStack(spacing: 13) {
                                                    VStack(spacing: 4) {
                                                        if row.market.repeatType == 6 {
                                                            Image(systemName: "storefront.fill")
                                                                .font(.system(size: 19, weight: .semibold))
                                                            Text("集市")
                                                                .font(.system(size: 9, weight: .bold))
                                                        } else {
                                                            Text("圩日").font(.system(size: 9, weight: .bold))
                                                            Text(row.market.displaySchedule.components(separatedBy: "、").first ?? "—")
                                                                .font(.system(size: 12, weight: .black, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                                                        }
                                                    }
                                                    .foregroundColor(Color(red: 0.00, green: 0.48, blue: 1.00))
                                                    .frame(width: 48, height: 48)
                                                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))
                                                    VStack(alignment: .leading, spacing: 5) {
                                                        Text(row.market.name).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(Color.primary).lineLimit(1)
                                                        Text([row.market.city, row.market.area].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 11, weight: .medium)).foregroundColor(Color(red: 0.38, green: 0.39, blue: 0.36)).lineLimit(1)
                                                        HStack(spacing: 8) {
                                                            Text("生肖：\(LunarCalendar.zodiacName(row.date))")
                                                            Text("日干支：\(LunarCalendar.ganzhiName(row.date))")
                                                            Text("农历：\(LunarCalendar.lunarText(row.date))")
                                                        }
                                                        .font(.system(size: 10, weight: .semibold))
                                                        .foregroundColor(Color(red: 0.00, green: 0.40, blue: 0.82))
                                                        .lineLimit(1)
                                                        .minimumScaleFactor(0.75)
                                                    }
                                                    Spacer(minLength: 4)
                                                    Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold)).foregroundColor(Color(red: 0.00, green: 0.48, blue: 1.00))
                                                }
                                                .padding(.vertical, 12).padding(.horizontal, 12).contentShape(Rectangle())
                                            }.buttonStyle(.plain)
                                            if row.id != rows.last?.id { Divider().overlay(Color(uiColor: .separator)).padding(.leading, 72) }
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                    .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 26)
                }
            } else if homeTab == .favorites {
                let saved = favoriteMarkets.filter { favorites.contains($0.id) }
                if saved.isEmpty {
                    VStack(spacing: 15) {
                        ZStack { Circle().fill(Color(uiColor: .tertiarySystemGroupedBackground)).frame(width: 94, height: 94); Image(systemName: "bookmark").font(.system(size: 32, weight: .medium)).foregroundColor(Color(red: 0.00, green: 0.48, blue: 1.00)) }
                        Text("这里还空着").font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("在地区地图里找到常去的圩，\n点一下收藏，就能建立自己的赶圩清单。")
                            .font(.system(size: 13)).foregroundColor(.secondary).multilineTextAlignment(.center).lineSpacing(4)
                        Button { withAnimation { showMainPage = true; homeTab = .region } } label: {
                            HStack(spacing: 8) { Text("去发现圩日"); Image(systemName: "arrow.right") }
                                .font(.system(size: 14, weight: .bold)).foregroundColor(.white).padding(.horizontal, 20).frame(height: 46)
                                .background(Color(red: 0.00, green: 0.48, blue: 1.00), in: Capsule())
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(28)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("已收藏 · \(saved.count) 个地点").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary).padding(.bottom, 4)
                            ForEach(saved) { market in
                                HStack(spacing: 13) {
                                    RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.88, green: 0.40, blue: 0.23)).frame(width: 5)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(market.name).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundColor(Color.primary)
                                        Text([market.province, market.city, market.area].filter { !$0.isEmpty }.joined(separator: " / ")).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary).lineLimit(1)
                                        Label(market.repeatType == 6 ? "属相：\(market.repeatValue.joined(separator: "、"))" : "开圩：\(market.displaySchedule)", systemImage: "calendar").font(.system(size: 12, weight: .medium)).foregroundColor(Color(red: 0.00, green: 0.48, blue: 1.00))
                                    }
                                    Spacer(minLength: 0)
                                    Button { toggleFavorite(market.id) } label: {
                                        Image(systemName: "heart.fill")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundColor(Color(red: 0.82, green: 0.27, blue: 0.25))
                                            .frame(width: 38, height: 38)
                                            .background(Color(red: 0.98, green: 0.89, blue: 0.85), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("取消收藏\(market.name)")
                                }
                                .padding(14).frame(minHeight: 94).background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 17))
                                .contentShape(Rectangle()).onTapGesture { withAnimation { showMainPage = true; homeTab = .region }; selectedMarketID = market.id }
                            }
                        }.padding(.horizontal, 18).padding(.bottom, 24)
                    }
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { homeRegionExpanded.toggle(); if homeRegionExpanded { alignPickerToSelectedRegion() } }
                        } label: {
                            HStack(spacing: 14) {
                                ZStack { RoundedRectangle(cornerRadius: 15).fill(Color(red: 0.00, green: 0.48, blue: 1.00)).frame(width: 52, height: 52); Image(systemName: "map.fill").font(.system(size: 20)).foregroundColor(Color(red: 0.00, green: 0.48, blue: 1.00)) }
                                VStack(alignment: .leading, spacing: 5) { Text("当前探索区域").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary); Text(homeRegionDisplayName).font(.system(size: 15, weight: .bold)).foregroundColor(Color.primary).lineLimit(2) }
                                Spacer(minLength: 0)
                                Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .semibold)).foregroundColor(Color(red: 0.00, green: 0.48, blue: 1.00))
                            }.padding(16).background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 19))
                        }.buttonStyle(.plain)
                        if homeRegionExpanded {
                            VStack(spacing: 12) {
                                HStack { Text("省份"); Spacer(); Text("城市"); Spacer(); Text("区县") }.font(.system(size: 11, weight: .bold)).foregroundColor(.secondary)
                                HStack(spacing: 0) { pickerColumn(title: "省份", selection: $selectedPickerProvinceCode, options: pickerProvinces); pickerColumn(title: "城市", selection: $selectedPickerCityCode, options: pickerCities); pickerColumn(title: "区县", selection: $selectedPickerCountyCode, options: pickerCounties) }.frame(height: 160)
                                Text(regionLoadMessage).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(2).multilineTextAlignment(.center)
                                Button { if let option = pickerCounties.first(where: { $0.code == selectedPickerCountyCode }) ?? pickerCities.first(where: { $0.code == selectedPickerCityCode }) ?? pickerProvinces.first(where: { $0.code == selectedPickerProvinceCode }) { chooseRegion(option) }; withAnimation { homeRegionExpanded = false } } label: { Text("应用这个地区").font(.system(size: 14, weight: .bold)).foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 46).background(Color(red: 0.00, green: 0.48, blue: 1.00), in: RoundedRectangle(cornerRadius: 13)) }
                            }.padding(16).background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 19))
                        }
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle.fill").foregroundColor(Color(red: 0.00, green: 0.48, blue: 1.00))
                            Text("地图中可以查看集市位置，点选标记查看圩日详情。")
                                .font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15))
                    }.padding(.horizontal, 18).padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .foregroundColor(Color.primary)
    }

    private var homeRegionDisplayName: String {
        if let selected = regionOptions.first(where: { $0.kind == .county && $0.code == selectedAreaCode }) {
            return [selected.province, selected.city, selected.name].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return selectedAreaDisplayName ?? MarketStore.availableAreas.first(where: { $0.code == selectedAreaCode })?.name ?? "选择省份 / 城市 / 区县"
    }

    private var sharedDock: some View {
        HStack(spacing: 0) {
            dockItem("house.fill", title: "主页", tab: .home)
            dockItem("heart.fill", title: "收藏", tab: .favorites)
            dockItem("mappin.and.ellipse", title: "地区", tab: .region)
        }
        .padding(.top, 9)
        .padding(.bottom, 28)
        // Keep the bottom navigation readable over the map; only the map canvas
        // itself is transparent to the system, not the Dock surface.
        // Use a stable system surface instead of material that blends map colors into the Dock.
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .top) {
            Rectangle().fill(Color(uiColor: .separator).opacity(0.55)).frame(height: 0.5)
        }
    }

    private func dockItem(_ symbol: String, title: String, tab: HomeTab) -> some View {
        Button {
            if tab == .region {
                // The Region tab is now the map experience; no separate Map tab.
                withAnimation {
                    showMainPage = true
                    homeTab = .region
                }
            } else {
                withAnimation {
                    showMainPage = false
                    homeTab = tab
                }
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundColor((homeTab == tab || (tab == .region && showMainPage)) ? Color(red: 0.00, green: 0.48, blue: 1.00) : Color.secondary)
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func toggleFavorite(_ id: String) {
        if favorites.contains(id) {
            favorites.remove(id)
            favoriteMarkets.removeAll { $0.id == id }
        } else {
            favorites.insert(id)
            if let market = allMarkets.first(where: { $0.id == id }), !favoriteMarkets.contains(where: { $0.id == id }) {
                favoriteMarkets.append(market)
            }
        }
        UserDefaults.standard.set(Array(favorites).sorted(), forKey: "GanJiFavoriteMarketIDs")
        if let data = try? JSONEncoder().encode(favoriteMarkets) {
            UserDefaults.standard.set(data, forKey: "GanJiFavoriteMarketsData")
        }
    }

    // Destination search: a dedicated location header, prominent input, and structured results.
    // Keep the existing search state, region picker, result selection, and keyboard behavior.
    private var mapSearchAndDock: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color(red: 0.12, green: 0.40, blue: 0.98))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前服务地区")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(red: 0.48, green: 0.53, blue: 0.61))
                        Text(homeRegionDisplayName.split(separator: "·").last.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? homeRegionDisplayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(red: 0.14, green: 0.19, blue: 0.27))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button { showRegionPicker = true } label: {
                        HStack(spacing: 5) {
                            Text("切换地区")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(Color(red: 0.12, green: 0.40, blue: 0.98))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.92, green: 0.95, blue: 1.0))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("切换地区，当前地区：\(homeRegionDisplayName)")
                }

                HStack(spacing: 11) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.16, green: 0.39, blue: 0.91))
                    TextField("输入城市、区县或具体地点", text: $searchText)
                        .focused($isPlaceSearchFocused)
                        .font(.system(size: 15, weight: .medium))
                        .submitLabel(.search)
                        .onChange(of: searchText) { value in
                            placeSearch.query(value)
                            placeSearchMessage = nil
                            if value.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                                Task { await loadNationalRegions() }
                            }
                        }
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color(red: 0.58, green: 0.62, blue: 0.69))
                        }
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 15)
                .frame(height: 50)
                .background(Color(red: 0.95, green: 0.96, blue: 0.98))
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color(red: 0.87, green: 0.89, blue: 0.93), lineWidth: 1))

                if !placeSearch.results.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text("搜索结果")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 0.14, green: 0.19, blue: 0.27))
                        Spacer()
                        Text("选择地点以查看当地圩日")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 0.53, green: 0.57, blue: 0.64))
                    }
                    .padding(.horizontal, 3)
                    .padding(.top, 1)

                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(placeSearch.results.prefix(12).enumerated()), id: \.offset) { entry in
                                let completion = entry.element
                                Button {
                                    Task { await selectPlace(completion) }
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color(red: 0.91, green: 0.95, blue: 1.0))
                                                .frame(width: 42, height: 42)
                                            Image(systemName: "mappin.and.ellipse")
                                                .font(.system(size: 17, weight: .semibold))
                                                .foregroundColor(Color(red: 0.13, green: 0.40, blue: 0.94))
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(completion.title)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(Color(red: 0.13, green: 0.17, blue: 0.24))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .lineLimit(1)
                                            if !completion.subtitle.isEmpty {
                                                Text(completion.subtitle)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(Color(red: 0.48, green: 0.53, blue: 0.61))
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .lineLimit(2)
                                            }
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(Color(red: 0.64, green: 0.68, blue: 0.74))
                                    }
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(red: 0.98, green: 0.985, blue: 1.0))
                                    .clipShape(RoundedRectangle(cornerRadius: 15))
                                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color(red: 0.91, green: 0.93, blue: 0.96), lineWidth: 1))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 2)
                    }
                    .frame(maxHeight: isKeyboardVisible ? 240 : 340)
                }
                if let message = placeSearchMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 4)
                }
            }
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(red: 0.87, green: 0.90, blue: 0.94), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 5)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 5)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var mapLayer: some View {
        Map(coordinateRegion: $region, annotationItems: mapMarkets) { market in
            MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: market.lat, longitude: market.lon)) {
                Button {
                    selectedMarketID = market.id
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { sheetExpanded = false }
                } label: {
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(market.id == selectedMarketID ? Color(red: 0.90, green: 0.34, blue: 0.19) : Color(red: 0.16, green: 0.29, blue: 0.23))
                                .frame(width: market.id == selectedMarketID ? 42 : 34, height: market.id == selectedMarketID ? 42 : 34)
                            Circle().stroke(Color.white, lineWidth: 2).frame(width: market.id == selectedMarketID ? 42 : 34, height: market.id == selectedMarketID ? 42 : 34)
                            Image(systemName: market.id == selectedMarketID ? "scope" : "storefront.fill")
                                .font(.system(size: market.id == selectedMarketID ? 17 : 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .shadow(color: Color.black.opacity(0.22), radius: 7, x: 0, y: 3)
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(180))
                            .foregroundColor(market.id == selectedMarketID ? Color(red: 0.90, green: 0.34, blue: 0.19) : Color(red: 0.16, green: 0.29, blue: 0.23))
                            .offset(y: -2)
                        Text(market.name)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .lineLimit(1).padding(.horizontal, 7).padding(.vertical, 4)
                            .foregroundColor(Color(red: 0.16, green: 0.23, blue: 0.19))
                            .background(Color(red: 0.99, green: 0.97, blue: 0.89), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.95), lineWidth: 1))
                            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: centerOnUser) {
                Image(systemName: "location.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.ganjiBlue)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
            }
            .padding(.trailing, 16)
            .padding(.bottom, sheetExpanded ? 470 : 335)
        }
    }

    private var topControls: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer(minLength: 44)
                Text("赶集日记")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.12, green: 0.17, blue: 0.23))
                Spacer(minLength: 0)
                Button {
                    showRegionPicker = false
                    showDatePicker = false
                    withAnimation(.easeInOut(duration: 0.2)) { showMainPage = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 0.23, green: 0.30, blue: 0.39))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.75), in: Circle())
                        .overlay(Circle().stroke(Color.gray.opacity(0.18), lineWidth: 1))
                }
                .accessibilityLabel("关闭地图页面")
            }
            HStack(spacing: 12) {
                Button { showRegionPicker = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 17, weight: .semibold))
                        Text(selectedAreaDisplayName ?? MarketStore.availableAreas.first(where: { $0.code == selectedAreaCode })?.name ?? "选择地区")
                            .font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(Color(red: 0.23, green: 0.30, blue: 0.39))
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) {
                ForEach(MarketFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                        if let offset = filter.offset {
                            selectedDate = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                        } else {
                            selectedDate = Calendar.current.startOfDay(for: Date())
                        }
                    } label: {
                        VStack(spacing: 9) {
                            Text(filter.rawValue)
                                .font(.system(size: 15, weight: selectedFilter == filter ? .bold : .medium))
                                .foregroundColor(selectedFilter == filter ? Color.ganjiBlue : Color(red: 0.39, green: 0.46, blue: 0.56))
                            Capsule().fill(selectedFilter == filter ? Color.ganjiBlue : .clear).frame(height: 3)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                Button { showDatePicker = true } label: {
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(LunarCalendar.shortDate(selectedDate))
                                .font(.system(size: 18, weight: .bold))
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(Color(red: 0.12, green: 0.17, blue: 0.23))
                        Text(LunarCalendar.lunarText(selectedDate))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 0.43, green: 0.50, blue: 0.60))
                    }
                    .frame(minWidth: 88, alignment: .trailing)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(Color(red: 0.98, green: 0.97, blue: 0.91), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.95), lineWidth: 1))
        .shadow(color: Color(red: 0.13, green: 0.20, blue: 0.16).opacity(0.12), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // Region discovery is intentionally a floating map HUD rather than a large
    // opaque bottom sheet. The map remains the primary canvas and market rows
    // form a vertical list above the persistent search and Dock.
    private func marketSheet(screenHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Unified destination search + nearby market panel.
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(red: 0.18, green: 0.39, blue: 0.28))
                TextField("搜索地点，或查找附近圩日", text: $searchText)
                    .focused($isPlaceSearchFocused)
                    .font(.system(size: 14, weight: .medium))
                    .submitLabel(.search)
                    .onChange(of: searchText) { value in
                        placeSearch.query(value)
                        placeSearchMessage = nil
                        if value.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                            Task { await loadNationalRegions() }
                        }
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        placeSearch.clearResults()
                        placeSearchMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(red: 0.54, green: 0.59, blue: 0.53))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
                Rectangle().fill(Color(red: 0.85, green: 0.87, blue: 0.81)).frame(width: 1, height: 24)
                Button { showRegionPicker = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(red: 0.17, green: 0.34, blue: 0.23))
                        .frame(width: 28, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("切换地区，当前地区：\(homeRegionDisplayName)")
            }
            .padding(.horizontal, 13)
            .frame(height: 48)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color(red: 0.87, green: 0.88, blue: 0.82), lineWidth: 1))

            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !placeSearch.results.isEmpty {
                    Text("搜索地点 · 选择后查看当地圩日")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 0.30, green: 0.38, blue: 0.29))
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(placeSearch.results.prefix(8).enumerated()), id: \.offset) { entry in
                                let completion = entry.element
                                Button { Task { await selectPlace(completion) } } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 25))
                                            .foregroundColor(Color(red: 0.27, green: 0.46, blue: 0.30))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(completion.title).font(.system(size: 13, weight: .semibold)).foregroundColor(Color(red: 0.17, green: 0.23, blue: 0.17)).lineLimit(1)
                                            if !completion.subtitle.isEmpty { Text(completion.subtitle).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(2) }
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "arrow.up.left").font(.system(size: 11, weight: .bold)).foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 9).padding(.vertical, 7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: isKeyboardVisible ? 230 : 220)
                } else if let message = placeSearchMessage {
                    Text(message).font(.system(size: 11)).foregroundColor(.secondary)
                } else {
                    Text("输入地点名称，搜索城市、区县或具体位置")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }

            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text("附近赶圩指南")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(1.5)
                            .foregroundColor(Color(red: 0.35, green: 0.36, blue: 0.39))
                        Capsule().fill(Color.white.opacity(0.22)).frame(width: 24, height: 1)
                        Text("圩日地图")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(red: 0.48, green: 0.52, blue: 0.45))
                    }
                    Text("附近圩日")
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .foregroundColor(Color.primary)
                    Text(loadingMarkets ? "正在更新集市" : "\(filteredMarkets.count) 个目的地 · 找一场附近的热闹")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.45, green: 0.49, blue: 0.43))
                }
                Spacer(minLength: 4)
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { sheetExpanded.toggle() }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: sheetExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.right.and.arrow.down.left")
                            .font(.system(size: 13, weight: .bold))
                        Text(sheetExpanded ? "收起" : "展开")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(Color(red: 0.13, green: 0.22, blue: 0.18))
                    .frame(width: 54, height: 54)
                    .background(Color(red: 0.98, green: 0.72, blue: 0.36), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sheetExpanded ? "收起集市列表" : "展开集市列表")
            }

            if filteredMarkets.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "map")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Color(red: 0.98, green: 0.72, blue: 0.36))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("暂时没有找到圩日").font(.system(size: 14, weight: .bold)).foregroundColor(Color(uiColor: .systemBackground))
                        Text("尝试切换地区或调整日期筛选").font(.system(size: 11)).foregroundColor(Color(red: 0.45, green: 0.49, blue: 0.43))
                    }
                    Spacer(minLength: 0)
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.93, green: 0.92, blue: 0.84), in: RoundedRectangle(cornerRadius: 18))
            } else if sheetExpanded {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredMarkets) { row in
                            MarketListRow(row: row, distanceText: distanceText(for: row), selected: selectedMarketID == row.market.id, isFavorite: favorites.contains(row.market.id), toggleFavorite: { toggleFavorite(row.market.id) }) {
                                selectedMarketID = row.market.id
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: min(screenHeight * 0.68, 520))
            } else {
                // Compact nearby-market list uses vertical scrolling; no horizontal carousel.
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredMarkets) { row in
                            MarketListRow(
                                row: row,
                                distanceText: distanceText(for: row),
                                selected: selectedMarketID == row.market.id,
                                isFavorite: favorites.contains(row.market.id),
                                toggleFavorite: { toggleFavorite(row.market.id) }
                            ) {
                                selectedMarketID = row.market.id
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                    region.center = CLLocationCoordinate2D(latitude: row.market.lat, longitude: row.market.lon)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 2)
                }
                .frame(maxHeight: min(screenHeight * 0.32, 250))
            }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        // Give the search state extra bottom breathing room so the hint/results
        // do not sit against the panel's rounded lower edge.
        .padding(.bottom, searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.98, green: 0.97, blue: 0.91), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.95), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color(red: 0.13, green: 0.20, blue: 0.16).opacity(0.18), radius: 22, x: 0, y: 8)
        .padding(.horizontal, 12)
        .gesture(DragGesture(minimumDistance: 18).onEnded { value in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                if value.translation.height < -35 { sheetExpanded = true }
                if value.translation.height > 45 { sheetExpanded = false }
            }
        })
    }

    // Use only the nationwide administrative dataset; no hard-coded offline regions.
    private var regionOptions: [RegionOption] {
        nationalRegionOptions
    }

    // Homepage search uses the same administrative-region data as the Region picker,
    // rather than MapKit place autocomplete. County matches rank first, then city/province.
    private var homeRegionSearchResults: [RegionOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return regionOptions.filter { option in
            option.name.localizedCaseInsensitiveContains(query) ||
            option.city.localizedCaseInsensitiveContains(query) ||
            option.province.localizedCaseInsensitiveContains(query)
        }.sorted { lhs, rhs in
            let leftRank = lhs.kind == .county ? 0 : (lhs.kind == .city ? 1 : 2)
            let rightRank = rhs.kind == .county ? 0 : (rhs.kind == .city ? 1 : 2)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    private var pickerProvinces: [RegionOption] {
        regionOptions.filter { $0.kind == .province }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var pickerCities: [RegionOption] {
        let provincePrefix = selectedPickerProvinceCode / 10000
        let items = regionOptions.filter { $0.kind == .city && $0.code / 10000 == provincePrefix }
        return items.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var pickerCounties: [RegionOption] {
        let cityPrefix = selectedPickerCityCode / 100
        let items = regionOptions.filter { $0.kind == .county && $0.code / 100 == cityPrefix }
        return items.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    @ViewBuilder
    private func pickerColumn(title: String, selection: Binding<Int>, options: [RegionOption]) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.system(size: 12)).foregroundColor(.secondary).padding(.top, 4)
            if options.isEmpty {
                Text("暂无数据").font(.system(size: 14)).foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Picker(title, selection: selection) {
                    ForEach(options) { option in
                        Text(option.name).font(.system(size: 16)).lineLimit(1).tag(option.code)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func alignPickerToSelectedRegion() {
        let code = selectedAreaCode
        let provinceCode = (code / 10000) * 10000
        let cityCode = (code / 100) * 100
        if pickerProvinces.contains(where: { $0.code == provinceCode }) { selectedPickerProvinceCode = provinceCode }
        else if let first = pickerProvinces.first { selectedPickerProvinceCode = first.code }
        if pickerCities.contains(where: { $0.code == cityCode }) { selectedPickerCityCode = cityCode }
        else if let first = pickerCities.first { selectedPickerCityCode = first.code }
        if pickerCounties.contains(where: { $0.code == code }) { selectedPickerCountyCode = code }
        else if let first = pickerCounties.first { selectedPickerCountyCode = first.code }
    }

    @MainActor
    private func loadNationalRegions() async {
        guard !loadingRegionOptions, nationalRegionOptions.isEmpty else { return }
        loadingRegionOptions = true
        defer { loadingRegionOptions = false }

        // Try the official national place-name service first, then a public
        // county-level administrative dataset. This avoids relying on the tiny
        // local HAR snapshot (which only contains a handful of counties).
        let sources = [
            "https://dmfw.mca.gov.cn/9095/xzqh/getList?code=&maxLevel=3",
            "https://unpkg.com/province-city-china@latest/dist/level.json"
        ]
        var lastError: Error = URLError(.cannotLoadFromNetwork)
        for source in sources {
            guard let url = URL(string: source) else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 25
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let root = try JSONSerialization.jsonObject(with: data)
                var parsed: [RegionOption] = []
                var seen = Set<Int>()
                func walk(_ value: Any, province: String, city: String, depth: Int) {
                    guard depth < 16 else { return }
                    if let array = value as? [Any] {
                        for item in array { walk(item, province: province, city: city, depth: depth + 1) }
                        return
                    }
                    guard let object = value as? [String: Any] else { return }
                    let codeKeys = ["code", "xzqhCode", "areaCode", "adcode", "value", "id", "c"]
                    let nameKeys = ["name", "xzqhName", "areaName", "label", "title", "n"]
                    let rawCode = codeKeys.compactMap { object[$0] }.compactMap { item -> String? in
                        if let str = item as? String { return str }
                        if let num = item as? NSNumber { return num.stringValue }
                        return nil
                    }.first(where: { $0.allSatisfy(\.isNumber) && ($0.count == 2 || $0.count == 4 || $0.count == 6 || $0.count == 9 || $0.count == 12) })
                    let rawName = nameKeys.compactMap { object[$0] as? String }.first
                    var nextProvince = province
                    var nextCity = city
                    if let rawCode = rawCode, let rawName = rawName, !rawName.isEmpty {
                        let digits = String(rawCode.prefix(6))
                        if digits.count == 6, let code = Int(digits) {
                            let kind: RegionOption.Kind
                            if digits.hasSuffix("0000") { kind = .province; nextProvince = rawName; nextCity = "" }
                            else if digits.hasSuffix("00") { kind = .city; nextCity = rawName }
                            else { kind = .county }
                            if seen.insert(code).inserted {
                                let option = RegionOption(code: code, name: rawName,
                                    city: kind == .county ? city : (kind == .city ? province : ""),
                                    province: kind == .province ? rawName : province, kind: kind)
                                parsed.append(option)
                            }
                        }
                    }
                    let metadataKeys = Set(codeKeys + nameKeys + ["province", "city", "area", "town", "parent", "parentCode", "parent_adcode", "level"])
                    for (key, child) in object where !metadataKeys.contains(key) {
                        if child is [Any] || child is [String: Any] {
                            walk(child, province: nextProvince, city: nextCity, depth: depth + 1)
                        }
                    }
                }
                walk(root, province: "", city: "", depth: 0)
                // Do not replace a working list with a province-only or malformed parse.
                let countyCount = parsed.filter { $0.kind == .county }.count
                guard countyCount > 2500 else { throw URLError(.cannotParseResponse) }
                nationalRegionOptions = parsed.sorted {
                    if $0.province != $1.province { return $0.province.localizedCompare($1.province) == .orderedAscending }
                    if $0.city != $1.city { return $0.city.localizedCompare($1.city) == .orderedAscending }
                    return $0.name.localizedCompare($1.name) == .orderedAscending
                }
                regionLoadMessage = "已加载全国县区行政区划数据；选择县区后自动查询圩日。行政区划数据与圩日数据覆盖范围不同。"
                return
            } catch {
                lastError = error
            }
        }
        regionLoadMessage = "全国行政区划数据暂时无法加载，请检查网络后重试。"
        _ = lastError
    }


    @MainActor
    private func selectPlace(_ completion: MKLocalSearchCompletion) async {
        // Hide the keyboard while resolving the place, then restore the nearby-markets panel.
        defer { withAnimation(.easeInOut(duration: 0.25)) { isMarketSheetVisible = true } }
        isPlaceSearchFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        placeSearch.clearResults()
        placeSearchMessage = "正在解析地点并匹配行政区划…"
        do {
            let request = MKLocalSearch.Request(completion: completion)
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else {
                placeSearchMessage = "没有找到可用地点，请尝试输入更完整的地名。"
                return
            }
            let placemark = item.placemark
            let province = placemark.administrativeArea ?? ""
            let city = placemark.locality ?? ""
            let district = placemark.subAdministrativeArea ?? placemark.subLocality ?? ""

            // Ensure the nationwide administrative-code list has had a chance to load
            // before matching MapKit's place result. Otherwise the same search may work
            // on one attempt and fail on another depending on network/load timing.
            if nationalRegionOptions.isEmpty {
                if !loadingRegionOptions {
                    await loadNationalRegions()
                } else {
                    // The Region screen starts loading this dataset while the user types.
                    // If they tap a result during that load, wait for the nationwide
                    // dataset instead of matching before it has finished loading.
                    while loadingRegionOptions {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                    // If the first load failed, make one awaited retry before matching.
                    if nationalRegionOptions.isEmpty {
                        await loadNationalRegions()
                    }
                }
            }
            let countyOptions = regionOptions.filter { $0.kind == .county }

            // Normalize common administrative suffixes while preserving the actual county identity.
            func normalized(_ value: String) -> String {
                value.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "中华人民共和国", with: "")
                    .replacingOccurrences(of: "壮族自治区", with: "")
                    .replacingOccurrences(of: "自治区", with: "")
                    .replacingOccurrences(of: "特别行政区", with: "")
                    .replacingOccurrences(of: "省", with: "")
                    .replacingOccurrences(of: "市", with: "")
                    .replacingOccurrences(of: "区", with: "")
                    .replacingOccurrences(of: "县", with: "")
                    .replacingOccurrences(of: "镇", with: "")
                    .replacingOccurrences(of: "乡", with: "")
                    .replacingOccurrences(of: "街道", with: "")
            }
            let normalizedProvince = normalized(province)
            let normalizedCity = normalized(city)
            let normalizedDistrict = normalized(district)
            let addressText = "\(completion.title) \(completion.subtitle) \(province) \(city) \(district)"
            let normalizedAddress = normalized(addressText)
            let normalizedTitle = normalized(completion.title)
            let normalizedSubtitle = normalized(completion.subtitle)

            // First match an explicitly searched county/district name itself. MapKit may
            // return only the province in placemark fields for queries such as "青秀区";
            // requiring the city/district fields in that case incorrectly rejects a valid hit.
            let exactQueryMatches = countyOptions.filter { option in
                let countyName = normalized(option.name)
                let titleMatches = !countyName.isEmpty && countyName == normalizedTitle
                let subtitleMatches = !countyName.isEmpty && countyName == normalizedSubtitle
                let addressMatches = !countyName.isEmpty && normalizedAddress.contains(countyName)
                return titleMatches || subtitleMatches || addressMatches
            }
            // If the query name is unique in the loaded administrative data, it is safe to
            // use even when MapKit's address metadata is incomplete. Duplicate county names
            // still require the city/province context to avoid selecting the wrong area.
            let exactQueryMatch: [RegionOption] = exactQueryMatches.count == 1
                ? exactQueryMatches
                : exactQueryMatches.filter { option in
                    let cityName = normalized(option.city)
                    let provinceName = normalized(option.province)
                    let cityCompatible = !cityName.isEmpty && normalizedAddress.contains(normalized(cityName))
                    let provinceCompatible = !provinceName.isEmpty && normalizedAddress.contains(normalized(provinceName))
                    return cityCompatible || provinceCompatible
                }

            // Also match an explicit district returned in the placemark, then fall back to
            // the complete title/subtitle/address text. City/province fields may be shifted.
            let exactDistrictMatches = countyOptions.filter { option in
                normalized(option.name) == normalizedDistrict && !normalizedDistrict.isEmpty
            }
            let candidates: [RegionOption]
            if exactQueryMatch.count == 1 {
                candidates = exactQueryMatch
            } else if !exactDistrictMatches.isEmpty {
                candidates = exactDistrictMatches
            } else {
                candidates = countyOptions.filter { option in
                    let countyName = normalized(option.name)
                    guard !countyName.isEmpty, normalizedAddress.contains(countyName) else { return false }
                    let cityName = normalized(option.city)
                    let provinceName = normalized(option.province)
                    let cityCompatible = normalizedCity.isEmpty || cityName.isEmpty || cityName == normalizedCity || normalizedAddress.contains(cityName)
                    let provinceCompatible = normalizedProvince.isEmpty || provinceName.isEmpty || provinceName == normalizedProvince || normalizedAddress.contains(provinceName)
                    return cityCompatible && provinceCompatible
                }
            }
            var match = candidates.count == 1 ? candidates[0] : nil

            // MapKit sometimes omits county details from placemark metadata. If the
            // visible search title/subtitle names a unique county, use that exact hit
            // as a fallback instead of depending only on the parsed address fields.
            if match == nil {
                let queryNames = [completion.title, completion.subtitle]
                    .map { normalized($0) }
                    .filter { !$0.isEmpty }
                let fallbackMatches = countyOptions.filter { option in
                    let countyName = normalized(option.name)
                    return !countyName.isEmpty && queryNames.contains(countyName)
                }
                if fallbackMatches.count == 1 {
                    match = fallbackMatches[0]
                }
            }

            if let match = match {
                // A selected place is a location choice, not a market-name filter.
                // Clear the search query immediately so the market list is not hidden
                // until the user manually taps the clear (×) button.
                searchText = ""
                chooseRegion(match)
                withAnimation { showMainPage = true; homeTab = .region }
                if let lat = placemark.location?.coordinate.latitude,
                   let lon = placemark.location?.coordinate.longitude {
                    region.center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
                placeSearchMessage = "已选择：\(match.province)\(match.city)\(match.name)，正在加载该区县集市。镇级地点会查询所属区县数据。"
            } else {
                placeSearchMessage = "找到地点：\(completion.title)（\(completion.subtitle)），但未能可靠匹配市集接口所需的区县代码。请通过“切换地区”手动选择区县后再查询。"
            }
        } catch {
            placeSearchMessage = "地点搜索失败，请检查网络后重试。"
        }
    }

    private func chooseRegion(_ option: RegionOption) {
        selectedAreaCode = option.code
        selectedAreaDisplayName = option.name
        selectedMarketID = nil
        showRegionPicker = false
        // Switching regions should dismiss search/keyboard and restore the nearby-markets panel.
        isPlaceSearchFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        searchText = ""
        placeSearch.clearResults()
        withAnimation(.easeInOut(duration: 0.25)) { isMarketSheetVisible = true }
        Task { await refreshMarkets(for: option.code) }
        if let area = MarketStore.availableAreas.first(where: { $0.code == option.code }) {
            region.center = CLLocationCoordinate2D(latitude: area.lat, longitude: area.lon)
        }
        region.span = MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
    }

    private func distanceValue(for market: Market) -> Double? {
        guard let lat = locator.latitude, let lon = locator.longitude else { return nil }
        return MarketStore.distanceKm(market, from: lat, lon: lon)
    }
    private func distanceValue(for market: Market?) -> Double? { guard let market = market else { return nil }; return distanceValue(for: market) }
    private func distanceText(for row: MarketDay) -> String {
        if let distance = distanceValue(for: row.market) { return kmText(distance) }
        return row.market.area
    }
    @MainActor
    private func refreshMarkets(for areaCode: Int) async {
        loadingMarkets = true
        marketLoadError = nil
        defer { loadingMarkets = false }
        do {
            let fetched = try await MarketAPI.fetch(areaCode: areaCode)
            if !fetched.isEmpty {
                displayedMarkets = fetched
                if let first = fetched.first {
                    withAnimation {
                        region.center = CLLocationCoordinate2D(latitude: first.lat, longitude: first.lon)
                        region.span = MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
                    }
                    if selectedAreaDisplayName == nil || selectedAreaDisplayName?.hasPrefix("地区 ") == true {
                        selectedAreaDisplayName = first.area.isEmpty ? "地区 \(areaCode)" : first.area
                    }
                }
                MarketCache.save(fetched, areaCode: areaCode)
            } else {
                marketLoadError = "该地区暂未返回圩点数据"
                displayedMarkets = MarketCache.load(areaCode: areaCode) ?? MarketStore.load().filter { $0.areaCode == areaCode }
            }
        } catch {
            displayedMarkets = MarketCache.load(areaCode: areaCode) ?? MarketStore.load().filter { $0.areaCode == areaCode }
            marketLoadError = displayedMarkets.isEmpty ? "网络请求失败，请稍后重试" : "网络不可用，显示已缓存数据"
        }
    }

    private func centerOnUser() {
        if let lat = locator.latitude, let lon = locator.longitude {
            withAnimation { region.center = CLLocationCoordinate2D(latitude: lat, longitude: lon); region.span = MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12) }
        } else { locator.start() }
    }
}

private struct RegionOption: Identifiable {
    enum Kind { case county, city, province }
    let code: Int
    let name: String
    let city: String
    let province: String
    let kind: Kind
    var id: Int { code }
}

private struct MarketListRow: View {
    let row: MarketDay
    let distanceText: String
    let selected: Bool
    let isFavorite: Bool
    var showFavoriteButton: Bool = true
    let toggleFavorite: () -> Void
    let action: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(selected ? Color(red: 0.80, green: 0.38, blue: 0.20) : Color(red: 0.77, green: 0.79, blue: 0.69))
                .frame(width: 4)
                .padding(.vertical, 4)
            Button(action: action) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(row.market.size)
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundColor(Color(red: 0.75, green: 0.35, blue: 0.18))
                        Text("·") .foregroundColor(.secondary)
                        Text(row.dayLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(red: 0.24, green: 0.45, blue: 0.30))
                        Spacer(minLength: 2)
                        Text(distanceText)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(red: 0.44, green: 0.49, blue: 0.42))
                    }
                    HStack(alignment: .center, spacing: 6) {
                        Text(row.market.name)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 0.13, green: 0.20, blue: 0.15))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 0.59, green: 0.62, blue: 0.53))
                    }
                    Text((row.market.repeatType == 6 ? "属相  " : "圩日  ") + row.animals)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.48, green: 0.52, blue: 0.44))
                        .lineLimit(1)
                }
                .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showFavoriteButton {
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(isFavorite ? Color(red: 0.82, green: 0.27, blue: 0.25) : Color(red: 0.67, green: 0.69, blue: 0.61))
                        .frame(width: 38, height: 38)
                        .background(isFavorite ? Color(red: 0.98, green: 0.89, blue: 0.85) : Color(red: 0.94, green: 0.94, blue: 0.89), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
                .accessibilityLabel(isFavorite ? "取消收藏" : "收藏圩日")
            }
        }
        .background(selected ? Color(red: 0.93, green: 0.93, blue: 0.85) : Color.white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color(red: 0.88, green: 0.88, blue: 0.81), lineWidth: 0.8))
    }
}

private extension Color {
    static let ganjiBlue = Color(red: 0.16, green: 0.43, blue: 0.94)
    static let ganjiOrange = Color(red: 0.96, green: 0.43, blue: 0.20)
    static let ganjiGreen = Color(red: 0.10, green: 0.63, blue: 0.30)
}


private struct RegionPickerSheetSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.hidden)
        } else {
            content
        }
    }
}


// Included in ContentView.swift so the model is compiled even if the project file
// has not yet registered PlaceSearchModel.swift as a source file.
import Foundation
import MapKit
import Combine


