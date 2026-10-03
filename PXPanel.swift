import UIKit

private let preferenceDomain = "com.moxuan.parallelx"
private enum PXMotion {
    private static let defaults = UserDefaults(suiteName: preferenceDomain)
    private static var speed: TimeInterval {
        let saved = defaults?.object(forKey: "animationSpeedPercent") as? Int ?? 100
        return Double(min(150, max(10, saved))) / 100
    }

    static func ease(_ duration: TimeInterval, delay: TimeInterval = 0,
                     options: UIView.AnimationOptions = .curveEaseOut,
                     animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : duration / speed,
                       delay: UIAccessibility.isReduceMotionEnabled ? 0 : delay / speed,
                       options: [options, .allowUserInteraction, .beginFromCurrentState],
                       animations: animations, completion: completion)
    }

    static func spring(_ duration: TimeInterval, animations: @escaping () -> Void,
                       completion: ((Bool) -> Void)? = nil) {
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : duration / speed,
                       delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 2,
                       options: [.allowUserInteraction, .beginFromCurrentState],
                       animations: animations, completion: completion)
    }

    static func rotation(_ card: UIView, from frame: CGRect, in oldBounds: CGRect, to newBounds: CGRect,
                         oldOrientation: UIInterfaceOrientation, newOrientation: UIInterfaceOrientation) {
        guard !UIAccessibility.isReduceMotionEnabled, oldBounds.width > 0, oldBounds.height > 0,
              frame.width > 0, frame.height > 0, card.frame.width > 0, card.frame.height > 0,
              card.window?.isHidden == false else { return }
        let start = CGPoint(x: newBounds.minX + (frame.midX - oldBounds.minX) / oldBounds.width * newBounds.width,
                            y: newBounds.minY + (frame.midY - oldBounds.minY) / oldBounds.height * newBounds.height)
        let scale = min(2, max(0.5, sqrt(frame.width * frame.height / (card.frame.width * card.frame.height))))
        let landscape = oldOrientation.isLandscape ? oldOrientation : newOrientation
        let turn: CGFloat = oldOrientation.isLandscape != newOrientation.isLandscape
            ? (landscape == .landscapeLeft ? -1 : 1) * (oldOrientation.isLandscape ? 1 : -1) * .pi / 2 : 0
        let position = CABasicAnimation(keyPath: "position")
        position.fromValue = NSValue(cgPoint: start)
        position.toValue = NSValue(cgPoint: card.layer.position)
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: CATransform3DRotate(
            CATransform3DScale(card.layer.transform, scale, scale, 1), turn, 0, 0, 1))
        transform.toValue = NSValue(caTransform3D: card.layer.transform)
        let animation = CAAnimationGroup()
        animation.animations = [position, transform]
        animation.duration = 0.32 / speed
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        card.layer.removeAnimation(forKey: "pxHostGeometry")
        card.layer.add(animation, forKey: "pxScreenRotation")
    }

    static func geometry(_ card: UIView, from frame: CGRect, duration: TimeInterval = 0.28,
                         cornerRadius: CGFloat? = nil) {
        guard !UIAccessibility.isReduceMotionEnabled, frame.width > 0, frame.height > 0,
              card.frame.width > 0, card.frame.height > 0, card.window?.isHidden == false else { return }
        let position = CABasicAnimation(keyPath: "position")
        position.fromValue = NSValue(cgPoint: CGPoint(x: frame.midX, y: frame.midY))
        position.toValue = NSValue(cgPoint: card.layer.position)
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: CATransform3DScale(card.layer.transform,
            frame.width / card.frame.width, frame.height / card.frame.height, 1))
        transform.toValue = NSValue(caTransform3D: card.layer.transform)
        let animation = CAAnimationGroup()
        animation.animations = [position, transform]
        animation.duration = duration / speed
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        if let cornerRadius = cornerRadius {
            let corners = CABasicAnimation(keyPath: "cornerRadius")
            corners.fromValue = cornerRadius
            corners.toValue = card.layer.cornerRadius
            animation.animations?.append(corners)
            corners.duration = animation.duration
            corners.timingFunction = animation.timingFunction
            card.subviews.first?.layer.add(corners, forKey: "pxHostCorners")
        }
        card.layer.removeAnimation(forKey: "pxScreenRotation")
        card.layer.add(animation, forKey: "pxHostGeometry")
    }
}
private let shortcuts: [(id: String, name: String, symbol: String)] = [
    ("px.action.dark", "深色模式", "moon.fill"),
    ("px.action.record", "屏幕录制", "record.circle"),
    ("px.action.rotation", "方向锁定", "lock.rotation"),
    ("px.action.window", "切换全屏/分屏（长按停靠小窗/交换窗口）", "rectangle.on.rectangle"),
    ("px.action.screenshot", "截屏（长按仅复制）", "camera.viewfinder"),
    ("px.action.recent", "最近打开的应用", "clock.arrow.circlepath"),
    ("px.action.kayoko", "呼出 Kayoko", "doc.on.clipboard"),
    ("px.action.brightness", "调节亮度（长按并上下拖动）", "sun.max.fill"),
    ("px.action.restart", "重新打开应用", "arrow.clockwise"),
    ("px.action.search", "搜索（长按选择应用）", "magnifyingglass")
]

private func isShortcut(_ id: String) -> Bool {
    id.hasPrefix("px.action.") || id.hasPrefix("px.url.") || id.hasPrefix("px.recent.") || id.hasPrefix("px.custom.")
}

private func configuredAction(_ id: String) -> [String: Any]? {
    (UserDefaults(suiteName: preferenceDomain)?.array(forKey: "customActions") as? [[String: Any]])?
        .first { $0["id"] as? String == id }
}

private func applicationID(_ id: String) -> String? {
    if id.hasPrefix("px.recent.") {
        let parts = id.split(separator: ".", maxSplits: 3)
        return parts.count == 4 ? String(parts[3]) : nil
    }
    return isShortcut(id) ? nil : id
}

private func panelIcon(_ id: String) -> UIImage? {
    if id.hasPrefix("px.recent.") {
        let parts = id.split(separator: ".", maxSplits: 3)
        if parts.count == 4 { return PXApplicationIcon(String(parts[3])) }
    }
    if isShortcut(id) {
        let defaults = UserDefaults(suiteName: preferenceDomain)
        let key = id.hasPrefix("px.recent.") ? "px.action.recent" : id
        let custom = (defaults?.dictionary(forKey: "shortcutSymbols") as? [String: String])?[key]
        let fallback = shortcuts.first(where: { $0.id == key })?.symbol ??
            (id.hasPrefix("px.custom.") ? "square.stack.3d.up" : "link")
        return UIImage(systemName: custom ?? fallback) ?? UIImage(systemName: fallback)
    }
    return PXApplicationIcon(id)
}

private func panelPreviewIcon(_ id: String) -> UIImage? {
    if id.hasPrefix("px.recent.") {
        let parts = id.split(separator: ".", maxSplits: 3)
        if parts.count == 4 { return PXApplicationIconLarge(String(parts[3])) }
    }
    return isShortcut(id) ? panelIcon(id) : PXApplicationIconLarge(id)
}

private final class PXHandleWindow: PXOverlayWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result === self || result === rootViewController?.view ? nil : result
    }
}

private final class PXHostViewController: UIViewController {
    var onLayout: (() -> Void)?
    var onAppearance: (() -> Void)?
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onLayout?()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle { onAppearance?() }
    }
}

private final class PXDockedHost {
    let window: UIWindow
    let card: UIView
    let canvas: UIView
    let bridge: PXSceneBridge
    let bundleID: String
    var side: Int
    let originalCornerRadius: CGFloat
    let corners: [UIView]
    let topCorners: [UIView]
    let topGrip: UIView?
    let moveGrip: UIView?
    let overlay: UIView
    var loading: Bool
    var fullscreenHandoffInProgress = false

    init(window: UIWindow, card: UIView, canvas: UIView, bridge: PXSceneBridge,
         bundleID: String, side: Int, corners: [UIView], topCorners: [UIView],
         topGrip: UIView?, moveGrip: UIView?, overlay: UIView, loading: Bool) {
        self.window = window
        self.card = card
        self.canvas = canvas
        self.bridge = bridge
        self.bundleID = bundleID
        self.side = side
        self.originalCornerRadius = card.layer.cornerRadius
        self.corners = corners
        self.topCorners = topCorners
        self.topGrip = topGrip
        self.moveGrip = moveGrip
        self.overlay = overlay
        self.loading = loading
    }
}

private final class PXPanelViewController: UIViewController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
    var apps: [(id: String, name: String)] = []
    var onBrightnessHold: ((CGPoint) -> Void)?
    var onProgress: ((CGFloat) -> Void)?
    var handleCenterY: CGFloat = 0
    var handleCenterX: CGFloat = 0
    var holdDuration: TimeInterval = 0.7
    private let shade = UIView()
    private let pageControl = UIPageControl()
    private let selectionPreview = UIImageView()
    private let brightnessOverlay = UIView()
    private let brightnessTrack = UIView()
    private let brightnessFill = UIView()
    private let brightnessPercent = UILabel()
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let holdFeedback = UIImpactFeedbackGenerator(style: .medium)
    private var buttons: [UIButton] = []
    private var buttonRings: [Int] = []
    private var selectedIndex: Int?
    private var selectedSince: CFTimeInterval?
    private var lastSelectionPoint = CGPoint.zero
    private var holdFeedbackTask: DispatchWorkItem?
    private var fullscreenReadyView: UIView?
    private var groupMenu: UIView?
    private var groupScroll: UIScrollView?
    private var groupRows: [UILabel] = []
    private var groupItems: [[String: Any]] = []
    private var groupSelected: Int?
    private var groupOriginY: CGFloat = 0
    private var groupCancel: UILabel?
    var groupMenuActive: Bool { groupMenu != nil }
    private var appSelector: PXAppSelectorView?
    var appSelectorActive: Bool { appSelector != nil }
    var selectedIndexedApp: String? { appSelector?.selectedApp }
    func updateAppSelector(at point: CGPoint) { appSelector?.update(at: point) }
    private var page = 0
    private var pageCapacity = 1
    private var lastSize = CGSize.zero
    private var progress: CGFloat = 0
    private var opening = false
    private let defaults = UserDefaults(suiteName: preferenceDomain)
    private var iconSize: CGFloat {
        min(72, max(36, CGFloat(defaults?.object(forKey: "launcherIconSize") as? Int ?? 52)))
    }
    private var edgeInset: CGFloat {
        min(120, max(0, CGFloat(defaults?.object(forKey: "launcherEdgeInset") as? Int ?? 6)))
    }
    private var ringGap: CGFloat {
        min(60, max(0, CGFloat(defaults?.object(forKey: "launcherRingGap") as? Int ?? 10)))
    }
    private var ringCounts: [Int] {
        Array([3, 5, 7, 9].enumerated().map { index, fallback in
            min(max(1, apps.count), max(0, defaults?.object(forKey: "launcherRing\(index + 1)") as? Int ?? fallback))
        }.prefix(while: { $0 > 0 }))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        shade.backgroundColor = UIColor.black.withAlphaComponent(0.14)
        view.addSubview(shade)
        pageControl.isUserInteractionEnabled = false
        pageControl.hidesForSinglePage = true
        view.addSubview(pageControl)
        selectionPreview.backgroundColor = .systemGray5
        selectionPreview.contentMode = .scaleAspectFill
        selectionPreview.layer.cornerRadius = 26
        selectionPreview.layer.borderWidth = 6
        selectionPreview.layer.borderColor = UIColor.systemGray5.cgColor
        selectionPreview.clipsToBounds = true
        selectionPreview.isUserInteractionEnabled = false
        selectionPreview.alpha = 0
        view.addSubview(selectionPreview)
        brightnessOverlay.backgroundColor = .secondarySystemBackground
        brightnessOverlay.layer.cornerRadius = 30
        brightnessOverlay.isHidden = true
        let sun = UIImageView(image: UIImage(systemName: "sun.max.fill"))
        sun.tintColor = .label
        sun.contentMode = .scaleAspectFit
        sun.frame = CGRect(x: 42, y: 22, width: 28, height: 28)
        brightnessOverlay.addSubview(sun)
        brightnessTrack.backgroundColor = .systemGray4
        brightnessTrack.layer.cornerRadius = 22
        brightnessTrack.clipsToBounds = true
        brightnessTrack.frame = CGRect(x: 34, y: 64, width: 44, height: 172)
        brightnessOverlay.addSubview(brightnessTrack)
        brightnessFill.backgroundColor = .label
        brightnessTrack.addSubview(brightnessFill)
        brightnessPercent.font = .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        brightnessPercent.textAlignment = .center
        brightnessPercent.frame = CGRect(x: 0, y: 252, width: 112, height: 24)
        brightnessOverlay.addSubview(brightnessPercent)
        view.addSubview(brightnessOverlay)
        if apps.isEmpty {
            let label = UILabel()
            label.text = "请先在设置中添加应用"
            label.textColor = .secondaryLabel
            label.font = .preferredFont(forTextStyle: .body)
            label.textAlignment = .center
            label.frame = CGRect(x: 20, y: view.bounds.midY - 30,
                                 width: view.bounds.width - 40, height: 60)
            label.autoresizingMask = [.flexibleWidth, .flexibleTopMargin, .flexibleBottomMargin]
            view.addSubview(label)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        shade.frame = view.bounds
        if let selector = appSelector {
            selector.frame = view.bounds
            return
        }
        pageControl.frame = CGRect(x: view.bounds.width - 110,
                                   y: min(view.bounds.maxY - 42,
                                          handleCenterY + min(300, view.bounds.height * 0.38)),
                                   width: 100, height: 26)
        selectionPreview.frame = CGRect(x: view.bounds.midX - 55,
                                        y: max(view.safeAreaInsets.top + 24, view.bounds.height * 0.2 - 55),
                                        width: 110, height: 110)
        brightnessOverlay.frame = CGRect(x: view.bounds.midX - 56,
                                         y: view.bounds.midY - 148, width: 112, height: 296)
        guard lastSize != view.bounds.size else { return }
        lastSize = view.bounds.size
        layoutPage()
    }

    func setProgress(_ progress: CGFloat) {
        self.progress = min(1, max(0, progress))
        onProgress?(self.progress)
        guard appSelector == nil else { return }
        shade.alpha = self.progress
        for (index, button) in buttons.enumerated() {
            let step = CGFloat(buttonRings[index]) * 0.12
            let amount = min(1, max(0, (self.progress - step) / (1 - step)))
            button.alpha = amount
            button.transform = CGAffineTransform(translationX: (handleCenterX - button.center.x) * (1 - amount),
                                                 y: (handleCenterY - button.center.y) * (1 - amount))
                .scaledBy(x: 0.72 + 0.28 * amount, y: 0.72 + 0.28 * amount)
        }
        pageControl.alpha = self.progress
        selectionPreview.alpha = selectedIndex == nil ? 0 : self.progress
    }

    func completeOpening() {
        guard !opening else { return }
        opening = true
        PXMotion.spring(0.23) { self.setProgress(1) }
    }

    private func layoutPage() {
        cancelSelectionFeedback()
        selectedIndex = nil
        selectedSince = nil
        selectionPreview.alpha = 0
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        buttonRings.removeAll()
        let size = iconSize
        let spacing = size + 10
        let ringSpacing = size + ringGap
        let centerY = handleCenterY == 0 ? view.bounds.midY : handleCenterY
        let maxRadius = min(view.bounds.width - size - edgeInset - 16,
                            min(centerY - view.safeAreaInsets.top - size / 2 - 12,
                                view.bounds.maxY - view.safeAreaInsets.bottom - centerY - size / 2 - 12))
        let angle: CGFloat = .pi / 2
        var rings: [(count: Int, radius: CGFloat)] = []
        var previousRadius: CGFloat = 0
        for requested in ringCounts {
            let desiredRadius = requested == 1 ? 0 :
                spacing / (2 * sin(.pi / (2 * CGFloat(requested - 1))))
            let radius = max(size * 1.2,
                             max(previousRadius + (rings.isEmpty ? 0 : ringSpacing),
                                 min(desiredRadius, maxRadius)))
            guard radius <= maxRadius else { break }
            let fits = radius + 0.01 >= desiredRadius ? requested :
                Int((.pi / (2 * asin(min(1, spacing / (2 * radius))))).rounded(.down)) + 1
            rings.append((min(requested, fits), radius))
            previousRadius = radius
        }
        pageCapacity = max(1, rings.reduce(0) { $0 + $1.count })
        pageControl.numberOfPages = rings.isEmpty ? 1 : max(1, (apps.count + pageCapacity - 1) / pageCapacity)
        page = min(page, pageControl.numberOfPages - 1)
        pageControl.currentPage = page
        var appIndex = page * pageCapacity
        let end = min(apps.count, appIndex + pageCapacity)
        let centerX = view.bounds.maxX - size / 2 - edgeInset
        for (ringIndex, ring) in rings.enumerated() {
            let count = min(ring.count, end - appIndex)
            guard count > 0 else { break }
            for slot in 0..<count {
                let theta = count == 1 ? 0 : -angle + 2 * angle * CGFloat(slot) / CGFloat(count - 1)
                let center = CGPoint(x: centerX - ring.radius * cos(theta),
                                     y: centerY + ring.radius * sin(theta))
                let button = UIButton(type: .custom)
                button.frame = CGRect(x: center.x - size / 2, y: center.y - size / 2,
                                      width: size, height: size)
                button.tag = appIndex
                button.accessibilityLabel = apps[appIndex].name
                let id = apps[appIndex].id
                let action = isShortcut(id) && !id.hasPrefix("px.recent.") ||
                    (id.hasPrefix("px.recent.") && id.split(separator: ".", maxSplits: 3).count < 4)
                let active = action && PXSceneBridge.shared().shortcutIsActive(id)
                button.backgroundColor = active ? UIColor(white: 0.42, alpha: 1) : .systemGray5
                button.layer.cornerRadius = size / 2
                button.layer.shadowColor = UIColor.black.cgColor
                button.layer.shadowOpacity = 0.12
                button.layer.shadowRadius = 5
                button.layer.shadowOffset = CGSize(width: 0, height: 2)
                let icon = UIImageView(image: panelIcon(id)?.withConfiguration(
                    UIImage.SymbolConfiguration(pointSize: size * 0.43, weight: .medium)) ?? UIImage(systemName: "app"))
                icon.frame = button.bounds.insetBy(dx: 4, dy: 4)
                icon.tintColor = active ? .white : .label
                icon.contentMode = action ? .center : .scaleAspectFill
                icon.layer.cornerRadius = (size - 8) / 2
                icon.clipsToBounds = true
                icon.isUserInteractionEnabled = false
                button.addSubview(icon)
                view.addSubview(button)
                buttons.append(button)
                buttonRings.append(ringIndex)
                appIndex += 1
            }
        }
        view.bringSubviewToFront(selectionPreview)
        setProgress(progress)
    }

    func advancePage(forDrag verticalDistance: CGFloat) {
        let next = min(pageControl.numberOfPages - 1, max(0, Int(-verticalDistance / 150)))
        guard next > page else { return }
        page = next
        layoutPage()
    }

    func updateSelection(at point: CGPoint) -> String? {
        lastSelectionPoint = point
        let hit = buttons.reversed().first {
            $0.frame.insetBy(dx: -4, dy: -4).contains(point)
        }
        let next = hit?.tag
        if next != selectedIndex {
            holdFeedbackTask?.cancel()
            fullscreenReadyView?.removeFromSuperview()
            fullscreenReadyView = nil
            if let selectedIndex = selectedIndex,
               let old = buttons.first(where: { $0.tag == selectedIndex }) {
                PXMotion.ease(0.13) { old.subviews.first?.transform = .identity }
            }
            selectedIndex = next
            selectedSince = next.map { applicationID(apps[$0].id) != nil || ["px.action.screenshot", "px.action.window"].contains(apps[$0].id) } == true ? CACurrentMediaTime() : nil
            if let hit = hit, let next = next {
                selectionFeedback.selectionChanged()
                selectionFeedback.prepare()
                let id = apps[next].id
                let group = configuredAction(id)
                if applicationID(id) != nil || id == "px.action.brightness" || id == "px.action.screenshot" || id == "px.action.window" || id == "px.action.search" || group?["kind"] as? String == "group" {
                    holdFeedback.prepare()
                    let task = DispatchWorkItem { [weak self] in
                        guard let self = self, self.selectedIndex == next else { return }
                        self.holdFeedback.impactOccurred()
                        if id == "px.action.brightness" {
                            self.onBrightnessHold?(self.lastSelectionPoint)
                        } else if id == "px.action.search" {
                            self.showAppSelector(at: self.lastSelectionPoint)
                        } else if group?["kind"] as? String == "group" {
                            self.showGroupMenu(group?["items"] as? [[String: Any]] ?? [], at: self.lastSelectionPoint)
                        } else if applicationID(id) != nil {
                            self.animateFullscreenReady()
                        }
                    }
                    holdFeedbackTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration, execute: task)
                }
                let symbol = isShortcut(id) && (!id.hasPrefix("px.recent.") ||
                    id.split(separator: ".", maxSplits: 3).count < 4)
                let preview = panelPreviewIcon(id)
                selectionPreview.image = (symbol ? preview?.withConfiguration(
                    UIImage.SymbolConfiguration(pointSize: 52, weight: .medium)) : preview) ??
                    UIImage(systemName: "app")
                selectionPreview.contentMode = symbol ? .center : .scaleAspectFill
                selectionPreview.tintColor = PXSceneBridge.shared().shortcutIsActive(id) ? .white : .label
                selectionPreview.backgroundColor = PXSceneBridge.shared().shortcutIsActive(id) ?
                    UIColor(white: 0.42, alpha: 1) : .systemGray5
                selectionPreview.transform = CGAffineTransform(scaleX: 0.76, y: 0.76)
                PXMotion.spring(0.23) {
                    hit.subviews.first?.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
                    self.selectionPreview.transform = .identity
                    self.selectionPreview.alpha = self.progress
                }
            } else {
                PXMotion.ease(0.10) { self.selectionPreview.alpha = 0 }
            }
        }
        return next.map { apps[$0].id }
    }

    var selectedDuration: CFTimeInterval {
        selectedSince.map { CACurrentMediaTime() - $0 } ?? 0
    }

    private func animateFullscreenReady() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let trail = UIView(frame: view.bounds.insetBy(dx: 8, dy: 8))
        trail.isUserInteractionEnabled = false
        trail.backgroundColor = .clear
        trail.layer.cornerRadius = 40
        trail.layer.cornerCurve = .continuous
        trail.layer.borderWidth = 6
        trail.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.85).cgColor
        trail.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.14)
        trail.transform = CGAffineTransform(translationX: selectionPreview.center.x - view.bounds.midX,
                                            y: selectionPreview.center.y - view.bounds.midY)
            .scaledBy(x: 110 / trail.bounds.width, y: 110 / trail.bounds.height)
        view.addSubview(trail)
        fullscreenReadyView = trail
        PXMotion.ease(0.44, animations: {
            trail.transform = .identity
            trail.alpha = 0
        }, completion: { [weak self, weak trail] _ in
            trail?.removeFromSuperview()
            if self?.fullscreenReadyView === trail { self?.fullscreenReadyView = nil }
        })
    }

    func cancelSelectionFeedback() {
        holdFeedbackTask?.cancel()
        fullscreenReadyView?.removeFromSuperview()
        fullscreenReadyView = nil
    }

    private func showAppSelector(at point: CGPoint) {
        guard appSelector == nil else { return }
        cancelSelectionFeedback()
        buttons.forEach { $0.alpha = 0 }
        selectionPreview.alpha = 0
        pageControl.alpha = 0
        let selector = PXAppSelectorView(frame: view.bounds, point: point)
        shade.alpha = 0
        appSelector = selector
        view.addSubview(selector)
        selector.alpha = 0
        selector.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        PXMotion.ease(0.18) {
            selector.alpha = 1
            selector.transform = .identity
        }
    }

    private func showGroupMenu(_ items: [[String: Any]], at point: CGPoint) {
        guard !items.isEmpty else { return }
        cancelSelectionFeedback()
        groupItems = items
        buttons.forEach { $0.alpha = 0 }
        selectionPreview.alpha = 0
        pageControl.alpha = 0
        shade.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        let menu = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        menu.layer.cornerRadius = 24
        menu.layer.cornerCurve = .continuous
        menu.layer.borderWidth = 1 / UIScreen.main.scale
        menu.layer.borderColor = UIColor.separator.cgColor
        menu.clipsToBounds = true
        let font = UIFont.preferredFont(forTextStyle: .body)
        let widest = items.map { (($0["title"] as? String ?? "快捷指令") as NSString)
            .size(withAttributes: [.font: font]).width }.max() ?? 0
        let width = min(view.bounds.width - 48, max(150, ceil(widest) + 32))
        let availableHeight = max(96, view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom - 20)
        let height = min(availableHeight, CGFloat(min(6, items.count)) * 52 + 104)
        let top = view.safeAreaInsets.top + 10
        let bottom = view.bounds.maxY - view.safeAreaInsets.bottom - 10
        menu.frame = CGRect(x: view.bounds.maxX - width - 10,
                            y: min(max(top, handleCenterY - height / 2), bottom - height),
                            width: width, height: height)
        let heading = UILabel(frame: CGRect(x: 16, y: 0, width: width - 32, height: 56))
        heading.text = "上下滑动选择，松手运行"
        heading.textAlignment = .center
        heading.numberOfLines = 2
        heading.font = .preferredFont(forTextStyle: .footnote)
        heading.textColor = .secondaryLabel
        menu.contentView.addSubview(heading)
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 56, width: width, height: height - 104))
        scroll.isUserInteractionEnabled = false
        scroll.contentSize = CGSize(width: width, height: CGFloat(items.count) * 52)
        menu.contentView.addSubview(scroll)
        groupRows = items.enumerated().map { index, entry in
            let label = UILabel(frame: CGRect(x: 0, y: CGFloat(index) * 52, width: width, height: 52))
            label.text = entry["title"] as? String ?? "快捷指令"
            label.textAlignment = .center
            label.font = font
            label.textColor = .label
            let separator = UIView(frame: CGRect(x: 16, y: 51, width: width - 32, height: 1 / UIScreen.main.scale))
            separator.backgroundColor = .separator
            label.addSubview(separator)
            scroll.addSubview(label)
            return label
        }
        let cancel = UILabel(frame: CGRect(x: 0, y: height - 48, width: width, height: 48))
        cancel.text = "取消"
        cancel.textAlignment = .center
        cancel.textColor = .systemRed
        cancel.font = .preferredFont(forTextStyle: .body)
        cancel.accessibilityTraits = .button
        menu.contentView.addSubview(cancel)
        view.addSubview(menu)
        groupMenu = menu
        groupScroll = scroll
        groupCancel = cancel
        groupOriginY = menu.frame.midY
        menu.alpha = 0
        menu.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        PXMotion.ease(0.18) {
            menu.alpha = 1; menu.transform = .identity
        }
        updateGroupSelection(at: point)
    }

    func updateGroupSelection(at point: CGPoint) {
        lastSelectionPoint = point
        guard let menu = groupMenu, let scroll = groupScroll else { return }
        let local = menu.convert(point, from: view)
        guard menu.bounds.contains(local) else {
            groupSelected = nil
            groupRows.forEach { $0.backgroundColor = .clear; $0.textColor = .label }
            groupCancel?.backgroundColor = .clear
            return
        }
        let delta = point.y - groupOriginY
        let step = min(36, max(8, scroll.bounds.height / CGFloat(groupItems.count + 1)))
        let row = min(groupItems.count, max(0, groupItems.count / 2 + Int(delta / step)))
        let moved = abs(delta) >= 8
        let next: Int? = moved && groupItems.indices.contains(row) ? row : nil
        if next != groupSelected {
            selectionFeedback.selectionChanged()
            groupSelected = next
        }
        for (index, label) in groupRows.enumerated() {
            label.backgroundColor = index == next ? UIColor.systemBlue.withAlphaComponent(0.16) : .clear
            label.textColor = index == next ? .systemBlue : .label
        }
        groupCancel?.backgroundColor = moved && row == groupItems.count ?
            UIColor.systemRed.withAlphaComponent(0.12) : .clear
        if let next = next { scroll.scrollRectToVisible(groupRows[next].frame, animated: false) }
    }

    var selectedGroupAction: [String: Any]? { groupSelected.map { groupItems[$0] } }

    func showBrightness(_ value: CGFloat) {
        cancelSelectionFeedback()
        buttons.forEach { $0.alpha = 0 }
        selectionPreview.alpha = 0
        pageControl.alpha = 0
        shade.backgroundColor = UIColor.black.withAlphaComponent(0.48)
        brightnessOverlay.isHidden = false
        updateBrightness(value)
    }

    func updateBrightness(_ value: CGFloat) {
        let amount = min(1, max(0, value))
        let height = brightnessTrack.bounds.height * amount
        brightnessFill.frame = CGRect(x: 0, y: brightnessTrack.bounds.height - height,
                                      width: brightnessTrack.bounds.width, height: height)
        brightnessPercent.text = "亮度 \(Int((amount * 100).rounded()))%"
    }

    func animateClosed(completion: @escaping () -> Void) {
        cancelSelectionFeedback()
        let duration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.20
        let outer = buttonRings.max() ?? 0
        for (index, button) in buttons.enumerated() {
            PXMotion.ease(duration, delay: Double(outer - buttonRings[index]) * 0.028,
                          options: .curveEaseIn) {
                button.alpha = 0
                button.transform = CGAffineTransform(translationX: self.handleCenterX - button.center.x,
                                                     y: self.handleCenterY - button.center.y)
                    .scaledBy(x: 0.72, y: 0.72)
            }
        }
        PXMotion.ease(duration + Double(outer) * 0.028, options: .curveEaseIn, animations: {
            self.onProgress?(0)
            self.shade.alpha = 0
            self.pageControl.alpha = 0
            self.selectionPreview.alpha = 0
            self.brightnessOverlay.alpha = 0
            self.groupMenu?.alpha = 0
            self.appSelector?.alpha = 0
        }, completion: { _ in completion() })
    }
}

private final class PXAppSelectorView: UIView {
    private typealias App = (id: String, name: String)
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let scroll = UIScrollView()
    private let heading = UILabel()
    private let glow = CAGradientLayer()
    private let glowMask = CAShapeLayer()
    private let feedback = UISelectionFeedbackGenerator()
    private var groups: [String: [App]] = [:]
    private var letters: [String] = []
    private var letterLabels: [UILabel] = []
    private var tiles: [UIView] = []
    private var currentApps: [App] = []
    private var currentLetter = ""
    private var railSelection = PXAppRailSelection()
    private var selected: Int?
    private let entryPoint: CGPoint
    private var lastPoint = CGPoint.zero
    private var rail = CGRect.zero
    private var railBaseX: CGFloat = 0
    private var railBow: CGFloat = 0
    private var laidOutSize = CGSize.zero
    var selectedApp: String? { selected.map { currentApps[$0].id } }

    init(frame: CGRect, point: CGPoint) {
        entryPoint = point
        super.init(frame: frame)
        isUserInteractionEnabled = false // The original handle drag owns this entire interaction.
        lastPoint = point
        backgroundColor = .clear
        isOpaque = false
        blur.alpha = 0.46
        addSubview(blur)
        scroll.isUserInteractionEnabled = false
        scroll.clipsToBounds = true
        addSubview(scroll)
        heading.font = .systemFont(ofSize: 54, weight: .light)
        heading.textColor = .label
        heading.textAlignment = .center
        addSubview(heading)
        glow.colors = [UIColor.systemBlue.withAlphaComponent(0).cgColor,
                       UIColor.systemCyan.cgColor, UIColor.systemBlue.cgColor,
                       UIColor.systemPurple.withAlphaComponent(0).cgColor]
        glowMask.fillColor = nil
        glowMask.strokeColor = UIColor.white.cgColor
        glowMask.lineWidth = 3
        glowMask.lineCap = .round
        glow.mask = glowMask
        layer.addSublayer(glow)
        feedback.prepare()
        // Catalogue work stays off the gesture's main-thread path. Icons load only for the visible letter.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let apps = PXInstalledApplications().compactMap { item -> App? in
                guard let id = item["id"], let name = item["name"] else { return nil }
                return (id, name)
            }
            let groups = Dictionary(grouping: apps, by: { PXAppInitial($0.name) })
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.superview != nil else { return }
                self.groups = groups
                self.letters = groups.keys.sorted { $0 == "#" ? false : ($1 == "#" || $0 < $1) }
                self.letterLabels = self.letters.map { letter in
                    let label = UILabel()
                    label.text = letter
                    label.textAlignment = .center
                    label.font = .systemFont(ofSize: 11, weight: .semibold)
                    label.textColor = .secondaryLabel
                    self.addSubview(label)
                    return label
                }
                self.setNeedsLayout()
                self.layoutIfNeeded()
                let point = self.lastPoint
                let indexY = min(self.rail.maxY, max(self.rail.minY, point.y))
                self.update(at: CGPoint(x: self.railX(at: indexY), y: indexY))
                self.update(at: point)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        let top = safeAreaInsets.top + 16
        let bottom = bounds.height - safeAreaInsets.bottom - 20
        let available = max(1, bottom - top)
        railBaseX = bounds.width - safeAreaInsets.right - 22
        railBow = min(52, bounds.width * 0.12)
        let railHeight = min(430, available * 0.60)
        rail = CGRect(x: railBaseX - railBow - 22,
                      y: top + (available - railHeight) * 0.54,
                      width: railBow + 44, height: railHeight)
        heading.frame = CGRect(x: safeAreaInsets.left + bounds.width * 0.08,
                               y: rail.midY - 40, width: bounds.width * 0.18, height: 80)
        for (index, label) in letterLabels.enumerated() {
            let step = rail.height / CGFloat(max(1, letters.count))
            let y = rail.minY + (CGFloat(index) + 0.5) * step
            label.transform = .identity
            label.bounds = CGRect(x: 0, y: 0, width: 28, height: max(14, step))
            label.center = CGPoint(x: railX(at: y), y: y)
        }
        if laidOutSize != bounds.size {
            laidOutSize = bounds.size
            renderApps()
        }
        updateLight(at: railSelection.locked ? (letterLabels.first { $0.text == currentLetter }?.center.y ?? lastPoint.y) : lastPoint.y)
    }

    private func renderApps() {
        tiles.forEach { $0.removeFromSuperview() }
        selected = nil
        let top = safeAreaInsets.top + 16
        let bottom = bounds.height - safeAreaInsets.bottom - 20
        let rows = max(1, (currentApps.count + 2) / 3)
        let width = min(260, bounds.width * 0.46)
        let cellWidth = PXAppGridCell(count: currentApps.count, width: width, height: bottom - top)
        let height = CGFloat(rows) * cellWidth
        scroll.frame = CGRect(x: railBaseX - railBow - 14 - cellWidth * 3,
                              y: min(max(top, rail.midY - height / 2), bottom - height),
                              width: cellWidth * 3, height: height)
        scroll.contentOffset = .zero
        let iconSize = min(48, cellWidth * 0.62)
        let rowHeight = cellWidth
        tiles = currentApps.enumerated().map { index, app in
            let tile = UIView(frame: CGRect(x: CGFloat(index % 3) * cellWidth,
                                           y: CGFloat(index / 3) * rowHeight,
                                           width: cellWidth, height: rowHeight))
            tile.layer.cornerRadius = 14
            let icon = UIImageView(image: PXApplicationIconLarge(app.id) ?? UIImage(systemName: "app"))
            icon.frame = CGRect(x: (cellWidth - iconSize) / 2, y: (cellWidth - iconSize) / 2,
                                width: iconSize, height: iconSize)
            icon.contentMode = .scaleAspectFit
            icon.layer.cornerRadius = iconSize * 0.225
            icon.clipsToBounds = true
            tile.addSubview(icon)
            tile.accessibilityLabel = app.name
            tile.accessibilityTraits = .button
            scroll.addSubview(tile)
            return tile
        }
        scroll.contentSize = CGSize(width: scroll.bounds.width,
                                    height: CGFloat((currentApps.count + 2) / 3) * rowHeight)
    }

    func update(at point: CGPoint) {
        lastPoint = point
        guard !letters.isEmpty else { return }
        if let index = railSelection.update(point: point, rail: rail, railX: railX(at: point.y), count: letters.count) {
            let letter = letters[index]
            if letter != currentLetter {
                currentLetter = letter
                currentApps = groups[letter] ?? []
                scroll.contentOffset = .zero
                renderApps()
                scroll.alpha = 0.55
                PXMotion.ease(0.16) { self.scroll.alpha = 1 }
                feedback.selectionChanged()
                feedback.prepare()
            }
            setSelection(nil)
            heading.text = letter
            updateLight(at: point.y)
            return
        }
        if railSelection.locked, let label = letterLabels.first(where: { $0.text == currentLetter }) {
            updateLight(at: label.center.y)
        }
        guard scroll.frame.contains(point), hypot(point.x - entryPoint.x, point.y - entryPoint.y) >= 12 else {
            setSelection(nil)
            return
        }
        let local = scroll.convert(point, from: self)
        setSelection(tiles.firstIndex { $0.frame.contains(local) })
    }

    private func setSelection(_ next: Int?) {
        guard next != selected else { return }
        selected = next
        feedback.selectionChanged()
        feedback.prepare()
        heading.text = currentLetter
        PXMotion.spring(0.20) {
            for (index, tile) in self.tiles.enumerated() {
                tile.backgroundColor = index == next ? UIColor.systemBlue.withAlphaComponent(0.15) : .clear
                tile.subviews.first?.transform = index == next ? CGAffineTransform(scaleX: 1.3, y: 1.3) : .identity
            }
        }
    }

    private func railX(at y: CGFloat) -> CGFloat {
        PXAppRailX(base: railBaseX, bow: railBow, progress: (y - rail.minY) / max(1, rail.height))
    }

    private func updateLight(at y: CGFloat) {
        let y = min(rail.maxY, max(rail.minY, y))
        let radius = min(70, rail.height / 4)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.frame = CGRect(x: rail.minX, y: y - radius, width: rail.width, height: radius * 2)
        let path = UIBezierPath()
        for step in 0...24 {
            let sampleY = min(rail.maxY, max(rail.minY, y - radius + CGFloat(step) * radius * 2 / 24))
            let point = CGPoint(x: railX(at: sampleY) - glow.frame.minX, y: sampleY - glow.frame.minY)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        glowMask.frame = glow.bounds
        glowMask.path = path.cgPath
        glow.isHidden = letters.isEmpty || UIAccessibility.isReduceMotionEnabled
        CATransaction.commit()
        for label in letterLabels {
            let amount = max(0, 1 - abs(label.center.y - y) / max(1, radius))
            label.transform = CGAffineTransform(scaleX: 1 + 0.5 * amount, y: 1 + 0.5 * amount)
            label.textColor = amount > 0.6 ? .systemBlue : .secondaryLabel
        }
    }
}

private final class PXSearchViewController: UIViewController, UITableViewDataSource, UITextFieldDelegate {
    var onSelect: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    private let backdrop = UIView()
    private let card = UIView()
    private let field = UISearchTextField()
    private let table = UITableView()
    private let apps = PXInstalledApplications().compactMap { item -> (id: String, name: String)? in
        guard let id = item["id"], let name = item["name"] else { return nil }
        return (id, name)
    }
    private var matches: [(id: String, name: String)] = []
    private var keyboardFrame: CGRect?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.08)
        backdrop.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissSearch)))
        view.addSubview(backdrop)
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        view.addSubview(card)
        field.placeholder = "搜索应用"
        field.returnKeyType = .search
        field.delegate = self
        field.addTarget(self, action: #selector(filterApps), for: .editingChanged)
        card.addSubview(field)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.dataSource = self
        table.rowHeight = 60
        table.keyboardDismissMode = .none
        card.addSubview(table)
        matches = apps
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop.frame = view.bounds
        let bottom = keyboardFrame.map { max(0, view.convert($0, from: nil).minY) } ??
            view.bounds.height - view.safeAreaInsets.bottom
        let height = min(330, max(190, bottom * 0.45))
        card.frame = CGRect(x: 12, y: bottom - height - 8,
                            width: view.bounds.width - 24, height: height)
        field.frame = CGRect(x: 16, y: 12, width: card.bounds.width - 32, height: 40)
        table.frame = CGRect(x: 12, y: 60, width: card.bounds.width - 24,
                             height: card.bounds.height - 68)
    }

    func focus() {
        view.layoutIfNeeded()
        card.alpha = 0
        card.transform = CGAffineTransform(translationX: 0, y: 28)
        view.alpha = 1
        field.becomeFirstResponder()
        PXMotion.spring(0.25) {
            self.card.alpha = 1
            self.card.transform = .identity
        }
    }

    @objc private func keyboardChanged(_ note: Notification) {
        guard let rect = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        keyboardFrame = rect
        PXMotion.ease(0.22) { self.view.setNeedsLayout(); self.view.layoutIfNeeded() }
    }

    @objc private func filterApps() {
        let query = field.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        matches = query.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }
        table.reloadData()
    }

    @objc private func dismissSearch() { onDismiss?() }

    @objc private func openResult(_ sender: UIButton) {
        guard matches.indices.contains(sender.tag) else { return }
        onSelect?(matches[sender.tag].id)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let first = matches.first { onSelect?(first.id) }
        return true
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        (matches.count + 1) / 2
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "results") ??
            UITableViewCell(style: .default, reuseIdentifier: "results")
        cell.selectionStyle = .none
        cell.backgroundColor = .clear
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        for index in (indexPath.row * 2)..<min(matches.count, indexPath.row * 2 + 2) {
            let app = matches[index]
            let button = UIButton(type: .system)
            button.tag = index
            button.setTitle(app.name, for: .normal)
            if let icon = PXApplicationIcon(app.id) {
                let size = CGSize(width: 32, height: 32)
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    icon.draw(in: CGRect(origin: .zero, size: size))
                }
                button.setImage(image.withRenderingMode(.alwaysOriginal), for: .normal)
            }
            button.imageView?.contentMode = .scaleAspectFit
            button.titleLabel?.font = .systemFont(ofSize: 14)
            button.setTitleColor(.label, for: .normal)
            button.contentHorizontalAlignment = .left
            button.semanticContentAttribute = .forceLeftToRight
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 7)
            button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 7, bottom: 0, right: 0)
            button.backgroundColor = .tertiarySystemBackground
            button.layer.cornerRadius = 12
            button.addTarget(self, action: #selector(openResult(_:)), for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        if matches.count == indexPath.row * 2 + 1 { row.addArrangedSubview(UIView()) }
        cell.contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -6),
            row.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 3),
            row.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -3)
        ])
        return cell
    }
}

@objc(PXPanelEntry)
public final class PXPanelEntry: NSObject {
    private static let shared = PXPanelEntry()
    private var handleWindow: PXHandleWindow?
    private var panelWindow: UIWindow?
    private var searchWindow: UIWindow?
    private weak var searchPreviousKeyWindow: UIWindow?
    private var hostWindow: UIWindow?
    private var hostCard: UIView?
    private var hostCorners: [UIView] = []
    private var hostTopCorners: [UIView] = []
    private var dockedHosts: [PXDockedHost] = []
    private var activeBridge: PXSceneBridge = .shared()
    private var hostMoveGrip: UIView?
    private var hostTopGrip: UIView?
    private weak var hostCanvas: UIView?
    private var panel: PXPanelViewController?
    private var handle: UIView?
    private var hostedBundleID: String?
    private var hostLayoutSourceSize = CGSize.zero
    private var fullscreenToWindowInProgress = false
    private var fullscreenLaunchInProgress = false
    private var externalPendingBundleID: String?
    private var panelFrontmostBundleID: String?
    private var dockAfterOpenBundleID: String?
    private var fullscreenAfterOpenBundleID: String?
    private var pendingSwap: (foreground: String, host: String)?
    private var resizeStartFrame: CGRect?
    private var resizeStartRadius: CGFloat = 0
    private var resizePreview: (scale: CGFloat, x: CGFloat, y: CGFloat)?
    private var moveStartFrame: CGRect?
    private var launchMovedCenter: CGPoint?
    private var launchWidthScale: CGFloat?
    private var needsHostRefresh = false
    private var deviceLocked = false
    private var coverSheetVisible = false
    private var coverSheetPresented = false
    private var coverSheetEntering = false
    private var coverSheetWindowLevel: UIWindow.Level?
    private var panelDragProgress: CGFloat = 0
    private var handleDragMode = 0 // 0 undecided, 1 panel, 2 vertical placement
    private var handleDragStartY: CGFloat = 0
    private var brightnessStart: (y: CGFloat, value: CGFloat)?
    private var keyboardDismissWindow: UIWindow?
    private var keyboardDismissSuppressed = false
    private var keyboardHideInFlight = false
    private var keyboardDismissFadingOut = false
    private var keyboardAnimationDuration: TimeInterval = 0.25
    private var keyboardAnimationOptions: UIView.AnimationOptions = [.beginFromCurrentState, .allowUserInteraction]
    private var layoutScreenBounds = CGRect.zero
    private var layoutOrientation = UIInterfaceOrientation.unknown
    private var applyingScreenGeometry = false
    private var keyboardFocusBase: CGRect?
    private var keyboardFocusFrame = CGRect.null
    private var keyboardFocusRadius: CGFloat = 20

    @objc public static func hasVisibleHost() -> Bool {
        shared.hostWindow?.isHidden == false || shared.dockedHosts.contains { !$0.window.isHidden }
    }

    @objc public static func isInteractiveHostedURLSource(_ bundleID: String) -> Bool {
        guard Thread.isMainThread, !shared.deviceLocked, !shared.coverSheetVisible,
              shared.hostedBundleID == bundleID,
              shared.hostWindow?.isHidden == false,
              shared.hostWindow?.isUserInteractionEnabled == true else { return false }
        return shared.activeBridge.hasHostedSurface()
    }

    @objc public static func start() {
        NotificationCenter.default.addObserver(shared,
            selector: #selector(sceneActivated), name: UIScene.didActivateNotification, object: nil)
        NotificationCenter.default.addObserver(shared,
            selector: #selector(sceneDeactivated), name: UIScene.willDeactivateNotification, object: nil)
        shared.installHandle()
        NotificationCenter.default.addObserver(shared, selector: #selector(screenGeometryChanged),
            name: Notification.Name("PXScreenGeometryChanged"), object: nil)
        NotificationCenter.default.addObserver(shared, selector: #selector(hostedGeometryChanged(_:)),
            name: Notification.Name("PXHostedGeometryChanged"), object: nil)
        NotificationCenter.default.addObserver(shared, selector: #selector(hostedKeyboardChanged(_:)),
            name: Notification.Name("PXKeyboardStateChanged"), object: nil)
        for name in [Notification.Name("PXKeyboardFrameChanged"), UIResponder.keyboardWillChangeFrameNotification,
                     UIResponder.keyboardWillShowNotification, UIResponder.keyboardWillHideNotification,
                     UIResponder.keyboardDidShowNotification, UIResponder.keyboardDidChangeFrameNotification,
                     UIResponder.keyboardDidHideNotification] {
            NotificationCenter.default.addObserver(shared, selector: #selector(keyboardFrameChanged(_:)), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(shared,
            selector: #selector(lockStateChanged), name: Notification.Name("PXLockStateChanged"), object: nil)
    }

    @objc public static func updateCaptureVisibility() {
        let hide = UserDefaults(suiteName: preferenceDomain)?.bool(forKey: "hideForScreenshot") == true
        if let handle = shared.handle { PXSceneBridge.setCaptureHidden(hide, for: handle) }
        if let view = shared.panel?.view { PXSceneBridge.setCaptureHidden(hide, for: view) }
        shared.layoutHostControls()
        shared.activeBridge.refreshKeyboardPlacement()
        shared.refreshKeyboardDismissLayer()
    }

    @objc public static func applicationActivated(_ bundleID: String) {
        let clear = {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if shared.hostedBundleID == bundleID, shared.hostWindow != nil,
                   !shared.fullscreenToWindowInProgress, !shared.fullscreenLaunchInProgress,
                   PXSceneBridge.shared().frontmostBundleID() == bundleID {
                    shared.closeHost(animated: false, fullscreenHandoff: true)
                }
            }
            for dock in shared.dockedHosts.filter({ $0.bundleID == bundleID && !$0.fullscreenHandoffInProgress }) {
                shared.removeDock(dock, fullscreenHandoff: true)
            }
        }
        if Thread.isMainThread { clear() }
        else { DispatchQueue.main.async(execute: clear) }
    }

    @objc public static func frontDisplayChanged(_ bundleID: String?) {
        // The first app activation can arrive while Cover Sheet is still sliding in.
        if bundleID != nil, bundleID != "com.apple.springboard",
           shared.coverSheetVisible, !shared.coverSheetPresented, !shared.coverSheetEntering {
            shared.coverSheetVisible = false
            shared.updateHandleVisibility()
        }
        if shared.fullscreenToWindowInProgress && bundleID != shared.hostedBundleID {
            shared.fullscreenToWindowInProgress = false
            shared.layoutHostControls()
        }
        if let bundleID = bundleID { applicationActivated(bundleID) }
        if let swap = shared.pendingSwap, bundleID == swap.foreground {
            shared.pendingSwap = nil
            shared.panelFrontmostBundleID = nil
            shared.openHost(swap.host)
        }
    }

    @objc public static func switcherRemovedApplication(_ bundleID: String) {
        guard !bundleID.isEmpty else { return }
        if shared.hostedBundleID == bundleID { shared.closeHost(animated: false) }
        for dock in Array(shared.dockedHosts) where dock.bundleID == bundleID {
            shared.removeDock(dock)
        }
    }

    @objc public static func closeSplitAfterExcludedURL() {
        shared.closeHost(animated: true)
    }

    @objc public static func externalOpenApplication(_ bundleID: String) {
        guard !shared.deviceLocked, shared.activeScene() != nil else { return }
        shared.externalPendingBundleID = bundleID
        // A URL target already displayed fullscreen needs the normal surface
        // handoff. A different fullscreen app must remain untouched underneath.
        shared.panelFrontmostBundleID = PXSceneBridge.shared().frontmostBundleID()
        shared.openHost(bundleID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard shared.externalPendingBundleID == bundleID else { return }
            shared.externalPendingBundleID = nil
            guard shared.hostedBundleID == bundleID, shared.hostWindow != nil else { return }
            shared.closeHost(animated: false)
            _ = PXSceneBridge.shared().openFullscreenApplication(bundleID)
        }
    }

    private func externalOpenFailed(_ bundleID: String) {
        guard externalPendingBundleID == bundleID else { return }
        externalPendingBundleID = nil
        _ = PXSceneBridge.shared().openFullscreenApplication(bundleID)
    }

    @objc private func lockStateChanged(_ notification: Notification) {
        let locked = notification.userInfo?["locked"] as? Bool ?? false
        guard locked != deviceLocked else { return }
        deviceLocked = locked
        updateHandleVisibility()
        if locked {
            if UserDefaults(suiteName: preferenceDomain)?.bool(forKey: "clearOnLock") == true {
                closeHost(animated: false)
                for dock in Array(dockedHosts) { removeDock(dock) }
                return
            }
            hostWindow?.isHidden = true
            if hostWindow != nil {
                needsHostRefresh = true
                activeBridge.close()
            }
            for dock in dockedHosts {
                dock.window.isHidden = true
                dock.overlay.isHidden = true
                dock.bridge.close()
            }
        } else {
            refreshHost()
            guard let controls = handleWindow?.rootViewController?.view else { return }
            for dock in dockedHosts {
                dock.bridge.openApplication(dock.bundleID, in: dock.canvas,
                                            keyboardOverlay: controls) { [weak self, weak dock] success in
                    guard let dock = dock, self?.dockedHosts.contains(where: { $0 === dock }) == true else { return }
                    if success {
                        dock.loading = false
                        dock.window.isHidden = false
                        dock.overlay.isHidden = false
                        dock.bridge.layoutHost()
                    } else { self?.removeDock(dock) }
                }
            }
        }
    }

    @objc private func sceneDeactivated(_ notification: Notification) {
        if (notification.object as? UIWindowScene) === hostWindow?.windowScene {
            needsHostRefresh = true
        }
    }

    @objc private func sceneActivated(_ notification: Notification) {
        installHandle()
        if (notification.object as? UIWindowScene) === hostWindow?.windowScene {
            if fullscreenToWindowInProgress, PXSceneBridge.shared().frontmostBundleID() != hostedBundleID {
                fullscreenToWindowInProgress = false
            }
            refreshHost()
        }
        if !dockedHosts.isEmpty { layoutDocks() }
    }

    private func refreshHost() {
        guard !deviceLocked, needsHostRefresh, let window = hostWindow,
              let bundleID = hostedBundleID, let canvas = hostCanvas,
              let controls = handleWindow?.rootViewController?.view else { return }
        if activeBridge.hasHostedSurface(), !window.isHidden {
            needsHostRefresh = false
            return
        }
        if fullscreenToWindowInProgress { return }
        needsHostRefresh = false
        canvas.isUserInteractionEnabled = false
        activeBridge.openApplication(bundleID, in: canvas,
                                               keyboardOverlay: controls) { [weak self, weak window] success in
            guard let self = self, self.hostWindow === window else { return }
            if success {
                self.activeBridge.layoutHost()
                self.hostCard?.alpha = 1
                self.hostCard?.transform = .identity
                canvas.isUserInteractionEnabled = true
                window?.isUserInteractionEnabled = true
                window?.isHidden = false
            }
            else { self.closeHost(animated: false) }
        }
    }

    private func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let main = scenes.first(where: { $0.session.persistentIdentifier == "com.apple.springboard" }) { return main }
        if let main = scenes.first(where: { NSStringFromClass(type(of: $0)) == "SBWindowScene" }) { return main }
        return scenes.first {
            let kind = ($0.session.persistentIdentifier + NSStringFromClass(type(of: $0))).lowercased()
            return $0.activationState == .foregroundActive && !kind.contains("keyboard") && !kind.contains("aperture")
        }
    }

    @objc private func screenGeometryChanged() {
        guard !applyingScreenGeometry, handleWindow != nil else { return }
        guard let scene = handleWindow?.windowScene else { return }
        let orientation = PXSceneBridge.systemOrientation()
        let physical = scene.screen.fixedCoordinateSpace.bounds.size
        let expectedSize = orientation.isLandscape
            ? CGSize(width: max(physical.width, physical.height), height: min(physical.width, physical.height))
            : CGSize(width: min(physical.width, physical.height), height: max(physical.width, physical.height))
        if expectedSize == layoutScreenBounds.size && orientation == layoutOrientation { return }
        let oldBounds = layoutScreenBounds
        let oldOrientation = layoutOrientation
        let rotating = orientation != layoutOrientation && layoutOrientation != .unknown
        let cards = ([hostCard].compactMap { $0 } + dockedHosts.map { $0.card }).map { ($0, $0.frame) }
        applyingScreenGeometry = true
        defer { applyingScreenGeometry = false }
        UIView.performWithoutAnimation {
            ([handleWindow, hostWindow, panelWindow, searchWindow, keyboardDismissWindow].compactMap { $0 } +
                dockedHosts.map { $0.window }).forEach { ($0 as? PXOverlayWindow)?.applySystemOrientation() }
        }
        let screen = handleWindow?.rootViewController?.view.bounds ?? scene.coordinateSpace.bounds
        guard screen != layoutScreenBounds || orientation != layoutOrientation else { return }
        layoutScreenBounds = screen
        layoutOrientation = orientation
        resizePreview = nil
        resizeStartFrame = nil
        moveStartFrame = nil
        keyboardFocusBase = nil
        keyboardFocusFrame = .null
        hostCard?.transform = .identity
        updateHandleAppearance()
        panel?.handleCenterX = handle?.center.x ?? screen.maxX
        panel?.handleCenterY = handle?.center.y ?? screen.midY
        panel?.view.setNeedsLayout()
        // Home can rotate to portrait during the handoff. The hosted scene
        // keeps its direction, but its card must enter the new screen bounds.
        UIView.performWithoutAnimation { matchHostAspect() }
        activeBridge.refreshHostedOrientationMap()
        activeBridge.refreshKeyboardPlacement()
        layoutDocks(animated: false)
        refreshKeyboardDismissLayer()
        if rotating && !fullscreenToWindowInProgress {
            for (card, frame) in cards {
                PXMotion.rotation(card, from: frame, in: oldBounds, to: screen,
                                  oldOrientation: oldOrientation, newOrientation: orientation)
            }
        }
    }

    @objc private func hostedGeometryChanged(_ notification: Notification) {
        let ownScene = (notification.object as? PXSceneBridge) === activeBridge
        let source = activeBridge.hostedSourceSize()
        let orientationChanged = hostLayoutSourceSize.width > 0 && source.width > 0 &&
            (hostLayoutSourceSize.width > hostLayoutSourceSize.height) != (source.width > source.height)
        let card = hostCard
        let oldFrame = card?.layer.presentation()?.frame ?? card?.frame
        UIView.performWithoutAnimation {
            if ownScene && !fullscreenToWindowInProgress { matchHostAspect() }
            for dock in dockedHosts { dock.bridge.layoutHost() }
            layoutDocks(animated: false)
        }
        if ownScene, orientationChanged, !fullscreenToWindowInProgress,
           PXSceneBridge.systemOrientation() == layoutOrientation,
           hostCanvas?.isUserInteractionEnabled == true, let card = card, let oldFrame = oldFrame {
            PXMotion.geometry(card, from: oldFrame)
        }
    }

    private func installHandle() {
        if handleWindow != nil { updateHandleAppearance(); return }
        guard let scene = activeScene() else { return }
        let window = PXHandleWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .alert + 51
        window.backgroundColor = .clear
        let root = PXHostViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        window.applySystemOrientation()
        root.onLayout = { [weak self] in self?.screenGeometryChanged() }
        root.onAppearance = { [weak self] in self?.refreshHostedAppearance() }
        let pill = UIView(frame: .zero)
        pill.backgroundColor = .secondarySystemBackground
        pill.layer.cornerCurve = .continuous
        pill.layer.borderWidth = 1 / UIScreen.main.scale
        pill.layer.borderColor = UIColor.separator.cgColor
        pill.layer.shadowColor = UIColor.black.cgColor
        pill.layer.shadowOpacity = 0.18
        pill.layer.shadowRadius = 6
        pill.layer.shadowOffset = CGSize(width: -2, height: 1)
        pill.autoresizingMask = []
        let mark = UIView(frame: .zero)
        mark.backgroundColor = UIColor.label.withAlphaComponent(0.55)
        mark.layer.cornerRadius = 2
        pill.addSubview(mark)
        pill.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragHandle(_:))))
        root.view.addSubview(pill)
        window.isHidden = false
        handle = pill
        handleWindow = window
        layoutScreenBounds = root.view.bounds
        layoutOrientation = PXSceneBridge.systemOrientation()
        updateHandleAppearance()
    }

    @objc private func outsideKeyboardTapped() { closeHost(animated: true) }

    @objc private func hostedKeyboardChanged(_ notification: Notification) {
        guard (notification.object as? PXSceneBridge) === activeBridge else { return }
        let visible = activeBridge.isHostedKeyboardVisible()
        if !visible && !keyboardHideInFlight { removeKeyboardDismissLayer() }
        keyboardDismissSuppressed = keyboardHideInFlight || !visible
        refreshKeyboardDismissLayer()
    }

    @objc private func keyboardFrameChanged(_ notification: Notification) {
        if notification.name == UIResponder.keyboardWillChangeFrameNotification || notification.name == UIResponder.keyboardWillShowNotification || notification.name == UIResponder.keyboardWillHideNotification {
            keyboardAnimationDuration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
            let curve = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 7
            keyboardAnimationOptions = [.beginFromCurrentState, .allowUserInteraction,
                                        UIView.AnimationOptions(rawValue: curve << 16)]
            if let end = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardDismissSuppressed = end.intersection(UIScreen.main.bounds).height < 30
            }
            if notification.name == UIResponder.keyboardWillHideNotification {
                keyboardHideInFlight = true
                keyboardDismissSuppressed = true
            }
            if notification.name == UIResponder.keyboardWillShowNotification {
                keyboardHideInFlight = false
                keyboardDismissSuppressed = false
            }
        } else if notification.name == UIResponder.keyboardDidHideNotification {
            keyboardHideInFlight = true
            keyboardDismissSuppressed = true
        } else if notification.name == UIResponder.keyboardDidShowNotification {
            keyboardHideInFlight = false
            keyboardDismissSuppressed = false
        } else if notification.name == Notification.Name("PXKeyboardStateChanged"),
                  !keyboardHideInFlight, activeBridge.isHostedKeyboardVisible() {
            keyboardDismissSuppressed = false
        }
        refreshKeyboardDismissLayer()
    }

    @objc private func refreshKeyboardDismissLayer() {
        updateKeyboardFocus()
        let defaults = UserDefaults(suiteName: preferenceDomain)
        let enabled = defaults?.object(forKey: "closeOutsideWithKeyboard") == nil ||
            defaults?.bool(forKey: "closeOutsideWithKeyboard") == true
        guard enabled, activeBridge.usesExternalKeyboard(), !deviceLocked,
              !keyboardHideInFlight, !keyboardDismissSuppressed, activeBridge.isHostedKeyboardVisible(),
              activeBridge.isKeyboardRelocated(),
              let host = hostWindow, let scene = host.windowScene else {
            fadeKeyboardDismissLayer()
            return
        }
        if keyboardDismissWindow == nil {
            let window = PXOverlayWindow(windowScene: scene)
            window.alpha = 0
            window.backgroundColor = .clear
            let root = UIViewController()
            let layer = UIControl()
            layer.backgroundColor = .clear
            layer.accessibilityLabel = "双击关闭分屏"
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(outsideKeyboardTapped))
            doubleTap.numberOfTapsRequired = 2
            layer.addGestureRecognizer(doubleTap)
            root.view = layer
            window.rootViewController = root
            window.applySystemOrientation()
            keyboardDismissWindow = window
        }
        (keyboardDismissWindow as? PXOverlayWindow)?.applySystemOrientation()
        keyboardDismissWindow?.windowLevel = host.windowLevel - 0.5
        keyboardDismissWindow?.isHidden = false
        let configured = (defaults?.object(forKey: "keyboardDimOpacity") as? NSNumber)?.doubleValue ?? 0.12
        let dim = min(0.6, max(0, configured))
        keyboardDismissWindow?.rootViewController?.view.backgroundColor = UIColor.black.withAlphaComponent(dim)
        if let window = keyboardDismissWindow, window.alpha < 1 || keyboardDismissFadingOut {
            keyboardDismissFadingOut = false
            UIView.animate(withDuration: keyboardAnimationDuration, delay: 0,
                           options: keyboardAnimationOptions) { window.alpha = 1 }
        }
    }

    private func fadeKeyboardDismissLayer() {
        guard let window = keyboardDismissWindow, !keyboardDismissFadingOut else { return }
        keyboardDismissFadingOut = true
        UIView.animate(withDuration: keyboardAnimationDuration, delay: 0,
                       options: keyboardAnimationOptions) { window.alpha = 0 } completion: { [weak self, weak window] _ in
            guard let self = self, let window = window, self.keyboardDismissFadingOut,
                  self.keyboardDismissWindow === window else { return }
            self.removeKeyboardDismissLayer()
        }
    }

    private func removeKeyboardDismissLayer() {
        keyboardDismissFadingOut = false
        keyboardDismissWindow?.isHidden = true
        keyboardDismissWindow?.rootViewController = nil
        keyboardDismissWindow = nil
    }

    private func updateHandleAppearance() {
        guard let window = handleWindow, let pill = handle else { return }
        updateHandleVisibility()
        let defaults = UserDefaults(suiteName: preferenceDomain)
        let width = min(52, max(12, CGFloat(defaults?.object(forKey: "handleWidth") as? Int ?? 24)))
        let height = min(160, max(44, CGFloat(defaults?.object(forKey: "handleHeight") as? Int ?? 86)))
        window.applySystemOrientation()
        let bounds = window.rootViewController?.view.bounds ?? window.bounds
        let fraction = min(0.78, max(0.22, CGFloat(defaults?.object(forKey: handlePositionKey) as? Double ?? 0.5)))
        let panelTransform = pill.transform
        pill.transform = .identity
        pill.frame = CGRect(x: bounds.maxX - width,
                            y: bounds.height * fraction - height / 2, width: width, height: height)
        pill.transform = panelTransform
        pill.layer.cornerRadius = min(width / 2, 16)
        let markHeight = height * 0.46
        pill.subviews.first?.frame = CGRect(x: (width - 4) / 2,
                                           y: (height - markHeight) / 2,
                                           width: 4, height: markHeight)
        Self.updateCaptureVisibility()
    }

    private func setHandlePanelProgress(_ progress: CGFloat) {
        guard let pill = handle else { return }
        pill.transform = CGAffineTransform(translationX: (pill.bounds.width + 8) * min(1, max(0, progress)), y: 0)
    }

    private func updateHandleVisibility() {
        // Myrtle's lock-screen handle level is 1035, below the Cover Sheet chrome.
        if let handle = handle, handle.isHidden != deviceLocked { handle.isHidden = deviceLocked }
        updateOverlayWindowLevels()
    }

    private func updateOverlayWindowLevels() {
        let level = coverSheetVisible
            ? coverSheetWindowLevel ?? UIWindow.Level(rawValue: 1035) : .alert + 51
        if let window = handleWindow, window.windowLevel != level { window.windowLevel = level }
        for (index, dock) in dockedHosts.enumerated() {
            // Older docks stay above the fullscreen-sized entrance of a new dock.
            let dockLevel: UIWindow.Level = dock.fullscreenHandoffInProgress ? .statusBar + 0.3 : level - CGFloat(index + 1)
            if dock.window.windowLevel != dockLevel { dock.window.windowLevel = dockLevel }
        }
    }

    @objc public static func setCoverSheetVisible(_ visible: Bool) {
        guard shared.coverSheetVisible != visible else { return }
        shared.coverSheetVisible = visible
        shared.updateHandleVisibility()
        if visible { shared.hidePanel() }
    }

    @objc public static func setCoverSheetWindowLevel(_ level: Double) {
        shared.coverSheetWindowLevel = UIWindow.Level(rawValue: min(CGFloat(level) - 0.5, 1035))
        shared.updateHandleVisibility()
    }

    @objc public static func setCoverSheetPresented(_ presented: Bool) {
        shared.coverSheetPresented = presented
    }

    @objc public static func setCoverSheetEntering(_ entering: Bool) {
        shared.coverSheetEntering = entering
    }

    private var handlePositionKey: String {
        let bounds = handleWindow?.rootViewController?.view.bounds ?? UIScreen.main.bounds
        return bounds.width > bounds.height ? "handleCenterLandscapeFraction" : "handleCenterFraction"
    }

    private func selectedApps() -> [(id: String, name: String)] {
        let defaults = UserDefaults(suiteName: preferenceDomain)
        let ids = defaults?.stringArray(forKey: "applications") ?? []
        let names = defaults?.dictionary(forKey: "applicationNames") as? [String: String] ?? [:]
        let excluded = ids.filter { !isShortcut($0) }
        return ids.flatMap { id -> [(id: String, name: String)] in
            if id == "px.action.recent" {
                let count = min(20, max(1, defaults?.integer(forKey: "recentAppRank") ?? 1))
                return (1...count).map { rank in
                    let bundleID = PXSceneBridge.shared().recentApplicationSkipping(excluded, rank: rank)
                    return (id: bundleID.map { "px.recent.\(rank).\($0)" } ?? "px.recent.\(rank)",
                            name: bundleID ?? "最近应用为空")
                }
            }
            let name = shortcuts.first(where: { $0.id == id })?.name ?? names[id] ?? id
            return [(id: id, name: name)]
        }
    }

    private func beginPanel() {
        guard panelWindow == nil, let scene = handleWindow?.windowScene else { return }
        panelFrontmostBundleID = PXSceneBridge.shared().frontmostBundleID()
        let window = PXOverlayWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .alert + 52
        window.backgroundColor = .clear
        let controller = PXPanelViewController()
        controller.onProgress = { [weak self] in self?.setHandlePanelProgress($0) }
        controller.apps = selectedApps()
        controller.handleCenterY = handle?.center.y ?? window.bounds.midY
        controller.handleCenterX = handle?.center.x ?? window.bounds.maxX
        let holdMillis = UserDefaults(suiteName: preferenceDomain)?
            .object(forKey: "launcherHoldMilliseconds") as? Int ?? 700
        controller.holdDuration = Double(min(2000, max(300, holdMillis))) / 1000
        controller.onBrightnessHold = { [weak self, weak controller] point in
            guard let self = self, self.handleDragMode == 1 else { return }
            let value = CGFloat(UIScreen.main.brightness)
            self.brightnessStart = (point.y, value)
            controller?.showBrightness(value)
        }
        window.rootViewController = controller
        window.applySystemOrientation()
        _ = controller.view
        controller.view.layoutIfNeeded()
        controller.setProgress(0)
        window.isHidden = false
        window.isUserInteractionEnabled = false
        panel = controller
        panelWindow = window
        Self.updateCaptureVisibility()
    }

    @objc private func dragHandle(_ gesture: UIPanGestureRecognizer) {
        guard let root = handleWindow?.rootViewController?.view, let pill = handle else { return }
        let translation = gesture.translation(in: root)
        let distance = -translation.x
        let savedDistance = UserDefaults(suiteName: preferenceDomain)?
            .object(forKey: "launcherDragDistance") as? Int ?? 120
        let threshold = min(240, max(10, CGFloat(savedDistance)))
        switch gesture.state {
        case .began:
            panelDragProgress = 0
            brightnessStart = nil
            handleDragMode = 0
            handleDragStartY = pill.center.y
            fallthrough
        case .changed:
            if handleDragMode == 0, max(abs(translation.x), abs(translation.y)) > 5 {
                handleDragMode = abs(translation.y) > abs(translation.x) ? 2 : 1
                if handleDragMode == 1 { beginPanel() }
            }
            if handleDragMode == 2 {
                pill.center.y = min(root.bounds.height * 0.78,
                                    max(root.bounds.height * 0.22, handleDragStartY + translation.y))
                return
            }
            guard handleDragMode == 1 else { return }
            if let controller = panel, controller.appSelectorActive {
                controller.updateAppSelector(at: gesture.location(in: controller.view))
                return
            }
            if let controller = panel, controller.groupMenuActive {
                controller.updateGroupSelection(at: gesture.location(in: controller.view))
                return
            }
            if let start = brightnessStart, let controller = panel {
                let y = gesture.location(in: controller.view).y
                let value = min(1, max(0, start.value + (start.y - y) / (root.bounds.height * 0.405)))
                controller.updateBrightness(value)
                _ = PXSceneBridge.shared().setBrightnessLevel(Float(value))
                return
            }
            let prior = panelDragProgress
            panelDragProgress = max(panelDragProgress, min(1, max(0, distance / threshold)))
            if prior < 0.8 && panelDragProgress >= 0.8 {
                panel?.completeOpening()
            } else if panelDragProgress < 0.8 {
                panel?.setProgress(panelDragProgress)
            }
            if panelDragProgress >= 0.8 {
                panel?.advancePage(forDrag: gesture.translation(in: root).y)
                if let controller = panel {
                    _ = controller.updateSelection(at: gesture.location(in: controller.view))
                }
            }
        case .ended:
            if let controller = panel, controller.appSelectorActive {
                controller.updateAppSelector(at: gesture.location(in: controller.view))
                let appID = controller.selectedIndexedApp
                hidePanel()
                if let appID = appID { openHost(appID) }
                return
            }
            if let controller = panel, controller.groupMenuActive {
                controller.updateGroupSelection(at: gesture.location(in: controller.view))
                let entry = controller.selectedGroupAction
                hidePanel { [weak self] in if let entry = entry { self?.runConfiguredAction(entry) } }
                return
            }
            if brightnessStart != nil {
                brightnessStart = nil
                hidePanel()
                return
            }
            if handleDragMode == 2 {
                UserDefaults(suiteName: preferenceDomain)?.set(Double(pill.center.y / root.bounds.height),
                                                                  forKey: handlePositionKey)
                handleDragMode = 0
                return
            }
            if panelDragProgress >= 0.8,
               let controller = panel,
               let bundleID = controller.updateSelection(at: gesture.location(in: controller.view)) {
                let fullscreen = controller.selectedDuration >= controller.holdDuration
                if let appID = applicationID(bundleID) {
                    hidePanel()
                    if fullscreen { openFullscreen(appID) }
                    else { openHost(appID) }
                } else {
                    let action = bundleID == "px.action.screenshot" && fullscreen ? "px.action.screenshot.copy" : bundleID
                    if action == "px.action.window" {
                        if fullscreen {
                            // A swap can rotate SpringBoard before the close animation finishes.
                            hidePanel(animated: false)
                            performWindowHold()
                        } else {
                            hidePanel()
                            performShortcut(action)
                        }
                    } else { hidePanel { [weak self] in self?.performShortcut(action) } }
                }
            } else { hidePanel() }
        case .cancelled, .failed:
            brightnessStart = nil
            if handleDragMode == 2 { updateHandleAppearance() }
            hidePanel()
        default: break
        }
    }

    private func hidePanel(animated: Bool = true, _ completion: (() -> Void)? = nil) {
        guard let window = panelWindow, let controller = panel else {
            completion?()
            return
        }
        window.isUserInteractionEnabled = false
        let finish = { [weak self] in
            guard let self = self, self.panelWindow === window else { return }
            window.isHidden = true
            window.rootViewController = nil
            self.panelWindow = nil
            self.panel = nil
            self.setHandlePanelProgress(0)
            self.handleWindow?.isHidden = false
            completion?()
        }
        if animated { controller.animateClosed(completion: finish) }
        else {
            controller.cancelSelectionFeedback()
            finish()
        }
    }

    private func openHost(_ bundleID: String) {
        if hostedBundleID == bundleID, hostWindow != nil {
            externalPendingBundleID = nil
            panelFrontmostBundleID = nil
            return
        }
        if let dock = dockedHosts.first(where: { $0.bundleID == bundleID }) {
            restoreDock(dock)
            return
        }
        let wasFullscreen = panelFrontmostBundleID == bundleID
        panelFrontmostBundleID = nil
        presentHost(bundleID, wasFullscreen: wasFullscreen)
    }

    private func openFullscreen(_ bundleID: String) {
        if hostedBundleID == bundleID, hostWindow != nil { fullscreenTapped(); return }
        closeHost(animated: false)
        if let dock = dockedHosts.first(where: { $0.bundleID == bundleID }) {
            removeDock(dock, fullscreenHandoff: true)
        }
        panelFrontmostBundleID = nil
        _ = PXSceneBridge.shared().openFullscreenApplication(bundleID)
    }

    private func performShortcut(_ id: String) {
        if id == "px.action.brightness" { return }
        if let entry = configuredAction(id) {
            if entry["kind"] as? String != "group" { runConfiguredAction(entry) }
            return
        }
        if id == "px.action.restart" {
            restartCurrentApplication()
        } else if id == "px.action.search" {
            showSearch()
        } else if id.hasPrefix("px.recent.") {
            let parts = id.split(separator: ".", maxSplits: 3)
            if parts.count == 4 { openHost(String(parts[3])) }
        } else if id.hasPrefix("px.url."),
                  let entries = UserDefaults(suiteName: preferenceDomain)?.array(forKey: "urlShortcuts") as? [[String: String]],
                  let text = entries.first(where: { $0["id"] == id })?["url"],
                  let url = URL(string: text) {
            UIApplication.shared.open(url)
        } else if id == "px.action.window" {
            if hostWindow != nil { fullscreenTapped() }
            else if let frontmost = PXSceneBridge.shared().frontmostBundleID() { openHost(frontmost) }
        } else {
            _ = PXSceneBridge.shared().performShortcut(id)
        }
    }

    private func performWindowHold() {
        let frontmost = panelFrontmostBundleID ?? PXSceneBridge.shared().frontmostBundleID()
        panelFrontmostBundleID = nil
        let fullID = frontmost == "com.apple.springboard" || frontmost == hostedBundleID || frontmost?.isEmpty == true ? nil : frontmost
        if let splitID = hostedBundleID {
            guard let fullID = fullID else { parkMain(side: defaultDockSide); return }
            // Promote the hosted scene before releasing it; attach the former
            // foreground app only after SpringBoard reports the new foreground.
            guard activeBridge.openFullscreenApplication(splitID) else { return }
            closeHost(animated: false, fullscreenHandoff: true)
            pendingSwap = (splitID, fullID)
            if PXSceneBridge.shared().frontmostBundleID() == splitID {
                pendingSwap = nil
                openHost(fullID)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    if self?.pendingSwap?.foreground == splitID { self?.pendingSwap = nil }
                }
            }
        } else if let fullID = fullID {
            dockAfterOpenBundleID = fullID
            panelFrontmostBundleID = fullID
            openHost(fullID)
        }
    }

    private func restartCurrentApplication() {
        let splitID = hostedBundleID
        guard let bundleID = splitID ?? PXSceneBridge.shared().frontmostBundleID(),
              bundleID != "com.apple.springboard", !bundleID.isEmpty else { return }
        let window = hostWindow
        let card = hostCard
        let restart = { [weak self] in
            guard let self = self else { return }
            if splitID != nil && self.hostWindow !== window { return }
            guard PXSceneBridge.shared().restartApplication(bundleID, suspended: splitID != nil,
                completion: { [weak self] success in
                    guard let self = self, success, splitID != nil,
                          self.hostWindow == nil, !self.deviceLocked else { return }
                    self.presentHost(bundleID, wasFullscreen: false)
                }) else {
                window?.isUserInteractionEnabled = true
                PXMotion.spring(0.18) { card?.alpha = 1; card?.transform = .identity }
                return
            }
            if splitID != nil { self.closeHost(animated: false) }
        }
        if splitID != nil, let window = window, let card = card {
            window.isUserInteractionEnabled = false
            PXMotion.ease(0.20, animations: {
                card.alpha = 0
                card.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            }, completion: { _ in restart() })
        } else { restart() }
    }

    private func runConfiguredAction(_ entry: [String: Any]) {
        if entry["kind"] as? String == "quick", let bundleID = entry["app"] as? String {
            if hostedBundleID == bundleID { closeHost(animated: false) }
            if let dock = dockedHosts.first(where: { $0.bundleID == bundleID }) { removeDock(dock, fullscreenHandoff: true) }
        }
        guard !PXSceneBridge.shared().performConfiguredAction(entry) else { return }
        let alert = UIAlertController(title: "无法运行快捷方式", message: "请确认快捷指令或应用操作仍然存在，并在设置中重新选择。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        handleWindow?.rootViewController?.present(alert, animated: true)
    }

    private func showSearch() {
        guard searchWindow == nil, let scene = activeScene() else { return }
        let window = PXOverlayWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .alert + 52
        window.backgroundColor = .clear
        let controller = PXSearchViewController()
        controller.onSelect = { [weak self] bundleID in
            self?.hideSearch()
            self?.openHost(bundleID)
        }
        controller.onDismiss = { [weak self] in self?.hideSearch() }
        window.rootViewController = controller
        window.applySystemOrientation()
        searchPreviousKeyWindow = scene.windows.first(where: { $0.isKeyWindow })
        searchWindow = window
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        controller.view.alpha = 0
        window.makeKeyAndVisible()
        controller.focus()
    }

    private func hideSearch() {
        searchWindow?.rootViewController?.view.endEditing(true)
        searchWindow?.isHidden = true
        searchWindow?.rootViewController = nil
        searchWindow = nil
        searchPreviousKeyWindow?.makeKey()
    }

    private func presentHost(_ bundleID: String, wasFullscreen: Bool) {
        guard let scene = activeScene(),
              let controls = handleWindow?.rootViewController?.view else { return }
        if hostWindow != nil, hostedBundleID != bundleID {
            let defaults = UserDefaults(suiteName: preferenceDomain)
            if defaults?.object(forKey: "autoParkOnNewSplit") as? Bool ?? true {
                parkMain(side: defaultDockSide)
            } else { closeHost(animated: false) }
        }
        else { closeHost(animated: false) }
        fullscreenToWindowInProgress = wasFullscreen
        hostedBundleID = bundleID
        hostLayoutSourceSize = .zero
        launchMovedCenter = nil
        launchWidthScale = nil
        let screen = controls.bounds
        let natural = UIScreen.main.fixedCoordinateSpace.bounds.size
        let size = initialCardSize(in: screen, source: CGSize(width: min(natural.width, natural.height), height: max(natural.width, natural.height)))
        let width = size.width
        let height = size.height
        let cardFrame = initialCardFrame(in: screen, size: CGSize(width: width, height: height))
        let window = PXHandleWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .statusBar + 0.2
        window.backgroundColor = .clear
        let root = PXHostViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        window.applySystemOrientation()
        let card = UIView(frame: cardFrame)
        // The outer view owns only the shadow. A second rounded backing leaks
        // a light antialiased seam beside dark hosted surfaces.
        card.backgroundColor = .clear
        let defaults = UserDefaults(suiteName: preferenceDomain)
        card.layer.cornerRadius = configuredCornerRadius(in: screen, source: CGSize(width: min(natural.width, natural.height), height: max(natural.width, natural.height)))
        card.layer.cornerCurve = .continuous
        updateCardShadow(card)
        root.view.addSubview(card)
        let clip = UIView(frame: card.bounds)
        clip.backgroundColor = .secondarySystemBackground
        clip.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        clip.layer.cornerRadius = card.layer.cornerRadius
        clip.layer.cornerCurve = .continuous
        clip.clipsToBounds = true
        card.addSubview(clip)
        let canvas = UIView(frame: clip.bounds)
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        clip.addSubview(canvas)
        let indicator = UIView(frame: .zero)
        indicator.tag = 0x505847
        indicator.backgroundColor = UIColor(white: 0.65, alpha: 0.65)
        indicator.layer.cornerRadius = 2
        indicator.isUserInteractionEnabled = false
        clip.addSubview(indicator)
        let title = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        title.tag = 0x505848
        title.isUserInteractionEnabled = false
        title.layer.cornerRadius = 9
        title.clipsToBounds = true
        let titleIcon = UIImageView(image: PXApplicationIcon(bundleID) ?? UIImage(systemName: "app"))
        titleIcon.frame = CGRect(x: 6, y: 3, width: 12, height: 12)
        titleIcon.layer.cornerRadius = 2.8
        titleIcon.clipsToBounds = true
        titleIcon.contentMode = .scaleAspectFit
        title.contentView.addSubview(titleIcon)
        let titleName = UILabel()
        titleName.tag = 0x505849
        titleName.text = PXApplicationDisplayName(bundleID)
        titleName.textColor = .label
        titleName.font = .systemFont(ofSize: 11, weight: .medium)
        titleName.lineBreakMode = .byTruncatingTail
        title.contentView.addSubview(titleName)
        clip.addSubview(title)
        hostCanvas = canvas
        let coldStart = !activeBridge.hasScene(forApplication: bundleID)
        let debug = defaults?.bool(forKey: "gestureDebug") == true
        for side in [-1, 1] {
            let corner = UIView(frame: .zero)
            corner.tag = side
            corner.isOpaque = false
            corner.backgroundColor = debug ? UIColor.systemBlue.withAlphaComponent(0.25) : .clear
            PXSceneBridge.keepTransparentGestureViewHittable(corner)
            corner.isUserInteractionEnabled = true
            corner.isAccessibilityElement = true
            corner.accessibilityLabel = "拖动调整窗口大小"
            corner.addGestureRecognizer(UIPanGestureRecognizer(target: self,
                                                               action: #selector(resizeHost(_:))))
            root.view.addSubview(corner)
            hostCorners.append(corner)
            let top = UIControl(frame: .zero)
            top.tag = side
            top.backgroundColor = debug ? UIColor.systemBlue.withAlphaComponent(0.25) : .clear
            PXSceneBridge.keepTransparentGestureViewHittable(top)
            top.isAccessibilityElement = true
            top.accessibilityLabel = "停靠到小窗"
            top.addTarget(self, action: #selector(dockTapped(_:)), for: .touchUpInside)
            root.view.addSubview(top)
            hostTopCorners.append(top)
        }
        let topGrip = UIView(frame: .zero)
        topGrip.backgroundColor = debug ? UIColor.systemBlue.withAlphaComponent(0.25) : .clear
        PXSceneBridge.keepTransparentGestureViewHittable(topGrip)
        topGrip.isAccessibilityElement = true
        topGrip.accessibilityLabel = "顶部拖动移动；上滑恢复初始位置与大小；下滑关闭分屏与后台；双击关闭；长按全屏"
        let topPan = UIPanGestureRecognizer(target: self, action: #selector(moveHost(_:)))
        topPan.maximumNumberOfTouches = 1
        topGrip.addGestureRecognizer(topPan)
        let topDoubleTap = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        topDoubleTap.numberOfTapsRequired = 2
        topGrip.addGestureRecognizer(topDoubleTap)
        topGrip.addGestureRecognizer(UILongPressGestureRecognizer(target: self,
                                                                  action: #selector(moveGripHeld(_:))))
        root.view.insertSubview(topGrip, belowSubview: hostTopCorners[0])
        hostTopGrip = topGrip
        let moveGrip = UIView(frame: .zero)
        moveGrip.backgroundColor = .clear
        PXSceneBridge.keepTransparentGestureViewHittable(moveGrip)
        if debug {
            moveGrip.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.25)
            moveGrip.layer.borderColor = UIColor.systemBlue.cgColor
            moveGrip.layer.borderWidth = 1
        }
        moveGrip.isAccessibilityElement = true
        moveGrip.accessibilityLabel = "拖动移动；双击关闭；长按全屏"
        moveGrip.addGestureRecognizer(UIPanGestureRecognizer(target: self,
                                                              action: #selector(moveHost(_:))))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        doubleTap.numberOfTapsRequired = 2
        moveGrip.addGestureRecognizer(doubleTap)
        moveGrip.addGestureRecognizer(UILongPressGestureRecognizer(target: self,
                                                                   action: #selector(moveGripHeld(_:))))
        root.view.addSubview(moveGrip)
        hostMoveGrip = moveGrip
        root.onLayout = { [weak self] in
            self?.screenGeometryChanged()
            self?.layoutHostControls()
        }
        root.onAppearance = { [weak self] in
            self?.refreshHostedAppearance()
        }
        // Keep the native full-screen surface visible until its hosted surface
        // is mounted; showing an empty backing here produces a bright frame.
        window.isHidden = wasFullscreen
        hostWindow = window
        hostCard = card
        layoutHostControls()
        window.isUserInteractionEnabled = true
        canvas.isUserInteractionEnabled = false
        if !wasFullscreen {
            card.transform = CGAffineTransform(scaleX: 0.84, y: 0.84)
            PXMotion.spring(0.4) { card.transform = .identity }
        }
        if coldStart, let image = activeBridge.launchImage(forApplication: bundleID, size: card.bounds.size) {
            let preview = UIImageView(image: image)
            preview.tag = 0x50584c
            preview.frame = clip.bounds
            preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            preview.contentMode = .scaleToFill
            preview.isUserInteractionEnabled = false
            clip.insertSubview(preview, aboveSubview: canvas)
        }
        activeBridge.openApplication(bundleID, in: canvas,
                                               keyboardOverlay: controls) { [weak self, weak window] success in
            guard let self = self else { return }
            let dock = self.dockedHosts.first { $0.window === window }
            guard self.hostWindow === window || dock != nil else { return }
            guard success else {
                if self.dockAfterOpenBundleID == bundleID { self.dockAfterOpenBundleID = nil }
                if let dock = dock { self.removeDock(dock) }
                else { self.closeHost(animated: false) }
                self.externalOpenFailed(bundleID)
                return
            }
            if let preview = card.viewWithTag(0x50584c) {
                PXMotion.ease(0.15, animations: { preview.alpha = 0 }) { _ in
                    preview.removeFromSuperview()
                }
            }
            if let dock = dock {
                dock.loading = false
                if self.externalPendingBundleID == bundleID { self.externalPendingBundleID = nil }
                let screen = dock.window.rootViewController?.view.bounds ?? UIScreen.main.bounds
                dock.card.layer.cornerRadius = self.configuredCornerRadius(in: screen,
                                                                          source: dock.bridge.hostedSourceSize())
                dock.card.subviews.first?.layer.cornerRadius = dock.card.layer.cornerRadius
                dock.window.isHidden = false
                self.layoutDocks(animated: false)
                return
            }
            self.matchHostAspect()
            let frame = card.frame
            let radius = card.layer.cornerRadius
            let skipHandoffAnimation = self.dockAfterOpenBundleID == bundleID ||
                self.fullscreenAfterOpenBundleID == bundleID
            let dockingFullscreen = wasFullscreen && self.dockAfterOpenBundleID == bundleID
            if wasFullscreen && (!skipHandoffAnimation || dockingFullscreen), frame.width > 0, frame.height > 0 {
                let screen = window?.rootViewController?.view.bounds ?? UIScreen.main.bounds
                let scale = min(screen.width / frame.width, screen.height / frame.height)
                card.transform = CGAffineTransform(scaleX: scale, y: scale)
                card.center = CGPoint(x: screen.midX, y: screen.midY)
                card.layer.cornerRadius = 0
                card.subviews.first?.layer.cornerRadius = 0
            }
            window?.isHidden = false
            self.activeBridge.prepareWindow(for: bundleID, wasFullscreen: wasFullscreen) { [weak self, weak window] ready in
                guard let self = self else { return }
                let dock = self.dockedHosts.first { $0.window === window }
                guard self.hostWindow === window || dock != nil else { return }
                guard ready else {
                    if self.dockAfterOpenBundleID == bundleID { self.dockAfterOpenBundleID = nil }
                    if let dock = dock { self.removeDock(dock) }
                    else { self.closeHost(animated: false) }
                    self.externalOpenFailed(bundleID)
                    return
                }
                if let dock = dock {
                    dock.loading = false
                    if self.externalPendingBundleID == bundleID { self.externalPendingBundleID = nil }
                    self.layoutDocks(animated: false)
                    return
                }
                if self.externalPendingBundleID == bundleID { self.externalPendingBundleID = nil }
                canvas.isUserInteractionEnabled = true
                window?.isUserInteractionEnabled = true
                self.layoutHostControls()
                if self.fullscreenAfterOpenBundleID == bundleID {
                    self.fullscreenAfterOpenBundleID = nil
                    self.fullscreenTapped()
                    return
                }
                if self.dockAfterOpenBundleID == bundleID {
                    self.dockAfterOpenBundleID = nil
                    if dockingFullscreen {
                        let start = card.frame
                        card.layer.cornerRadius = radius
                        card.subviews.first?.layer.cornerRadius = radius
                        self.parkMain(side: self.defaultDockSide, animated: false)
                        PXMotion.geometry(card, from: start, duration: 0.40, cornerRadius: 0)
                    } else { self.parkMain(side: self.defaultDockSide) }
                }
            }
            if wasFullscreen && !skipHandoffAnimation {
                PXMotion.spring(0.4, animations: {
                    card.transform = .identity
                    card.center = CGPoint(x: frame.midX, y: frame.midY)
                    card.layer.cornerRadius = radius
                    card.subviews.first?.layer.cornerRadius = radius
                }) { _ in
                    guard self.hostWindow === window else { return }
                    self.layoutHostControls()
                }
            }
        }
    }

    private func matchHostAspect() {
        guard let window = hostWindow, let card = hostCard else { return }
        let source = activeBridge.hostedSourceSize()
        guard source.width > 0, source.height > 0 else { return }
        hostLayoutSourceSize = source
        let screen = window.rootViewController?.view.bounds ?? UIScreen.main.bounds
        let initial = initialCardSize(in: screen, source: source)
        var size = initial
        if let requested = launchWidthScale {
            let scale = min(requested, (screen.width - 24) / initial.width,
                            (screen.height - 40) / initial.height)
            size = CGSize(width: initial.width * scale, height: initial.height * scale)
        }
        keyboardFocusBase = nil
        keyboardFocusFrame = .null
        card.transform = .identity
        card.frame = initialCardFrame(in: screen, size: size)
        if let center = launchMovedCenter {
            card.center = CGPoint(x: min(max(center.x, screen.minX + size.width / 2), screen.maxX - size.width / 2),
                                  y: min(max(center.y, screen.minY + size.height / 2), screen.maxY - size.height / 2))
        }
        launchMovedCenter = nil
        launchWidthScale = nil
        card.layer.cornerRadius = configuredCornerRadius(in: screen, source: source)
        card.layoutIfNeeded()
        layoutHostControls()
        activeBridge.layoutHost()
    }

    private func initialCardFrame(in screen: CGRect, size: CGSize) -> CGRect {
        let defaults = UserDefaults(suiteName: preferenceDomain)
        let key = screen.width > screen.height ? "landscapeInitialRightInset" : "initialRightInset"
        let saved = defaults?.object(forKey: key) as? NSNumber
        let legacy = defaults?.object(forKey: "initialRightInset") as? NSNumber
        let inset = min(max(0, screen.width - size.width), max(0, CGFloat(saved?.doubleValue ?? legacy?.doubleValue ?? 12)))
        return CGRect(x: screen.maxX - size.width - inset,
                      y: screen.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func initialCardSize(in screen: CGRect, source: CGSize) -> CGSize {
        guard source.width > 0, source.height > 0 else { return .zero }
        let landscape = screen.width > screen.height
        let defaults = UserDefaults(suiteName: preferenceDomain)
        let key = landscape ? "initialWidthPercent" : source.width > source.height
            ? "portraitLandscapeInitialWidthPercent" : "portraitInitialWidthPercent"
        let saved = defaults?.object(forKey: key) as? NSNumber
        let legacy = defaults?.object(forKey: "initialWidthPercent") as? NSNumber
        let portrait = defaults?.object(forKey: "portraitInitialWidthPercent") as? NSNumber
        let fallback = !landscape && source.width > source.height ? portrait : legacy
        let initialWidthFraction = CGFloat(min(95, max(35, saved?.doubleValue ?? fallback?.doubleValue ?? 78))) / 100
        let scale = landscape
            ? min(screen.height * initialWidthFraction / max(source.width, source.height),
                  (screen.width - landscapeDockWidth(in: screen) - 48) / source.width)
            : min(screen.width * initialWidthFraction / source.width, (screen.height - 80) / source.height)
        return CGSize(width: source.width * scale, height: source.height * scale)
    }

    private func landscapeDockWidth(in screen: CGRect) -> CGFloat {
        let widest = max(dockWidth(for: CGSize(width: 1, height: 2), in: screen),
                         dockWidth(for: CGSize(width: 2, height: 1), in: screen))
        return min(widest, screen.width * 0.25)
    }

    private func dockWidth(for source: CGSize, in screen: CGRect) -> CGFloat {
        let defaults = UserDefaults(suiteName: preferenceDomain)
        let key = source.width > source.height ? "landscapeDockWidth" : "dockWidth"
        let saved = defaults?.object(forKey: key) as? NSNumber
        let legacy = defaults?.object(forKey: "dockWidth") as? NSNumber
        return min(max(35, screen.width - 54), CGFloat(min(240, max(35, saved?.doubleValue ?? legacy?.doubleValue ?? 110))))
    }

    private func updateKeyboardFocus() {
        guard let card = hostCard, let root = hostWindow?.rootViewController?.view else { return }
        let focused = !activeBridge.usesExternalKeyboard() && activeBridge.isHostedKeyboardVisible() &&
            !keyboardDismissSuppressed && !deviceLocked && hostWindow?.isUserInteractionEnabled == true &&
            resizeStartFrame == nil && moveStartFrame == nil
        if focused && keyboardFocusBase == nil {
            keyboardFocusBase = card.frame
            keyboardFocusRadius = card.layer.cornerRadius
        }
        guard let base = keyboardFocusBase else { return }
        // Landscape focus intentionally grows above the screen, leaving the
        // input field and keyboard anchored at the bottom rather than flying in.
        let room = root.bounds.width > root.bounds.height ? (base.maxX - 12) / base.width :
            min((base.maxX - 12) / base.width, (base.maxY - 12) / base.height)
        let savedZoom = (UserDefaults(suiteName: preferenceDomain)?.object(forKey: "internalKeyboardZoomPercent") as? NSNumber)?.doubleValue ?? 160
        let requestedZoom = CGFloat(min(200, max(100, savedZoom.isFinite ? savedZoom : 160))) / 100
        let zoom = focused ? max(1, min(requestedZoom, room)) : 1
        let target = CGRect(x: base.maxX - base.width * zoom, y: base.maxY - base.height * zoom,
                            width: base.width * zoom, height: base.height * zoom)
        guard target != keyboardFocusFrame else { return }
        keyboardFocusFrame = target
        if !focused { keyboardFocusBase = nil }
        UIView.animate(withDuration: keyboardAnimationDuration, delay: 0, options: keyboardAnimationOptions) {
            card.transform = CGAffineTransform(scaleX: zoom, y: zoom)
            card.center = CGPoint(x: target.midX, y: target.midY)
            card.layer.cornerRadius = self.keyboardFocusRadius / zoom
            self.layoutHostControls()
        }
    }

    private func restoreKeyboardFocus() {
        if let base = keyboardFocusBase {
            hostCard?.transform = .identity
            hostCard?.frame = base
            hostCard?.layer.cornerRadius = keyboardFocusRadius
            hostCard?.layoutIfNeeded()
            activeBridge.layoutHost()
        }
        keyboardFocusBase = nil
        keyboardFocusFrame = .null
    }

    private func configuredCornerRadius(in screen: CGRect, source: CGSize) -> CGFloat {
        let defaults = UserDefaults(suiteName: preferenceDomain)
        let key = screen.width > screen.height ? "cornerRadius" : source.width > source.height
            ? "portraitLandscapeCornerRadius" : "portraitCornerRadius"
        let saved = defaults?.object(forKey: key) as? NSNumber
        let legacy = defaults?.object(forKey: "cornerRadius") as? NSNumber
        let portrait = defaults?.object(forKey: "portraitCornerRadius") as? NSNumber
        let fallback = screen.width <= screen.height && source.width > source.height ? portrait : legacy
        return CGFloat(min(60, max(0, saved?.doubleValue ?? fallback?.doubleValue ?? 20)))
    }

    private func updateCardShadow(_ card: UIView) {
        let defaults = UserDefaults(suiteName: preferenceDomain)
        let strength = Float(min(50, max(0, defaults?.object(forKey: "shadowStrength") as? Int ?? 22))) / 100
        let blur = CGFloat(min(24, max(0, defaults?.object(forKey: "shadowBlur") as? Int ?? 15)))
        let dark = card.traitCollection.userInterfaceStyle == .dark
        card.layer.shadowColor = dark ? UIColor.white.cgColor : UIColor.black.cgColor
        card.layer.shadowOpacity = dark ? min(0.35, strength * 0.8) : strength
        card.layer.shadowRadius = dark ? blur + 4 : blur
        card.layer.shadowOffset = CGSize(width: 0, height: 3)
        card.layer.shadowPath = UIBezierPath(roundedRect: card.bounds,
                                             cornerRadius: card.layer.cornerRadius).cgPath
    }

    private var defaultDockSide: Int {
        UserDefaults(suiteName: preferenceDomain)?.integer(forKey: "dockSide") == -1 ? -1 : 1
    }

    private func refreshHostedAppearance() {
        layoutHostControls()
        for dock in dockedHosts {
            dock.bridge.updateAppearance(for: dock.card.traitCollection.userInterfaceStyle)
            updateCardShadow(dock.card)
        }
    }

    private func layoutHostControls() {
        guard let card = hostCard, hostWindow != nil else { return }
        let defaults = UserDefaults(suiteName: preferenceDomain)
        activeBridge.updateAppearance(for: card.traitCollection.userInterfaceStyle)
        updateCardShadow(card)
        card.subviews.first?.layer.cornerRadius = card.layer.cornerRadius
        if let title = card.viewWithTag(0x505848), let name = title.viewWithTag(0x505849) as? UILabel {
            let source = activeBridge.hostedSourceSize()
            title.isHidden = !(defaults?.object(forKey: "showSplitAppIdentity") as? Bool ?? true) ||
                source.width <= 0 || source.height <= source.width ||
                card.bounds.width < 64 || card.bounds.height < 48
            // Keep one portrait reference: landscape's smaller card must also shrink its identity.
            let physical = (hostWindow?.screen ?? UIScreen.main).fixedCoordinateSpace.bounds.size
            let referenceScreen = CGRect(x: 0, y: 0, width: min(physical.width, physical.height),
                                         height: max(physical.width, physical.height))
            let initialWidth = initialCardSize(in: referenceScreen, source: source).width
            let scale = initialWidth > 0 ? card.bounds.width / initialWidth : 1
            let titleWidth = min(160, (initialWidth > 0 ? initialWidth : card.bounds.width) - 32,
                                 name.intrinsicContentSize.width + 29)
            // Preview already scales the parent card; bounds-based scaling keeps the same size on release.
            title.bounds = CGRect(x: 0, y: 0, width: max(0, titleWidth), height: 18)
            title.transform = CGAffineTransform(scaleX: scale * 1.067, y: scale * 1.067)
            title.center = CGPoint(x: card.bounds.midX, y: 13 * scale)
            name.frame = CGRect(x: 23, y: 0, width: max(0, titleWidth - 29), height: 18)
            title.superview?.bringSubviewToFront(title)
        }
        if let indicator = card.viewWithTag(0x505847) {
            let barWidth = min(100, card.bounds.width * 0.32)
            indicator.frame = CGRect(x: (card.bounds.width - barWidth) / 2,
                                     y: card.bounds.height - 8, width: barWidth, height: 4)
            indicator.isHidden = false
            indicator.superview?.bringSubviewToFront(indicator)
        }
        let frame = card.frame
        for corner in hostCorners {
            let radius = max(CGFloat(12), card.layer.cornerRadius)
            let center = CGPoint(x: corner.tag < 0 ? frame.minX + radius : frame.maxX - radius,
                                 y: frame.maxY - radius)
            let middle: CGFloat = corner.tag < 0 ? 3 * .pi / 4 : .pi / 4
            let arcRadius = radius + 3
            let midpoint = CGPoint(x: center.x + arcRadius * cos(middle),
                                   y: center.y + arcRadius * sin(middle))
            corner.frame = CGRect(x: midpoint.x - 22, y: midpoint.y - 22, width: 44, height: 44)
        }
        for corner in hostTopCorners {
            corner.frame = CGRect(x: corner.tag < 0 ? frame.minX - 12 : frame.maxX - 32,
                                  y: frame.minY - 12, width: 44, height: 44)
        }
        let width = min(360, max(120, CGFloat(truncating: defaults?.object(forKey: "gestureWidth") as? NSNumber ?? 300)))
        let height = min(120, max(36, CGFloat(truncating: defaults?.object(forKey: "gestureHeight") as? NSNumber ?? 80)))
        let offset = min(40, max(-30, CGFloat(truncating: defaults?.object(forKey: "gestureOffset") as? NSNumber ?? 0)))
        hostMoveGrip?.frame = CGRect(x: frame.midX - width / 2, y: frame.maxY + offset,
                                     width: width, height: height)
        let topWidth = min(360, max(120, CGFloat(truncating: defaults?.object(forKey: "topGestureWidth") as? NSNumber ?? 300)))
        let topHeight = min(120, max(36, CGFloat(truncating: defaults?.object(forKey: "topGestureHeight") as? NSNumber ?? 80)))
        let topOffset = min(40, max(-30, CGFloat(truncating: defaults?.object(forKey: "topGestureOffset") as? NSNumber ?? 0)))
        hostTopGrip?.frame = CGRect(x: frame.midX - topWidth / 2, y: frame.minY - topHeight - topOffset,
                                    width: topWidth, height: topHeight)
        refreshKeyboardDismissLayer()
    }

    @objc private func dockTapped(_ sender: UIControl) {
        parkMain(side: defaultDockSide)
    }

    @discardableResult private func parkMain(side: Int, animated: Bool = true) -> Bool {
        restoreKeyboardFocus()
        guard let window = hostWindow, let card = hostCard, let canvas = hostCanvas,
              let bundleID = hostedBundleID,
              let root = window.rootViewController?.view else { return false }
        let loading = !canvas.isUserInteractionEnabled
        let limit = min(4, max(1, UserDefaults(suiteName: preferenceDomain)?
            .object(forKey: "dockCount") as? Int ?? 2))
        while dockedHosts.count >= limit, let oldest = dockedHosts.first { removeDock(oldest) }
        let overlay = UIView(frame: card.frame)
        overlay.backgroundColor = UIColor(white: 1, alpha: 0.02)
        overlay.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(restoreDockTapped(_:))))
        overlay.accessibilityLabel = "轻点恢复分屏；上滑关闭小窗；下滑全屏；左右滑动更换位置"
        for direction in [UISwipeGestureRecognizer.Direction.up, .down, .left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(dockSwiped(_:)))
            swipe.direction = direction
            overlay.addGestureRecognizer(swipe)
        }
        root.addSubview(overlay)
        card.viewWithTag(0x505847)?.isHidden = true
        card.viewWithTag(0x505848)?.isHidden = true
        canvas.isUserInteractionEnabled = false
        activeBridge.setHostedInteractionEnabled(false)
        let dock = PXDockedHost(window: window, card: card, canvas: canvas,
                                bridge: activeBridge, bundleID: bundleID, side: side,
                                corners: hostCorners, topCorners: hostTopCorners,
                                topGrip: hostTopGrip, moveGrip: hostMoveGrip, overlay: overlay,
                                loading: loading)
        dockedHosts.append(dock)
        if dockAfterOpenBundleID == bundleID { dockAfterOpenBundleID = nil }
        if fullscreenAfterOpenBundleID == bundleID { fullscreenAfterOpenBundleID = nil }
        (hostCorners + hostTopCorners + [hostTopGrip, hostMoveGrip].compactMap { $0 }).forEach { $0.isHidden = true }
        hostWindow = nil
        hostCard = nil
        hostCanvas = nil
        hostCorners = []
        hostTopCorners = []
        hostMoveGrip = nil
        hostTopGrip = nil
        hostedBundleID = nil
        activeBridge = PXSceneBridge()
        refreshKeyboardDismissLayer()
        layoutDocks(animated: animated)
        return true
    }

    private func layoutDocks(animated: Bool = true) {
        updateOverlayWindowLevels()
        let screen = handleWindow?.rootViewController?.view.bounds ?? UIScreen.main.bounds
        let landscape = screen.width > screen.height
        let top: CGFloat = landscape ? 16 : max(50, handleWindow?.rootViewController?.view.safeAreaInsets.top ?? 50) + 12
        let natural = UIScreen.main.fixedCoordinateSpace.bounds.size
        let fallback = CGSize(width: min(natural.width, natural.height),
                              height: max(natural.width, natural.height))
        let sourceForDock: (PXDockedHost) -> CGSize = { dock in
            let source = dock.bridge.hostedSourceSize()
            return source.width > 0 && source.height > 0 ? source : fallback
        }
        for (index, dock) in dockedHosts.enumerated() where !dock.fullscreenHandoffInProgress {
            let source = sourceForDock(dock)
            let requested = dockWidth(for: source, in: screen)
            let baseSize = initialCardSize(in: screen, source: source)
            let count = max(1, dockedHosts.filter { $0.side == dock.side }.count)
            let available = max(120, screen.height - top - 40 - CGFloat(count - 1) * 12)
            let ratio = source.height / source.width
            let width = max(35, min(requested, available / CGFloat(count) / max(1, ratio)))
            let height = width * ratio
            let preceding = dockedHosts.prefix(index).filter { $0.side == dock.side }.reduce(CGFloat.zero) { sum, item in
                let itemSource = sourceForDock(item)
                let r = itemSource.height / max(1, itemSource.width)
                let itemWidth = dockWidth(for: itemSource, in: screen)
                return sum + max(35, min(itemWidth, available / CGFloat(count) / max(1, r))) * r + 12
            }
            let edge: CGFloat = landscape ? 27 : 12
            let frame = CGRect(x: dock.side < 0 ? edge : screen.maxX - width - edge,
                               y: top + preceding, width: width, height: height)
            let scale = width / max(1, baseSize.width)
            let changes = {
                dock.card.bounds = CGRect(origin: .zero, size: baseSize)
                self.updateCardShadow(dock.card)
                dock.card.layoutIfNeeded()
                dock.bridge.layoutHost()
                dock.card.transform = CGAffineTransform(scaleX: scale, y: scale)
                dock.card.center = CGPoint(x: frame.midX, y: frame.midY)
                dock.overlay.frame = frame
            }
            if animated { PXMotion.spring(0.30, animations: changes) }
            else { UIView.performWithoutAnimation(changes) }
        }
    }

    @objc private func restoreDockTapped(_ sender: UITapGestureRecognizer) {
        guard let dock = dockedHosts.first(where: { $0.overlay === sender.view }) else { return }
        restoreDock(dock)
    }

    @objc private func dockSwiped(_ sender: UISwipeGestureRecognizer) {
        guard let dock = dockedHosts.first(where: { $0.overlay === sender.view }) else { return }
        if sender.direction == .up {
            removeDock(dock, animated: true)
        } else if sender.direction == .down {
            fullscreenDock(dock)
        } else {
            dock.side = sender.direction == .left ? -1 : 1
            layoutDocks()
        }
    }

    private func fullscreenDock(_ dock: PXDockedHost) {
        guard dock.overlay.isUserInteractionEnabled else { return }
        let screen = dock.window.rootViewController?.view.bounds ?? dock.window.bounds
        let bounds = dock.card.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        let transform = dock.card.transform
        let center = dock.card.center
        let radius = dock.card.layer.cornerRadius
        let shadow = dock.card.layer.shadowOpacity
        let scale = dock.card.frame.width / bounds.width
        dock.fullscreenHandoffInProgress = true
        updateOverlayWindowLevels()
        dock.overlay.isUserInteractionEnabled = false
        dock.window.isUserInteractionEnabled = false
        PXMotion.spring(0.40, animations: {
            dock.card.transform = CGAffineTransform(scaleX: screen.width / bounds.width,
                                                   y: screen.height / bounds.height)
            dock.card.center = CGPoint(x: screen.midX, y: screen.midY)
            dock.card.layer.cornerRadius = radius * scale / min(screen.width / bounds.width, screen.height / bounds.height)
            dock.card.subviews.first?.layer.cornerRadius = dock.card.layer.cornerRadius
            dock.card.layer.shadowOpacity = 0
        }, completion: { [weak self] _ in
            guard let self = self,
                  self.dockedHosts.contains(where: { $0 === dock }) else { return }
            // Activation is only a request; keep the expanded surface until
            // the native foreground handoff, just as fullscreenTapped does.
            if !self.deviceLocked && dock.bridge.openFullscreenApplication(dock.bundleID) {
                var ticks = 0
                var readyTicks = 0
                let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak dock] timer in
                    guard let self = self, let dock = dock,
                          self.dockedHosts.contains(where: { $0 === dock }) else {
                        timer.invalidate()
                        return
                    }
                    ticks += 1
                    readyTicks = PXSceneBridge.shared().frontmostBundleID() == dock.bundleID
                        ? readyTicks + 1 : 0
                    if readyTicks >= 2 || ticks >= 15 {
                        timer.invalidate()
                        dock.fullscreenHandoffInProgress = false
                        self.removeDock(dock, fullscreenHandoff: true)
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
            } else {
                PXMotion.spring(0.20, animations: {
                    dock.card.transform = transform
                    dock.card.center = center
                    dock.card.layer.cornerRadius = radius
                    dock.card.subviews.first?.layer.cornerRadius = radius
                    dock.card.layer.shadowOpacity = shadow
                }, completion: { [weak self] _ in
                    guard let self = self, self.dockedHosts.contains(where: { $0 === dock }) else { return }
                    dock.fullscreenHandoffInProgress = false
                    self.updateOverlayWindowLevels()
                    dock.overlay.isUserInteractionEnabled = true
                    dock.window.isUserInteractionEnabled = true
                })
            }
        })
    }

    private func removeDock(_ dock: PXDockedHost, fullscreenHandoff: Bool = false, animated: Bool = false) {
        dockedHosts.removeAll { $0 === dock }
        dock.overlay.removeFromSuperview()
        dock.window.isUserInteractionEnabled = false
        let finish = {
            dock.window.isHidden = true
            if fullscreenHandoff { dock.bridge.closeForFullscreen() }
            else { dock.bridge.close() }
            dock.window.rootViewController = nil
        }
        if animated && !fullscreenHandoff {
            PXMotion.ease(0.22, options: .curveEaseInOut, animations: {
                dock.card.alpha = 0
                dock.card.transform = dock.card.transform.scaledBy(x: 0.94, y: 0.94)
                dock.card.layer.shadowOpacity = 0
            }, completion: { _ in finish() })
        } else { finish() }
        layoutDocks()
    }

    private func restoreDock(_ dock: PXDockedHost) {
        dockedHosts.removeAll { $0 === dock }
        if hostWindow != nil {
            if UserDefaults(suiteName: preferenceDomain)?.object(forKey: "autoParkOnNewSplit") as? Bool ?? true {
                parkMain(side: defaultDockSide)
            } else { closeHost(animated: false) }
        }
        dock.overlay.removeFromSuperview()
        dock.window.windowLevel = .statusBar + 0.3
        dock.window.isUserInteractionEnabled = true
        dock.canvas.isUserInteractionEnabled = !dock.loading
        dock.bridge.setHostedInteractionEnabled(!dock.loading)
        activeBridge = dock.bridge
        hostWindow = dock.window
        hostCard = dock.card
        hostCanvas = dock.canvas
        hostCorners = dock.corners
        hostTopCorners = dock.topCorners
        hostMoveGrip = dock.moveGrip
        hostTopGrip = dock.topGrip
        hostedBundleID = dock.bundleID
        (hostCorners + hostTopCorners + [hostTopGrip, hostMoveGrip].compactMap { $0 }).forEach { $0.isHidden = false }
        let screen = dock.window.rootViewController?.view.bounds ?? UIScreen.main.bounds
        let natural = UIScreen.main.fixedCoordinateSpace.bounds.size
        let source = dock.bridge.hostedSourceSize()
        let fallback = CGSize(width: min(natural.width, natural.height),
                              height: max(natural.width, natural.height))
        let resolved = source.width > 0 && source.height > 0 ? source : fallback
        hostLayoutSourceSize = resolved
        let frame = initialCardFrame(in: screen, size: initialCardSize(in: screen, source: resolved))
        dock.card.layer.cornerRadius = configuredCornerRadius(in: screen, source: resolved)
        PXMotion.spring(0.32, animations: {
            dock.card.transform = .identity
            dock.card.frame = frame
            dock.card.layoutIfNeeded()
            dock.bridge.layoutHost()
        }, completion: { [weak self, weak dock] _ in
            guard let self = self, let dock = dock, self.hostWindow === dock.window else { return }
            self.layoutHostControls()
        })
        layoutDocks()
    }

    @objc private func closeTapped() { closeHost(animated: true) }

    @objc private func fullscreenTapped() {
        restoreKeyboardFocus()
        if hostCanvas?.isUserInteractionEnabled == false {
            fullscreenAfterOpenBundleID = hostedBundleID
            dockAfterOpenBundleID = nil
            return
        }
        guard let bundleID = hostedBundleID, let window = hostWindow,
              let card = hostCard, let scene = window.windowScene else { return }
        let cardFrame = card.frame
        let cornerRadius = card.layer.cornerRadius
        let shadowOpacity = card.layer.shadowOpacity
        let oldFrame = card.frame
        hostCorners.forEach { $0.isHidden = true }
        hostMoveGrip?.isHidden = true
        hostTopGrip?.isHidden = true
        window.isUserInteractionEnabled = false
        card.frame = oldFrame
        PXMotion.spring(0.40, animations: {
            let screen = window.rootViewController?.view.bounds ?? scene.coordinateSpace.bounds
            let scaleX = screen.width / oldFrame.width
            let scaleY = screen.height / oldFrame.height
            card.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            card.center = CGPoint(x: screen.midX, y: screen.midY)
            card.layer.cornerRadius = cornerRadius / min(scaleX, scaleY)
            card.subviews.first?.layer.cornerRadius = card.layer.cornerRadius
            card.layer.shadowOpacity = 0
        }, completion: { [weak self, weak window] _ in
            guard let self = self, let window = window, self.hostWindow === window else { return }
            self.fullscreenLaunchInProgress = true
            guard self.activeBridge.openFullscreenApplication(bundleID) else {
                self.fullscreenLaunchInProgress = false
                card.transform = .identity
                card.frame = cardFrame
                card.layer.cornerRadius = cornerRadius
                card.subviews.first?.layer.cornerRadius = cornerRadius
                card.layer.shadowOpacity = shadowOpacity
                window.isUserInteractionEnabled = true
                self.hostCorners.forEach { $0.isHidden = false }
                self.hostMoveGrip?.isHidden = false
                self.hostTopGrip?.isHidden = false
                self.layoutHostControls()
                return
            }
            var ticks = 0
            var readyTicks = 0
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak window] timer in
                guard let self = self, let window = window, self.hostWindow === window else {
                    timer.invalidate()
                    return
                }
                ticks += 1
                readyTicks = PXSceneBridge.shared().frontmostBundleID() == bundleID
                    ? readyTicks + 1 : 0
                if readyTicks >= 2 || ticks >= 15 {
                    timer.invalidate()
                    self.closeHost(animated: false)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        })
    }

    @objc private func moveGripHeld(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { fullscreenTapped() }
    }

    @objc private func resizeHost(_ gesture: UIPanGestureRecognizer) {
        guard let window = hostWindow, let card = hostCard else { return }
        if gesture.state == .began {
            restoreKeyboardFocus()
            resizeStartFrame = card.frame
            resizeStartRadius = card.layer.cornerRadius
        }
        guard let start = resizeStartFrame else { return }
        if gesture.state == .changed || gesture.state == .ended {
            let translation = gesture.translation(in: window.rootViewController?.view)
            let horizontal = (gesture.view?.tag == -1 ? -translation.x : translation.x) / start.width
            let vertical = translation.y / start.height
            // Project both axes continuously; switching the dominant axis snaps the size.
            let change = (horizontal + vertical) / 2
            let screen = window.rootViewController?.view.bounds ?? UIScreen.main.bounds
            let horizontalRoom = gesture.view?.tag == -1 ?
                start.maxX - screen.minX - 12 : screen.maxX - start.minX - 12
            let hosted = activeBridge.hostedSourceSize()
            let natural = UIScreen.main.fixedCoordinateSpace.bounds.size
            let source = hosted.width > 0 && hosted.height > 0 ? hosted :
                CGSize(width: min(natural.width, natural.height), height: max(natural.width, natural.height))
            let base = initialCardSize(in: screen, source: source)
            let limit = CGFloat(min(200, max(100, UserDefaults(suiteName: preferenceDomain)?
                .object(forKey: "resizeMaxPercent") as? Int ?? 200))) / 100
            let maximum = min(horizontalRoom / start.width,
                              (screen.maxY - start.minY - 20) / start.height,
                              (base.width > 0 ? base.width : start.width) * limit / start.width)
            let minimumWidth = min(220, max(80, (screen.height - 40) * start.width / start.height))
            let minimum = minimumWidth / start.width
            let scale = min(max(1 + change, minimum), max(minimum, maximum))
            let size = CGSize(width: start.width * scale, height: start.height * scale)
            let x = gesture.view?.tag == -1 ? start.maxX - size.width : start.minX
            if gesture.state == .changed {
                if hostCanvas?.isUserInteractionEnabled == false {
                    dockAfterOpenBundleID = nil
                    fullscreenAfterOpenBundleID = nil
                }
                resizePreview = (scale, x, start.minY)
                applyResizePreview()
            } else {
                resizePreview = nil
                UIView.performWithoutAnimation {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    card.transform = .identity
                    card.frame = CGRect(x: x, y: start.minY,
                                        width: size.width, height: size.height)
                    card.layer.cornerRadius = resizeStartRadius
                    card.layoutIfNeeded()
                    activeBridge.layoutHost()
                    layoutHostControls()
                    CATransaction.commit()
                }
                if hostCanvas?.isUserInteractionEnabled == false {
                    launchWidthScale = size.width / max(1, base.width)
                    launchMovedCenter = card.center
                }
            }
        }
        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            resizePreview = nil
            if gesture.state != .ended {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                card.transform = .identity
                card.frame = start
                card.layer.cornerRadius = resizeStartRadius
                CATransaction.commit()
            }
            resizeStartFrame = nil
            layoutHostControls()
        }
    }

    @objc private func applyResizePreview() {
        guard let card = hostCard, let start = resizeStartFrame, let preview = resizePreview else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        card.transform = CGAffineTransform(scaleX: preview.scale, y: preview.scale)
        card.center = CGPoint(x: preview.x + start.width * preview.scale / 2,
                              y: preview.y + start.height * preview.scale / 2)
        card.layer.cornerRadius = resizeStartRadius / preview.scale
        layoutHostControls()
        CATransaction.commit()
    }

    @objc private func moveHost(_ gesture: UIPanGestureRecognizer) {
        guard let window = hostWindow, let card = hostCard else { return }
        if gesture.state == .began {
            restoreKeyboardFocus()
            moveStartFrame = card.frame
        }
        guard let start = moveStartFrame else { return }
        let translation = gesture.translation(in: window.rootViewController?.view)
        let velocity = gesture.velocity(in: window.rootViewController?.view)
        let dockSwipeEnabled = UserDefaults(suiteName: preferenceDomain)?
            .object(forKey: "dockSwipeEnabled") as? Bool ?? true
        if dockSwipeEnabled, gesture.view === hostMoveGrip,
           gesture.state == .ended, abs(translation.x) > 35,
           abs(translation.x) > abs(translation.y) * 1.2,
           abs(velocity.x) > 500, translation.x * velocity.x > 0 {
            moveStartFrame = nil
            parkMain(side: translation.x < 0 ? -1 : 1)
            return
        }
        let topReset = gesture.view === hostTopGrip && gesture.state == .ended &&
            translation.y < -35 && -translation.y > abs(translation.x) * 1.2 && velocity.y < -500
        if dockSwipeEnabled, gesture.view === hostMoveGrip,
           gesture.state == .ended, translation.y < -35,
           -translation.y > abs(translation.x) * 1.2,
           velocity.y < -500 {
            moveStartFrame = nil
            parkMain(side: defaultDockSide)
            return
        }
        let swipeDown = gesture.state == .ended && translation.y > 35 &&
            translation.y > abs(translation.x) * 1.2 && velocity.y > 500
        if topReset || swipeDown {
            moveStartFrame = nil
            if swipeDown, gesture.view === hostTopGrip, let bundleID = hostedBundleID {
                closeHost(animated: true, completion: { [weak self] in
                    guard let self = self, self.hostedBundleID != bundleID,
                          !self.dockedHosts.contains(where: { $0.bundleID == bundleID }) else { return }
                    _ = PXSceneBridge.shared().closeApplicationAndRemoveSwitcherCard(bundleID)
                })
                return
            }
            let screen = window.rootViewController?.view.bounds ?? UIScreen.main.bounds
            // Use the position before this swipe moved the card. Only the
            // bottom region at the initial position promotes the app fullscreen.
            let initial = initialCardFrame(in: screen, size: start.size)
            if swipeDown, gesture.view === hostMoveGrip,
               abs(start.maxX - initial.maxX) <= 2, abs(start.midY - initial.midY) <= 2 {
                fullscreenTapped()
                return
            }
            let source = activeBridge.hostedSourceSize()
            let natural = UIScreen.main.fixedCoordinateSpace.bounds.size
            let size = initialCardSize(in: screen, source: source.width > 0 && source.height > 0 ? source :
                CGSize(width: min(natural.width, natural.height), height: max(natural.width, natural.height)))
            let target = initialCardFrame(in: screen, size: size)
            guard target.width > 0, target.height > 0 else { return }
            dockAfterOpenBundleID = nil
            fullscreenAfterOpenBundleID = nil
            launchMovedCenter = nil
            launchWidthScale = nil
            let radius = card.layer.cornerRadius
            let scale = target.width / max(1, card.bounds.width)
            PXMotion.ease(0.24, animations: {
                card.transform = CGAffineTransform(scaleX: scale,
                                                   y: target.height / max(1, card.bounds.height))
                card.center = CGPoint(x: target.midX, y: target.midY)
                card.layer.cornerRadius = radius / scale
                self.layoutHostControls()
            }, completion: { _ in
                guard self.hostWindow === window else { return }
                UIView.performWithoutAnimation {
                    card.transform = .identity
                    card.frame = target
                    card.layer.cornerRadius = radius
                    if self.activeBridge.hostedSourceSize() != source { self.matchHostAspect() }
                    card.layoutIfNeeded()
                    self.activeBridge.layoutHost()
                    self.layoutHostControls()
                }
            })
            return
        }
        if gesture.state == .changed || gesture.state == .ended {
            if gesture.state == .changed, hostCanvas?.isUserInteractionEnabled == false {
                dockAfterOpenBundleID = nil
                fullscreenAfterOpenBundleID = nil
            }
            card.frame = start.offsetBy(dx: translation.x, dy: translation.y)
            if hostCanvas?.isUserInteractionEnabled == false { launchMovedCenter = card.center }
            layoutHostControls()
        }
        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            moveStartFrame = nil
        }
    }

    private func closeHost(animated: Bool, fullscreenHandoff: Bool = false, completion: (() -> Void)? = nil) {
        guard let window = hostWindow else { return }
        keyboardHideInFlight = false
        keyboardDismissSuppressed = false
        removeKeyboardDismissLayer()
        keyboardFocusBase = nil
        keyboardFocusFrame = .null
        let closingCard = hostCard
        resizePreview = nil
        hostCorners.forEach { $0.removeFromSuperview() }
        hostTopCorners.forEach { $0.removeFromSuperview() }
        hostMoveGrip?.removeFromSuperview()
        hostTopGrip?.removeFromSuperview()
        window.isUserInteractionEnabled = false
        hostWindow = nil
        hostCard = nil
        hostCanvas = nil
        hostCorners = []
        hostTopCorners = []
        hostMoveGrip = nil
        hostTopGrip = nil
        hostedBundleID = nil
        launchMovedCenter = nil
        launchWidthScale = nil
        dockAfterOpenBundleID = nil
        fullscreenAfterOpenBundleID = nil
        resizeStartFrame = nil
        moveStartFrame = nil
        needsHostRefresh = false
        fullscreenToWindowInProgress = false
        fullscreenLaunchInProgress = false
        let bridge = activeBridge
        let finish = { [weak self] in
            window.isHidden = true
            if self?.hostWindow == nil {
                if fullscreenHandoff { bridge.closeForFullscreen() }
                else { bridge.close() }
            }
            window.rootViewController = nil
            completion?()
        }
        if animated, let card = closingCard {
            PXMotion.ease(0.28, options: .curveEaseInOut, animations: {
                card.alpha = 0
                card.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
                card.layer.shadowOpacity = 0
            }, completion: { _ in finish() })
        } else { finish() }
    }

}
