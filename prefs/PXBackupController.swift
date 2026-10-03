import UIKit
import UniformTypeIdentifiers
import CoreFoundation

@objc(PXBackupController)
public final class PXBackupController: UITableViewController, UIDocumentPickerDelegate {
    private let domain = "com.moxuan.parallelx"
    private let defaults = UserDefaults(suiteName: "com.moxuan.parallelx")

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "备份与恢复"
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 54
    }

    public override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "保存配置" : "恢复配置"
    }

    public override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0
            ? "导出应用排序、快捷操作、窗口、手势及其他插件设置。文件可能包含你保存的快捷链接，请妥善保管。"
            : "从 ParallelX 备份文件恢复会覆盖当前设置；已打开的窗口重新打开后应用新设置。"
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = indexPath.section == 0 ? "导出备份" : "从文件恢复"
        cell.imageView?.image = UIImage(systemName: indexPath.section == 0 ? "square.and.arrow.up" : "square.and.arrow.down")
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 { exportBackup(from: indexPath) }
        else {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.propertyList], asCopy: true)
            picker.delegate = self
            present(picker, animated: true)
        }
    }

    private func exportBackup(from indexPath: IndexPath) {
        let settings = defaults?.persistentDomain(forName: domain) ?? [:]
        do {
            let backup: [String: Any] = ["formatVersion": 1, "domain": domain, "settings": settings]
            let data = try PropertyListSerialization.data(fromPropertyList: backup, format: .xml, options: 0)
            let name = "ParallelX-settings-\(Int(Date().timeIntervalSince1970)).plist"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = tableView
            share.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath)
            present(share, animated: true)
        } catch {
            showError("备份文件创建失败。")
        }
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        controller.dismiss(animated: true) { [weak self] in self?.importBackup(at: url) }
    }

    private func importBackup(at url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1_000_000 else { showError("备份文件过大。"); return }
            let data = try Data(contentsOf: url)
            guard data.count <= 1_000_000,
                  let backup = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  backup["formatVersion"] as? Int == 1,
                  backup["domain"] as? String == domain,
                  let settings = backup["settings"] as? [String: Any] else {
                showError("这不是受支持的 ParallelX 备份文件。")
                return
            }
            let alert = UIAlertController(title: "恢复设置？", message: "当前配置将被备份文件覆盖。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "恢复", style: .destructive) { [weak self] _ in
                self?.restore(settings)
            })
            present(alert, animated: true)
        } catch {
            showError("无法读取备份文件。")
        }
    }

    private func restore(_ settings: [String: Any]) {
        guard let defaults = defaults else { showError("无法访问插件设置。"); return }
        let previous = defaults.persistentDomain(forName: domain) ?? [:]
        defaults.setPersistentDomain(settings, forName: domain)
        guard defaults.synchronize() else {
            defaults.setPersistentDomain(previous, forName: domain)
            defaults.synchronize()
            showError("恢复失败，原设置已保留。")
            return
        }
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: "com.moxuan.parallelx.capture-updated" as CFString), nil, nil, true)
        let alert = UIAlertController(title: "恢复完成", message: "重新打开设置页面和分屏窗口后，配置将全部生效。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "备份与恢复", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}
