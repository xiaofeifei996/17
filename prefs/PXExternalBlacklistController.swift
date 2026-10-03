import UIKit

@objc(PXExternalBlacklistController)
public final class PXExternalBlacklistController: UITableViewController, UISearchResultsUpdating {
    private let defaults = UserDefaults(suiteName: "com.moxuan.parallelx")
    private let search = UISearchController(searchResultsController: nil)
    private var apps: [(id: String, name: String)] = []
    private var visible: [(id: String, name: String)] = []
    private var excluded = Set<String>()
    private var icons: [String: UIImage] = [:]

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "URL 分屏黑名单"
        excluded = Set(defaults?.stringArray(forKey: "urlSplitExcluded") ?? [])
        apps = PXInstalledApplications().compactMap { app in
            guard let id = app["id"], let name = app["name"] else { return nil }
            return (id, name)
        }
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "搜索应用"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        updateSearchResults(for: search)
    }

    public func updateSearchResults(for searchController: UISearchController) {
        let query = search.searchBar.text ?? ""
        visible = query.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }
        visible.sort {
            let left = excluded.contains($0.id), right = excluded.contains($1.id)
            if left != right { return left }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        tableView.reloadData()
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visible.count
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "app") ??
            UITableViewCell(style: .subtitle, reuseIdentifier: "app")
        let app = visible[indexPath.row]
        cell.textLabel?.text = app.name
        cell.detailTextLabel?.text = app.id
        cell.detailTextLabel?.textColor = .secondaryLabel
        if let cached = icons[app.id] { cell.imageView?.image = cached }
        else if let raw = PXApplicationIcon(app.id) {
            let size = CGSize(width: 32, height: 32)
            let icon = UIGraphicsImageRenderer(size: size).image { _ in
                raw.draw(in: CGRect(origin: .zero, size: size))
            }
            icons[app.id] = icon
            cell.imageView?.image = icon
        } else { cell.imageView?.image = UIImage(systemName: "app") }
        cell.accessoryType = .none
        cell.selectionStyle = .none
        let toggle = UISwitch()
        toggle.isOn = excluded.contains(app.id)
        toggle.accessibilityLabel = "禁止 \(app.name) URL 分屏"
        toggle.addAction(UIAction { [weak self] action in
            guard let self = self, let toggle = action.sender as? UISwitch else { return }
            if toggle.isOn { self.excluded.insert(app.id) }
            else { self.excluded.remove(app.id) }
            self.defaults?.set(Array(self.excluded).sorted(), forKey: "urlSplitExcluded")
            self.updateSearchResults(for: self.search)
        }, for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }
}
