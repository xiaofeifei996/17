import UIKit

@objc(PXDockController)
public final class PXDockController: UIViewController {
    private let defaults = UserDefaults(suiteName: "com.moxuan.parallelx")
    private let widthLabel = UILabel()
    private let widthSlider = UISlider()
    private let landscapeWidthLabel = UILabel()
    private let landscapeWidthSlider = UISlider()
    private let countLabel = UILabel()
    private let countSlider = UISlider()
    private let sideLabel = UILabel()
    private let sideControl = UISegmentedControl(items: ["左侧", "右侧"])
    private let autoParkLabel = UILabel()
    private let autoParkSwitch = UISwitch()
    private let card = UIView()
    private let heading = UILabel()
    private let lines = [UIView(), UIView(), UIView(), UIView()]
    private var inputButtons: [UIButton] = []
    private let scroll = UIScrollView()

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "角落小窗"
        view.backgroundColor = .systemGroupedBackground
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scroll)
        heading.text = "位置与容量"
        heading.font = .preferredFont(forTextStyle: .footnote)
        heading.textColor = .secondaryLabel
        scroll.addSubview(heading)
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        scroll.addSubview(card)
        for line in lines {
            line.backgroundColor = .separator
            scroll.addSubview(line)
        }
        for label in [widthLabel, landscapeWidthLabel, countLabel, sideLabel, autoParkLabel] {
            label.font = .preferredFont(forTextStyle: .body)
            scroll.addSubview(label)
        }
        sideLabel.text = "小窗默认放置位置"
        sideControl.selectedSegmentIndex = defaults?.integer(forKey: "dockSide") == -1 ? 0 : 1
        sideControl.addTarget(self, action: #selector(sideChanged), for: .valueChanged)
        scroll.addSubview(sideControl)
        autoParkLabel.text = "新开分屏时当前窗口变小窗"
        autoParkSwitch.isOn = defaults?.object(forKey: "autoParkOnNewSplit") as? Bool ?? true
        autoParkSwitch.addTarget(self, action: #selector(autoParkChanged), for: .valueChanged)
        scroll.addSubview(autoParkSwitch)
        widthSlider.minimumValue = 35
        widthSlider.maximumValue = 240
        widthSlider.value = Float(defaults?.object(forKey: "dockWidth") as? Int ?? 110)
        landscapeWidthSlider.minimumValue = 35
        landscapeWidthSlider.maximumValue = 240
        landscapeWidthSlider.value = Float(defaults?.object(forKey: "landscapeDockWidth") as? Int ?? Int(widthSlider.value))
        countSlider.minimumValue = 1
        countSlider.maximumValue = 4
        countSlider.value = Float(defaults?.object(forKey: "dockCount") as? Int ?? 2)
        for slider in [widthSlider, landscapeWidthSlider, countSlider] {
            slider.addTarget(self, action: #selector(changed), for: .valueChanged)
            slider.addTarget(self, action: #selector(finished),
                             for: [.touchUpInside, .touchUpOutside, .touchCancel])
            scroll.addSubview(slider)
            let name = slider === widthSlider ? "竖屏应用小窗宽度（pt）" : slider === landscapeWidthSlider ? "横屏应用小窗宽度（pt）" : "小窗数量"
            let button = PXSettingsStyle.inputButton(for: slider, title: name, in: self)
            scroll.addSubview(button)
            inputButtons.append(button)
        }
        changed()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let y: CGFloat = 20
        let width = view.bounds.width - 64
        heading.frame = CGRect(x: 32, y: y, width: width, height: 22)
        card.frame = CGRect(x: 16, y: y + 30, width: view.bounds.width - 32, height: 440)
        for row in 0..<5 {
            let rowY = y + 30 + CGFloat(row) * 88
            let label = [widthLabel, landscapeWidthLabel, countLabel, sideLabel, autoParkLabel][row]
            label.frame = CGRect(x: 32, y: rowY + 10,
                                 width: row == 4 ? width - 70 : width, height: 28)
            if row < 3 {
                [widthSlider, landscapeWidthSlider, countSlider][row].frame = CGRect(x: 32, y: rowY + 42,
                                                                 width: width - 48, height: 34)
                inputButtons[row].frame = CGRect(x: view.bounds.width - 70, y: rowY + 40, width: 38, height: 38)
                lines[row].frame = CGRect(x: 32, y: rowY + 87, width: width, height: 0.5)
            } else if row == 3 {
                sideControl.frame = CGRect(x: 32, y: rowY + 40, width: width, height: 36)
                lines[row].frame = CGRect(x: 32, y: rowY + 87, width: width, height: 0.5)
            } else {
                autoParkSwitch.frame = CGRect(x: view.bounds.width - 82, y: rowY + 20,
                                              width: 51, height: 31)
            }
        }
        scroll.contentSize = CGSize(width: view.bounds.width, height: card.frame.maxY + 24)
    }

    @objc private func changed() {
        widthLabel.text = "竖屏应用小窗宽度：\(Int(widthSlider.value.rounded())) pt"
        landscapeWidthLabel.text = "横屏应用小窗宽度：\(Int(landscapeWidthSlider.value.rounded())) pt"
        countLabel.text = "最多保留：\(Int(countSlider.value.rounded())) 个小窗"
    }

    @objc private func finished() {
        widthSlider.value = widthSlider.value.rounded()
        landscapeWidthSlider.value = landscapeWidthSlider.value.rounded()
        countSlider.value = countSlider.value.rounded()
        defaults?.set(Int(widthSlider.value), forKey: "dockWidth")
        defaults?.set(Int(landscapeWidthSlider.value), forKey: "landscapeDockWidth")
        defaults?.set(Int(countSlider.value), forKey: "dockCount")
        changed()
    }

    @objc private func sideChanged() {
        defaults?.set(sideControl.selectedSegmentIndex == 0 ? -1 : 1, forKey: "dockSide")
    }

    @objc private func autoParkChanged() {
        defaults?.set(autoParkSwitch.isOn, forKey: "autoParkOnNewSplit")
    }
}
