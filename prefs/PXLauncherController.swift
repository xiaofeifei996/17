import UIKit

@objc(PXLauncherController)
public final class PXLauncherController: UIViewController {
    private let defaults = UserDefaults(suiteName: "com.moxuan.parallelx")
    private let keys = ["launcherIconSize", "launcherRing1", "launcherRing2",
                        "launcherRing3", "launcherRing4", "launcherRingGap", "launcherDragDistance",
                        "launcherEdgeInset", "launcherHoldMilliseconds", "handleWidth", "handleHeight",
                        "animationSpeedPercent"]
    private let titles = ["图标大小", "第一环应用数", "第二环应用数", "第三环应用数",
                          "第四环应用数", "环间距", "手柄滑动距离", "面板距右边缘", "长按全屏时长",
                          "手柄宽度", "手柄高度", "全局动画速度"]
    private let initial = [52, 3, 5, 7, 9, 10, 120, 6, 700, 24, 86, 100]
    private let limits: [(Float, Float)] = [(36, 72), (0, 30), (0, 30),
                                            (0, 30), (0, 30), (0, 60), (10, 240), (0, 120),
                                            (300, 2000), (12, 52), (44, 160), (10, 150)]
    private let labels = (0..<12).map { _ in UILabel() }
    private let sliders = (0..<12).map { _ in UISlider() }
    private let buttons = (0..<12).map { _ in UIButton(type: .system) }
    private let scroll = UIScrollView()
    private let hint = UILabel()
    private var cards: [UIView] = []
    private var headings: [UILabel] = []
    private var lines: [[UIView]] = []
    private var values = [52, 3, 5, 7, 9, 10, 120, 6, 700, 24, 86, 100]

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "半圆应用面板"
        view.backgroundColor = .systemGroupedBackground
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scroll)
        for (title, count) in [("图标与环形排列", 6), ("呼出与选择", 3), ("手柄尺寸", 2), ("动画", 1)] {
            headings.append(PXSettingsStyle.heading(title, in: scroll))
            cards.append(PXSettingsStyle.card(in: scroll))
            lines.append((0..<(count - 1)).map { _ in PXSettingsStyle.separator(in: scroll) })
        }
        for index in keys.indices {
            let label = labels[index]
            label.font = .preferredFont(forTextStyle: .body)
            if (1...4).contains(index) {
                label.tag = index
                label.isUserInteractionEnabled = true
                label.addGestureRecognizer(UILongPressGestureRecognizer(target: self,
                                                                         action: #selector(editRingCount(_:))))
            }
            scroll.addSubview(label)
            let slider = sliders[index]
            slider.tag = index
            slider.minimumValue = limits[index].0
            slider.maximumValue = limits[index].1
            values[index] = defaults?.object(forKey: keys[index]) as? Int ?? initial[index]
            slider.value = Float(values[index])
            slider.addTarget(self, action: #selector(valueChanged(_:)), for: .valueChanged)
            slider.addTarget(self, action: #selector(valueFinished(_:)),
                             for: [.touchUpInside, .touchUpOutside, .touchCancel])
            scroll.addSubview(slider)
            let button = buttons[index]
            button.tag = index
            button.setImage(UIImage(systemName: "keyboard"), for: .normal)
            button.accessibilityLabel = "输入\(titles[index])"
            button.addTarget(self, action: #selector(editValue(_:)), for: .touchUpInside)
            scroll.addSubview(button)
            updateLabel(index)
        }
        hint.text = "环数设为 0 会关闭当前及后续环。长按环容量文字可输入数量。滑到图标后松手打开分屏；保持选中至设定时长再松手打开全屏。换图标会重新计时。空白处松手收回。"
        hint.textColor = .secondaryLabel
        hint.font = .preferredFont(forTextStyle: .footnote)
        hint.numberOfLines = 0
        scroll.addSubview(hint)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = scroll.bounds.width
        var y: CGFloat = 20
        var index = 0
        for (section, count) in [6, 3, 2, 1].enumerated() {
            headings[section].frame = CGRect(x: 32, y: y, width: width - 64, height: 22)
            y += 30
            let cardY = y
            cards[section].frame = CGRect(x: 16, y: cardY, width: width - 32,
                                           height: CGFloat(count) * 78)
            for row in 0..<count {
                let rowY = cardY + CGFloat(row) * 78
                labels[index].frame = CGRect(x: 32, y: rowY + 9, width: width - 64, height: 28)
                sliders[index].frame = CGRect(x: 32, y: rowY + 38, width: width - 112, height: 34)
                buttons[index].frame = CGRect(x: width - 70, y: rowY + 36, width: 38, height: 38)
                if row < count - 1 {
                    lines[section][row].frame = CGRect(x: 32, y: rowY + 77,
                                                        width: width - 64, height: 0.5)
                }
                index += 1
            }
            y += CGFloat(count) * 78 + 28
        }
        hint.frame = CGRect(x: 32, y: y, width: width - 64, height: 80)
        scroll.contentSize = CGSize(width: scroll.bounds.width, height: hint.frame.maxY + 20)
    }

    private func updateLabel(_ index: Int) {
        if index == 11 {
            labels[index].text = "\(titles[index])：\(String(format: "%.2f", Double(values[index]) / 100))×"
        } else if index == 8 {
            labels[index].text = "\(titles[index])：\(String(format: "%.2f", Double(values[index]) / 1000)) 秒"
        } else {
            labels[index].text = "\(titles[index])：\(values[index])\((1...4).contains(index) ? " 个" : " pt")"
        }
    }

    @objc private func valueChanged(_ slider: UISlider) {
        values[slider.tag] = Int(slider.value.rounded())
        updateLabel(slider.tag)
    }

    @objc private func valueFinished(_ slider: UISlider) {
        slider.value = slider.value.rounded()
        values[slider.tag] = Int(slider.value)
        updateLabel(slider.tag)
        defaults?.set(values[slider.tag], forKey: keys[slider.tag])
    }

    @objc private func editRingCount(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let index = gesture.view?.tag else { return }
        presentValueEditor(index)
    }

    @objc private func editValue(_ button: UIButton) { presentValueEditor(button.tag) }

    private func presentValueEditor(_ index: Int) {
        let range = index == 11 ? "范围 0.10–1.50×（输入 10–150%）" :
            "范围 \(Int(limits[index].0))–\(Int(limits[index].1))"
        let alert = UIAlertController(title: titles[index], message: range, preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .numbersAndPunctuation
            field.text = "\(self.values[index])"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let text = alert?.textFields?.first?.text,
                  let value = Int(text), value >= Int(self.limits[index].0),
                  value <= Int(self.limits[index].1) else { return }
            self.values[index] = value
            self.sliders[index].value = Float(value)
            self.updateLabel(index)
            self.defaults?.set(value, forKey: self.keys[index])
        })
        present(alert, animated: true)
    }
}
