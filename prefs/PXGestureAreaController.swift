import UIKit

@objc(PXGestureAreaController)
public final class PXGestureAreaController: UIViewController {
    private let defaults = UserDefaults(suiteName: "com.moxuan.parallelx")
    private let keys = ["gestureWidth", "gestureHeight", "gestureOffset",
                        "topGestureWidth", "topGestureHeight", "topGestureOffset"]
    private let titles = ["区域宽度", "区域高度", "垂直偏移", "区域宽度", "区域高度", "垂直偏移"]
    private let initial: [Float] = [300, 80, 0, 300, 80, 0]
    private let limits: [(Float, Float)] = [(120, 360), (36, 120), (-30, 40),
                                           (120, 360), (36, 120), (-30, 40)]
    private let labels = (0..<6).map { _ in UILabel() }
    private let sliders = (0..<6).map { _ in UISlider() }
    private let debugLabel = UILabel()
    private let debugSwitch = UISwitch()
    private let dockSwipeLabel = UILabel()
    private let dockSwipeSwitch = UISwitch()
    private let hint = UILabel()
    private let gestureCard = UIView()
    private let topCard = UIView()
    private let debugCard = UIView()
    private let gestureHeading = UILabel()
    private let topHeading = UILabel()
    private let debugHeading = UILabel()
    private let lines = (0..<4).map { _ in UIView() }
    private var inputButtons: [UIButton] = []
    private let scroll = UIScrollView()

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "手势区域"
        view.backgroundColor = .systemGroupedBackground
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scroll)
        for (label, title) in [(gestureHeading, "底部触发区域"),
                               (topHeading, "顶部触发区域"), (debugHeading, "调试")] {
            label.text = title
            label.font = .preferredFont(forTextStyle: .footnote)
            label.textColor = .secondaryLabel
            scroll.addSubview(label)
        }
        for card in [gestureCard, topCard, debugCard] {
            card.backgroundColor = .secondarySystemGroupedBackground
            card.layer.cornerRadius = 16
            card.layer.cornerCurve = .continuous
            scroll.addSubview(card)
        }
        for line in lines {
            line.backgroundColor = .separator
            scroll.addSubview(line)
        }
        for index in keys.indices {
            let label = labels[index]
            label.font = .preferredFont(forTextStyle: .body)
            scroll.addSubview(label)
            let slider = sliders[index]
            slider.tag = index
            slider.minimumValue = limits[index].0
            slider.maximumValue = limits[index].1
            slider.value = defaults?.object(forKey: keys[index]) == nil
                ? initial[index] : Float(defaults?.double(forKey: keys[index]) ?? Double(initial[index]))
            slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
            slider.addTarget(self, action: #selector(sliderFinished(_:)),
                             for: [.touchUpInside, .touchUpOutside, .touchCancel])
            scroll.addSubview(slider)
            let button = PXSettingsStyle.inputButton(for: slider, title: titles[index], in: self)
            scroll.addSubview(button)
            inputButtons.append(button)
            updateLabel(index)
        }
        debugLabel.text = "显示手势触发区域"
        debugLabel.font = .preferredFont(forTextStyle: .body)
        scroll.addSubview(debugLabel)
        dockSwipeLabel.text = "上滑及左右快滑停靠小窗"
        dockSwipeLabel.font = .preferredFont(forTextStyle: .body)
        scroll.addSubview(dockSwipeLabel)
        dockSwipeSwitch.isOn = defaults?.object(forKey: "dockSwipeEnabled") as? Bool ?? true
        dockSwipeSwitch.addTarget(self, action: #selector(dockSwipeChanged), for: .valueChanged)
        scroll.addSubview(dockSwipeSwitch)
        debugSwitch.isOn = defaults?.bool(forKey: "gestureDebug") ?? false
        debugSwitch.addTarget(self, action: #selector(debugChanged), for: .valueChanged)
        scroll.addSubview(debugSwitch)
        hint.text = "顶部和底部透明区域分别设置；双击关闭、长按全屏、拖动移动、下滑恢复初始位置与大小。底部快滑向左或向右，可停靠到对应的上角。区域尺寸更改在下次打开窗口时生效。"
        hint.textColor = .secondaryLabel
        hint.font = .preferredFont(forTextStyle: .footnote)
        hint.numberOfLines = 0
        scroll.addSubview(hint)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let top: CGFloat = 20
        gestureHeading.frame = CGRect(x: 32, y: top, width: width - 64, height: 22)
        gestureCard.frame = CGRect(x: 16, y: top + 30, width: width - 32, height: 320)
        dockSwipeLabel.frame = CGRect(x: 32, y: top + 292, width: width - 130, height: 36)
        dockSwipeSwitch.frame.origin = CGPoint(x: width - 32 - dockSwipeSwitch.bounds.width, y: top + 291)
        topHeading.frame = CGRect(x: 32, y: top + 378, width: width - 64, height: 22)
        topCard.frame = CGRect(x: 16, y: top + 408, width: width - 32, height: 234)
        for index in keys.indices {
            let y = top + 30 + CGFloat(index / 3) * 378 + CGFloat(index % 3) * 78
            labels[index].frame = CGRect(x: 32, y: y + 8, width: width - 64, height: 28)
            sliders[index].frame = CGRect(x: 32, y: y + 38, width: width - 112, height: 34)
            inputButtons[index].frame = CGRect(x: width - 70, y: y + 36, width: 38, height: 38)
            if index % 3 < 2 {
                lines[index - index / 3].frame = CGRect(x: 32, y: y + 77,
                                            width: width - 64, height: 0.5)
            }
        }
        let row = top + 670
        debugHeading.frame = CGRect(x: 32, y: row, width: width - 64, height: 22)
        debugCard.frame = CGRect(x: 16, y: row + 30, width: width - 32, height: 62)
        debugLabel.frame = CGRect(x: 32, y: row + 43, width: width - 130, height: 36)
        debugSwitch.frame.origin = CGPoint(x: width - 32 - debugSwitch.bounds.width, y: row + 42)
        hint.frame = CGRect(x: 32, y: row + 106, width: width - 64, height: 90)
        scroll.contentSize = CGSize(width: width, height: hint.frame.maxY + 24)
    }

    private func updateLabel(_ index: Int) {
        labels[index].text = "\(titles[index])：\(Int(sliders[index].value.rounded())) pt"
    }

    @objc private func sliderChanged(_ slider: UISlider) { updateLabel(slider.tag) }

    @objc private func sliderFinished(_ slider: UISlider) {
        slider.value = slider.value.rounded()
        updateLabel(slider.tag)
        defaults?.set(Int(slider.value), forKey: keys[slider.tag])
    }

    @objc private func debugChanged() {
        defaults?.set(debugSwitch.isOn, forKey: "gestureDebug")
    }

    @objc private func dockSwipeChanged() {
        defaults?.set(dockSwipeSwitch.isOn, forKey: "dockSwipeEnabled")
    }
}
