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

struct ContentView: View {
    @StateObject private var locator = LocationModel()
    @State private var selectedFilter: MarketFilter = .all
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var searchText = ""
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
    private var mapMarkets: [Market] { filteredMarkets.map { $0.market } }

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
                // Hard cover for the bottom safe-area gap: keep the map from showing
                // beneath the rounded market sheet on devices with a home indicator.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Color(red: 0.96, green: 0.96, blue: 0.96)
                        .frame(height: 130)
                }
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
                .zIndex(2.5)
                // When the software keyboard is open, cover the exposed map gap
                // with the same solid surface used by the search controls.
                if isKeyboardVisible {
                    Color(red: 0.96, green: 0.96, blue: 0.96)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .zIndex(2.7)
                }
                marketSheet(screenHeight: geo.size.height)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 116)
                    .zIndex(3)
                // Only render the map Dock while the map page is active.
                // The home/favorites page has its own Dock; rendering both at once
                // causes overlapping hit targets and a brief visual flash during tab changes.
                if showMainPage {
                    mapSearchAndDock
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 58)
                        .zIndex(4)
                } else {
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
                guard let id = newValue, let market = allMarkets.first(where: { $0.id == id }) else { return }
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

    private var homePage: some View {
        VStack(spacing: 0) {
            HStack {
                Text(homeTab == .region ? "地区搜索" : (homeTab == .favorites ? "我的收藏" : "赶集日记")).font(.system(size: 25, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 16)
            if homeTab == .home {
                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(0..<3, id: \.self) { offset in
                                let rows = homeMarkets(for: offset)
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(spacing: 8) {
                                        RoundedRectangle(cornerRadius: 2).fill(Color.ganjiBlue).frame(width: 4, height: 19)
                                        Text(["今日圩日", "明日圩日", "后日圩日"][offset]).font(.system(size: 18, weight: .bold))
                                        Text("\(rows.count) 个集市").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    if rows.isEmpty {
                                        Text("这一天暂无开圩集市").font(.system(size: 13)).foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 14)
                                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                                            .padding(.horizontal, 16)
                                    } else {
                                        VStack(spacing: 1) {
                                            ForEach(rows) { row in
                                                MarketListRow(row: row, distanceText: distanceText(for: row), selected: selectedMarketID == row.market.id, isFavorite: favorites.contains(row.market.id), showFavoriteButton: false, toggleFavorite: { toggleFavorite(row.market.id) }) {
                                                    selectedMarketID = row.market.id
                                                    withAnimation { showMainPage = true }
                                                }
                                            }
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4).padding(.bottom, 18)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("收藏圩日").font(.system(size: 21, weight: .bold))
                    Spacer()
                    Text("\(favorites.count) 个").font(.system(size: 13)).foregroundColor(.secondary)
                }.padding(.horizontal, 22).padding(.bottom, 10)
                let saved = favoriteMarkets
                if saved.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "heart").font(.system(size: 42)).foregroundColor(.secondary.opacity(0.7))
                        Text("还没有收藏圩日").font(.system(size: 17, weight: .semibold))
                        Text("进入“地区”页面，在集市列表中点击心形按钮即可收藏。")
                            .font(.system(size: 14)).foregroundColor(.secondary).multilineTextAlignment(.center)
                        Button { withAnimation { showMainPage = true; homeTab = .region } } label: {
                            Text("去地区页面添加收藏").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                                .padding(.horizontal, 22).padding(.vertical, 12).background(Color.ganjiBlue, in: Capsule())
                        }.padding(.top, 4)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(28)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(saved) { market in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(market.name).font(.system(size: 17, weight: .semibold)).foregroundColor(.primary)
                                        Text([market.province, market.city, market.area].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1)
                                        Text(market.repeatType == 6 ? "属相：\(market.repeatValue.joined(separator: "、"))" : "圩日：\(market.displaySchedule)")
                                            .font(.system(size: 13)).foregroundColor(.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    Button { toggleFavorite(market.id) } label: {
                                        Image(systemName: "heart.fill").font(.system(size: 20)).foregroundColor(.pink).frame(width: 42, height: 44)
                                    }.accessibilityLabel("取消收藏\(market.name)")
                                    Button { withAnimation { showMainPage = true; homeTab = .region }; selectedMarketID = market.id } label: {
                                        Image(systemName: "arrow.up.right").foregroundColor(Color.ganjiBlue).frame(width: 32, height: 40)
                                    }.accessibilityLabel("在地图查看\(market.name)")
                                }.padding(15).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                            }
                        }.padding(.horizontal, 16).padding(.bottom, 16)
                    }
                }
            }
            // Region search is a first-class tab alongside Home and Favorites.
            if homeTab == .region {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        homeRegionExpanded.toggle()
                        if homeRegionExpanded { alignPickerToSelectedRegion() }
                    }
                } label: {
                HStack(spacing: 11) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.ganjiBlue)
                        .frame(width: 38, height: 38)
                        .background(Color.ganjiBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("当前赶集地区")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(homeRegionDisplayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text("切换")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.ganjiBlue)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.black.opacity(0.05), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("选择省份、城市和区县，当前地区：\(homeRegionDisplayName)")
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Color(uiColor: .systemGroupedBackground))

            if homeRegionExpanded {
                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        pickerColumn(title: "省份", selection: $selectedPickerProvinceCode, options: pickerProvinces)
                        pickerColumn(title: "城市", selection: $selectedPickerCityCode, options: pickerCities)
                        pickerColumn(title: "区县", selection: $selectedPickerCountyCode, options: pickerCounties)
                    }
                    .frame(height: 154)
                    Text(regionLoadMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 10) {
                        Button("收起") {
                            withAnimation(.easeInOut(duration: 0.2)) { homeRegionExpanded = false }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))

                        Button("确定地区") {
                            if let option = pickerCounties.first(where: { $0.code == selectedPickerCountyCode })
                                ?? pickerCities.first(where: { $0.code == selectedPickerCityCode })
                                ?? pickerProvinces.first(where: { $0.code == selectedPickerProvinceCode }) {
                                chooseRegion(option)
                            }
                            withAnimation(.easeInOut(duration: 0.2)) { homeRegionExpanded = false }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(Color.ganjiBlue, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            }

        }
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
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color(uiColor: .systemGroupedBackground))
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
            .foregroundColor((homeTab == tab || (tab == .region && showMainPage)) ? Color.ganjiBlue : .secondary)
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

    // Compact location + search bar, styled like a single horizontal navigation control.
    private var mapSearchAndDock: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button { showRegionPicker = true } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(Color(red: 0.56, green: 0.62, blue: 0.71))
                            Text(homeRegionDisplayName.split(separator: "·").last.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? homeRegionDisplayName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(red: 0.20, green: 0.25, blue: 0.32))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(red: 0.56, green: 0.62, blue: 0.71))
                        }
                        .padding(.leading, 12)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("切换地区，当前地区：\(homeRegionDisplayName)")

                    HStack(spacing: 11) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(Color(red: 0.56, green: 0.62, blue: 0.71))
                        TextField("搜索地点", text: $searchText)
                            .font(.system(size: 16))
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
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }
                            .accessibilityLabel("清除搜索")
                        }
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 44)
                    .background(Color(red: 0.93, green: 0.95, blue: 0.98))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color(red: 0.87, green: 0.89, blue: 0.93), lineWidth: 1))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if !placeSearch.results.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Keep suggestions scrollable when the iOS keyboard covers the lower part
                    // of the screen. A visible scroll indicator helps users discover more results.
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(placeSearch.results.prefix(12).enumerated()), id: \.offset) { entry in
                                let completion = entry.element
                                Button {
                                    Task { await selectPlace(completion) }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(completion.title)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        if !completion.subtitle.isEmpty {
                                            Text(completion.subtitle)
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .lineLimit(2)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: isKeyboardVisible ? 300 : 420)
                    .scrollBounceBehavior(.basedOnSize)
                    .padding(.horizontal, 12)
                }
                if let message = placeSearchMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(red: 0.86, green: 0.89, blue: 0.93), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 5)
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.96).ignoresSafeArea(edges: .bottom))
        // Keep the existing keyboard-aware positioning.
        .offset(y: isKeyboardVisible ? 44 : 0)
    }

    private var mapLayer: some View {
        Map(coordinateRegion: $region, annotationItems: mapMarkets) { market in
            MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: market.lat, longitude: market.lon)) {
                Button {
                    selectedMarketID = market.id
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { sheetExpanded = false }
                } label: {
                    VStack(spacing: 3) {
                        HStack(spacing: 4) {
                            Circle().fill(market.id == selectedMarketID ? Color.white : Color.ganjiOrange).frame(width: 7, height: 7)
                            Text(market.name)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(market.id == selectedMarketID ? .white : Color(red: 0.19, green: 0.24, blue: 0.29))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(market.id == selectedMarketID ? Color.ganjiBlue : Color.white, in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.9), lineWidth: 1))
                        .shadow(color: .black.opacity(0.13), radius: 6, x: 0, y: 3)
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 7))
                            .rotationEffect(.degrees(180))
                            .foregroundColor(market.id == selectedMarketID ? Color.ganjiBlue : .white)
                            .offset(y: -4)
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
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.regularMaterial)
        .background(Color(red: 0.78, green: 0.84, blue: 0.72).opacity(0.48))
    }

    private func marketSheet(screenHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(red: 0.79, green: 0.82, blue: 0.87)).frame(width: 42, height: 5).padding(.top, 10).padding(.bottom, 12)
            HStack(alignment: .firstTextBaseline) {
                Text(selectedFilter == .all ? "附近集市" : "\(selectedFilter.rawValue)赶集")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Color(red: 0.12, green: 0.17, blue: 0.23))
                Text(loadingMarkets ? "正在加载…" : (marketLoadError ?? "\(filteredMarkets.count) 个集市"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(marketLoadError == nil ? .secondary : .orange)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { sheetExpanded.toggle() }
                } label: {
                    Image(systemName: sheetExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.ganjiBlue)
                        .frame(width: 32, height: 32)
                        .background(Color.ganjiBlue.opacity(0.08), in: Circle())
                }
            }
            .padding(.horizontal, 20)
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if filteredMarkets.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "map").font(.system(size: 28)).foregroundColor(.secondary)
                            Text("没有找到符合条件的集市").font(.system(size: 14)).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 35)
                    } else {
                        ForEach(filteredMarkets) { row in
                            MarketListRow(row: row, distanceText: distanceText(for: row), selected: selectedMarketID == row.market.id, isFavorite: favorites.contains(row.market.id), toggleFavorite: { toggleFavorite(row.market.id) }) {
                                selectedMarketID = row.market.id
                            }
                            Divider().overlay(Color.black.opacity(0.025)).padding(.leading, 20)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .padding(.top, 3)
            // Prevent iOS ScrollView from drawing any default/translucent scroll surface.
            // Omitted scrollContentBackground: deployment target is iOS 15.
            .background(Color(red: 0.96, green: 0.96, blue: 0.96))
        }
        .frame(maxWidth: .infinity)
        // Keep enough market rows visible while the keyboard is open. SwiftUI may
        // report a keyboard-reduced GeometryReader height, so use a taller share
        // of the available area and avoid the normal collapsed-sheet height.
        .frame(height: min(
            screenHeight * (isKeyboardVisible ? 0.90 : (sheetExpanded ? 0.78 : 0.43)),
            screenHeight - (isKeyboardVisible ? 130 : 175)
        ))
        // Keep the visible sheet opaque and rounded; extend its solid fill behind the home indicator.
        .background {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(Color(red: 0.96, green: 0.96, blue: 0.96))
                .ignoresSafeArea(edges: .bottom)
        }
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(alignment: .top) { RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(Color.white.opacity(0.7), lineWidth: 1) }
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: -5)
        .gesture(DragGesture(minimumDistance: 12).onEnded { value in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                if value.translation.height < -35 { sheetExpanded = true }
                if value.translation.height > 35 { sheetExpanded = false }
            }
        })
    }

    private var regionOptions: [RegionOption] {
        let fallback = [
            RegionOption(code: 450821, name: "平南县", city: "贵港市", province: "广西壮族自治区", kind: .county),
            RegionOption(code: 450881, name: "桂平市", city: "贵港市", province: "广西壮族自治区", kind: .county),
            RegionOption(code: 450924, name: "兴业县", city: "玉林市", province: "广西壮族自治区", kind: .county),
            RegionOption(code: 451324, name: "金秀瑶族自治县", city: "来宾市", province: "广西壮族自治区", kind: .county)
        ]
        var combined = nationalRegionOptions + fallback
        // Derive parent province/city rows from the locally-known county entries as a safe offline fallback.
        for item in fallback {
            let provinceCode = (item.code / 10000) * 10000
            let cityCode = (item.code / 100) * 100
            if !combined.contains(where: { $0.code == provinceCode }) {
                combined.append(RegionOption(code: provinceCode, name: item.province, city: "", province: item.province, kind: .province))
            }
            if !combined.contains(where: { $0.code == cityCode }) {
                combined.append(RegionOption(code: cityCode, name: item.city, city: item.province, province: item.province, kind: .city))
            }
        }
        var seen = Set<Int>()
        return combined.filter { seen.insert($0.code).inserted }
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
        guard let url = URL(string: "https://dmfw.mca.gov.cn/9095/xzqh/getList?code=&maxLevel=3") else {
            regionLoadMessage = "无法生成行政区划请求，显示本地已知地区。"
            return
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let root = try JSONSerialization.jsonObject(with: data)
            var parsed: [RegionOption] = []
            var seen = Set<Int>()
            func walk(_ value: Any, province: String, city: String, depth: Int) {
                guard depth < 12 else { return }
                if let array = value as? [Any] {
                    for item in array { walk(item, province: province, city: city, depth: depth + 1) }
                    return
                }
                guard let object = value as? [String: Any] else { return }
                let codeKeys = ["code", "xzqhCode", "areaCode", "value", "id"]
                let nameKeys = ["name", "xzqhName", "areaName", "label", "title"]
                let rawCode = codeKeys.compactMap { object[$0] }.compactMap { item -> String? in
                    if let str = item as? String { return str }
                    if let num = item as? NSNumber { return num.stringValue }
                    return nil
                }.first(where: { $0.allSatisfy(\.isNumber) && ($0.count == 6 || $0.count == 12) })
                let rawName = nameKeys.compactMap { object[$0] as? String }.first
                var nextProvince = province
                var nextCity = city
                if let rawCode = rawCode, let rawName = rawName, !rawName.isEmpty {
                    let codeString = String(rawCode.prefix(6))
                    if let code = Int(codeString) {
                        let kind: RegionOption.Kind
                        if codeString.hasSuffix("0000") { kind = .province; nextProvince = rawName; nextCity = "" }
                        else if codeString.hasSuffix("00") { kind = .city; nextCity = rawName }
                        else { kind = .county }
                        if seen.insert(code).inserted {
                            let option = RegionOption(code: code, name: rawName, city: kind == .county ? city : (kind == .city ? province : ""), province: kind == .province ? rawName : province, kind: kind)
                            parsed.append(option)
                        }
                    }
                }
                for (key, child) in object where !["code", "xzqhCode", "areaCode", "value", "id", "name", "xzqhName", "areaName", "label", "title"].contains(key) {
                    if child is [Any] || child is [String: Any] {
                        walk(child, province: nextProvince, city: nextCity, depth: depth + 1)
                    }
                }
            }
            walk(root, province: "", city: "", depth: 0)
            guard !parsed.isEmpty else { throw URLError(.cannotParseResponse) }
            nationalRegionOptions = parsed.sorted {
                if $0.province != $1.province { return $0.province.localizedCompare($1.province) == .orderedAscending }
                if $0.city != $1.city { return $0.city.localizedCompare($1.city) == .orderedAscending }
                return $0.name.localizedCompare($1.name) == .orderedAscending
            }
            regionLoadMessage = "已加载全国行政区划；选择县区后自动查询圩日数据。若官方服务暂不可用，将显示本地已知地区。"
        } catch {
            regionLoadMessage = "全国区划服务暂不可用，当前显示本地已知地区。请联网后重新打开此页面。"
        }
    }


    @MainActor
    private func selectPlace(_ completion: MKLocalSearchCompletion) async {
        // Dismiss the software keyboard immediately when the user taps a place suggestion.
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
            let placeName = item.name ?? completion.title
            let countyOptions = regionOptions.filter { $0.kind == .county }
            let normalizedProvince = province.replacingOccurrences(of: "省", with: "").replacingOccurrences(of: "市", with: "")
            let normalizedCity = city.replacingOccurrences(of: "市", with: "")
            let normalizedDistrict = district.replacingOccurrences(of: "区", with: "").replacingOccurrences(of: "县", with: "").replacingOccurrences(of: "市", with: "")
            let match = countyOptions.first { option in
                let op = option.province.replacingOccurrences(of: "省", with: "").replacingOccurrences(of: "市", with: "")
                let oc = option.city.replacingOccurrences(of: "市", with: "")
                let oa = option.name.replacingOccurrences(of: "区", with: "").replacingOccurrences(of: "县", with: "").replacingOccurrences(of: "市", with: "")
                let provinceMatch = normalizedProvince.isEmpty || op.contains(normalizedProvince) || normalizedProvince.contains(op)
                let cityMatch = normalizedCity.isEmpty || oc.contains(normalizedCity) || normalizedCity.contains(oc)
                let districtMatch = !normalizedDistrict.isEmpty && (oa == normalizedDistrict || option.name == district)
                return provinceMatch && cityMatch && districtMatch
            }
            if let match = match {
                // A selected place is a location choice, not a market-name filter.
                // Clear the search query immediately so the market list is not hidden
                // until the user manually taps the clear (×) button.
                searchText = ""
                chooseRegion(match)
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
        HStack(alignment: .center, spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 7) {
                            Text(row.market.name).font(.system(size: 17, weight: .semibold)).foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.23)).lineLimit(1)
                            Text(row.market.size).font(.system(size: 10, weight: .medium)).foregroundColor(Color.ganjiBlue).padding(.horizontal, 7).padding(.vertical, 4).background(Color.ganjiBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                            Text(row.dayLabel).font(.system(size: 10, weight: .semibold)).foregroundColor(Color.ganjiGreen).padding(.horizontal, 7).padding(.vertical, 4).background(Color.ganjiGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                        }
                        Text(row.market.repeatType == 6 ? "属相  \(row.animals)" : "圩日  \(row.animals)").font(.system(size: 12)).foregroundColor(Color(red: 0.42, green: 0.49, blue: 0.59)).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(distanceText).font(.system(size: 13, weight: .medium)).foregroundColor(Color(red: 0.42, green: 0.49, blue: 0.59)).lineLimit(1)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(red: 0.62, green: 0.68, blue: 0.75))
                    }
                }
                .padding(.leading, 20).padding(.trailing, 8).padding(.vertical, 17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showFavoriteButton {
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundColor(isFavorite ? .pink : Color.secondary)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .frame(width: 56)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "取消收藏" : "收藏圩日")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Each row gets a fully opaque fill as well, including non-selected rows.
        .background(selected ? Color(red: 0.95, green: 0.97, blue: 1.0) : Color.white)
        .clipShape(Rectangle())
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


