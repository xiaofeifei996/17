import UIKit

@objc(PXAppPickerController)
public final class PXAppPickerController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating {
    private let domain = "com.moxuan.parallelx"
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let search = UISearchController(searchResultsController: nil)
    private var apps: [(id: String, name: String)] = []
    private var selected: [String] = []
    private var available: [(id: String, name: String)] = []
    private var urls: [[String: String]] = []
    private var customActions: [[String: Any]] = []
    private var extraItems: [(id: String, name: String)] {
        (urls.map { $0 as [String: Any] } + customActions).compactMap {
            guard let id = $0["id"] as? String, let title = $0["title"] as? String else { return nil }
            return (id, title)
        }
    }
    private var addableShortcuts: [(id: String, name: String)] {
        (shortcuts.map { (id: $0.id, name: $0.name) } + extraItems)
            .filter { $0.id.hasPrefix("px.add.") || !selected.contains($0.id) }
    }
    private var symbols: [String: String] = [:]
    private var icons: [String: UIImage] = [:]
    private let shortcuts: [(id: String, name: String, symbol: String)] = [
        ("px.action.dark", "深色模式", "moon.fill"),
        ("px.action.record", "屏幕录制 · 再次选择停止", "record.circle"),
        ("px.action.rotation", "方向锁定", "lock.rotation"),
        ("px.action.window", "切换全屏/分屏（长按停靠小窗/交换窗口）", "rectangle.on.rectangle"),
        ("px.action.screenshot", "截屏（长按仅复制）", "camera.viewfinder"),
        ("px.action.recent", "最近打开的应用", "clock.arrow.circlepath"),
        ("px.action.kayoko", "呼出 Kayoko", "doc.on.clipboard"),
        ("px.action.brightness", "调节亮度（长按并上下拖动）", "sun.max.fill"),
        ("px.action.restart", "重新打开应用", "arrow.clockwise"),
        ("px.action.search", "搜索（长按选择应用）", "magnifyingglass"),
        ("px.add.workflow", "添加快捷指令 · 单个或集合", "square.stack.3d.up"),
        ("px.add.quick", "添加应用快捷方式", "app.badge")
    ]

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "分屏应用"
        view.backgroundColor = .systemGroupedBackground
        selected = UserDefaults(suiteName: domain)?.stringArray(forKey: "applications") ?? []
        urls = UserDefaults(suiteName: domain)?.array(forKey: "urlShortcuts") as? [[String: String]] ?? []
        customActions = UserDefaults(suiteName: domain)?.array(forKey: "customActions") as? [[String: Any]] ?? []
        symbols = UserDefaults(suiteName: domain)?.dictionary(forKey: "shortcutSymbols") as? [String: String] ?? [:]
        apps = PXInstalledApplications().compactMap { item in
            guard let id = item["id"], let name = item["name"] else { return nil }
            return (id: id, name: name)
        }
        refreshAvailable()
        table.frame = view.bounds
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        table.backgroundColor = .systemGroupedBackground
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 58
        table.sectionHeaderHeight = 44
        table.separatorColor = .quaternaryLabel
        table.separatorInset = UIEdgeInsets(top: 0, left: 72, bottom: 0, right: 16)
        table.allowsSelectionDuringEditing = true
        view.addSubview(table)
        table.setEditing(true, animated: false)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "搜索应用名称或标识"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    private func refreshAvailable() {
        let query = search.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        available = apps.filter { !selected.contains($0.id) &&
            (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) ||
             $0.id.localizedCaseInsensitiveContains(query)) }
    }

    public func updateSearchResults(for searchController: UISearchController) {
        refreshAvailable()
        table.reloadData()
    }

    private func saveSelection() {
        let defaults = UserDefaults(suiteName: domain)
        defaults?.set(selected, forKey: "applications")
        defaults?.set(urls, forKey: "urlShortcuts")
        defaults?.set(customActions, forKey: "customActions")
        defaults?.set(symbols, forKey: "shortcutSymbols")
        defaults?.set(Dictionary(
            apps.map { ($0.id, $0.name) } + shortcuts.map { ($0.id, $0.name) } + extraItems.map { ($0.id, $0.name) },
            uniquingKeysWith: { _, latest in latest }),
                      forKey: "applicationNames")
    }

    public func numberOfSections(in tableView: UITableView) -> Int { 3 }

    private func headerTitle(for section: Int) -> String? {
        if search.searchBar.text?.isEmpty == false && section < 2 { return nil }
        return section == 0 ? "已添加 · 拖动右侧排序" :
            section == 1 ? "快捷操作 · 长按可自定义图标与选项" : "可添加应用"
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let title = headerTitle(for: section) else { return nil }
        let header = UIView()
        let label = UILabel(frame: CGRect(x: 32, y: 12, width: tableView.bounds.width - 64, height: 24))
        label.autoresizingMask = [.flexibleWidth]
        label.text = title
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        header.addSubview(label)
        return header
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if search.searchBar.text?.isEmpty == false && section < 2 { return 0 }
        return section == 0 ? selected.count : section == 1 ? addableShortcuts.count + (urls.count < 10 ? 1 : 0) : available.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "app") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "app")
        let isAddURL = indexPath.section == 1 && indexPath.row == addableShortcuts.count
        let app = isAddURL ? (id: "", name: "添加 URL · 最多 10 个") : indexPath.section == 0
            ? apps.first(where: { $0.id == selected[indexPath.row] }) ??
                shortcuts.first(where: { $0.id == selected[indexPath.row] }).map { (id: $0.id, name: $0.name) } ??
                extraItems.first(where: { $0.id == selected[indexPath.row] }) ?? (id: selected[indexPath.row], name: selected[indexPath.row])
            : indexPath.section == 1 ? addableShortcuts[indexPath.row] : available[indexPath.row]
        if !app.id.hasPrefix("px.") {
            cell.textLabel?.text = app.name
        } else if customActions.contains(where: { $0["id"] as? String == app.id && $0["kind"] as? String == "group" }) {
            cell.textLabel?.text = app.name + "（长按展开）"
        } else { cell.textLabel?.text = app.name }
        cell.detailTextLabel?.text = urls.first(where: { $0["id"] == app.id })?["url"] ?? app.id
        if let entry = customActions.first(where: { $0["id"] as? String == app.id }) {
            cell.detailTextLabel?.text = entry["kind"] as? String == "group" ? "长按展开集合，滑动选择，松手运行" : "松手运行"
        }
        cell.textLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        cell.textLabel?.textColor = .label
        cell.textLabel?.adjustsFontSizeToFitWidth = true
        cell.textLabel?.minimumScaleFactor = 0.85
        cell.detailTextLabel?.font = .systemFont(ofSize: 11)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.lineBreakMode = .byTruncatingMiddle
        let fallback = shortcuts.first(where: { $0.id == app.id })?.symbol ?? (isAddURL ? "plus.circle" : app.id.hasPrefix("px.custom.") ? "square.stack.3d.up" : "link")
        if app.id.hasPrefix("px.") || isAddURL {
            cell.imageView?.image = (UIImage(systemName: symbols[app.id] ?? fallback) ?? UIImage(systemName: fallback))?
                .applyingSymbolConfiguration(.init(pointSize: 22))
        } else if let cached = icons[app.id] { cell.imageView?.image = cached }
        else {
            if let rawIcon = PXApplicationIcon(app.id) {
                let size = CGSize(width: 32, height: 32)
                let icon = UIGraphicsImageRenderer(size: size).image { _ in
                    rawIcon.draw(in: CGRect(origin: .zero, size: size))
                }
                icons[app.id] = icon
                cell.imageView?.image = icon
            } else { cell.imageView?.image = nil }
        }
        cell.imageView?.tintColor = .label
        cell.backgroundColor = .secondarySystemGroupedBackground
        cell.selectionStyle = .none
        cell.accessoryType = .none
        if app.id.hasPrefix("px.add.") { cell.accessoryType = .disclosureIndicator }
        cell.showsReorderControl = indexPath.section == 0
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        addItem(at: indexPath)
    }

    private func addItem(at indexPath: IndexPath) {
        if indexPath.section == 0 { return }
        else if indexPath.section == 1 {
            if indexPath.row == addableShortcuts.count { addOrEditURL(at: nil); return }
            let id = addableShortcuts[indexPath.row].id
            if id == "px.add.workflow" { chooseWorkflowMode(); return }
            if id == "px.add.quick" { configureActions(kind: "apps"); return }
            guard !selected.contains(id) else { return }
            selected.append(id)
        } else { selected.append(available[indexPath.row].id) }
        refreshAvailable()
        saveSelection()
        table.reloadData()
    }

    private func prompt(_ title: String, value: String, help: String,
                        onSave: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: help, preferredStyle: .alert)
        alert.addTextField { $0.text = value }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak alert] _ in
            onSave(alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        })
        present(alert, animated: true)
    }

    private func addOrEditURL(at index: Int?) {
        let old = index.map { urls[$0] } ?? [:]
        let alert = UIAlertController(title: index == nil ? "添加 URL 快捷方式" : "编辑 URL",
                                      message: "输入名称与完整 URL（含协议）", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "名称"; $0.text = old["title"] }
        alert.addTextField { $0.placeholder = "https:// 或应用 URL Scheme"; $0.text = old["url"] }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self = self,
                  let fields = alert?.textFields, fields.count == 2,
                  let name = fields[0].text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let text = fields[1].text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: text), let scheme = url.scheme?.lowercased(),
                  !["file", "javascript", "data"].contains(scheme), !text.contains(where: { $0.isWhitespace })
            else { self?.showInvalidURL(); return }
            let id = old["id"] ?? "px.url.\(UUID().uuidString)"
            let entry = ["id": id, "title": name, "url": text]
            if let index = index { self.urls[index] = entry }
            else if self.urls.count < 10 {
                self.urls.append(entry)
                self.selected.append(id)
            }
            self.saveSelection()
            self.table.reloadData()
        })
        present(alert, animated: true)
    }

    private func showInvalidURL() {
        let alert = UIAlertController(title: "URL 无效", message: "请填写名称和带协议的 URL。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    public func tableView(_ tableView: UITableView,
                          contextMenuConfigurationForRowAt indexPath: IndexPath,
                          point: CGPoint) -> UIContextMenuConfiguration? {
        let id: String
        if indexPath.section == 0 { id = selected[indexPath.row] }
        else if indexPath.section == 1 && indexPath.row < addableShortcuts.count {
            id = addableShortcuts[indexPath.row].id
        } else { return nil }
        guard id.hasPrefix("px."), !id.hasPrefix("px.add.") else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return nil }
            var actions: [UIAction] = [UIAction(title: "自定义 SF Symbols 图标", image: UIImage(systemName: "paintbrush")) { [weak self] _ in
                guard let self = self else { return }
                self.prompt("SF Symbols 名称", value: self.symbols[id] ?? "",
                            help: "例如 moon.fill；留空恢复默认图标") { value in
                    if value.isEmpty { self.symbols.removeValue(forKey: id) }
                    else if UIImage(systemName: value) != nil { self.symbols[id] = value }
                    else { self.showInvalidSymbol(); return }
                    self.saveSelection(); self.table.reloadData()
                }
            }]
            if id == "px.action.recent" {
                let rank = UserDefaults(suiteName: self.domain)?.integer(forKey: "recentAppRank") ?? 1
                actions.append(UIAction(title: "显示几个最近应用", image: UIImage(systemName: "number")) { [weak self] _ in
                    guard let self = self else { return }
                    self.prompt("最近应用数量", value: String(max(1, rank)), help: "各占一个图标位置，跳过当前面板中的应用；范围 1–20") { value in
                        guard let number = Int(value), (1...20).contains(number) else { return }
                        UserDefaults(suiteName: self.domain)?.set(number, forKey: "recentAppRank")
                    }
                })
            }
            if let index = self.urls.firstIndex(where: { $0["id"] == id }) {
                actions.append(UIAction(title: "编辑 URL", image: UIImage(systemName: "link")) { [weak self] _ in
                    self?.addOrEditURL(at: index)
                })
                actions.append(UIAction(title: "删除 URL", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    guard let self = self else { return }
                    self.urls.remove(at: index)
                    self.selected.removeAll { $0 == id }
                    self.symbols.removeValue(forKey: id)
                    self.saveSelection(); self.table.reloadData()
                })
            }
            if let index = self.customActions.firstIndex(where: { $0["id"] as? String == id }) {
                if self.customActions[index]["kind"] as? String == "group" {
                    actions.append(UIAction(title: "编辑集合与排序", image: UIImage(systemName: "list.bullet")) { [weak self] _ in
                        self?.configureActions(kind: "workflow", multiple: true, editingID: id)
                    })
                }
                actions.append(UIAction(title: "删除快捷方式", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    guard let self = self else { return }
                    self.customActions.removeAll { $0["id"] as? String == id }
                    self.selected.removeAll { $0 == id }
                    self.symbols.removeValue(forKey: id)
                    self.saveSelection(); self.table.reloadData()
                })
            }
            return UIMenu(children: actions)
        }
    }

    private func showInvalidSymbol() {
        let alert = UIAlertController(title: "图标不存在", message: "请输入 iOS 15 支持的 SF Symbols 名称。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func chooseWorkflowMode() {
        let menu = UIAlertController(title: "添加快捷指令", message: "单个指令占一个位置；集合中的多个指令共用一个位置。", preferredStyle: .actionSheet)
        menu.addAction(UIAlertAction(title: "单个快捷指令", style: .default) { [weak self] _ in self?.configureActions(kind: "workflow") })
        menu.addAction(UIAlertAction(title: "多个快捷指令集合", style: .default) { [weak self] _ in self?.configureActions(kind: "workflow", multiple: true) })
        menu.addAction(UIAlertAction(title: "取消", style: .cancel))
        menu.popoverPresentationController?.sourceView = view
        menu.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(menu, animated: true)
    }

    private func configureActions(kind: String, multiple: Bool = false, editingID: String? = nil) {
        let picker = PXActionPickerController()
        picker.kind = kind
        picker.multiple = multiple
        let old = customActions.first { $0["id"] as? String == editingID } ?? [:]
        picker.chosen = old["items"] as? [[String: Any]] ?? []
        picker.onSave = { [weak self, weak picker] items in
            guard let self = self, !items.isEmpty else { return }
            let persist: (String) -> Void = { title in
                var entry: [String: Any] = multiple ? ["kind": "group", "items": items] : items[0]
                let id = editingID ?? "px.custom.\(UUID().uuidString)"
                entry["id"] = id
                entry["title"] = title
                if let index = self.customActions.firstIndex(where: { $0["id"] as? String == id }) { self.customActions[index] = entry }
                else { self.customActions.append(entry); self.selected.append(id) }
                self.saveSelection(); self.table.reloadData()
                self.navigationController?.popToViewController(self.parent ?? self, animated: true)
            }
            if multiple {
                let alert = UIAlertController(title: "集合名称", message: nil, preferredStyle: .alert)
                alert.addTextField { $0.text = old["title"] as? String ?? "快捷指令集合" }
                alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak alert] _ in
                    let title = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !title.isEmpty { persist(title) }
                })
                picker?.present(alert, animated: true)
            } else {
                let title = items[0]["title"] as? String ?? "快捷方式"
                persist((items[0]["appTitle"] as? String).map { "\($0) · \(title)" } ?? title)
            }
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    public func tableView(_ tableView: UITableView,
                          editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        if indexPath.section == 0 { return .delete }
        if indexPath.section == 2 { return .insert }
        return .insert
    }

    public func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle,
                          forRowAt indexPath: IndexPath) {
        if editingStyle == .insert { addItem(at: indexPath); return }
        guard editingStyle == .delete, indexPath.section == 0 else { return }
        selected.remove(at: indexPath.row)
        refreshAvailable()
        saveSelection()
        tableView.reloadData()
    }

    public func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == 0
    }

    public func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath,
                          to destinationIndexPath: IndexPath) {
        let id = selected.remove(at: sourceIndexPath.row)
        selected.insert(id, at: destinationIndexPath.row)
        saveSelection()
    }

    public func tableView(_ tableView: UITableView,
                          targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
                          toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        proposedDestinationIndexPath.section == 0 ? proposedDestinationIndexPath : sourceIndexPath
    }
}
