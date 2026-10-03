from pathlib import Path
from math import pi, sin

root = Path(__file__).resolve().parents[1]
control = (root / "control").read_text(encoding="utf-8")
makefile = (root / "Makefile").read_text(encoding="utf-8")
panel = (root / "PXPanel.swift").read_text(encoding="utf-8")
bridge = (root / "PXSceneBridge.m").read_text(encoding="utf-8")
bridge_header = (root / "PXSceneBridge.h").read_text(encoding="utf-8")
tweak = (root / "Tweak.m").read_text(encoding="utf-8")
external_settings = (root / "prefs/Resources/External.plist").read_text(encoding="utf-8")
app_picker = (root / "prefs/PXAppPickerController.swift").read_text(encoding="utf-8")
action_picker = (root / "prefs/PXActionPickerController.swift").read_text(encoding="utf-8")
blacklist = (root / "prefs/PXExternalBlacklistController.swift").read_text(encoding="utf-8")

# Selected URL exclusions stay above other apps, including during search.
assert 'style: .insetGrouped' in blacklist and 'let toggle = UISwitch()' in blacklist
assert '.checkmark' not in blacklist and 'didSelectRowAt' not in blacklist
assert 'if left != right { return left }' in blacklist
assert 'for: .valueChanged' in blacklist and 'cell.accessoryView = toggle' in blacklist
external_target = tweak.split('static BOOL PXExternalTarget(', 1)[1].split('static id PXOptionsWithSuspendedLaunch(', 1)[0]
assert 'if ([values[@"__LaunchOrigin"] isEqualToString:@"BulletinDestinationCoverSheet"]) return NO;' in external_target
assert external_target.index('BulletinDestinationCoverSheet') < external_target.index('BOOL notification = PXIsNotificationOpen(values)')
assert 'BulletinDestinationBanner' in tweak and 'notificationSplitEnabled' in external_target
assert 'BOOL candidate = PXExternalTarget(' in tweak and tweak.count('BOOL candidate = PXExternalTarget(') == 2
assert '通知横幅跳转分屏' in external_settings and '通知中心点击仍按系统原方式全屏打开' in external_settings
apps = [('c', 'C'), ('b', 'B'), ('a', 'A')]
# Both native URL entry points close the expanded host only on successful
# blacklist launches. Notification taps and parked windows are unaffected.
assert 'if (closeSplitOut) *closeSplitOut = [excluded containsObject:bundleID];' in external_target
assert tweak.count('if (!error && closeSplit) PXCloseSplitAfterExcludedURL();') == 2
assert tweak.count('if (route || closeSplit)') == 2
excluded_close = panel.split('@objc public static func closeSplitAfterExcludedURL()', 1)[1].split('@objc public static func externalOpenApplication', 1)[0]
assert 'shared.closeHost(animated: true)' in excluded_close
assert 'removeDock' not in excluded_close and 'dockedHosts' not in excluded_close
assert 'logURLBlacklist' not in panel + tweak + bridge
# Real visible hosted clients need per-request trust for suspended URL opens.
# Do not trust payload attribution, parked/hidden hosts, brokers or notification taps.
trust = tweak.split('static BOOL PXTrustHostedURLRequest(', 1)[1].split('static BOOL PXExternalTarget(', 1)[0]
assert 'PXDeviceLocked || PXIsNotificationOpen(values)' in trust
assert 'PXRequestTrustState(request) != 0' in trust
assert 'NSString *sourceID = PXBundleID(source);' in trust and 'PXSourceBundleID(' not in trust
assert 'isInteractiveHostedURLSource:' in trust and 'signature.numberOfArguments != 3' in trust
assert 'PXRequestTrustState(request) == 1' in trust
assert 'if (prepared) PXTrustHostedURLRequest(request, source, options);' in tweak
request_flow = tweak.split('static void PXHandleOpenRequest(', 1)[1].split('static void PXHandleTrustedOpen(', 1)[0]
assert request_flow.index('request, setOptions, prepared') < request_flow.index('PXTrustHostedURLRequest(')
assert request_flow.index('PXTrustHostedURLRequest(') < request_flow.index('PXOriginalHandleOpenRequest(')
assert 'if (original) original(error);' in request_flow
source_gate = panel.split('func isInteractiveHostedURLSource(', 1)[1].split('@objc public static func start()', 1)[0]
assert 'Thread.isMainThread, !shared.deviceLocked, !shared.coverSheetVisible' in source_gate
assert 'shared.hostedBundleID == bundleID' in source_gate and 'shared.activeBridge.hasHostedSurface()' in source_gate
assert 'isHidden == false' in source_gate and 'isUserInteractionEnabled == true' in source_gate
assert 'dockedHosts' not in source_gate
assert 'PXOriginalServiceActivate' not in tweak and 'PXOriginalServiceTrusted' not in tweak
for removed in ('logURLOpen', 'traceURLOpen', 'PXTraceURLOpen', 'url-open.log', 'trustedBefore', 'trustApplied'):
    assert removed not in tweak + panel + bridge + bridge_header
# Both external launch callbacks reuse the ordinary fullscreen-to-host handoff.
# Only the currently fullscreen target leaves the native fullscreen presentation.
external_open = panel.split('@objc public static func externalOpenApplication(', 1)[1].split('private func externalOpenFailed(', 1)[0]
assert 'shared.panelFrontmostBundleID = PXSceneBridge.shared().frontmostBundleID()' in external_open
assert external_open.index('shared.panelFrontmostBundleID =') < external_open.index('shared.openHost(bundleID)')
assert 'shared.panelFrontmostBundleID = nil' not in external_open
open_host = panel.split('private func openHost(', 1)[1].split('private func openFullscreen(', 1)[0]
assert 'let wasFullscreen = panelFrontmostBundleID == bundleID' in open_host
assert 'presentHost(bundleID, wasFullscreen: wasFullscreen)' in open_host
for frontmost, target, current_at_handoff, expected in (
    ('target', 'target', 'target', True),
    ('main', 'target', 'main', False),
    (None, 'target', None, False),
    ('target', 'target', 'other', False),
):
    was_fullscreen = frontmost == target
    assert (was_fullscreen and current_at_handoff == target) == expected
# Empty UIKit keyboard containers do not count as visible keyboards or relocate.
content_gate = bridge.split('static BOOL PXKeyboardHasContent(', 1)[1].split('static BOOL PXSetBool(', 1)[0]
assert 'layer.sublayers.count > 0' in content_gate
assert 'NSSelectorFromString(@"contextId")' in content_gate
assert 'respondsToSelector:context' in content_gate and 'objc_msgSend)(layer, context) != 0' in content_gate
assert 'return view.bounds.size.height > 0 && PXKeyboardHasContent(view);' in bridge
assert 'BOOL visible = PXKeyboardHasContent(view) && view.window && !view.window.hidden;' in bridge
relocation = bridge.split('- (void)relocateKeyboardView:(UIView *)view', 1)[1].split('- (void)relocateExistingKeyboard:', 1)[0]
assert 'if (![self usesExternalKeyboard] || !PXKeyboardHasContent(view))' in relocation
empty_branch = relocation.split('\n    if (view == self.keyboardHostView) {', 1)[0]
assert '[self.keyboardOriginalParent addSubview:view]' in empty_branch
assert '[self.keyboardSlot removeFromSuperview]' in empty_branch and '[self publishKeyboardVisibility]' in empty_branch
for height, sublayers, context, expected in ((926, 0, 0, False), (926, 1, 0, True), (360, 1, 0, True), (360, 0, 42, True), (0, 1, 0, False)):
    assert (height > 0 and (sublayers > 0 or context != 0)) == expected
# Confirmed keyboard-content fix stays, temporary diagnostic code does not.
for removed in ('logKeyboardShadowEvent', 'traceKeyboardState', 'traceKeyboardDismissState',
                'keyboardShadowProbeState', 'keyboardProbeState', 'keyboard-shadow'):
    assert removed not in bridge + bridge_header + panel + tweak
excluded = {'b'}
assert sorted(apps, key=lambda app: (app[0] not in excluded, app[1])) == [('b', 'B'), ('a', 'A'), ('c', 'C')]

# Only our matched app-to-Home request receives immediate fluid-switcher settings.
handoff = tweak.split('static BOOL PXExecuteTransition(', 1)[1].split('static NSString *PXBundleID', 1)[0]
assert '[to count] == 0' in handoff and 'consumeHomeHandoffForBundleID:bundleID' in handoff
assert 'objc_setAssociatedObject(request, &PXHomeHandoffRequestKey' in handoff
assert 'objc_getAssociatedObject(request, &PXHomeHandoffRequestKey)' in handoff
assert 'PXOriginalFluidAnimationInit(controller, selector, request, settings, block)' in handoff
assert 'settingsWithDuration:' in handoff and 'animation, zero, 0' in handoff
assert 'dispatch_after' not in handoff and 'sleep' not in handoff
assert 'method_getNumberOfArguments(initializer) == 5' in tweak
assert 'PXTransitionProbe' not in tweak and 'PXTransitionProbe' not in bridge
assert 'SBUIAnimationController' not in tweak
assert 'consumeHomeHandoffForCurrentApplication' in tweak and 'consumeHomeHandoffForCurrentApplication' in bridge_header
handoff = tweak.split('static BOOL PXExecuteTransition(', 1)[1].split('static id PXFluidAnimationInit', 1)[0]
assert handoff.index('if (!matched &&') < handoff.index('if (matched)')
assert '[from count] == 0' in handoff and '[to count] == 0' in handoff
assert handoff.index('consumeHomeHandoffForCurrentApplication') < handoff.index('objc_setAssociatedObject')
assert 'layer.hidden =' not in tweak and 'layer.opacity =' not in tweak

assert 'originalCardFrame' not in panel
assert 'PXLandscapeProbe' not in bridge and 'LandscapeProbe' not in bridge_header
assert 'traceLandscape' not in panel and 'for delay in [0.2, 0.8, 1.6]' not in panel
screen_geometry = panel.split('@objc private func screenGeometryChanged()', 1)[1].split('@objc private func hostedGeometryChanged', 1)[0]
assert 'if !fullscreenToWindowInProgress' not in screen_geometry
assert 'UIView.performWithoutAnimation { matchHostAspect() }' in screen_geometry
assert 'activeBridge.refreshHostedOrientationMap()' in screen_geometry
assert 'let rotating = orientation != layoutOrientation && layoutOrientation != .unknown' in screen_geometry
assert 'if rotating && !fullscreenToWindowInProgress {' in screen_geometry
assert screen_geometry.index('layoutDocks(animated: false)') < screen_geometry.index('PXMotion.rotation(card, from: frame, in: oldBounds, to: screen,')
rotation_motion = panel.split('static func rotation(_ card: UIView', 1)[1].split('\n}', 1)[0]
assert 'UIAccessibility.isReduceMotionEnabled' in rotation_motion and 'animation.duration = 0.32 / speed' in rotation_motion
assert 'card.layer.add(animation, forKey: "pxScreenRotation")' in rotation_motion
assert 'oldOrientation.isLandscape != newOrientation.isLandscape' in rotation_motion
assert '(landscape == .landscapeLeft ? -1 : 1) * (oldOrientation.isLandscape ? 1 : -1)' in rotation_motion
assert 'CATransform3DRotate(' in rotation_motion and 'sqrt(frame.width * frame.height /' in rotation_motion
assert 'oldOrientation: oldOrientation, newOrientation: orientation' in screen_geometry
for old_size, new_size, old_center in (((390, 844), (844, 390), (300, 422)),
                                       ((844, 390), (390, 844), (60, 70))):
    start = tuple(old_center[index] / old_size[index] * new_size[index] for index in (0, 1))
    assert 0 <= start[0] <= new_size[0] and 0 <= start[1] <= new_size[1]
assert 'self.originalOrientationMapResolver = PXCall(settings, @"interfaceOrientationMapResolver")' in bridge
assert 'objc_msgSend)(mutable, resolver, self.originalOrientationMapResolver)' in bridge
foreground = bridge.split('- (BOOL)foregroundScene:', 1)[1].split('- (void)keepHostedProcessAlive', 1)[0]
assert '[[self frontmostBundleID] isEqualToString:self.bundleID]' in foreground
assert foreground.index('orientation = current;') < foreground.index('PXSetHostedOrientation(mutable, orientation)')
for is_frontmost, current, preferred, expected in (
    (True, 3, 1, 3), (True, 4, 1, 4), (True, 1, 1, 1),
    (False, 3, 1, 1), (False, 3, 3, 3), (True, 0, 1, 1),
):
    orientation = current if is_frontmost and 1 <= current <= 4 else preferred
    assert orientation == expected
# Device log: Home narrows 926 to 428 while the card remains at x=660.6.
# Recompute against the new screen even while fullscreen handoff is active.
source_width, source_height = 428, 926
screen_width, screen_height = 428, 926
scale = min(screen_width * .78 / source_width, (screen_height - 80) / source_height)
card_width, card_height = source_width * scale, source_height * scale
card_x, card_y = screen_width - card_width - 12, (screen_height - card_height) / 2
assert 0 <= card_x and card_x + card_width <= screen_width
assert 0 <= card_y and card_y + card_height <= screen_height
assert 'uniquingKeysWith:' in app_picker and 'uniquingKeysWith:' in action_picker
assert app_picker.count('[weak alert]') >= 2 and '[weak self, weak alert]' in app_picker
assert 'context respondsToSelector:@selector(mutableCopy)' in tweak
assert '@catch (__unused NSException *exception) { return context; }' in tweak
assert 'PXRuntimeHostedOrientation(client)' in bridge.split('static UIInterfaceOrientation PXPreferredHostedOrientation', 1)[1].split('// PullOver-X', 1)[0]
assert '- (BOOL)hasHostedSurface;' in bridge_header
assert 'if activeBridge.hasHostedSurface(), !window.isHidden {' in panel
assert 'frontDisplayChanged:' in tweak and 'frontDisplayChanged(_ bundleID: String?)' in panel
front_display = panel.split('@objc public static func frontDisplayChanged(_ bundleID: String?)', 1)[1].split('@objc public static func', 1)[0]
assert 'shared.coverSheetVisible, !shared.coverSheetPresented, !shared.coverSheetEntering' in front_display
assert front_display.index('shared.coverSheetVisible = false') < front_display.index('shared.updateHandleVisibility()')
switcher_cleanup = panel.split('@objc public static func switcherRemovedApplication', 1)[1].split('@objc public static func externalOpenApplication', 1)[0]
assert 'shared.hostedBundleID == bundleID' in switcher_cleanup and 'shared.closeHost(animated: false)' in switcher_cleanup
assert 'dock.bundleID == bundleID' in switcher_cleanup and 'shared.removeDock(dock)' in switcher_cleanup
assert 'killContainer:forReason:' in tweak and 'PXKillSwitcherContainer' in tweak
assert tweak.index('switcherRemovedApplication:') < tweak.index('PXOriginalKillSwitcherContainer(switcher, selector, container, reason)')
assert 'window.windowLevel = .alert + 52' in panel.split('private func beginPanel()', 1)[1].split('@objc private func dragHandle', 1)[0]

assert "Package: com.moxuan.parallelx" in control
assert "firmware (<< 17.0)" in control
assert "PXPanel.swift" in makefile and "PXSceneBridge.m" in makefile
assert 'stringArray(forKey: "applications")' in panel
assert 'dictionary(forKey: "applicationNames")' in panel
assert 'launcherIconSize' in panel and 'launcherRing\\(index + 1)' in panel
assert 'let ringSpacing = size + ringGap' in panel
assert 'previousRadius + (rings.isEmpty ? 0 : ringSpacing)' in panel
assert 'ring.radius * cos(theta)' in panel and 'ring.radius * sin(theta)' in panel
assert 'let angle: CGFloat = .pi / 2' in panel
assert 'let desiredRadius = requested == 1' in panel
assert 'pageCapacity = max(1, rings.reduce' in panel
assert 'let centerX = view.bounds.maxX - size / 2 - edgeInset' in panel
assert 'sheet = UIVisualEffectView' not in panel
assert 'launcherDragDistance' in panel
assert 'updateSelection(at: gesture.location(in: controller.view))' in panel
assert 'selectedSince = next.map { applicationID(apps[$0].id) != nil || ["px.action.screenshot", "px.action.window"].contains(apps[$0].id) }' in panel
assert 'if applicationID(id) != nil || id == "px.action.brightness" || id == "px.action.screenshot" || id == "px.action.window"' in panel
assert 'recentApplicationSkipping(excluded, rank: rank)' in panel
assert 'return (1...count).map { rank in' in panel
assert 'id.hasPrefix("px.recent.")' in panel
assert 'hideForScreenshot' in panel and 'PXSceneBridge.setCaptureHidden(hide, for: handle)' in panel
assert 'hasScene(forApplication: bundleID)' in panel
assert 'launchImage(forApplication: bundleID, size: card.bounds.size)' in panel
assert 'urlShortcuts' in panel and 'shortcutSymbols' in panel
assert '[overlay insertSubview:slot atIndex:0]' in bridge
assert 'recentApplicationSkipping:(NSArray<NSString *> *)excluded rank:(NSInteger)rank' in bridge
assert 'UISelectionFeedbackGenerator()' in panel
assert 'UIImpactFeedbackGenerator(style: .medium)' in panel
assert 'holdFeedbackTask?.cancel()' in panel
assert 'self.selectedIndex == next' in panel
assert 'selectedDuration >= controller.holdDuration' in panel
reset_gesture = panel.split('if topReset || swipeDown {', 1)[1].split('if gesture.state == .changed || gesture.state == .ended', 1)[0]
animated_reset = reset_gesture.split('PXMotion.ease(0.24', 1)[1]
assert animated_reset.index('card.transform = CGAffineTransform(scaleX: scale') < animated_reset.index('card.frame = target')
assert animated_reset.index('UIView.performWithoutAnimation {') < animated_reset.index('card.frame = target')
assert reset_gesture.index('card.layer.cornerRadius = radius / scale') < reset_gesture.index('card.layer.cornerRadius = radius\n')
window_action = panel.split('if action == "px.action.window" {', 1)[1].split('} else { hidePanel {', 1)[0]
assert window_action.index('hidePanel(animated: false)') < window_action.index('performWindowHold()')
panel_close = panel.split('private func hidePanel(animated: Bool = true', 1)[1].split('private func openHost', 1)[0]
assert panel_close.index('self.setHandlePanelProgress(0)') < panel_close.rindex('completion?()')
assert 'guard let fullID = fullID else { parkMain(side: defaultDockSide); return }' in panel
window_hold = panel.split('private func performWindowHold()', 1)[1].split('private func restartCurrentApplication()', 1)[0]
assert 'else if let fullID = fullID {' in window_hold
assert 'dockedHosts.isEmpty' not in window_hold
assert 'dockAfterOpenBundleID = fullID' in window_hold
assert 'while dockedHosts.count >= limit, let oldest = dockedHosts.first { removeDock(oldest) }' in panel
assert 'pendingSwap = (splitID, fullID)' in panel
assert 'if self.dockAfterOpenBundleID == bundleID {' in panel
assert 'if wasFullscreen && !skipHandoffAnimation {' in panel
assert 'handleCenterFraction' in panel and 'handleDragMode == 2' in panel
assert 'buttonRings.append(ringIndex)' in panel and 'controller.animateClosed' in panel
assert 'selectionPreview.layer.cornerRadius = 26' in panel
assert 'width: 110, height: 110' in panel
assert 'selectionPreview.layer.borderWidth = 6' in panel
assert 'shortcuts: [(id: String, name: String, symbol: String)]' in panel
assert 'if hostedBundleID == bundleID, hostWindow != nil { fullscreenTapped(); return }' in panel
assert 'window.windowLevel = .statusBar + 0.2' in panel
assert 'shadowStrength' in panel and 'shadowBlur' in panel
assert 'card.layer.shadowPath = UIBezierPath' in panel
assert 'let card = UIView(frame: cardFrame)' in panel
assert 'launcherHoldMilliseconds' in panel
assert 'handleWidth' in panel and 'handleHeight' in panel
assert 'showPanel()' not in panel
for count in (3, 5, 7, 12):
    spacing = 62
    radius = spacing / (2 * sin(pi / (2 * (count - 1))))
    assert 2 * radius * sin(pi / (2 * (count - 1))) >= spacing - 1e-6
assert 'bridge.close()' in panel
assert 'screen.width * initialWidthFraction / source.width' in panel
assert "CGSize(width: source.width * scale, height: source.height * scale)" in panel
assert "let canvas = UIView(frame: clip.bounds)" in panel
assert panel.index("root.view.addSubview(card)") < panel.index("let clip = UIView(frame:")
assert "private func refreshHost()" in panel
assert "height: start.height * scale" in panel
assert "#selector(resizeHost(_:))" in panel
assert "if gesture.state == .began { fullscreenTapped() }" in panel
fullscreen = panel.split('@objc private func fullscreenTapped()', 1)[1].split('@objc private func moveGripHeld', 1)[0]
assert fullscreen.index('PXMotion.spring(') < fullscreen.index('openFullscreenApplication(bundleID)')
assert 'card.frame = cardFrame' in fullscreen
assert fullscreen.index('openFullscreenApplication(bundleID)') < fullscreen.index('self.closeHost(animated: false)')
assert 'readyTicks >= 2 || ticks >= 15' in fullscreen
assert 'fullscreenToWindowInProgress = wasFullscreen' in panel
assert 'shared.closeHost(animated: false, fullscreenHandoff: true)' in panel
assert '!shared.fullscreenLaunchInProgress' in panel
assert 'deadline: .now() + 0.75' not in fullscreen
assert 'exposeSystemHomeIndicator' not in panel
close_host = panel.split('private func closeHost(animated: Bool, fullscreenHandoff: Bool = false, completion:', 1)[1]
assert close_host.index('window.isHidden = true\n            if self?.hostWindow == nil') < close_host.index('window.rootViewController = nil\n            completion?()')
assert "#selector(moveHost(_:))" in panel
assert "card.layer.cornerRadius" in panel and '"cornerRadius"' in panel
assert 'resizePreview = (scale, x, start.minY)\n                applyResizePreview()' in panel
resize = panel.split('private func resizeHost', 1)[1].split('private func applyResizePreview', 1)[0]
assert 'card.layer.shadowOpacity = 0' not in resize
assert 'card.layer.cornerRadius = resizeStartRadius / preview.scale' in panel
assert 'let change = (horizontal + vertical) / 2' in panel
assert '(base.width > 0 ? base.width : start.width) * limit' in panel
assert '"resizeMaxPercent"' in (root / 'prefs' / 'PXCornerRadiusController.swift').read_text(encoding='utf-8')
assert 'abs(horizontal) > abs(vertical)' not in panel
# The alphabet selector deliberately draws an arc; corner gesture regions must stay invisible.
outside_selector = panel.split('private final class PXAppSelectorView:', 1)[0] + panel.split('private final class PXSearchViewController:', 1)[1]
assert 'PXCornerGrip' not in panel and 'path.addQuadCurve' not in outside_selector
assert 'corner.isOpaque = false' in panel
assert 'corner.backgroundColor = debug ?' in panel
assert 'for side in [-1, 1]' in panel
assert 'root.view.addSubview(corner)' in panel
assert 'root.view.addSubview(moveGrip)' in panel
assert 'window.frame = scene.coordinateSpace.bounds' in panel
assert 'window.isUserInteractionEnabled = false' in panel
assert 'hostMoveGrip?.frame = CGRect' in panel
assert 'hostTopGrip?.frame = CGRect' in panel and 'hostTopGrip = dock.topGrip' in panel
assert 'gestureWidth' in panel and 'gestureHeight' in panel and 'gestureOffset' in panel
assert 'gestureDebug' in panel and 'moveLine' not in panel
assert 'moveGrip.backgroundColor = .clear' in panel
assert 'corner.backgroundColor = debug ? UIColor.systemBlue.withAlphaComponent(0.25) : .clear' in panel
assert 'top.backgroundColor = debug ? UIColor.systemBlue.withAlphaComponent(0.25) : .clear' in panel
assert panel.count('PXSceneBridge.keepTransparentGestureViewHittable(') == 4
assert 'PXSetBool(view.layer, @"setHitTestsAsOpaque:", YES)' in bridge
assert 'hostCorners.forEach { $0.removeFromSuperview() }' in panel
assert 'moveGrip.addGestureRecognizer(doubleTap)' in panel
assert 'numberOfTapsRequired = 2' in panel
assert '#selector(moveGripHeld(_:))' in panel
assert 'let clip = UIView(frame: card.bounds)' in panel
assert 'let toolbarWidth' not in panel
assert 'layoutHostControls()' in panel.split('@objc private func moveHost')[1].split('private func closeHost')[0]
assert 'private func layoutHostControls()' in panel
assert 'self?.screenGeometryChanged()' in panel and 'self?.layoutHostControls()' in panel
assert 'if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle { onAppearance?() }' in panel
assert 'root.onAppearance = { [weak self] in' in panel
assert 'if expectedSize == layoutScreenBounds.size && orientation == layoutOrientation { return }' in panel
assert 'shared.hostWindow?.isHidden == false' in panel
assert 'shared.dockedHosts.contains { !$0.window.isHidden }' in panel.split('func hasVisibleHost()', 1)[1].split('@objc public static func start()', 1)[0]
assert 'PXHostedAppearanceContext(context, protected != nil)' in tweak
assert 'settingsWithDuration:' in tweak and 'setAnimationSettings:' in tweak
assert '_animateUserInterfaceStyleChangeInScene:transitionContext:applyChangesBlock:' not in tweak
assert 'com.moxuan.parallelx.appearance.log' not in tweak
assert 'let root = PXHostViewController()' in panel.split('private func presentHost')[1]
assert 'layoutHostControls()' in panel.split('private func matchHostAspect()')[1].split('private func layoutHostControls()')[0]
assert 'let window = PXHandleWindow(windowScene: scene)' in panel
assert 'panelFrontmostBundleID = PXSceneBridge.shared().frontmostBundleID()' in panel
assert '"↙"' not in panel and '"↘"' not in panel
assert 'presentHost(bundleID, wasFullscreen: wasFullscreen)' in panel
assert 'activeBridge.prepareWindow(for: bundleID, wasFullscreen: wasFullscreen)' in panel
assert panel.index('let card = UIView(frame: cardFrame)') < panel.index('activeBridge.prepareWindow(for: bundleID, wasFullscreen: wasFullscreen)')
handoff = panel.split('private func presentHost(', 1)[1].split('private func matchHostAspect()', 1)[0]
assert 'card.backgroundColor = .clear' in handoff
assert 'clip.backgroundColor = .secondarySystemBackground' in handoff
assert 'clip.insertSubview(preview, aboveSubview: canvas)' in handoff
assert 'card.viewWithTag(0x50584c)' in handoff
assert 'preview.layer.cornerRadius' not in handoff
assert handoff.index('activeBridge.openApplication(bundleID, in: canvas') < handoff.index('self.activeBridge.prepareWindow(for: bundleID, wasFullscreen: wasFullscreen)')
assert 'window.isHidden = wasFullscreen' in handoff
assert handoff.index('window.isUserInteractionEnabled = true\n        canvas.isUserInteractionEnabled = false') < handoff.index('activeBridge.openApplication(bundleID, in: canvas')
assert 'canvas.isUserInteractionEnabled = true\n                window?.isUserInteractionEnabled = true' in handoff
assert 'launchMovedCenter = nil' in handoff
assert 'homeReady' not in handoff and 'finishWhenReady' not in handoff
assert handoff.index('window?.isHidden = false') < handoff.index('self.activeBridge.prepareWindow(')
assert handoff.index('let skipHandoffAnimation = self.dockAfterOpenBundleID == bundleID ||') < handoff.index('card.layer.cornerRadius = 0')
assert 'self.fullscreenAfterOpenBundleID == bundleID' in handoff
assert 'if wasFullscreen && (!skipHandoffAnimation || dockingFullscreen), frame.width > 0, frame.height > 0 {' in handoff
assert handoff.index('self.activeBridge.prepareWindow(') < handoff.index('if wasFullscreen && !skipHandoffAnimation {\n                PXMotion.spring(0.4')
assert 'let scale = min(screen.width / frame.width, screen.height / frame.height)' in handoff
assert handoff.index('clip.insertSubview(preview, aboveSubview: canvas)') < handoff.index('activeBridge.openApplication(bundleID, in: canvas')
assert 'UIActivityIndicatorView' not in handoff and 'spinner' not in handoff
open_host = bridge.split('- (void)openApplication:', 1)[1].split('- (void)closeForFullscreen', 1)[0]
assert 'retry();' in open_host and 'dispatch_async(dispatch_get_main_queue(), retry)' not in open_host
assert 'card.transform = CGAffineTransform(scaleX: scale, y: scale)' in panel
assert 'UIScene.willDeactivateNotification' in panel
assert 'needsHostRefresh' in panel
assert 'BOOL shouldReturnHome = wasFullscreen && [currentID isEqualToString:bundleID]' in bridge
assert 'screen.maxX' not in panel.split('@objc private func moveHost')[1].split('private func closeHost')[0]
assert "PXSetSceneFrame(mutable, PXServerFrameSize(mutable))" in bridge
assert 'PXRect(PXCall(settings, @"displayConfiguration"), @"bounds")' in bridge
assert "CGFloat scale = MIN(target.width / source.width, target.height / source.height)" in bridge
assert "host.transform = CGAffineTransformMakeScale(scale, scale)" in bridge
assert 'CGAffineTransformRotate' not in bridge
assert 'layer.frame = host.bounds' not in bridge
assert 'relocateKeyboardView:(UIView *)view' in bridge
assert 'self.keyboardOverlay = keyboardOverlay' in bridge
assert 'slot.opaque = NO' in bridge
assert 'screen.height * 0.55' in bridge and 'screen.height * 0.4' not in bridge
keyboard_layout = bridge.split('- (BOOL)layoutExternalKeyboardView:(UIView *)view', 1)[1].split('- (void)relocateKeyboardView:', 1)[0]
assert 'screen.width > screen.height' in keyboard_layout
assert 'self.keyboardSlot.transform = CGAffineTransformMakeScale' not in keyboard_layout
assert 'self.keyboardSlot.frame = CGRectMake(x, screen.height - height, width, height)' in keyboard_layout
assert 'view.frame = CGRectMake(0, height - keyboard.height, width, keyboard.height)' in keyboard_layout
assert 'CGFloat height = MIN(keyboard.height, screen.height)' in keyboard_layout
assert 'externalKeyboardHorizontalPercent' in keyboard_layout
assert 'screen.height * 0.55' in keyboard_layout.split('} else {', 1)[1]
assert 'key = "externalKeyboardHorizontalPercent"; default = 0; min = 0; max = 100;' in (root / 'prefs/Resources/Keyboard.plist').read_text(encoding='utf-8')
preferences_page = (root / 'prefs/PXRootListController.m').read_text(encoding='utf-8')
assert 'BOOL horizontal = [[specifier propertyForKey:@"key"] isEqual:@"externalKeyboardHorizontalPercent"]' in preferences_page
assert 'horizontal ? @"横屏外置键盘位置" : @"键盘关闭遮罩深度"' in preferences_page
assert 'int maximum = focus ? 200 : horizontal ? 100 : 60' in preferences_page
assert '[weakSelf setPreferenceValue:@(control.value / multiplier) specifier:specifier]' in preferences_page
for screen, keyboard in (((926, 428), (428, 600)), ((926, 428), (428, 360))):
    width, height = min(keyboard[0], screen[0]), min(keyboard[1], screen[1])
    for position in (0, .5, 1):
        x = (screen[0] - width) * position
        assert 0 <= x and x + width <= screen[0] and height <= screen[1]
assert 'Class keyboard = NSClassFromString(@"_UIKeyboardLayerHostView")' in (root / "Tweak.m").read_text(encoding="utf-8")
assert "openFullscreenApplication:" in (root / "PXSceneBridge.h").read_text(encoding="utf-8")
assert 'if (self.scene && [self.bundleID isEqualToString:bundleID])' in bridge
assert 'activateApplication:fromIcon:location:activationSettings:actions:' in bridge
assert 'PXProbeFullscreenRuntime' not in bridge
assert 'performShortcut:(NSString *)identifier' in bridge
assert all(action in bridge for action in ('px.action.dark', 'px.action.record',
                                          'px.action.rotation', 'px.action.screenshot'))
assert "_returnToHomeScreenWithCompletion:" in bridge
prepare = bridge.split("- (void)prepareWindowForBundleID:", 1)[1].split("- (void)layoutHost", 1)[0]
assert "id controller = UIApplication.sharedApplication;" in prepare
assert "SBHomeHardwareButtonActions" in prepare and "performSinglePressUpActions" in prepare
assert prepare.index('performSinglePressUpActions') < prepare.index('_returnToHomeScreenWithCompletion:')
assert 'finish(NO);' in prepare
assert 'objc_msgSend)(controller, selector, nil)' in prepare
assert "host.autoresizingMask" not in bridge
assert '_UISceneLayerHostContainerView' in bridge
assert 'hostViewForRequester:enableAndOrderFront:' in bridge
assert 'disableHostingForRequester:' in bridge
assert 'updateSettings:withTransitionContext:completion:' in bridge
assert 'updateSettings:withTransitionContext:' not in bridge.replace('updateSettings:withTransitionContext:completion:', '')
entry = (root / "Tweak.m").read_text(encoding="utf-8")
assert 'MSHookMessageEx(scene, update' in entry
assert 'protectedSettings:settings forAnyScene:scene' in entry
assert 'PXSceneBridge relocateAnyKeyboardView:view' in entry
assert 'private func layoutDocks(animated: Bool = true)' in panel and 'private func restoreDock(' in panel
assert 'dock.card.transform = CGAffineTransform(scaleX: scale, y: scale)' in panel
assert 'dock.card.transform = .identity' in panel
assert 'dock.card.frame = CGRect(origin: .zero, size: frame.size)' not in panel
assert 'if hostWindow != nil {' in panel
assert 'dock.side = sender.direction == .left ? -1 : 1' in panel
assert 'overlay.addGestureRecognizer(swipe)' in panel
park = panel.split('private func parkMain(side: Int, animated: Bool = true)', 1)[1].split('private func layoutDocks(', 1)[0]
assert 'root.addSubview(overlay)' in park and 'controls.addSubview(overlay)' not in park
assert 'window.windowLevel =' not in park
assert 'card.layer.shadowOpacity = 0' not in park
assert 'let overlay = UIView(frame: card.frame)' in park
assert 'dock.overlay.frame = frame' in panel
assert 'dock.window.windowLevel = .statusBar + 0.3' in panel
assert 'dock.window.isUserInteractionEnabled = true' in panel
assert 'activeBridge.setHostedInteractionEnabled(false)' in panel
assert 'dock.bridge.setHostedInteractionEnabled(!dock.loading)' in panel
assert bridge.count('setAllowsSelection:", !self.suppressSelection') == 2
assert 'host.userInteractionEnabled = !strongSelf.suppressSelection' in bridge
assert 'shared.removeDock(dock, fullscreenHandoff: true)' in panel
assert 'dock.bridge.closeForFullscreen()' in panel
assert 'activateApplication:fromIcon:location:activationSettings:actions:' in entry
assert 'applicationActivated:' in entry
assert 'self.fullscreenHandoff = YES;\n    [self close];' in bridge
assert 'hostTopCorners' in panel and '#selector(dockTapped(_:))' in panel
assert 'PXDockController.swift' in (root / 'prefs' / 'Makefile').read_text(encoding='utf-8')
dock_prefs = (root / 'prefs' / 'PXDockController.swift').read_text(encoding='utf-8')
assert 'UISegmentedControl(items: ["左侧", "右侧"])' in dock_prefs
assert 'forKey: "dockSide"' in dock_prefs
assert 'parkMain(side: defaultDockSide)' in panel.split('private func dockTapped', 1)[1].split('private func parkMain', 1)[0]
park_main = panel.split('private func parkMain(side: Int, animated: Bool = true)', 1)[1].split('private func layoutDocks(', 1)[0]
assert 'let loading = !canvas.isUserInteractionEnabled' in park_main
assert 'loading: loading' in park_main and 'dockedHosts.append(dock)' in park_main
assert 'guard canvas.isUserInteractionEnabled else {' not in park_main
assert 'let source = sourceForDock(dock)' in panel.split('private func layoutDocks(', 1)[1].split('private func restoreDockTapped', 1)[0]
assert 'let dock = self.dockedHosts.first { $0.window === window }' in handoff
assert 'parkMain(side: sender.tag)' not in panel
assert 'com.apple.springboard.lockstate' in entry
assert 'com.apple.springboard.hasBlankedScreen' in tweak
lock_callback = tweak.split('notify_register_dispatch("com.apple.springboard.lockstate"', 1)[1].split('uint64_t initialLockState', 1)[0]
assert 'state == 0' in lock_callback and 'blanked != 0' in lock_callback
assert 'PXPublishLockState(YES)' in lock_callback
assert 'guard !deviceLocked, needsHostRefresh' in panel
assert 'bool(forKey: "clearOnLock")' in panel
assert 'for dock in Array(dockedHosts) { removeDock(dock) }' in panel
assert 'recordDockTouch' not in panel and 'touchProbe' not in panel
assert 'overlay.backgroundColor = UIColor(white: 1, alpha: 0.02)' in panel
assert 'max(35, min(requested' in panel
dock_settings = (root / 'prefs' / 'PXDockController.swift').read_text(encoding='utf-8')
assert 'widthSlider.minimumValue = 35' in dock_settings
assert 'landscapeWidthSlider.maximumValue = 240' in dock_settings
assert 'forKey: "landscapeDockWidth"' in dock_settings
assert 'source.width > source.height ? "landscapeDockWidth" : "dockWidth"' in panel
assert 'let itemWidth = dockWidth(for: itemSource, in: screen)' in panel
for source, expected_width in (((926, 428), 220), ((428, 926), 110)):
    settings = {'dockWidth': 110, 'landscapeDockWidth': 220}
    key = 'landscapeDockWidth' if source[0] > source[1] else 'dockWidth'
    width = min(428 - 54, min(240, max(35, settings.get(key, settings['dockWidth']))))
    assert width == expected_width
# The next slot starts below the actual landscape height, not portrait width.
landscape_height = 220 * 428 / 926
assert abs((62 + landscape_height + 12) - 175.68466522678186) < .001
assert 'onBrightnessHold' in panel and 'start.value + (start.y - y)' in panel
assert 'setBrightnessLevel:(float)level' in bridge
picker = (root / 'prefs' / 'PXAppPickerController.swift').read_text(encoding='utf-8')
assert 'px.action.brightness' in panel and 'px.action.brightness' in picker
assert all(action in panel and action in picker for action in ('px.action.restart', 'px.action.search'))
assert 'kill(pid, SIGKILL)' in bridge and 'pid == getpid()' in bridge
assert 'private func showSearch()' in panel and 'private func hideSearch()' in panel
assert 'root.view.addSubview(top)' in panel and 'top.addSubview(mark)' not in panel
assert 'initialCardFrame(in: screen, size:' in panel.split('private func restoreDock', 1)[1]
assert 'root.bounds.height * 0.405' in panel
assert 'PXApplicationIconLarge(id)' in panel
assert 'navigationItem.searchController = search' in picker
assert 'localizedCaseInsensitiveContains(query)' in picker
assert 'CGSize(width: 32, height: 32)' in picker
root_plist = (root / 'prefs' / 'Resources' / 'Root.plist').read_text(encoding='utf-8')
assert 'cell = PSLinkCell; label = "应用、快捷操作与排序"' in root_plist
assert 'key = "clearOnLock"' in (root / 'prefs/Resources/System.plist').read_text(encoding='utf-8')
# The shared handle window has one current-state level owner, not per-keyboard
# snapshots that can outlive Cover Sheet transitions or another hosted bridge.
assert 'keyboardWindowLevel' not in bridge
assert 'keyboardOverlay.window.windowLevel' not in bridge
assert 'overlay.window.windowLevel' not in bridge
appearance = panel.split('private func updateHandleAppearance()', 1)[1].split('private func setHandlePanelProgress(', 1)[0]
assert 'updateHandleVisibility()' in appearance and 'window.windowLevel =' not in appearance
visibility = panel.split('private func updateHandleVisibility()', 1)[1].split('@objc public static func setCoverSheetVisible(', 1)[0]
assert 'let level = coverSheetVisible' in visibility and 'window.windowLevel = level' in visibility
overlay_levels = panel.split('private func updateOverlayWindowLevels()', 1)[1].split('@objc public static func setCoverSheetVisible(', 1)[0]
assert 'for (index, dock) in dockedHosts.enumerated() {' in overlay_levels
assert 'dock.fullscreenHandoffInProgress ? .statusBar + 0.3 : level - CGFloat(index + 1)' in overlay_levels
assert 'dock.window.windowLevel != dockLevel { dock.window.windowLevel = dockLevel }' in overlay_levels
dock_layout = panel.split('private func layoutDocks(', 1)[1].split('@objc private func restoreDockTapped(', 1)[0]
assert 'updateOverlayWindowLevels()' in dock_layout
assert 'where !dock.fullscreenHandoffInProgress' in dock_layout
for sheet_level in (None, 1035, 999):
    handle_level = 2051 if sheet_level is None else sheet_level
    for handing_off in (False, True):
        dock_level = 1000.3 if handing_off else handle_level - 1
        remaining_level = handle_level - 1
        assert remaining_level < handle_level
        if handing_off and sheet_level is None:
            assert remaining_level > dock_level
        if sheet_level is not None:
            assert remaining_level < sheet_level
    dock_levels = [handle_level - index - 1 for index in range(4)]
    assert all(older > newer for older, newer in zip(dock_levels, dock_levels[1:]))
    assert all(dock_level < handle_level for dock_level in dock_levels)
    if sheet_level is None:
        assert all(dock_level > 1000.3 for dock_level in dock_levels)
for events in (
    ('keyboard-mount', 'sheet-open', 'keyboard-remove', 'sheet-close'),
    ('sheet-open', 'keyboard-mount', 'sheet-close', 'keyboard-remove'),
    ('keyboard-mount', 'sheet-open', 'host-close', 'sheet-close'),
    ('sheet-open', 'keyboard-mount', 'sheet-close', 'host-close'),
    ('keyboard-mount', 'sheet-open', 'other-host-close', 'sheet-close', 'keyboard-remove'),
):
    sheet_visible, level = False, 2051
    for event in events:
        if event in ('sheet-open', 'sheet-close'):
            sheet_visible = event == 'sheet-open'
            level = 1035 if sheet_visible else 2051
        # Keyboard/host cleanup must leave the current handle level untouched.
        assert level == (1035 if sheet_visible else 2051)
assert 'self.relocatingKeyboard' in bridge
assert 'PXSetSceneFrame(mutable, PXServerFrameSize(mutable))' in bridge
assert 'UILaunchStoryboardName' in bridge and 'renderInContext:context' in bridge
assert 'NSClassFromString(@"LSApplicationProxy")' in bridge
assert 'codes.aurora.kayoko.core.show' in bridge
assert 'keepHostedProcessAlive' in bridge
assert 'applicationDisplayItemWithBundleIdentifier:sceneIdentifier:' in bridge
assert 'addAppLayoutForDisplayItem:completion:' in bridge
assert 'createApplicationProcessForBundleID:' not in bridge
assert bridge.index('completion(YES);') < bridge.index('[strongSelf registerSceneInSwitcher:scene bundleID:bundleID]')
assert 'if (strongSelf.generation == generation)\n                            [strongSelf registerSceneInSwitcher:scene bundleID:bundleID];' in bridge
assert 'deadline: .now() + 0.16' not in panel
assert 'while dockedHosts.count >= limit, let oldest = dockedHosts.first { removeDock(oldest) }' in park
assert 'captureOutsideKeyboard' not in panel and 'isKeyboardRelocated()' in panel
assert 'private final class PXKeyboardDismissLayer: UIControl' not in panel
assert 'let window = PXOverlayWindow(windowScene: scene)' in panel.split('private func refreshKeyboardDismissLayer()', 1)[1]
assert 'keyboardDismissWindow?.rootViewController?.view.backgroundColor = UIColor.black.withAlphaComponent(dim)' in panel
assert 'keyboardDismissWindow?.windowLevel = host.windowLevel - 0.5' in panel
assert '(keyboardDismissWindow as? PXOverlayWindow)?.applySystemOrientation()' in panel
assert 'excludedRects' not in panel
assert 'if (visible == self.keyboardWasVisible) return;' in bridge
assert 'name: Notification.Name("PXKeyboardStateChanged")' in panel
assert 'removeKeyboardDismissLayer()' in close_host
assert 'velocity.y < -500 {' in panel
assert 'if hostWindow != nil, hostedBundleID != bundleID {' in panel
assert 'object(forKey: "autoParkOnNewSplit") as? Bool ?? true' in panel
assert 'forKey: "autoParkOnNewSplit"' in dock_prefs
assert 'animationSpeedPercent' in panel
assert 'animationSpeedPercent' in (root / 'prefs' / 'PXLauncherController.swift').read_text(encoding='utf-8')
assert 'duration / speed' in panel and 'delay / speed' in panel
assert 'if action == "px.action.window"' in panel
for speed in (0.1, 1.0, 1.5):
    assert abs((0.4 / speed) * speed - 0.4) < 1e-9
open_fullscreen = panel.split('private func openFullscreen(', 1)[1].split('private func performShortcut', 1)[0]
assert open_fullscreen.index('closeHost(animated: false)') < open_fullscreen.index('openFullscreenApplication(bundleID)')
assert 'px.action.screenshot.copy' in panel and 'px.action.screenshot.copy' in bridge
copy_shot = bridge.split('if ([identifier isEqualToString:@"px.action.screenshot.copy"])', 1)[1].split('if ([identifier isEqualToString:@"px.action.screenshot"])', 1)[0]
assert '_UICreateScreenUIImage' in copy_shot and 'UIPasteboard.generalPasteboard.image = image' in copy_shot
assert 'takeScreenshot' not in copy_shot and 'UIImageWriteToSavedPhotosAlbum' not in copy_shot
assert 'urlSplitExcluded' in entry and 'URL 分屏黑名单' in (root / 'prefs/Resources/External.plist').read_text(encoding='utf-8')
assert '!notification && link ? [defaults stringArrayForKey:@"urlSplitExcluded"] : nil' in entry
assert 'displayItemWithType:bundleIdentifier:uniqueIdentifier:' not in bridge
assert 'self.processAssertion = nil' in bridge
assert 'com.moxuan.parallelx.scene.log' not in bridge
assert 'com.moxuan.parallelx.transition.log' not in bridge
assert not list(root.rglob("*.dylib")), "The project must not carry Myrtle binaries"
assert 'com.apple.springboard' in (root / "ParallelX.plist").read_text(encoding="utf-8")
assert not (root / "ParallelXSupport.plist").exists(), "Only SpringBoard may be injected"
radius = (root / "prefs" / "PXCornerRadiusController.swift").read_text(encoding="utf-8")
assert "UISlider()" in radius and "UILongPressGestureRecognizer" in radius
assert '"shadowStrength"' in radius and '"shadowBlur"' in radius
assert '"initialWidthPercent"' in radius and '"initialWidthPercent"' in panel
gesture = (root / "prefs" / "PXGestureAreaController.swift").read_text(encoding="utf-8")
assert all(key in gesture for key in ("gestureWidth", "gestureHeight", "gestureOffset", "gestureDebug",
                                      "topGestureWidth", "topGestureHeight", "topGestureOffset"))
assert 'title = "手势区域"' in gesture and '顶部触发区域' in gesture and '底部触发区域' in gesture
assert "PXGestureAreaController.swift" in (root / "prefs" / "Makefile").read_text(encoding="utf-8")
launcher = (root / "prefs" / "PXLauncherController.swift").read_text(encoding="utf-8")
assert all(key in launcher for key in ("launcherIconSize", "launcherRing1", "launcherRing4"))
assert launcher.count('(0, 30)') == 4 and '环数设为 0 会关闭当前及后续环' in launcher
assert '}.prefix(while: { $0 > 0 }))' in panel
assert 'rings.isEmpty ? 1' in panel
for configured, expected in (([0, 5, 7, 9], []), ([3, 0, 7, 9], [3]),
                             ([3, 5, 0, 9], [3, 5]), ([3, 5, 7, 0], [3, 5, 7])):
    assert configured[:next((i for i, count in enumerate(configured) if count == 0), 4)] == expected
assert 'launcherRingGap' in launcher and '"环间距"' in launcher
assert all(key in launcher for key in ("launcherEdgeInset", "launcherHoldMilliseconds", "handleWidth", "handleHeight"))
assert "PXLauncherController.swift" in (root / "prefs" / "Makefile").read_text(encoding="utf-8")
picker = (root / "prefs" / "PXAppPickerController.swift").read_text(encoding="utf-8")
assert 'cell.selectionStyle = .none' in picker and 'cell.accessoryType = .none' in picker
assert 'if indexPath.section == 0 { return .delete }' in picker
assert 'if indexPath.section == 2 { return .insert }' in picker
assert 'if editingStyle == .insert { addItem(at: indexPath); return }' in picker
assert 'table.allowsSelectionDuringEditing = true' in picker
assert 'table.setEditing(true, animated: false)' in picker and 'editButtonItem' not in picker
assert 'table.rowHeight = 58' in picker and 'table.separatorColor = .quaternaryLabel' in picker
assert 'style: .insetGrouped' in picker and 'viewForHeaderInSection section: Int' in picker
assert '.filter { $0.id.hasPrefix("px.add.") || !selected.contains($0.id) }' in picker
assert 'indexPath.section == 1 ? addableShortcuts[indexPath.row] : available[indexPath.row]' in picker
assert 'cell.textLabel?.font = .systemFont(ofSize: 14, weight: .regular)' in picker
assert 'cell.textLabel?.text = app.name + "（长按全屏）"' not in picker
assert 'cell.textLabel?.text = app.name' in picker
assert '最近打开的应用（长按全屏）' not in picker + panel
assert '("px.action.recent", "最近打开的应用",' in picker
selected_apps = panel.split('private func selectedApps()', 1)[1].split('private func beginPanel()', 1)[0]
assert '（长按全屏）' not in selected_apps
candidate_ids = ['px.action.dark', 'px.action.search', 'px.add.workflow', 'px.add.quick', 'px.url.saved']
selected_ids = {'px.action.dark', 'px.url.saved'}
assert [item for item in candidate_ids if item.startswith('px.add.') or item not in selected_ids] == [
    'px.action.search', 'px.add.workflow', 'px.add.quick']
assert 'moveRowAt sourceIndexPath' in picker and 'selected.insert(id, at: destinationIndexPath.row)' in picker
assert 'numberOfSections(in tableView: UITableView) -> Int { 3 }' in picker
assert 'px.action.window' in picker
assert 'px.action.recent' in picker and 'urls.count < 10' in picker
assert 'px.action.kayoko' in picker
assert 'key = "hideForScreenshot"' in (root / 'prefs' / 'Resources' / 'System.plist').read_text(encoding='utf-8')
assert 'closeOutsideWithKeyboard' in panel and 'key = "closeOutsideWithKeyboard"' in (root / 'prefs/Resources/Keyboard.plist').read_text(encoding='utf-8')
assert panel.count('initialCardFrame(in: screen, size:') == 5
assert 'initialRightInset' in panel
initial_frame = panel.split('private func initialCardFrame(', 1)[1].split('private func initialCardSize(', 1)[0]
assert 'screen.width > screen.height ? "landscapeInitialRightInset" : "initialRightInset"' in initial_frame
assert 'saved?.doubleValue ?? legacy?.doubleValue ?? 12' in initial_frame
assert 'landscapeDockWidth' not in initial_frame
for screen_width, card_width, right_inset in ((926, 332, 0), (926, 332, 40), (390, 304, 12)):
    inset = min(max(0, screen_width - card_width), max(0, right_inset))
    assert screen_width - (screen_width - card_width - inset + card_width) == right_inset
move_host = panel.split('@objc private func moveHost(_ gesture: UIPanGestureRecognizer)', 1)[1].split('private func closeHost(', 1)[0]
assert 'translation.y < -35' in move_host and 'parkMain(side: defaultDockSide)' in move_host
assert 'translation.y > 35' in move_host and 'velocity.y > 500' in move_host
assert 'dockSwipeEnabled, gesture.view === hostMoveGrip' in move_host
assert 'abs(translation.x) > abs(translation.y) * 1.2' in move_host
assert 'translation.x * velocity.x > 0' in move_host
assert 'parkMain(side: translation.x < 0 ? -1 : 1)' in move_host
assert 'if dockSwipeEnabled, gesture.view === hostMoveGrip,' in move_host
assert 'let topReset = gesture.view === hostTopGrip' in move_host
assert 'if swipeDown, gesture.view === hostTopGrip' in move_host
initial_down = move_host.split('let initial = initialCardFrame(in: screen, size: start.size)', 1)[1].split('let source = activeBridge.hostedSourceSize()', 1)[0]
assert 'if swipeDown, gesture.view === hostMoveGrip,' in initial_down
assert 'abs(start.maxX - initial.maxX) <= 2, abs(start.midY - initial.midY) <= 2' in initial_down
assert 'fullscreenTapped()' in initial_down and 'return' in initial_down
assert 'card.frame' not in initial_down  # The current frame already includes drag translation.
assert '已在初始位置时下滑全屏打开应用' in (root / 'prefs/PXGestureAreaController.swift').read_text(encoding='utf-8')
# Right-edge / vertical-center matching stays independent of resized dimensions.
for right, center, expected in ((378, 422, True), (379, 420, True), (381, 422, False), (378, 458, False)):
    assert (abs(right - 378) <= 2 and abs(center - 422) <= 2) == expected
assert 'switcherPulledApplication' not in panel and 'traceSwitcher' not in bridge and 'PXSwitcherPanProbe' not in tweak
assert 'closeApplicationAndRemoveSwitcherCard(bundleID)' in move_host
assert 'topPan.maximumNumberOfTouches = 1' in panel
assert 'fullscreenDock(dock)' in panel.split('@objc private func dockSwiped', 1)[1].split('private func removeDock', 1)[0]
dock_fullscreen = panel.split('private func fullscreenDock(', 1)[1].split('private func removeDock(', 1)[0]
assert dock_fullscreen.index('dock.fullscreenHandoffInProgress = true') < dock_fullscreen.index('dock.bridge.openFullscreenApplication(')
assert dock_fullscreen.index('dock.fullscreenHandoffInProgress = true') < dock_fullscreen.index('updateOverlayWindowLevels()') < dock_fullscreen.index('PXMotion.spring(0.40')
assert 'self.updateOverlayWindowLevels()' in dock_fullscreen
assert 'readyTicks >= 2 || ticks >= 15' in dock_fullscreen
assert 'weak dock' in dock_fullscreen and 'timer.invalidate()' in dock_fullscreen
assert '$0.bundleID == bundleID && !$0.fullscreenHandoffInProgress' in panel
assert '_deleteAppLayoutsMatchingBundleIdentifier:' in bridge
camera = (root / 'PXCameraSupport.m').read_text(encoding='utf-8')
assert 'if (!hosted && PXOriginalCameraState)' in camera
assert 'camera-client.' in camera and 'camera-session' in camera
assert '[self publishHostedCamera:NO]' in bridge and 'hostedCameraEnabled' in bridge
assert 'if (!hosted || PXHostedCameraLocked)' in bridge
assert '[PXSceneBridge setHostedCameraLocked:locked]' in tweak
assert 'loading && translation' not in move_host
assert 'initialCardSize(in: screen, source: source.width > 0 && source.height > 0 ? source :' in move_host
assert 'initialCardFrame(in: screen, size: size)' in move_host
assert 'card.frame = target' in move_host and 'self.activeBridge.layoutHost()' in move_host
assert move_host.index('translation.y < -35') < move_host.index('parkMain(side: defaultDockSide)')
assert 'launchWidthScale = nil' in move_host
assert move_host.index('launchMovedCenter = nil') < move_host.index('PXMotion.ease(0.24')
assert move_host.index('dockAfterOpenBundleID = nil') < move_host.index('PXMotion.ease(0.24')
assert 'launchMovedCenter = card.center' in move_host
assert 'if let center = launchMovedCenter' in panel.split('private func matchHostAspect()', 1)[1].split('private func initialCardFrame(', 1)[0]
assert 'if self.fullscreenAfterOpenBundleID == bundleID' in handoff
assert 'fullscreenAfterOpenBundleID = hostedBundleID' in panel.split('private func fullscreenTapped()', 1)[1].split('private func moveGripHeld(', 1)[0]
assert 'card.layer.cornerRadius = 0' not in panel.split('private func fullscreenTapped()', 1)[1].split('private func moveGripHeld(', 1)[0]
assert 'forKey: "dockSwipeEnabled"' in (root / 'prefs/PXGestureAreaController.swift').read_text(encoding='utf-8')
assert 'launchWidthScale = size.width / max(1, base.width)' in panel.split('private func resizeHost(', 1)[1].split('private func applyResizePreview()', 1)[0]
radius_settings = (root / 'prefs/PXCornerRadiusController.swift').read_text(encoding='utf-8')
assert 'defaults?.set(Int(landscapeRightInset.value), forKey: "landscapeInitialRightInset")' in radius_settings
assert '(landscapeRightInsetLabel, landscapeRightInset)' in radius_settings
assert '0..<8' in radius_settings
for landscape, landscape_inset, expected in ((False, 80, 12), (True, 80, 80), (True, None, 12)):
    preferences = {'initialRightInset': 12, 'landscapeInitialRightInset': landscape_inset}
    selected = preferences['landscapeInitialRightInset' if landscape else 'initialRightInset']
    assert (selected if selected is not None else preferences['initialRightInset']) == expected
assert 'mask = hidden ? mask | 0x12 : mask & ~0x12' in bridge
assert 'com.moxuan.parallelx.capture-updated' in entry and 'PostNotification' in (root / 'prefs/Resources/Keyboard.plist').read_text(encoding='utf-8')
blacklist = (root / 'prefs' / 'PXExternalBlacklistController.swift').read_text(encoding='utf-8')
assert 'PXApplicationIcon(app.id)' in blacklist and 'CGSize(width: 32, height: 32)' in blacklist
assert 'self.animateFullscreenReady()' in panel
assert 'fullscreenReadyView?.removeFromSuperview()' in panel
assert 'guard !UIAccessibility.isReduceMotionEnabled else { return }' in panel
for screen_width, card_width, saved_inset in ((390, 304.2, 12), (390, 304.2, 120), (320, 300, -5)):
    inset = min(max(0, screen_width - card_width), max(0, saved_inset))
    x = screen_width - card_width - inset
    assert x >= 0 and x + card_width <= screen_width
assert 'systemService:handleOpenApplicationRequest:withCompletion:' in (root / 'Tweak.m').read_text(encoding='utf-8')
assert '_handleTrustedOpenRequestForApplication:options:activationSettings:origin:withResult:' in (root / 'Tweak.m').read_text(encoding='utf-8')
assert 'FBSOpenApplicationOptionKeyActivateSuspended' in (root / 'Tweak.m').read_text(encoding='utf-8')
assert 'externalOpenApplication:' in (root / 'Tweak.m').read_text(encoding='utf-8')
assert 'externalPendingBundleID' in panel
external = (root / 'Tweak.m').read_text(encoding='utf-8')
assert '[request respondsToSelector:setOptions]' in external
assert 'objc_msgSend)(request, setOptions, prepared)' in external
assert 'objc_msgSend)([options class], factory, updated)' in external
trusted = external.split('static void PXHandleTrustedOpen', 1)[1].split('static void PXActivateApplication', 1)[0]
assert trusted.index('PXOptionsWithSuspendedLaunch(options)') < trusted.index('!PXRouteRecentlyHandled(bundleID)')
assert 'shared.panelFrontmostBundleID = nil' in panel
assert 'restoreExternalSource' not in panel
assert 'com.moxuan.parallelx.url-route' not in external
assert 'PXURLRouteLog' not in external and 'PXURLRouteEntities' not in external
transition = external.split('static BOOL PXExecuteTransition', 1)[1].split('static id PXFluidAnimationInit', 1)[0]
assert 'return YES;' not in transition
assert 'PXOriginalExecuteTransition(workspace, selector, request)' in transition
assert 'PXPendingURLTransition' not in external
assert 'NSSelectorFromString(@"setBackground:")' in transition
assert 'objc_msgSend)(context, background, YES)' in transition
assert transition.index('objc_msgSend)(context, background, YES)') < transition.index('PXOriginalExecuteTransition(workspace, selector, request)')
assert 'PXPendingURLBackgroundUntil = urlRoute ? PXRecentExternalTime + 2 : 0' in external
assert 'self.updateCardShadow(dock.card)' in panel
assert 'card.layer.shadowOpacity = 0\n        card.viewWithTag(0x505847)' not in panel
assert 'onProgress?(self.progress)' in panel
assert 'controller.onProgress = { [weak self] in self?.setHandlePanelProgress($0) }' in panel
assert 'self.onProgress?(0)' in panel
assert 'panelDragProgress = max(panelDragProgress, min(1, max(0, distance / threshold)))' in panel
assert 'panelRetracting' not in panel and 'func retract(' not in panel
assert 'func completeOpening()' in panel
assert 'withRenderingMode(.alwaysOriginal)' in panel

catalog = (root / 'PXAppCatalog.m').read_text(encoding='utf-8')
action_picker = (root / 'prefs' / 'PXActionPickerController.swift').read_text(encoding='utf-8')
assert 'sqlite3_open_v2' in catalog and 'SQLITE_OPEN_READONLY' in catalog
assert 'fetchApplicationShortcutItemsOfTypes:forBundleIdentifier:withCompletionHandler:' in catalog
assert 'setUserInfo:' in catalog and 'entry[@"userInfo"]' in catalog
assert 'WFSpringBoardWorkflowRunnerClient' in bridge and 'initWithWorkflowIdentifier:' in bridge
assert 'UIHandleApplicationShortcutAction' in bridge and 'initWithSBSShortcutItem:' in bridge
assert 'px.custom.' in panel and 'customActions' in picker
assert 'groupMenuActive' in panel and 'selectedGroupAction' in panel
assert 'cancel.text = "取消"' in panel and 'scroll.scrollRectToVisible(groupRows[next].frame, animated: false)' in panel
assert 'groupScrollLink' not in panel
assert 'menu.frame = CGRect(x: view.bounds.maxX - width - 10' in panel
assert 'handleCenterY - height / 2' in panel
assert 'groupOriginY = menu.frame.midY' in panel
assert 'guard menu.bounds.contains(local) else' in panel
assert 'let delta = point.y - groupOriginY' in panel
assert 'let step = min(36, max(8, scroll.bounds.height / CGFloat(groupItems.count + 1)))' in panel
assert 'let row = min(groupItems.count, max(0, groupItems.count / 2 + Int(delta / step)))' in panel
assert 'max(150, ceil(widest) + 32)' in panel and 'label.textAlignment = .center' in panel
assert 'groupItems.count + 1' in panel and 'let moved = abs(delta) >= 8' in panel
assert 'private enum PXMotion' in panel and panel.count('PXMotion.spring(') >= 7
assert panel.count('PXMotion.ease(') >= 7
assert 'multiple && indexPath.section == 0' in action_picker
assert 'chosen.insert(chosen.remove(at: sourceIndexPath.row)' in action_picker
assert 'shade.frame = view.bounds' in panel
assert 'doubleTap.numberOfTapsRequired = 2' in panel
assert 'UIResponder.keyboardWillChangeFrameNotification' in panel
assert 'UIResponder.keyboardDidHideNotification' in panel
assert 'activeBridge.isKeyboardRelocated()' in panel.split('private func refreshKeyboardDismissLayer()', 1)[1].split('private func fadeKeyboardDismissLayer()', 1)[0]
assert 'keyboardDismissSuppressed' in panel and 'fadeKeyboardDismissLayer()' in panel
assert 'PXKeyboardFrameChanged' in bridge
assert 'self.keyboardHostView.window' in bridge and 'view.hidden || view.alpha <= 0.01' in bridge
assert 'PXDismissOpenedNotificationBanner(options);' in (root / 'Tweak.m').read_text(encoding='utf-8')
assert (root / 'Tweak.m').read_text(encoding='utf-8').count('PXDismissOpenedNotificationBanner(options);') == 2

app_picker = (root / 'prefs' / 'PXAppPickerController.swift').read_text(encoding='utf-8')
action_picker = (root / 'prefs' / 'PXActionPickerController.swift').read_text(encoding='utf-8')
catalog = (root / 'PXAppCatalog.m').read_text(encoding='utf-8')
assert 'if indexPath.section == 0 { return }' in app_picker
assert 'if indexPath.section == 0 { return .delete }' in app_picker
assert 'commit editingStyle: UITableViewCell.EditingStyle' in app_picker
assert 'PXApplicationHasActions(id)' in action_picker
assert 'PXStaticActions(bundleID).count' in catalog
assert 'PXFetchApplicationActions(app.id)' in action_picker
assert 'kind == "apps" { onSave?([item]) }' in action_picker
assert 'localizedStringForKey:title value:title table:@"InfoPlist"' in catalog
assert 'keyboardDimOpacity' in panel and 'keyboardDimOpacity' in (root / 'prefs/Resources/Keyboard.plist').read_text(encoding='utf-8')
assert 'frontDisplayDidChange:' in (root / 'Tweak.m').read_text(encoding='utf-8')
assert 'PXOriginalFrontDisplayDidChange(springBoard, selector, application)' in (root / 'Tweak.m').read_text(encoding='utf-8')

for count in (1, 6, 20):
    height = min(6, count) * 52
    step = min(36, max(8, height / (count + 1)))
    middle = count // 2
    assert min(count, max(0, middle + int(step / step))) == min(count, middle + 1)
    assert min(count, max(0, middle + int(-step / step))) == max(0, middle - 1)

# Preferences must instantiate a native host, not a Swift subclass of the private controller.
prefs_host = (root / 'prefs' / 'PXRootListController.m').read_text(encoding='utf-8')
assert '@interface PXPageHostController : PSViewController' in prefs_host
assert 'initForContentSize:(CGSize)contentSize' in prefs_host
assert '[super initWithNibName:nil bundle:nil]' in prefs_host
assert root_plist.count('detail = PXPageHostController') == 4
for name in ('AppPicker', 'Launcher', 'CornerRadius', 'Dock', 'GestureArea'):
    assert ': UIViewController' in (root / 'prefs' / f'PX{name}Controller.swift').read_text(encoding='utf-8')
assert 'canvas.traitCollection.userInterfaceStyle' in bridge
foreground = bridge.split('- (BOOL)foregroundScene:(id)scene', 1)[1].split('- (void)keepHostedProcessAlive', 1)[0]
assert foreground.index('PXSetSceneAppearance(mutable,') < foreground.index('PXUpdateScene(scene, mutable)')
mount = bridge.split('- (void)openApplication:(NSString *)bundleID', 1)[1]
assert mount.index('updateAppearanceForStyle:canvas.traitCollection.userInterfaceStyle') < mount.index('enable, requester, YES')
assert mount.index('strongSelf.presentationContext = context;') < mount.index('updateAppearanceForStyle:canvas.traitCollection.userInterfaceStyle', mount.index('strongSelf.presentationContext = context;')) < mount.index('host, bindContext, context')
assert 'activeBridge.updateAppearance(for: card.traitCollection.userInterfaceStyle)' in panel
assert 'button.contentHorizontalAlignment = .left' in panel
import plistlib
prefs_info = plistlib.loads((root / 'prefs' / 'Resources' / 'Info.plist').read_bytes())
assert prefs_info['NSPrincipalClass'] == 'PXRootListController'
assert 'overridePrincipalClass = 1' in (root / 'layout' / 'Library' / 'PreferenceLoader' / 'Preferences' / 'ParallelX.plist').read_text()
assert '- (void)setSpecifier:(PSSpecifier *)specifier' in prefs_host
assert 'if (self.contentController || !self.specifier) return;' in prefs_host

# Every settings slider has a title/value and a numeric keyboard affordance.
for name in ('CornerRadius', 'Dock', 'GestureArea'):
    page = (root / 'prefs' / f'PX{name}Controller.swift').read_text(encoding='utf-8')
    assert 'inputButtons' in page and 'PXSettingsStyle.inputButton' in page
assert 'label.text = [NSString stringWithFormat:@"%@：%.0f%%", title, control.value]' in prefs_host
assert 'CGFloat multiplier = horizontal || focus ? 1 : 100' in prefs_host
assert 'PXScreenGeometryChanged' in panel and 'PXHostedGeometryChanged' in bridge
assert 'handleCenterLandscapeFraction' in panel
assert 'sourceOrientation = orientation' in bridge
client_update = bridge.split('- (void)scene:(id)scene didUpdateClientSettingsWithDiff:', 1)[1].split('- (NSArray *)mainLayersForScene:', 1)[0]
assert 'PXSetSceneFrame(mutable, PXServerFrameSize(mutable))' in client_update
assert 'sb_effectiveInterfaceOrientation' in bridge
# Both sideways orientations fit isotropically; portrait-only apps keep their aspect.
for landscape in (False, True):
    visual = (844, 390) if landscape else (390, 844)
    raw = (visual[1], visual[0]) if landscape else visual
    rotated = (raw[1], raw[0]) if landscape else raw
    assert rotated == visual
    for target in ((600, 300), (300, 650)):
        scale = min(target[0] / visual[0], target[1] / visual[1])
        assert visual[0] * scale <= target[0] + 0.001
        assert visual[1] * scale <= target[1] + 0.001

# Landscape card is sized by the short screen edge, and reserves the dock lane.
for screen_w, screen_h in ((844, 390), (852, 393), (932, 430)):
    dock_w = max(35, min(110, screen_h * 0.12))
    for source_w, source_h in ((390, 844), (844, 390)):
        scale = min(screen_h * .78 / max(source_w, source_h),
                    (screen_w - dock_w - 48) / source_w)
        width, height = source_w * scale, source_h * scale
        right = screen_w - (dock_w + 24 + 12)
        assert height <= screen_h * .78 + .001
        assert right - width > screen_w / 2
        assert right < screen_w - dock_w - 12
        zoom = max(1, min(1.6, (right - 12) / width))
        assert right - width * zoom >= 12 - .001
        assert abs(width / height - source_w / source_h) < .001
keyboard_plist = (root / 'prefs/Resources/Keyboard.plist').read_text(encoding='utf-8')
assert 'portraitExternalKeyboard' in keyboard_plist and 'landscapeExternalKeyboard' in keyboard_plist
assert '![self usesExternalKeyboard]' in bridge
assert '[self.keyboardOriginalParent addSubview:view]' in bridge
assert 'activeBridge.isHostedKeyboardVisible()' in panel
assert '!activeBridge.usesExternalKeyboard()' in panel
assert 'let oldFrame = card.frame' in panel
assert 'gesture.translation(in: window.rootViewController?.view)' in panel

# Overlay orientation is explicit and immediate; the app owns surface rotation.
assert 'private final class PXHandleWindow: PXOverlayWindow' in panel
assert 'self.screen.fixedCoordinateSpace.bounds' in bridge
assert 'self.center = center' in bridge and 'root.frame = content' in bridge
assert 'orientation != layoutOrientation' in panel
assert 'pill.autoresizingMask = []' in panel
assert 'dockedHosts.filter { $0.side == dock.side }.count' in panel
assert '[super _rotateWindowToOrientation:orientation updateStatusBar:NO duration:0 skipCallbacks:NO]' in bridge
assert 'didUpdateClientSettingsWithDiff:' in bridge
assert 'if (self.fullscreenHandoff || !scene' in bridge
activation = bridge.split('- (BOOL)openFullscreenApplication:', 1)[1].split('- (BOOL)', 1)[0]
assert activation.index('self.fullscreenHandoff = YES') < activation.index('objc_msgSend)(ui, activate')
# Both halves of a landscape source must map into the fitted card.
for source_w, source_h in ((390, 844), (844, 390)):
    scale = min(300 / source_w, 660 / source_h)
    for fraction in (.25, .75, 1):
        touch_x = source_w * scale * fraction
        assert abs(touch_x / scale - source_w * fraction) < .001
assert 'The scene host positions its own layers' in bridge
assert 'keyboardDismissSuppressed = keyboardHideInFlight || !visible' in panel
assert 'indicator.backgroundColor = UIColor(white: 0.65, alpha: 0.65)' in panel
assert 'let ratio = source.height / source.width' in panel
assert '[PXSceneBridge noteSystemOrientation:(UIInterfaceOrientation)orientation]' in entry
assert 'MSHookMessageEx(springBoard, orientation, (IMP)PXOrientationChanged' in entry
assert '_SBAppTransitionManager' not in entry
assert '_postActiveInterfaceOrientationChangedNotificationAnimated:' in entry
orientation_reader = bridge.split('+ (UIInterfaceOrientation)systemOrientation', 1)[1].split('- (void)updateAppearanceForStyle:', 1)[0]
assert orientation_reader.index('return PXSystemOrientation') < orientation_reader.index('activeInterfaceOrientation')
assert 'sceneForBundleID' not in orientation_reader
# A new system target wins even while the old desktop/app scene is portrait.
for target in (1, 2, 3, 4):
    cached_target, stale_scene = target, 1
    resolved = cached_target if cached_target in (1, 2, 3, 4) else stale_scene
    screen = (844, 390) if resolved in (3, 4) else (390, 844)
    handle_x = screen[0] - 24
    assert handle_x == (820 if target in (3, 4) else 366)
assert 'layoutDocks(animated: false)' in panel
assert 'card.transform = CGAffineTransform(scaleX: zoom, y: zoom)' in panel

# Device rotation must not replace a still-supported hosted orientation.
protected = bridge.split('- (id)protectedSettings:(id)settings forScene:', 1)[1].split('- (void)scene:', 1)[0]
assert 'self.sourceOrientation = orientation' not in protected
assert 'PXSetHostedOrientation(mutable, self.sourceOrientation)' in protected
assert 'setDeviceOrientation:' in bridge and 'BSCanonicalOrientationMapResolver' in bridge
assert 'supportedInterfaceOrientations' in client_update
assert 'UIInterfaceOrientation orientation = PXRuntimeHostedOrientation(client)' in client_update
assert 'UIInterfaceOrientation previous = PXRuntimeHostedOrientation(oldSettings)' in client_update
assert 'previous == UIInterfaceOrientationUnknown || previous == orientation' in client_update
assert 'PXPreferredHostedOrientation(self.bundleID, PXCall(scene, @"clientSettings"))' in bridge
assert 'CGSize sourceSize = PXSourceSize(mutable)' in bridge
assert 'row.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 6)' in panel
assert 'row.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -6)' in panel
assert 'let edge: CGFloat = landscape ? 27 : 12' in panel
assert 'window.windowLevel = .alert + 51' in panel
assert 'handle.isHidden != deviceLocked { handle.isHidden = deviceLocked }' in panel
assert 'window.windowLevel != level { window.windowLevel = level }' in panel
assert 'coverSheetWindowLevel ?? UIWindow.Level(rawValue: 1035)' in panel
assert 'UIWindow.Level(rawValue: min(CGFloat(level) - 0.5, 1035))' in panel
assert 'coverSheetVisible ? .normal' not in panel
assert 'PXUpdateCoverSheetWindowLevel(controller)' in tweak
assert 'shared.coverSheetVisible = visible' in panel
assert 'coverSheetExiting' not in panel and 'PXSetCoverSheetExiting' not in tweak
assert 'PXSetCoverSheetPresented(YES)' in tweak
assert 'PXSetCoverSheetPresented(NO)' in tweak
assert 'shared.updateHandleVisibility()' not in panel.split('func setCoverSheetPresented(', 1)[1].split('func setCoverSheetEntering(', 1)[0]
assert 'PXSetCoverSheetEntering(YES)' in tweak and 'PXSetCoverSheetEntering(NO)' in tweak
assert 'handleProbeState' not in panel and 'PXHandleProbe' not in tweak
assert 'NSClassFromString(@"CSCoverSheetViewController")' in tweak
assert 'PXSetCoverSheetVisible(YES)' in tweak and 'PXSetCoverSheetVisible(NO)' in tweak
assert 'PXCoverSheetWillDisappear' in tweak and 'NSSelectorFromString(@"isUILocked")' in tweak
cover_sheet_exit = tweak.split('static void PXCoverSheetWillDisappear(', 1)[1].split('static void PXCoverSheetDidDisappear(', 1)[0]
cover_sheet_done = tweak.split('static void PXCoverSheetDidDisappear(', 1)[1].split('static NSString *PXRecentExternalBundleID', 1)[0]
cover_sheet_entry = tweak.split('static void PXCoverSheetWillAppear(', 1)[1].split('static void PXSetCoverSheetPresented(', 1)[0]
cover_sheet_entered = tweak.split('static void PXCoverSheetDidAppear(', 1)[1].split('static void PXCoverSheetWillDisappear(', 1)[0]
assert cover_sheet_entry.index('PXSetCoverSheetEntering(YES)') < cover_sheet_entry.index('PXSetCoverSheetVisible(YES)')
assert cover_sheet_entered.index('PXSetCoverSheetPresented(YES)') < cover_sheet_entered.index('PXSetCoverSheetEntering(NO)')
assert 'PXSetCoverSheetPresented(NO)' not in cover_sheet_exit
assert cover_sheet_exit.index('PXUpdateCoverSheetWindowLevel(controller)') < cover_sheet_exit.index('PXSetCoverSheetVisible(YES)')
assert cover_sheet_done.index('PXSetCoverSheetPresented(NO)') < cover_sheet_done.index('PXSetCoverSheetVisible(NO)')
assert cover_sheet_done.index('PXSetCoverSheetVisible(NO)') < cover_sheet_done.index('PXSetCoverSheetEntering(NO)')
for visible, presented, entering, should_clear in (
    (True, False, True, False), (True, True, False, False),
    (True, False, False, True), (False, False, False, False),
):
    assert (visible and not presented and not entering) == should_clear
for locked, expected_hidden in ((False, False), (True, True)):
    assert locked == expected_hidden
for sheet_level, expected in ((1050, 1035), (1035, 1034.5), (1000, 999.5)):
    assert min(sheet_level - 0.5, 1035) == expected
assert 'PXPublishLockState(NO);' in cover_sheet_exit
assert 'PXDeviceLocked = YES;' not in cover_sheet_exit and '@"locked": @(PXDeviceLocked)' not in cover_sheet_exit
assert 'keyboardHideInFlight = true\n            keyboardDismissSuppressed = true' in panel
assert '!keyboardHideInFlight, !keyboardDismissSuppressed, activeBridge.isHostedKeyboardVisible()' in panel
for source, previous, current, mask, expected in (
    (1, 1, 3, 30, True),  # App requests landscape video.
    (1, 3, 3, 30, False), # Unchanged client state after device rotation.
    (1, 0, 3, 30, False), # Incomplete startup state is not authoritative.
    (1, 0, 3, 24, True),  # App now only supports landscape.
):
    changed = current != source and not (
        (previous == 0 or previous == current) and (mask == 0 or mask & (1 << source)))
    assert changed == expected
for screen_landscape in (False, True):
    for app_mask, expected_landscape in ((2, False), (2 | 8 | 16, False), (8 | 16, True)):
        orientation = next(value for value in (1, 2, 3, 4) if app_mask & (1 << value))
        assert (orientation in (3, 4)) == expected_landscape
        source = (844, 390) if expected_landscape else (390, 844)
        screen = (844, 390) if screen_landscape else (390, 844)
        scale = min(screen[0] / source[0], screen[1] / source[1])
        assert abs((source[0] * scale) / scale - source[0]) < .001
for current, mask, requested, expected in ((1, 30, 3, 1), (1, 24, 3, 3), (3, 2, 1, 1), (1, 0, 3, 1)):
    result = current if not mask or mask & (1 << current) else requested
    assert result == expected
for key in ('portraitInitialWidthPercent', 'portraitCornerRadius',
            'portraitLandscapeInitialWidthPercent', 'portraitLandscapeCornerRadius'):
    assert key in panel and key in radius
assert 'configuredCornerRadius(in: screen, source: source)' in panel
dismiss = panel.split('private func refreshKeyboardDismissLayer()', 1)[1].split('private func fadeKeyboardDismissLayer()', 1)[0]
assert 'guard enabled, activeBridge.usesExternalKeyboard()' in dismiss
assert '$0.session.persistentIdentifier == "com.apple.springboard"' in panel
assert '!kind.contains("keyboard") && !kind.contains("aperture")' in panel
for landscape in (False, True):
    width, height = (844, 390) if landscape else (390, 844)
    x, y, w, h = width - 90 - 140, (height - 303) / 2, 140, 303
    zoom = min(1.6, (x + w - 12) / w) if landscape else 1
    target_x, target_y = x + w - w * zoom, y + h - h * zoom
    assert abs(target_x + w * zoom - (x + w)) < .001
    assert abs(target_y + h * zoom - (y + h)) < .001
    if landscape:
        assert zoom == 1.6

# Both orientations retain alpha116's card-relative region without Home gesture overrides.
assert 'PXBottomGestureFrame' not in panel
assert 'PXBottomGestureView' not in panel
assert 'PXOriginalFluidReceiveTouch' not in tweak
assert 'traceGesture' not in panel and 'traceGesture' not in tweak and 'traceGesture' not in bridge
assert 'PXLandscapeBottomGestureFrame' not in panel
assert 'hostMoveGrip?.frame = CGRect(x: frame.midX - width / 2, y: frame.maxY + offset,' in panel

# The compact app identity follows hosted content orientation, never consumes touches or appears on docks.
root_preferences = (root / "prefs/Resources/Window.plist").read_text(encoding="utf-8")
assert 'key = "showSplitAppIdentity"; default = 1;' in root_preferences
assert 'defaults?.object(forKey: "showSplitAppIdentity") as? Bool ?? true' in panel
capture_update = panel.split('@objc public static func updateCaptureVisibility()', 1)[1].split('@objc public static func', 1)[0]
assert 'shared.layoutHostControls()' in capture_update
assert '滑动字母查找' not in panel and '移入图标松手打开' not in panel
assert 'private let hint = UILabel()' not in panel
assert 'title.isUserInteractionEnabled = false' in panel
assert 'titleName.text = PXApplicationDisplayName(bundleID)' in panel
assert 'source.height <= source.width' in panel
assert 'width: 12, height: 12' in panel and '.systemFont(ofSize: 11, weight: .medium)' in panel
assert 'card.viewWithTag(0x505848)?.isHidden = true' in panel
assert 'card.bounds.width / initialWidth' in panel
assert 'title.transform = CGAffineTransform(scaleX: scale * 1.067, y: scale * 1.067)' in panel
assert 'title.center = CGPoint(x: card.bounds.midX, y: 13 * scale)' in panel
assert 'initialCardSize(in: referenceScreen, source: source).width' in panel
assert 'width: min(physical.width, physical.height)' in panel
assert 'height: max(physical.width, physical.height)' in panel
for base, current, drag in ((334, 334, 0.65), (334, 250, 1.4), (178, 178, 1.5), (178, 240, 0.8)):
    # During preview the parent scales; after release the title owns exactly that scale.
    preview_icon = 12 * 1.067 * current / base * drag
    committed_icon = 12 * 1.067 * (current * drag) / base
    assert abs(preview_icon - committed_icon) < .001
for physical in ((428, 926), (926, 428)):
    reference_width = min(physical) * .78
    assert abs(reference_width - 333.84) < .001
    assert 12 * 178 / reference_width < 7  # Landscape card shrinks the title instead of resetting to 12pt.
