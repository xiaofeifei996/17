import UIKit

@objc(PXCornerRadiusController)
public final class PXCornerRadiusController: UIViewController {
    private let slider = UISlider()
    private let number = UIButton(type: .system)
    private let caption = UILabel()
    private let hint = UILabel()
    private let shadowStrength = UISlider()
    private let shadowBlur = UISlider()
    private let shadowStrengthLabel = UILabel()
    private let shadowBlurLabel = UILabel()
    private let rightInset = UISlider()
    private let rightInsetLabel = UILabel()
    private let landscapeRightInset = UISlider()
    private let landscapeRightInsetLabel = UILabel()
    private let initialWidth = UISlider()
    private let initialWidthLabel = UILabel()
    private let portraitWidth = UISlider()
    private let portraitWidthLabel = UILabel()
    private let portraitLandscapeWidth = UISlider()
    private let portraitLandscapeWidthLabel = UILabel()
    private let resizeMax = UISlider()
    private let resizeMaxLabel = UILabel()
    private let portraitRadius = UISlider()
    private let portraitRadiusLabel = UILabel()
    private let portraitLandscapeRadius = UISlider()
    private let portraitLandscapeRadiusLabel = UILabel()
    private let scroll = UIScrollView()
    private var cards: [UIView] = []
    private var headings: [UILabel] = []
    private var lines: [UIView] = []
    private var inputButtons: [UISlider: UIButton] = [:]
    private let defaults = UserDefaults(suiteName: "com.moxuan.parallelx")

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "位置、圆角与阴影"
        view.backgroundColor = .systemGroupedBackground
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scroll)

        for title in ["初始位置与尺寸", "窗口圆角", "窗口阴影"] {
            headings.append(PXSettingsStyle.heading(title, in: scroll))
            cards.append(PXSettingsStyle.card(in: scroll))
        }

        lines = (0..<8).map { _ in
            PXSettingsStyle.separator(in: scroll)
        }

        caption.text = "圆角大小"
        caption.font = .preferredFont(forTextStyle: .body)
        scroll.addSubview(caption)

        slider.minimumValue = 0
        slider.maximumValue = 60
        slider.value = Float(
            defaults?.object(forKey: "cornerRadius") == nil
            ? 20
            : defaults?.double(forKey: "cornerRadius") ?? 20
        )

        slider.addTarget(
            self,
            action: #selector(valueChanged),
            for: .valueChanged
        )

        slider.addTarget(
            self,
            action: #selector(valueFinished),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )

        scroll.addSubview(slider)

        number.titleLabel?.font = .monospacedDigitSystemFont(
            ofSize: 17,
            weight: .medium
        )

        number.addGestureRecognizer(
            UILongPressGestureRecognizer(
                target: self,
                action: #selector(editNumber(_:))
            )
        )

        number.accessibilityHint = "长按输入圆角数值"
        scroll.addSubview(number)

        number.setImage(
            UIImage(systemName: "keyboard"),
            for: .normal
        )

        number.addTarget(
            self,
            action: #selector(editCorner),
            for: .touchUpInside
        )

        hint.text = "点击键盘按钮输入精确数值"
        hint.textColor = .secondaryLabel
        hint.font = .preferredFont(forTextStyle: .footnote)
        scroll.addSubview(hint)

        // Explicitly typed array to avoid Swift compiler type-check timeout.
        typealias SliderRow = (
            control: UISlider,
            label: UILabel,
            key: String,
            fallback: Float,
            maximum: Float
        )

        let sliderRows: [SliderRow] = [
            (
                shadowStrength,
                shadowStrengthLabel,
                "shadowStrength",
                22.0,
                50.0
            ),
            (
                shadowBlur,
                shadowBlurLabel,
                "shadowBlur",
                15.0,
                24.0
            ),
            (
                rightInset,
                rightInsetLabel,
                "initialRightInset",
                12.0,
                120.0
            ),
            (
                landscapeRightInset,
                landscapeRightInsetLabel,
                "landscapeInitialRightInset",
                Float(
                    (defaults?.object(
                        forKey: "initialRightInset"
                    ) as? NSNumber)?.intValue ?? 12
                ),
                120.0
            ),
            (
                initialWidth,
                initialWidthLabel,
                "initialWidthPercent",
                78.0,
                95.0
            ),
            (
                portraitWidth,
                portraitWidthLabel,
                "portraitInitialWidthPercent",
                Float(
                    (defaults?.object(
                        forKey: "initialWidthPercent"
                    ) as? NSNumber)?.intValue ?? 78
                ),
                95.0
            ),
            (
                portraitLandscapeWidth,
                portraitLandscapeWidthLabel,
                "portraitLandscapeInitialWidthPercent",
                Float(
                    (defaults?.object(
                        forKey: "portraitInitialWidthPercent"
                    ) as? NSNumber)?.intValue ?? 78
                ),
                95.0
            ),
            (
                resizeMax,
                resizeMaxLabel,
                "resizeMaxPercent",
                200.0,
                200.0
            ),
            (
                portraitRadius,
                portraitRadiusLabel,
                "portraitCornerRadius",
                Float(
                    (defaults?.object(
                        forKey: "cornerRadius"
                    ) as? NSNumber)?.intValue ?? 20
                ),
                60.0
            ),
            (
                portraitLandscapeRadius,
                portraitLandscapeRadiusLabel,
                "portraitLandscapeCornerRadius",
                Float(
                    (defaults?.object(
                        forKey: "portraitCornerRadius"
                    ) as? NSNumber)?.intValue ?? 20
                ),
                60.0
            )
        ]

        for row in sliderRows {
            let control = row.control
            let label = row.label
            let key = row.key
            let fallback = row.fallback
            let maximum = row.maximum

            label.font = .preferredFont(forTextStyle: .body)
            scroll.addSubview(label)

            if key == "resizeMaxPercent" {
                control.minimumValue = 100.0
            } else if key.contains("WidthPercent") {
                control.minimumValue = 35.0
            } else {
                control.minimumValue = 0.0
            }

            control.maximumValue = maximum

            if let value = defaults?.object(
                forKey: key
            ) as? NSNumber {
                control.value = value.floatValue
            } else {
                control.value = fallback
            }

            control.addTarget(
                self,
                action: #selector(shadowChanged),
                for: .valueChanged
            )

            control.addTarget(
                self,
                action: #selector(shadowFinished),
                for: [
                    .touchUpInside,
                    .touchUpOutside,
                    .touchCancel
                ]
            )

            scroll.addSubview(control)

            let buttonTitle: String

            switch key {
            case "shadowStrength":
                buttonTitle = "阴影强度（%）"

            case "shadowBlur":
                buttonTitle = "阴影模糊（pt）"

            case "initialRightInset",
                 "landscapeInitialRightInset":
                buttonTitle = "初始右边距（pt）"

            case "resizeMaxPercent":
                buttonTitle = "拖动缩放上限（%）"

            case "portraitCornerRadius":
                buttonTitle = "竖屏圆角（pt）"

            case "portraitLandscapeCornerRadius":
                buttonTitle = "竖屏横屏应用圆角（pt）"

            case "portraitInitialWidthPercent":
                buttonTitle = "竖屏初始尺寸（%）"

            case "portraitLandscapeInitialWidthPercent":
                buttonTitle = "竖屏横屏应用尺寸（%）"

            default:
                buttonTitle = "横屏初始尺寸（%）"
            }

            let button = PXSettingsStyle.inputButton(
                for: control,
                title: buttonTitle,
                in: self
            )

            scroll.addSubview(button)
            inputButtons[control] = button
        }

        valueChanged()
        shadowChanged()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = scroll.bounds.width

        let groups: [[(UILabel, UISlider)]] = [
            [
                (rightInsetLabel, rightInset),
                (landscapeRightInsetLabel, landscapeRightInset),
                (portraitWidthLabel, portraitWidth),
                (portraitLandscapeWidthLabel, portraitLandscapeWidth),
                (initialWidthLabel, initialWidth),
                (resizeMaxLabel, resizeMax)
            ],
            [
                (portraitRadiusLabel, portraitRadius),
                (portraitLandscapeRadiusLabel, portraitLandscapeRadius),
                (caption, slider)
            ],
            [
                (shadowStrengthLabel, shadowStrength),
                (shadowBlurLabel, shadowBlur)
            ]
        ]

        var y: CGFloat = 20
        var lineIndex = 0

        for (section, rows) in groups.enumerated() {
            headings[section].frame = CGRect(
                x: 32,
                y: y,
                width: width - 64,
                height: 22
            )

            y += 30

            let cardY = y

            cards[section].frame = CGRect(
                x: 16,
                y: cardY,
                width: width - 32,
                height: CGFloat(rows.count) * 82
            )

            for (row, pair) in rows.enumerated() {
                let rowY = cardY + CGFloat(row) * 82

                pair.0.frame = CGRect(
                    x: 32,
                    y: rowY + 10,
                    width: width - 64,
                    height: 28
                )

                pair.1.frame = CGRect(
                    x: 32,
                    y: rowY + 40,
                    width: width - 112,
                    height: 34
                )

                if pair.1 === slider {
                    number.frame = CGRect(
                        x: width - 70,
                        y: rowY + 36,
                        width: 38,
                        height: 38
                    )
                } else {
                    inputButtons[pair.1]?.frame = CGRect(
                        x: width - 70,
                        y: rowY + 36,
                        width: 38,
                        height: 38
                    )
                }

                if row < rows.count - 1 {
                    lines[lineIndex].frame = CGRect(
                        x: 32,
                        y: rowY + 81,
                        width: width - 64,
                        height: 0.5
                    )

                    lineIndex += 1
                }
            }

            y += CGFloat(rows.count) * 82 + 28
        }

        hint.frame = CGRect(
            x: 32,
            y: y - 18,
            width: width - 64,
            height: 32
        )

        scroll.contentSize = CGSize(
            width: width,
            height: hint.frame.maxY + 16
        )
    }

    @objc private func valueChanged() {
        caption.text =
            "横屏圆角：\(Int(slider.value.rounded())) pt"
    }

    @objc private func valueFinished() {
        slider.value = slider.value.rounded()
        valueChanged()

        defaults?.set(
            Int(slider.value),
            forKey: "cornerRadius"
        )
    }

    @objc private func shadowChanged() {
        shadowStrengthLabel.text =
            "阴影强度：\(Int(shadowStrength.value.rounded()))%"

        shadowBlurLabel.text =
            "阴影模糊：\(Int(shadowBlur.value.rounded())) pt"

        rightInsetLabel.text =
            "竖屏初始窗口距离右边缘：\(Int(rightInset.value.rounded())) pt"

        landscapeRightInsetLabel.text =
            "横屏初始窗口距离右边缘：\(Int(landscapeRightInset.value.rounded())) pt"

        initialWidthLabel.text =
            "横屏初始尺寸：屏幕高度的 \(Int(initialWidth.value.rounded()))%"

        portraitWidthLabel.text =
            "竖屏初始尺寸：屏幕宽度的 \(Int(portraitWidth.value.rounded()))%"

        portraitLandscapeWidthLabel.text =
            "竖屏横屏应用尺寸：屏幕宽度的 \(Int(portraitLandscapeWidth.value.rounded()))%"

        resizeMaxLabel.text =
            "分屏拖动最大尺寸：初始尺寸的 \(Int(resizeMax.value.rounded()))%"

        portraitRadiusLabel.text =
            "竖屏圆角：\(Int(portraitRadius.value.rounded())) pt"

        portraitLandscapeRadiusLabel.text =
            "竖屏横屏应用圆角：\(Int(portraitLandscapeRadius.value.rounded())) pt"
    }

    @objc private func shadowFinished() {
        shadowStrength.value = shadowStrength.value.rounded()
        shadowBlur.value = shadowBlur.value.rounded()
        rightInset.value = rightInset.value.rounded()
        landscapeRightInset.value =
            landscapeRightInset.value.rounded()
        initialWidth.value =
            initialWidth.value.rounded()
        portraitWidth.value =
            portraitWidth.value.rounded()
        portraitLandscapeWidth.value =
            portraitLandscapeWidth.value.rounded()
        resizeMax.value =
            resizeMax.value.rounded()
        portraitRadius.value =
            portraitRadius.value.rounded()
        portraitLandscapeRadius.value =
            portraitLandscapeRadius.value.rounded()

        shadowChanged()

        defaults?.set(
            Int(shadowStrength.value),
            forKey: "shadowStrength"
        )

        defaults?.set(
            Int(shadowBlur.value),
            forKey: "shadowBlur"
        )

        defaults?.set(
            Int(rightInset.value),
            forKey: "initialRightInset"
        )

        defaults?.set(
            Int(landscapeRightInset.value),
            forKey: "landscapeInitialRightInset"
        )

        defaults?.set(
            Int(initialWidth.value),
            forKey: "initialWidthPercent"
        )

        defaults?.set(
            Int(portraitWidth.value),
            forKey: "portraitInitialWidthPercent"
        )

        defaults?.set(
            Int(portraitLandscapeWidth.value),
            forKey: "portraitLandscapeInitialWidthPercent"
        )

        defaults?.set(
            Int(resizeMax.value),
            forKey: "resizeMaxPercent"
        )

        defaults?.set(
            Int(portraitRadius.value),
            forKey: "portraitCornerRadius"
        )

        defaults?.set(
            Int(portraitLandscapeRadius.value),
            forKey: "portraitLandscapeCornerRadius"
        )
    }

    @objc private func editCorner() {
        let alert = UIAlertController(
            title: "输入圆角",
            message: "请输入 0 到 60 之间的数值",
            preferredStyle: .alert
        )

        alert.addTextField { field in
            field.keyboardType = .decimalPad
            field.text = "\(Int(self.slider.value.rounded()))"
        }

        alert.addAction(
            UIAlertAction(
                title: "取消",
                style: .cancel
            )
        )

        alert.addAction(
            UIAlertAction(
                title: "确定",
                style: .default
            ) { [weak self, weak alert] _ in
                guard let self = self,
                      let text = alert?.textFields?.first?.text,
                      let value = Float(text)
                else {
                    return
                }

                self.slider.value = min(
                    60,
                    max(0, value)
                )

                self.valueFinished()
            }
        )

        present(alert, animated: true)
    }

    @objc private func editNumber(
        _ gesture: UILongPressGestureRecognizer
    ) {
        guard gesture.state == .began else {
            return
        }

        editCorner()
    }
}