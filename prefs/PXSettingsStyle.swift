import UIKit

enum PXSettingsStyle {
    static func inputButton(for slider: UISlider, title: String, in controller: UIViewController) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "keyboard"), for: .normal)
        button.accessibilityLabel = "输入\(title)"
        button.addAction(UIAction { [weak controller, weak slider] _ in
            guard let controller = controller, let slider = slider else { return }
            let alert = UIAlertController(title: title,
                message: "范围 \(Int(slider.minimumValue))–\(Int(slider.maximumValue))", preferredStyle: .alert)
            alert.addTextField {
                $0.keyboardType = .numbersAndPunctuation
                $0.text = "\(Int(slider.value.rounded()))"
            }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak alert] _ in
                guard let text = alert?.textFields?.first?.text, let value = Float(text),
                      value.isFinite, value >= slider.minimumValue, value <= slider.maximumValue else { return }
                slider.value = value.rounded()
                slider.sendActions(for: .valueChanged)
                slider.sendActions(for: .touchUpInside)
            })
            controller.present(alert, animated: true)
        }, for: .touchUpInside)
        return button
    }

    static func card(in parent: UIView) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        parent.insertSubview(card, at: 0)
        return card
    }

    static func heading(_ title: String, in parent: UIView) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        parent.addSubview(label)
        return label
    }

    static func separator(in parent: UIView) -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        parent.addSubview(line)
        return line
    }
}
