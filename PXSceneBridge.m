#import "PXSceneBridge.h"
#import "PXAppCatalog.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>
#import <dlfcn.h>
#import <math.h>
#import <signal.h>
#import <unistd.h>
#import <notify.h>

static NSString *PXHomeHandoffBundleID;
static CFAbsoluteTime PXHomeHandoffDeadline;

@interface UIWindow (PXRotation)
- (void)_rotateWindowToOrientation:(long long)orientation updateStatusBar:(BOOL)updateStatusBar
                         duration:(double)duration skipCallbacks:(BOOL)skipCallbacks;
@end

@implementation PXOverlayWindow {
    UIInterfaceOrientation _appliedOrientation;
}
- (void)_rotateWindowToOrientation:(long long)orientation updateStatusBar:(BOOL)updateStatusBar
                         duration:(double)duration skipCallbacks:(BOOL)skipCallbacks
{
    // SpringBoard must not start a second rotation animation for our overlays.
}
- (void)applySystemOrientation
{
    UIInterfaceOrientation orientation = [PXSceneBridge systemOrientation];
    CGRect physical = self.screen.fixedCoordinateSpace.bounds;
    CGSize size = UIInterfaceOrientationIsLandscape(orientation)
        ? CGSizeMake(MAX(physical.size.width, physical.size.height), MIN(physical.size.width, physical.size.height))
        : CGSizeMake(MIN(physical.size.width, physical.size.height), MAX(physical.size.width, physical.size.height));
    CGPoint center = CGPointMake(size.width / 2, size.height / 2);
    UIView *root = self.rootViewController.view;
    CGRect content = (CGRect){CGPointZero, size};
    BOOL changed = _appliedOrientation != orientation;
    if (!changed &&
        CGRectEqualToRect(self.bounds, content) && CGPointEqualToPoint(self.center, center) &&
        CGRectEqualToRect(root.frame, content)) return;
    _appliedOrientation = orientation;
    // iOS 15 must update UIWindow's orientation contract, not just its visual
    // transform: UIKit uses that contract for scene hosting and touch mapping.
    [UIView performWithoutAnimation:^{
        if (changed)
            [super _rotateWindowToOrientation:orientation updateStatusBar:NO duration:0 skipCallbacks:NO];
        self.bounds = content;
        self.center = center;
        root.transform = CGAffineTransformIdentity;
        root.frame = content;
        [root setNeedsLayout];
        [root layoutIfNeeded];
    }];
}
@end

static UIInterfaceOrientation PXSystemOrientation = UIInterfaceOrientationUnknown;

@interface PXKeyboardSlot : UIView
@end

@implementation PXKeyboardSlot
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

static id PXCall(id object, NSString *name)
{
    SEL selector = NSSelectorFromString(name);
    return [object respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

static id PXIvar(id object, const char *name)
{
    if (!object) return nil;
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        Ivar ivar = class_getInstanceVariable(cls, name);
        if (ivar) return object_getIvar(object, ivar);
    }
    return nil;
}

static BOOL PXKeyboardHasContent(UIView *view)
{
    CALayer *layer = view.layer;
    // UIKit can retain a full-screen keyboard container after removing its
    // remote surface. Its bounds/window alone do not mean a keyboard is shown.
    if (layer.sublayers.count > 0) return YES;
    SEL context = NSSelectorFromString(@"contextId");
    return [layer respondsToSelector:context] &&
        ((unsigned int (*)(id, SEL))objc_msgSend)(layer, context) != 0;
}

static BOOL PXSetBool(id object, NSString *name, BOOL value)
{
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 3) return NO;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(object, selector, value);
    return YES;
}

static void PXSetSceneAppearance(id settings, UIUserInterfaceStyle style)
{
    SEL setter = NSSelectorFromString(@"setUserInterfaceStyle:");
    if (style != UIUserInterfaceStyleUnspecified && [settings respondsToSelector:setter])
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(settings, setter, style);
}

static CGRect PXRect(id object, NSString *name)
{
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    return signature && strcmp(signature.methodReturnType, @encode(CGRect)) == 0
        ? ((CGRect (*)(id, SEL))objc_msgSend)(object, selector) : CGRectZero;
}

static BOOL PXSetSceneFrame(id settings, CGSize size)
{
    SEL selector = NSSelectorFromString(@"setFrame:");
    NSMethodSignature *signature = [settings methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 3 ||
        strcmp([signature getArgumentTypeAtIndex:2], @encode(CGRect)) != 0) return NO;
    ((void (*)(id, SEL, CGRect))objc_msgSend)(settings, selector,
        (CGRect){CGPointZero, size});
    return YES;
}

static UIInterfaceOrientation PXSceneOrientation(id settings)
{
    SEL selector = NSSelectorFromString(@"interfaceOrientation");
    return [settings respondsToSelector:selector]
        ? ((NSInteger (*)(id, SEL))objc_msgSend)(settings, selector) : UIInterfaceOrientationUnknown;
}

static UIInterfaceOrientation PXRuntimeHostedOrientation(id client);

static void PXSetHostedOrientation(id settings, UIInterfaceOrientation orientation)
{
    if (!settings || orientation < UIInterfaceOrientationPortrait ||
        orientation > UIInterfaceOrientationLandscapeRight) return;
    UIDeviceOrientation device = orientation == UIInterfaceOrientationLandscapeLeft
        ? UIDeviceOrientationLandscapeRight : orientation == UIInterfaceOrientationLandscapeRight
        ? UIDeviceOrientationLandscapeLeft : (UIDeviceOrientation)orientation;
    SEL setDevice = NSSelectorFromString(@"setDeviceOrientation:");
    SEL getDevice = NSSelectorFromString(@"deviceOrientation");
    UIDeviceOrientation currentDevice = [settings respondsToSelector:getDevice]
        ? ((NSInteger (*)(id, SEL))objc_msgSend)(settings, getDevice) : UIDeviceOrientationUnknown;
    if (currentDevice != device && [settings respondsToSelector:setDevice])
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(settings, setDevice, device);
    SEL setInterface = NSSelectorFromString(@"setInterfaceOrientation:");
    if (PXSceneOrientation(settings) != orientation && [settings respondsToSelector:setInterface])
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(settings, setInterface, orientation);

    // A scene whose direction differs from the screen needs the native
    // orientation map as well as its interface/device orientation. The map
    // keeps the rendered surface and touch coordinates in the same space.
    SEL setResolver = NSSelectorFromString(@"setInterfaceOrientationMapResolver:");
    if (![settings respondsToSelector:setResolver]) return;
    UIInterfaceOrientation screen = [PXSceneBridge systemOrientation];
    if (UIInterfaceOrientationIsLandscape(screen) == UIInterfaceOrientationIsLandscape(orientation)) {
        ((void (*)(id, SEL, id))objc_msgSend)(settings, setResolver, nil);
        return;
    }
    Class resolverClass = NSClassFromString(@"BSCanonicalOrientationMapResolver");
    SEL init = NSSelectorFromString(@"initWithTargetOrientation:currentOrientation:");
    SEL mode = NSSelectorFromString(@"setInterfaceOrientationMode:");
    if (![resolverClass instancesRespondToSelector:init] || ![settings respondsToSelector:mode]) return;
    id resolver = ((id (*)(id, SEL, NSInteger, NSInteger))objc_msgSend)(
        [resolverClass alloc], init, screen, orientation);
    if (!resolver) return;
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(settings, mode, 1);
    ((void (*)(id, SEL, id))objc_msgSend)(settings, setResolver, resolver);
}

static UIInterfaceOrientation PXPreferredHostedOrientation(NSString *bundleID, id client)
{
    UIInterfaceOrientationMask mask = 0;
    SEL supported = NSSelectorFromString(@"supportedInterfaceOrientations");
    if ([client respondsToSelector:supported])
        mask = ((NSUInteger (*)(id, SEL))objc_msgSend)(client, supported);
    if (!mask && bundleID.length) {
        id proxyClass = NSClassFromString(@"LSApplicationProxy");
        SEL lookup = NSSelectorFromString(@"applicationProxyForIdentifier:");
        id proxy = [proxyClass respondsToSelector:lookup]
            ? ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, lookup, bundleID) : nil;
        NSURL *url = PXCall(proxy, @"bundleURL");
        NSDictionary *info = [url isKindOfClass:NSURL.class] ? [NSBundle bundleWithURL:url].infoDictionary : nil;
        NSString *key = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad
            ? @"UISupportedInterfaceOrientations~ipad" : @"UISupportedInterfaceOrientations~iphone";
        NSArray *names = [info[key] isKindOfClass:NSArray.class] ? info[key] : info[@"UISupportedInterfaceOrientations"];
        if (![names isKindOfClass:NSArray.class]) names = @[];
        for (NSString *name in names) {
            if ([name isEqualToString:@"UIInterfaceOrientationPortrait"]) mask |= UIInterfaceOrientationMaskPortrait;
            else if ([name isEqualToString:@"UIInterfaceOrientationPortraitUpsideDown"]) mask |= UIInterfaceOrientationMaskPortraitUpsideDown;
            else if ([name isEqualToString:@"UIInterfaceOrientationLandscapeLeft"]) mask |= UIInterfaceOrientationMaskLandscapeLeft;
            else if ([name isEqualToString:@"UIInterfaceOrientationLandscapeRight"]) mask |= UIInterfaceOrientationMaskLandscapeRight;
        }
    }
    if (!(mask & (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown))) {
        UIInterfaceOrientation live = PXRuntimeHostedOrientation(client);
        if (UIInterfaceOrientationIsLandscape(live)) return live;
    }
    if (mask & UIInterfaceOrientationMaskPortrait) return UIInterfaceOrientationPortrait;
    if (mask & UIInterfaceOrientationMaskPortraitUpsideDown) return UIInterfaceOrientationPortraitUpsideDown;
    if (mask & UIInterfaceOrientationMaskLandscapeRight) return UIInterfaceOrientationLandscapeRight;
    if (mask & UIInterfaceOrientationMaskLandscapeLeft) return UIInterfaceOrientationLandscapeLeft;
    return UIInterfaceOrientationPortrait;
}

// PullOver-X resolves the application's live request from client settings,
// independently of the physical screen orientation.
static UIInterfaceOrientation PXRuntimeHostedOrientation(id client)
{
    SEL supported = NSSelectorFromString(@"supportedInterfaceOrientations");
    UIInterfaceOrientationMask mask = [client respondsToSelector:supported]
        ? ((NSUInteger (*)(id, SEL))objc_msgSend)(client, supported) : 0;
    for (NSString *name in @[@"sb_effectiveInterfaceOrientation", @"preferredInterfaceOrientation"]) {
        SEL selector = NSSelectorFromString(name);
        UIInterfaceOrientation value = [client respondsToSelector:selector]
            ? ((NSInteger (*)(id, SEL))objc_msgSend)(client, selector) : UIInterfaceOrientationUnknown;
        if (value >= UIInterfaceOrientationPortrait && value <= UIInterfaceOrientationLandscapeRight &&
            (!mask || (mask & (1UL << value)))) return value;
    }
    if (mask && !(mask & (mask - 1)))
        for (UIInterfaceOrientation value = UIInterfaceOrientationPortrait;
             value <= UIInterfaceOrientationLandscapeRight; value++)
            if (mask & (1UL << value)) return value;
    return UIInterfaceOrientationUnknown;
}

static CGSize PXSourceSize(id settings)
{
    // The server frame can retain a stale floating size. The display is the
    // canonical full-screen source that every hosted app renders into.
    CGSize size = PXRect(PXCall(settings, @"displayConfiguration"), @"bounds").size;
    if (size.width <= 0 || size.height <= 0)
        size = UIScreen.mainScreen.bounds.size;
    UIInterfaceOrientation orientation = PXSceneOrientation(settings);
    CGRect sceneFrame = PXRect(settings, @"frame");
    BOOL landscape = orientation == UIInterfaceOrientationUnknown
        ? sceneFrame.size.width > sceneFrame.size.height : UIInterfaceOrientationIsLandscape(orientation);
    size = landscape ? CGSizeMake(MAX(size.width, size.height), MIN(size.width, size.height))
                     : CGSizeMake(MIN(size.width, size.height), MAX(size.width, size.height));
    return size;
}

static CGSize PXServerFrameSize(id settings)
{
    CGSize size = PXRect(PXCall(settings, @"displayConfiguration"), @"bounds").size;
    if (size.width <= 0 || size.height <= 0) size = UIScreen.mainScreen.bounds.size;
    // iOS 15 keeps the scene's server surface in canonical coordinates even
    // while its presentation and hit testing use a landscape orientation map.
    return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion == 15
        ? CGSizeMake(MIN(size.width, size.height), MAX(size.width, size.height))
        : PXSourceSize(settings);
}

static BOOL PXUpdateScene(id scene, id settings)
{
    SEL selector = NSSelectorFromString(@"updateSettings:withTransitionContext:completion:");
    NSMethodSignature *signature = [scene methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 5) return NO;
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(scene, selector, settings, nil, nil);
    return YES;
}

static int PXApplicationPID(NSString *bundleID)
{
    id controller = PXCall(NSClassFromString(@"SBApplicationController"), @"sharedInstance");
    id app = nil;
    for (NSString *name in @[@"applicationWithBundleIdentifier:",
                              @"applicationWithDisplayIdentifier:"]) {
        SEL selector = NSSelectorFromString(name);
        if ([controller respondsToSelector:selector]) {
            app = ((id (*)(id, SEL, id))objc_msgSend)(controller, selector, bundleID);
            if (app) break;
        }
    }
    id state = app;
    for (NSUInteger attempt = 0; attempt < 2 && state; attempt++) {
        SEL pidSelector = NSSelectorFromString(@"pid");
        if ([state respondsToSelector:pidSelector]) {
            int pid = ((int (*)(id, SEL))objc_msgSend)(state, pidSelector);
            if (pid > 0) return pid;
        }
        state = PXCall(state, @"processState");
    }
    return 0;
}

@interface PXSceneBridge ()
@property(nonatomic, strong) id scene;
@property(nonatomic, copy) NSString *bundleID;
@property(nonatomic, strong) UIView *hostView;
@property(nonatomic, strong) id hostManager;
@property(nonatomic, assign) BOOL suppressSelection;
@property(nonatomic, strong) id presentationContext;
@property(nonatomic, assign) UIUserInterfaceStyle appearanceStyle;
@property(nonatomic, strong) id processAssertion;
@property(nonatomic, weak) UIView *canvas;
@property(nonatomic, weak) UIView *keyboardOverlay;
@property(nonatomic, weak) UIView *keyboardHostView;
@property(nonatomic, strong) UIView *keyboardSlot;
@property(nonatomic, weak) UIView *keyboardOriginalParent;
@property(nonatomic, assign) CGRect keyboardOriginalFrame;
@property(nonatomic, assign) BOOL keyboardWasVisible;
@property(nonatomic, assign) BOOL relocatingKeyboard;
@property(nonatomic, assign) BOOL fullscreenHandoff;
@property(nonatomic, copy) NSString *latestSwitcherBundleID;
@property(nonatomic, assign) CGSize sourceSize;
@property(nonatomic, assign) UIInterfaceOrientation sourceOrientation;
@property(nonatomic, strong) id originalOrientationMapResolver;
@property(nonatomic, strong) NSNumber *originalOrientationMode;
@property(nonatomic, assign) NSUInteger generation;
@property(nonatomic, assign) int cameraNotifyToken;
@end

@implementation PXSceneBridge

+ (BOOL)consumeHomeHandoffForBundleID:(NSString *)bundleID
{
    if (!NSThread.isMainThread) return NO;
    if (CFAbsoluteTimeGetCurrent() > PXHomeHandoffDeadline) PXHomeHandoffBundleID = nil;
    if (![PXHomeHandoffBundleID isEqualToString:bundleID]) return NO;
    PXHomeHandoffBundleID = nil;
    return YES;
}

+ (BOOL)consumeHomeHandoffForCurrentApplication
{
    NSString *current = [[self sharedBridge] frontmostBundleID];
    return current.length && [self consumeHomeHandoffForBundleID:current];
}

+ (void)noteSystemOrientation:(UIInterfaceOrientation)orientation
{
    if (orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationPortraitUpsideDown ||
        orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight)
        PXSystemOrientation = orientation;
}

+ (UIInterfaceOrientation)systemOrientation
{
    // The transition callback supplies the new direction before the desktop
    // or foreground app scene has finished updating its cached orientation.
    if (PXSystemOrientation != UIInterfaceOrientationUnknown) return PXSystemOrientation;
    SEL active = NSSelectorFromString(@"activeInterfaceOrientation");
    UIInterfaceOrientation orientation = [UIApplication.sharedApplication respondsToSelector:active]
        ? ((NSInteger (*)(id, SEL))objc_msgSend)(UIApplication.sharedApplication, active)
        : UIInterfaceOrientationUnknown;
    if (orientation >= UIInterfaceOrientationPortrait && orientation <= UIInterfaceOrientationLandscapeRight)
        return orientation;
    SEL screenOrientation = NSSelectorFromString(@"_interfaceOrientation");
    if ([UIScreen.mainScreen respondsToSelector:screenOrientation]) {
        UIInterfaceOrientation orientation = ((NSInteger (*)(id, SEL))objc_msgSend)(UIScreen.mainScreen, screenOrientation);
        if (orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationPortraitUpsideDown ||
            orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight)
            return orientation;
    }
    if (orientation == UIInterfaceOrientationUnknown) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] &&
                [scene.session.persistentIdentifier isEqualToString:@"com.apple.springboard"]) {
                orientation = ((UIWindowScene *)scene).interfaceOrientation;
                break;
            }
        }
    }
    return orientation == UIInterfaceOrientationUnknown ? UIInterfaceOrientationPortrait : orientation;
}

- (void)updateAppearanceForStyle:(UIUserInterfaceStyle)style
{
    if (style == UIUserInterfaceStyleUnspecified) return;
    // The hostManager path has no presentationContext. Deliver the system
    // style to the application scene itself for both hosting paths.
    id settings = PXCall(self.scene, @"settings");
    SEL getter = NSSelectorFromString(@"userInterfaceStyle");
    if ([settings respondsToSelector:getter] &&
        ((NSInteger (*)(id, SEL))objc_msgSend)(settings, getter) != style) {
        id mutable = [settings respondsToSelector:@selector(mutableCopy)] ? [settings mutableCopy] : nil;
        SEL setter = NSSelectorFromString(@"setUserInterfaceStyle:");
        if ([mutable respondsToSelector:setter]) {
            PXSetSceneAppearance(mutable, style);
            PXUpdateScene(self.scene, mutable);
        }
    }
    if (!self.presentationContext || self.appearanceStyle == style) return;
    SEL selector = NSSelectorFromString(@"setAppearanceStyle:");
    if (![self.presentationContext respondsToSelector:selector]) return;
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(self.presentationContext, selector, style);
    self.appearanceStyle = style;
    SEL bind = NSSelectorFromString(@"_setPresentationContext:");
    if ([self.hostView respondsToSelector:bind])
        ((void (*)(id, SEL, id))objc_msgSend)(self.hostView, bind, self.presentationContext);
}

+ (void)keepTransparentGestureViewHittable:(UIView *)view
{
    PXSetBool(view.layer, @"setHitTestsAsOpaque:", YES);
}

static NSHashTable<PXSceneBridge *> *PXBridges;
static BOOL PXHostedCameraLocked;

+ (void)setHostedCameraLocked:(BOOL)locked
{
    PXHostedCameraLocked = locked;
    for (PXSceneBridge *bridge in PXBridges.allObjects)
        [bridge publishHostedCamera:bridge.canvas != nil];
}

- (void)publishHostedCamera:(BOOL)hosted
{
    if (!hosted || PXHostedCameraLocked) {
        if (_cameraNotifyToken >= 0) {
            notify_set_state(_cameraNotifyToken, 0);
            notify_cancel(_cameraNotifyToken);
            _cameraNotifyToken = -1;
        }
        return;
    }
    if (self.bundleID.length == 0) return;
    if (_cameraNotifyToken < 0) {
        NSString *name = [@"com.moxuan.parallelx.camera-client." stringByAppendingString:self.bundleID];
        if (notify_register_check(name.UTF8String, &_cameraNotifyToken) != NOTIFY_STATUS_OK) {
            _cameraNotifyToken = -1;
            return;
        }
    }
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.moxuan.parallelx"];
    notify_set_state(_cameraNotifyToken, [defaults boolForKey:@"hostedCameraEnabled"] ? (uint64_t)getpid() : 0);
}

- (instancetype)init
{
    if ((self = [super init])) {
        _cameraNotifyToken = -1;
        if (!PXBridges) {
            PXBridges = [NSHashTable weakObjectsHashTable];
            int epochToken;
            if (notify_register_check("com.moxuan.parallelx.camera-session", &epochToken) == NOTIFY_STATUS_OK) {
                notify_set_state(epochToken, (uint64_t)getpid());
                // Keep the registration for this SpringBoard lifetime.
            }
            int settingsToken;
            notify_register_dispatch("com.moxuan.parallelx.camera-updated", &settingsToken,
                dispatch_get_main_queue(), ^(__unused int token) {
                    for (PXSceneBridge *bridge in PXBridges.allObjects)
                        [bridge publishHostedCamera:bridge.canvas != nil];
                });
        }
        [PXBridges addObject:self];
    }
    return self;
}

- (void)dealloc
{
    if (_cameraNotifyToken >= 0) {
        notify_set_state(_cameraNotifyToken, 0);
        notify_cancel(_cameraNotifyToken);
    }
}

+ (id)protectedSettings:(id)settings forAnyScene:(id)scene
{
    for (PXSceneBridge *bridge in PXBridges.allObjects) {
        id protected = [bridge protectedSettings:settings forScene:scene];
        if (protected) return protected;
    }
    return nil;
}

+ (void)relocateAnyKeyboardView:(UIView *)view
{
    for (PXSceneBridge *bridge in PXBridges.allObjects)
        [bridge relocateKeyboardView:view];
    // A system-owned keyboard need not be reparented by ParallelX to be visible.
    BOOL visible = PXKeyboardHasContent(view) && view.window && !view.window.hidden;
    for (UIView *ancestor = view; ancestor && visible; ancestor = ancestor.superview)
        visible = !ancestor.hidden && ancestor.alpha > 0.01;
    CGRect frame = visible
        ? [view convertRect:view.bounds toView:nil] : CGRectNull;
    frame = CGRectIntersection(frame, UIScreen.mainScreen.bounds);
    if (CGRectIsEmpty(frame) || frame.size.height < 30) frame = CGRectNull;
    static char frameKey;
    NSValue *previous = objc_getAssociatedObject(view, &frameKey);
    if (previous && CGRectEqualToRect(previous.CGRectValue, frame)) return;
    objc_setAssociatedObject(view, &frameKey, [NSValue valueWithCGRect:frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [NSNotificationCenter.defaultCenter postNotificationName:@"PXKeyboardFrameChanged" object:view
        userInfo:@{@"frame":[NSValue valueWithCGRect:frame]}];
}

+ (instancetype)sharedBridge
{
    static PXSceneBridge *bridge;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ bridge = [PXSceneBridge new]; });
    return bridge;
}

- (id)sceneForBundleID:(NSString *)bundleID
{
    if (bundleID.length == 0) return nil;
    id manager = PXCall(NSClassFromString(@"FBSceneManager"), @"sharedInstance");
    id workspace = PXIvar(manager, "_workspace") ?: PXCall(manager, @"workspace");
    id scenes = PXIvar(workspace, "_allScenesByID") ?: PXCall(workspace, @"allScenesByID");
    if (![scenes isKindOfClass:NSDictionary.class]) return nil;
    NSString *marker = [bundleID stringByAppendingString:@"-"];
    for (NSString *key in (NSDictionary *)scenes) {
        if (![key isKindOfClass:NSString.class] || ![key containsString:marker]) continue;
        id scene = scenes[key];
        if ([scene isKindOfClass:NSClassFromString(@"FBScene")]) return scene;
    }
    return nil;
}

- (BOOL)hasSceneForApplication:(NSString *)bundleID
{
    return [self sceneForBundleID:bundleID] != nil;
}

- (UIImage *)launchImageForApplication:(NSString *)bundleID size:(CGSize)size
{
    if (bundleID.length == 0 || size.width <= 0 || size.height <= 0) return nil;
    @try {
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        SEL lookup = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if (![proxyClass respondsToSelector:lookup]) return nil;
        id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, lookup, bundleID);
        NSURL *url = PXCall(proxy, @"bundleURL");
        if (![url isKindOfClass:NSURL.class]) return nil;
        NSBundle *bundle = [NSBundle bundleWithURL:url];
        NSString *name = [bundle objectForInfoDictionaryKey:@"UILaunchStoryboardName"];
        if (![name isKindOfClass:NSString.class] || name.length == 0) return nil;
        UIViewController *controller = [[UIStoryboard storyboardWithName:name bundle:bundle]
                                         instantiateInitialViewController];
        if (!controller) return nil;
        UIView *view = controller.view;
        view.frame = (CGRect){CGPointZero, size};
        [view layoutIfNeeded];
        UIGraphicsBeginImageContextWithOptions(size, YES, 0);
        CGContextRef context = UIGraphicsGetCurrentContext();
        if (!context) { UIGraphicsEndImageContext(); return nil; }
        [view.layer renderInContext:context];
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return image;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

- (BOOL)launchSuspended:(NSString *)bundleID
{
    SEL selector = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    id springBoard = UIApplication.sharedApplication;
    NSMethodSignature *signature = [springBoard methodSignatureForSelector:selector];
    BOOL launched = signature && signature.numberOfArguments == 4 &&
        ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(springBoard, selector, bundleID, YES);
    if (!launched) {
        id workspace = PXCall(NSClassFromString(@"LSApplicationWorkspace"), @"defaultWorkspace");
        signature = [workspace methodSignatureForSelector:selector];
        launched = signature && signature.numberOfArguments == 4 &&
            ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(workspace, selector, bundleID, YES);
    }
    return launched;
}

- (BOOL)openFullscreenApplication:(NSString *)bundleID
{
    if (bundleID.length == 0) return NO;
    BOOL previousHandoff = self.fullscreenHandoff;
    self.fullscreenHandoff = YES;
    if (self.scene && [self.bundleID isEqualToString:bundleID]) {
        id controller = PXCall(NSClassFromString(@"SBApplicationController"), @"sharedInstance");
        SEL lookup = NSSelectorFromString(@"applicationWithBundleIdentifier:");
        id app = [controller respondsToSelector:lookup]
            ? ((id (*)(id, SEL, id))objc_msgSend)(controller, lookup, bundleID) : nil;
        id ui = PXCall(NSClassFromString(@"SBUIController"), @"sharedInstance");
        id settings = [NSClassFromString(@"SBActivationSettings") new];
        SEL flag = NSSelectorFromString(@"setFlag:forActivationSetting:");
        SEL activate = NSSelectorFromString(@"activateApplication:fromIcon:location:activationSettings:actions:");
        if (app && [settings respondsToSelector:flag] &&
            [ui respondsToSelector:activate]) {
            // Activation setting 1 is SpringBoard's noAnimate flag.
            ((void (*)(id, SEL, NSInteger, unsigned int))objc_msgSend)(settings, flag, 1, 1);
            ((void (*)(id, SEL, id, id, id, id, id))objc_msgSend)(ui, activate,
                app, nil, nil, settings, nil);
            return YES;
        }
    }
    SEL selector = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    id springBoard = UIApplication.sharedApplication;
    NSMethodSignature *signature = [springBoard methodSignatureForSelector:selector];
    if (signature && signature.numberOfArguments == 4 &&
        ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(springBoard, selector, bundleID, NO)) {
        return YES;
    }
    id workspace = PXCall(NSClassFromString(@"LSApplicationWorkspace"), @"defaultWorkspace");
    signature = [workspace methodSignatureForSelector:selector];
    BOOL opened = signature && signature.numberOfArguments == 4 &&
        ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(workspace, selector, bundleID, NO);
    if (!opened) self.fullscreenHandoff = previousHandoff;
    return opened;
}

- (BOOL)closeApplicationAndRemoveSwitcherCard:(NSString *)bundleID
{
    NSAssert(NSThread.isMainThread, @"ParallelX Scene access must be on the main thread");
    if (bundleID.length == 0 || [bundleID isEqualToString:@"com.apple.springboard"] ||
        [[self frontmostBundleID] isEqualToString:bundleID]) return NO;
    id switcher = PXCall(NSClassFromString(@"SBMainSwitcherViewController"), @"sharedInstance");
    SEL remove = NSSelectorFromString(@"_deleteAppLayoutsMatchingBundleIdentifier:");
    NSMethodSignature *signature = [switcher methodSignatureForSelector:remove];
    if (!signature || signature.numberOfArguments != 3 ||
        signature.methodReturnType[0] != 'v' || [signature getArgumentTypeAtIndex:2][0] != '@') return NO;
    NSArray *layouts = PXCall(switcher, @"recentAppLayouts");
    if (![layouts isKindOfClass:NSArray.class]) return NO;
    BOOL hasCard = NO;
    for (id layout in layouts) {
        NSArray *items = PXCall(layout, @"allItems");
        if (![items isKindOfClass:NSArray.class]) continue;
        for (id item in items) {
            if ([PXCall(item, @"bundleIdentifier") isEqualToString:bundleID]) { hasCard = YES; break; }
        }
        if (hasCard) break;
    }
    @try {
        // Native card deletion also performs SpringBoard's user-quit operation.
        ((void (*)(id, SEL, id))objc_msgSend)(switcher, remove, bundleID);
    } @catch (__unused NSException *exception) { return NO; }
    if (hasCard) return YES;
    // A cold launch can have a process before its switcher card is registered.
    int pid = PXApplicationPID(bundleID);
    if (pid <= 1) return YES;
    return pid != getpid() && kill(pid, SIGKILL) == 0;
}

- (BOOL)restartApplication:(NSString *)bundleID
                 suspended:(BOOL)suspended
                completion:(void (^)(BOOL success))completion
{
    if (bundleID.length == 0 || [bundleID isEqualToString:@"com.apple.springboard"] ||
        !completion) return NO;
    int pid = PXApplicationPID(bundleID);
    if (pid <= 1 || pid == getpid() || kill(pid, SIGKILL) != 0) return NO;
    __block NSUInteger attempts = 0;
    __weak typeof(self) weakSelf = self;
    __block void (^retry)(void) = nil;
    retry = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { retry = nil; return; }
        if (PXApplicationPID(bundleID) != pid) {
            BOOL launched = suspended ? [strongSelf launchSuspended:bundleID] :
                                         [strongSelf openFullscreenApplication:bundleID];
            completion(launched);
            retry = nil;
        } else if (++attempts >= 20) {
            completion(NO);
            retry = nil;
        } else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
                           dispatch_get_main_queue(), retry);
        }
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), retry);
    return YES;
}

- (BOOL)performShortcut:(NSString *)identifier
{
    if ([identifier isEqualToString:@"px.action.kayoko"]) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("codes.aurora.kayoko.core.show"), NULL, NULL, YES);
        return YES;
    }
    if ([identifier isEqualToString:@"px.action.dark"]) {
        Class styleClass = NSClassFromString(@"UISUserInterfaceStyleMode");
        SEL setter = NSSelectorFromString(@"setModeValue:");
        if (!styleClass || ![styleClass instancesRespondToSelector:setter]) return NO;
        id style = [styleClass new];
        NSInteger next = UIScreen.mainScreen.traitCollection.userInterfaceStyle ==
            UIUserInterfaceStyleDark ? 1 : 2;
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(style, setter, next);
        return YES;
    }
    if ([identifier isEqualToString:@"px.action.rotation"]) {
        id manager = PXCall(NSClassFromString(@"SBOrientationLockManager"), @"sharedInstance");
        SEL state = NSSelectorFromString(@"isUserLocked");
        if (![manager respondsToSelector:state]) return NO;
        BOOL locked = ((BOOL (*)(id, SEL))objc_msgSend)(manager, state);
        SEL action = NSSelectorFromString(locked ? @"unlock" : @"lock");
        if (![manager respondsToSelector:action]) return NO;
        ((void (*)(id, SEL))objc_msgSend)(manager, action);
        return YES;
    }
    if ([identifier isEqualToString:@"px.action.screenshot.copy"]) {
        CFTypeRef (*capture)(void) = (CFTypeRef (*)(void))dlsym(RTLD_DEFAULT, "_UICreateScreenUIImage");
        if (!capture) return NO;
        UIImage *image = (__bridge_transfer UIImage *)capture();
        if (!image) return NO;
        UIPasteboard.generalPasteboard.image = image;
        return YES;
    }
    if ([identifier isEqualToString:@"px.action.screenshot"]) {
        id springBoard = UIApplication.sharedApplication;
        SEL action = NSSelectorFromString(@"takeScreenshot");
        if (![springBoard respondsToSelector:action]) return NO;
        ((void (*)(id, SEL))objc_msgSend)(springBoard, action);
        return YES;
    }
    if ([identifier isEqualToString:@"px.action.record"]) {
        if (!NSClassFromString(@"RPScreenRecorder"))
            dlopen("/System/Library/Frameworks/ReplayKit.framework/ReplayKit", RTLD_LAZY);
        id recorder = PXCall(NSClassFromString(@"RPScreenRecorder"), @"sharedRecorder");
        SEL state = NSSelectorFromString(@"isRecording");
        if (![recorder respondsToSelector:state]) return NO;
        BOOL recording = ((BOOL (*)(id, SEL))objc_msgSend)(recorder, state);
        if (recording) {
            SEL stop = NSSelectorFromString(@"stopSystemRecording:");
            if (![recorder respondsToSelector:stop]) return NO;
            ((void (*)(id, SEL, id))objc_msgSend)(recorder, stop, ^(NSError *error) { (void)error; });
        } else {
            SEL start = NSSelectorFromString(@"startSystemRecordingWithMicrophoneEnabled:handler:");
            if ([recorder respondsToSelector:start]) {
                ((void (*)(id, SEL, BOOL, id))objc_msgSend)(recorder, start, NO,
                    ^(NSError *error) { (void)error; });
            } else {
                start = NSSelectorFromString(@"startRecordingWithMicrophoneEnabled:windowToRecord:systemRecording:handler:");
                if (![recorder respondsToSelector:start]) return NO;
                ((void (*)(id, SEL, BOOL, id, BOOL, id))objc_msgSend)(recorder, start, NO,
                    nil, YES, ^(NSError *error) { (void)error; });
            }
        }
        return YES;
    }
    return NO;
}

- (BOOL)setBrightnessLevel:(float)level
{
    static id controller;
    static SEL setter;
    if (!controller) {
        Class cls = NSClassFromString(@"SBDisplayBrightnessController");
        setter = NSSelectorFromString(@"setBrightnessLevel:animated:");
        if (!cls || ![cls instancesRespondToSelector:setter]) return NO;
        controller = [cls new];
    }
    if (![controller respondsToSelector:setter]) return NO;
    ((void (*)(id, SEL, float, BOOL))objc_msgSend)(controller, setter,
        fminf(1, fmaxf(0, level)), NO);
    return YES;
}

- (BOOL)shortcutIsActive:(NSString *)identifier
{
    if ([identifier isEqualToString:@"px.action.dark"])
        return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    if ([identifier isEqualToString:@"px.action.rotation"]) {
        id manager = PXCall(NSClassFromString(@"SBOrientationLockManager"), @"sharedInstance");
        SEL state = NSSelectorFromString(@"isUserLocked");
        return [manager respondsToSelector:state] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(manager, state);
    }
    if ([identifier isEqualToString:@"px.action.record"]) {
        if (!NSClassFromString(@"RPScreenRecorder"))
            dlopen("/System/Library/Frameworks/ReplayKit.framework/ReplayKit", RTLD_LAZY);
        id recorder = PXCall(NSClassFromString(@"RPScreenRecorder"), @"sharedRecorder");
        SEL state = NSSelectorFromString(@"isRecording");
        return [recorder respondsToSelector:state] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(recorder, state);
    }
    return NO;
}

- (NSString *)recentApplicationSkipping:(NSArray<NSString *> *)excluded rank:(NSInteger)rank
{
    if (rank < 1) return nil;
    id switcher = PXCall(NSClassFromString(@"SBMainSwitcherViewController"), @"sharedInstance");
    NSArray *layouts = PXCall(switcher, @"recentAppLayouts");
    if (![layouts isKindOfClass:NSArray.class]) return nil;
    NSMutableSet<NSString *> *seen = [NSMutableSet setWithArray:excluded];
    for (id layout in layouts) {
        for (id item in PXCall(layout, @"allItems")) {
            NSString *bundleID = PXCall(item, @"bundleIdentifier");
            if (![bundleID isKindOfClass:NSString.class] || bundleID.length == 0 ||
                [seen containsObject:bundleID] || [bundleID isEqualToString:@"com.apple.springboard"]) continue;
            [seen addObject:bundleID];
            if (--rank == 0) return bundleID;
        }
    }
    return nil;
}

- (NSString *)frontmostBundleID
{
    id frontmost = PXCall(UIApplication.sharedApplication,
                          @"_accessibilityFrontMostApplication");
    id bundleID = PXCall(frontmost, @"bundleIdentifier");
    return [bundleID isKindOfClass:NSString.class] ? bundleID : nil;
}

- (void)prepareWindowForBundleID:(NSString *)bundleID
            wasFullscreen:(BOOL)wasFullscreen
                      completion:(void (^)(BOOL success))completion
{
    if (!completion) return;
    NSString *currentID = [self frontmostBundleID];
    BOOL shouldReturnHome = wasFullscreen && [currentID isEqualToString:bundleID];
    void (^finish)(BOOL) = ^(BOOL success){
        if (NSThread.isMainThread) completion(success);
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(success); });
    };
    if (!shouldReturnHome || bundleID.length == 0) {
        finish(YES);
        return;
    }
    // alpha79 dispatches Home alongside the card animation. Match the queued
    // transition once by bundle ID; a stack-scoped flag misses queued requests.
    PXHomeHandoffBundleID = [bundleID copy];
    PXHomeHandoffDeadline = CFAbsoluteTimeGetCurrent() + 1.0;
    id actions = [NSClassFromString(@"SBHomeHardwareButtonActions") new];
    SEL press = NSSelectorFromString(@"performSinglePressUpActions");
    if ([actions respondsToSelector:press]) {
        ((void (*)(id, SEL))objc_msgSend)(actions, press);
        finish(YES);
        return;
    }
    id controller = UIApplication.sharedApplication;
    SEL selector = NSSelectorFromString(@"_returnToHomeScreenWithCompletion:");
    NSMethodSignature *signature = [controller methodSignatureForSelector:selector];
    if (signature && signature.numberOfArguments == 3 &&
        signature.methodReturnType[0] == 'v' &&
        [signature getArgumentTypeAtIndex:2][0] == '@') {
        ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, nil);
        finish(YES);
        return;
    }
    PXHomeHandoffBundleID = nil;
    finish(NO);
}

- (void)layoutHost
{
    UIView *host = self.hostView;
    UIView *canvas = self.canvas;
    CGSize source = self.sourceSize;
    CGSize target = canvas.bounds.size;
    if (!host || !canvas || source.width <= 0 || source.height <= 0 ||
        target.width <= 0 || target.height <= 0) return;
    CGFloat scale = MIN(target.width / source.width, target.height / source.height);
    // The scene owns its content orientation; do not rotate its surface again.
    [UIView performWithoutAnimation:^{
        host.transform = CGAffineTransformIdentity;
        host.bounds = (CGRect){CGPointZero, source};
        [host setNeedsLayout];
        [host layoutIfNeeded];
        // The scene host positions its own layers. Forcing canonical iOS 15
        // portrait layers into a landscape CGRect cropped half the picture.
        host.center = CGPointMake(target.width / 2, target.height / 2);
        host.transform = CGAffineTransformMakeScale(scale, scale);
    }];
    if (self.keyboardHostView) [self relocateKeyboardView:self.keyboardHostView];
}

- (void)setHostedInteractionEnabled:(BOOL)enabled
{
    self.suppressSelection = !enabled;
    self.hostView.userInteractionEnabled = enabled;
    id scene = self.scene;
    id settings = PXCall(scene, @"settings");
    id mutable = [settings respondsToSelector:@selector(mutableCopy)] ? [settings mutableCopy] : nil;
    if (mutable && PXSetBool(mutable, @"setAllowsSelection:", enabled))
        PXUpdateScene(scene, mutable);
}

- (CGSize)hostedSourceSize
{
    return self.sourceSize;
}

- (BOOL)hasHostedSurface
{
    return self.hostView != nil;
}

- (void)refreshHostedOrientationMap
{
    if (!self.scene || !self.canvas || self.fullscreenHandoff) return;
    id settings = PXCall(self.scene, @"settings");
    id mutable = [settings respondsToSelector:@selector(mutableCopy)] ? [settings mutableCopy] : nil;
    if (!mutable) return;
    PXSetHostedOrientation(mutable, self.sourceOrientation);
    PXUpdateScene(self.scene, mutable);
}

- (BOOL)usesExternalKeyboard
{
    CGSize size = self.keyboardOverlay.bounds.size;
    BOOL landscape = size.width > size.height;
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.moxuan.parallelx"];
    NSString *key = landscape ? @"landscapeExternalKeyboard" : @"portraitExternalKeyboard";
    return [defaults objectForKey:key] ? [defaults boolForKey:key] : !landscape;
}

- (BOOL)isHostedKeyboardVisible
{
    UIView *view = self.keyboardHostView;
    if (!self.hostView || !view.window || view.window.hidden ||
        (![view isDescendantOfView:self.hostView] && view.superview != self.keyboardSlot)) return NO;
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview)
        if (ancestor.hidden || ancestor.alpha <= 0.01) return NO;
    return view.bounds.size.height > 0 && PXKeyboardHasContent(view);
}

- (void)refreshKeyboardPlacement
{
    if (self.keyboardHostView) [self relocateKeyboardView:self.keyboardHostView];
}

- (void)publishKeyboardVisibility
{
    BOOL visible = [self isHostedKeyboardVisible];
    if (visible == self.keyboardWasVisible) return;
    self.keyboardWasVisible = visible;
    [NSNotificationCenter.defaultCenter postNotificationName:@"PXKeyboardStateChanged" object:self];
}

- (BOOL)isKeyboardRelocated
{
    if (!self.keyboardSlot.superview || self.keyboardHostView.superview != self.keyboardSlot ||
        !self.keyboardHostView.window) return NO;
    for (UIView *view = self.keyboardHostView; view; view = view.superview)
        if (view.hidden || view.alpha <= 0.01) return NO;
    return YES;
}

+ (void)setCaptureHidden:(BOOL)hidden forView:(UIView *)view
{
    CALayer *layer = view.layer;
    SEL getter = NSSelectorFromString(@"disableUpdateMask");
    SEL setter = NSSelectorFromString(@"setDisableUpdateMask:");
    if (![layer respondsToSelector:getter] || ![layer respondsToSelector:setter]) return;
    @try {
        unsigned int mask = [[layer valueForKey:@"disableUpdateMask"] unsignedIntValue];
        // Exclude only these layers, never the relocated keyboard sharing their window.
        mask = hidden ? mask | 0x12 : mask & ~0x12;
        [layer setValue:@(mask) forKey:@"disableUpdateMask"];
    } @catch (__unused NSException *exception) { }
}

- (CGRect)relocatedKeyboardFrame
{
    return [self isKeyboardRelocated] ? self.keyboardSlot.frame : CGRectNull;
}

- (BOOL)foregroundScene:(id)scene
{
    id settings = PXCall(scene, @"settings");
    if (self.scene != scene) {
        self.originalOrientationMapResolver = PXCall(settings, @"interfaceOrientationMapResolver");
        SEL mode = NSSelectorFromString(@"interfaceOrientationMode");
        self.originalOrientationMode = [settings respondsToSelector:mode]
            ? @(((NSInteger (*)(id, SEL))objc_msgSend)(settings, mode)) : nil;
    }
    id mutable = [settings respondsToSelector:@selector(mutableCopy)] ? [settings mutableCopy] : nil;
    if (!mutable || !PXSetBool(mutable, @"setBackgrounded:", NO)) return NO;
    PXSetBool(mutable, @"setForeground:", YES);
    PXSetBool(mutable, @"setAllowsSelection:", !self.suppressSelection);
    UIInterfaceOrientation orientation = PXPreferredHostedOrientation(self.bundleID, PXCall(scene, @"clientSettings"));
    // Resume with the target appearance in the same update as foregrounding,
    // not a second update after the old background surface is already mounted.
    PXSetSceneAppearance(mutable, self.canvas.traitCollection.userInterfaceStyle);
    // Converting the visible fullscreen scene is not a fresh launch. Preserve
    // its active content direction, including a video player's fullscreen mode.
    UIInterfaceOrientation current = PXSceneOrientation(settings);
    if ([[self frontmostBundleID] isEqualToString:self.bundleID] &&
        current >= UIInterfaceOrientationPortrait && current <= UIInterfaceOrientationLandscapeRight)
        orientation = current;
    PXSetHostedOrientation(mutable, orientation);
    CGSize sourceSize = PXSourceSize(mutable);
    if (!PXSetSceneFrame(mutable, PXServerFrameSize(mutable))) return NO;
    if (!PXUpdateScene(scene, mutable)) return NO;
    if (self.scene != scene) {
        SEL remove = NSSelectorFromString(@"removeObserver:");
        if ([self.scene respondsToSelector:remove])
            ((void (*)(id, SEL, id))objc_msgSend)(self.scene, remove, self);
        SEL add = NSSelectorFromString(@"addObserver:");
        if ([scene respondsToSelector:add])
            ((void (*)(id, SEL, id))objc_msgSend)(scene, add, self);
    }
    self.scene = scene;
    self.sourceSize = sourceSize;
    self.sourceOrientation = orientation;
    if (self.sourceOrientation == UIInterfaceOrientationUnknown)
        self.sourceOrientation = sourceSize.width > sourceSize.height ?
            UIInterfaceOrientationLandscapeRight : UIInterfaceOrientationPortrait;
    return YES;
}

- (void)keepHostedProcessAlive
{
    if (self.processAssertion || self.bundleID.length == 0) return;
    int pid = PXApplicationPID(self.bundleID);
    Class targetClass = NSClassFromString(@"RBSTarget");
    Class attributeClass = NSClassFromString(@"RBSLegacyAttribute");
    Class assertionClass = NSClassFromString(@"RBSAssertion");
    SEL targetSelector = NSSelectorFromString(@"targetWithPid:");
    SEL attributeSelector = NSSelectorFromString(@"attributeWithReason:flags:");
    SEL initSelector = NSSelectorFromString(@"initWithExplanation:target:attributes:");
    if (pid <= 0 || ![targetClass respondsToSelector:targetSelector] ||
        ![attributeClass respondsToSelector:attributeSelector] ||
        ![assertionClass instancesRespondToSelector:initSelector]) return;
    @try {
        id target = ((id (*)(id, SEL, int))objc_msgSend)(targetClass,
            targetSelector, pid);
        // Background UI must stay renderable while another app is full screen.
        NSUInteger flags = 1 | 2 | 8 | 32;
        id attribute = ((id (*)(id, SEL, NSUInteger, NSUInteger))objc_msgSend)(
            attributeClass, attributeSelector, 7, flags);
        if (!target || !attribute) return;
        id assertion = ((id (*)(id, SEL, id, id, id))objc_msgSend)([assertionClass alloc],
            initSelector,
            @"ParallelX visible window", target, @[attribute]);
        if (![assertion respondsToSelector:NSSelectorFromString(@"acquireWithError:")]) return;
        NSError *error = nil;
        if (((BOOL (*)(id, SEL, NSError **))objc_msgSend)(assertion,
            NSSelectorFromString(@"acquireWithError:"), &error)) self.processAssertion = assertion;
    } @catch (__unused NSException *exception) { }
}

- (id)protectedSettings:(id)settings forScene:(id)scene
{
    if (self.fullscreenHandoff || !scene || scene != self.scene || !self.canvas ||
        ![settings respondsToSelector:@selector(mutableCopy)]) return nil;
    id mutable = [settings mutableCopy];
    // Screen rotation moves the overlay, not the hosted application's scene.
    PXSetHostedOrientation(mutable, self.sourceOrientation);
    if (!PXSetBool(mutable, @"setBackgrounded:", NO)) return nil;
    PXSetBool(mutable, @"setForeground:", YES);
    PXSetBool(mutable, @"setAllowsSelection:", !self.suppressSelection);
    if (self.sourceSize.width > 0 && self.sourceSize.height > 0)
        PXSetSceneFrame(mutable, PXServerFrameSize(mutable));
    SEL deactivation = NSSelectorFromString(@"setDeactivationReasons:");
    NSMethodSignature *signature = [mutable methodSignatureForSelector:deactivation];
    if (signature && signature.numberOfArguments == 3)
        ((void (*)(id, SEL, NSUInteger))objc_msgSend)(mutable, deactivation, 0);
    return mutable;
}

- (void)scene:(id)scene didUpdateClientSettingsWithDiff:(id)diff
    oldClientSettings:(id)oldSettings transitionContext:(id)transitionContext
{
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self scene:scene didUpdateClientSettingsWithDiff:diff oldClientSettings:oldSettings transitionContext:transitionContext];
        });
        return;
    }
    if (scene != self.scene || !self.canvas || self.fullscreenHandoff) return;
    id client = PXCall(scene, @"clientSettings");
    UIInterfaceOrientation orientation = PXRuntimeHostedOrientation(client);
    UIInterfaceOrientation previous = PXRuntimeHostedOrientation(oldSettings);
    SEL supported = NSSelectorFromString(@"supportedInterfaceOrientations");
    UIInterfaceOrientationMask mask = [client respondsToSelector:supported] ?
        ((NSUInteger (*)(id, SEL))objc_msgSend)(client, supported) : 0;
    if (orientation < UIInterfaceOrientationPortrait || orientation > UIInterfaceOrientationLandscapeRight ||
        orientation == self.sourceOrientation) return;
    // An actual client update (or a new mask excluding the current direction)
    // is authoritative; device rotation alone is never read here.
    if ((previous == UIInterfaceOrientationUnknown || previous == orientation) &&
        (!mask || (mask & (1UL << self.sourceOrientation)))) return;
    id settings = PXCall(scene, @"settings");
    id mutable = [settings respondsToSelector:@selector(mutableCopy)] ? [settings mutableCopy] : nil;
    if (![mutable respondsToSelector:NSSelectorFromString(@"setInterfaceOrientation:")]) return;
    PXSetHostedOrientation(mutable, orientation);
    self.sourceOrientation = orientation;
    self.sourceSize = PXSourceSize(mutable);
    PXSetSceneFrame(mutable, PXServerFrameSize(mutable));
    PXUpdateScene(scene, mutable);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (scene != self.scene || !self.canvas || self.fullscreenHandoff) return;
        [self layoutHost];
        [NSNotificationCenter.defaultCenter postNotificationName:@"PXHostedGeometryChanged" object:self];
    });
}

- (NSArray *)mainLayersForScene:(id)scene
{
    id manager = PXCall(scene, @"layerManager");
    id layers = PXCall(manager, @"layers");
    if ([layers respondsToSelector:@selector(array)]) layers = [layers array];
    if (![layers isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *main = [NSMutableArray array];
    for (id layer in layers) {
        id external = PXCall(layer, @"externalSceneID");
        if (external) continue;
        SEL keyboard = NSSelectorFromString(@"isKeyboardLayer");
        if ([layer respondsToSelector:keyboard] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(layer, keyboard)) continue;
        [main addObject:layer];
    }
    return main;
}

- (BOOL)promoteSwitcherCard:(NSString *)bundleID
{
    if (![self.latestSwitcherBundleID isEqualToString:bundleID]) return NO;
    id switcher = PXCall(NSClassFromString(@"SBMainSwitcherViewController"), @"sharedInstance");
    NSArray *recent = PXCall(switcher, @"recentAppLayouts");
    SEL add = NSSelectorFromString(@"_addAppLayoutToFront:");
    if (![recent isKindOfClass:NSArray.class] || ![switcher respondsToSelector:add]) return NO;
    for (NSUInteger index = 0; index < recent.count; index++) {
        id layout = recent[index];
        BOOL contains = NO;
        SEL membership = NSSelectorFromString(@"containsItemWithBundleIdentifier:");
        if ([layout respondsToSelector:membership])
            contains = ((BOOL (*)(id, SEL, id))objc_msgSend)(layout, membership, bundleID);
        else for (id item in PXCall(layout, @"allItems")) {
            if ([PXCall(item, @"bundleIdentifier") isEqual:bundleID]) { contains = YES; break; }
        }
        if (!contains) continue;
        if (index) ((void (*)(id, SEL, id))objc_msgSend)(switcher, add, layout);
        return YES;
    }
    return NO;
}

- (void)registerSceneInSwitcher:(id)scene bundleID:(NSString *)bundleID
{
    NSString *sceneID = PXCall(scene, @"identifier");
    if (![sceneID isKindOfClass:NSString.class] || sceneID.length == 0) return;
    self.latestSwitcherBundleID = bundleID;
    BOOL existing = [self promoteSwitcherCard:bundleID];
    for (NSNumber *delay in @[@0.25, @0.75, @1.5, @3.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self promoteSwitcherCard:bundleID]; });
    }
    Class itemClass = NSClassFromString(@"SBDisplayItem");
    SEL factory = NSSelectorFromString(@"applicationDisplayItemWithBundleIdentifier:sceneIdentifier:");
    SEL add = NSSelectorFromString(@"addAppLayoutForDisplayItem:completion:");
    id switcher = PXCall(NSClassFromString(@"SBMainSwitcherViewController"), @"sharedInstance");
    Method factoryMethod = class_getClassMethod(itemClass, factory);
    Method addMethod = class_getInstanceMethod([switcher class], add);
    if (!factoryMethod || method_getNumberOfArguments(factoryMethod) != 4 ||
        !addMethod || method_getNumberOfArguments(addMethod) != 4 || existing) return;
    @try {
        id item = ((id (*)(id, SEL, id, id))objc_msgSend)(itemClass,
            factory, bundleID, sceneID);
        if (!item) return;
        ((void (*)(id, SEL, id, id))objc_msgSend)(switcher, add, item, ^{
            dispatch_async(dispatch_get_main_queue(), ^{ [self promoteSwitcherCard:bundleID]; });
        });
    } @catch (__unused NSException *exception) { }
}

- (BOOL)performConfiguredAction:(NSDictionary *)entry
{
    @try {
        if ([entry[@"kind"] isEqual:@"workflow"]) {
            NSString *identifier = entry[@"workflow"];
            if (![identifier isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:identifier]) return NO;
            if (!dlopen("/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/VoiceShortcutClient", RTLD_LAZY)) return NO;
            Class runnerClass = NSClassFromString(@"WFSpringBoardWorkflowRunnerClient");
            SEL initializer = NSSelectorFromString(@"initWithWorkflowIdentifier:");
            if (![runnerClass instancesRespondToSelector:initializer]) return NO;
            id runner = ((id (*)(id, SEL, id))objc_msgSend)([runnerClass alloc], initializer, identifier);
            SEL start = NSSelectorFromString(@"start");
            if (![runner respondsToSelector:start]) return NO;
            ((void (*)(id, SEL))objc_msgSend)(runner, start);
            return YES;
        }
        if (![entry[@"kind"] isEqual:@"quick"]) return NO;
        id item = PXApplicationActionItem(entry);
        if (!item) return NO;
        SEL activate = NSSelectorFromString(@"activateShortcut:withBundleIdentifier:forIconView:");
        Class iconClass = NSClassFromString(@"SBIconView");
        if ([iconClass respondsToSelector:activate]) {
            ((void (*)(id, SEL, id, id, id))objc_msgSend)(iconClass, activate, item, entry[@"app"], nil);
            return YES;
        }
        dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY);
        Class actionClass = NSClassFromString(@"UIHandleApplicationShortcutAction");
        Class optionsClass = NSClassFromString(@"FBSOpenApplicationOptions");
        Class serviceClass = NSClassFromString(@"FBSOpenApplicationService");
        SEL initialize = NSSelectorFromString(@"initWithSBSShortcutItem:");
        SEL optionsSelector = NSSelectorFromString(@"optionsWithDictionary:");
        SEL open = NSSelectorFromString(@"openApplication:withOptions:completion:");
        if (![actionClass instancesRespondToSelector:initialize] || ![optionsClass respondsToSelector:optionsSelector] ||
            ![serviceClass instancesRespondToSelector:open]) return NO;
        id action = ((id (*)(id, SEL, id))objc_msgSend)([actionClass alloc], initialize, item);
        if (!action) return NO;
        SEL mode = NSSelectorFromString(@"activationMode");
        BOOL suspended = [item respondsToSelector:mode] && ((NSUInteger (*)(id, SEL))objc_msgSend)(item, mode) == 1;
        id options = ((id (*)(id, SEL, id))objc_msgSend)(optionsClass, optionsSelector,
            @{@"__ActivateSuspended":@(suspended), @"__Actions":@[action], @"__PromptUnlockDevice":@YES,
              @"__LaunchOrigin":@"__SBLaunchOriginShortcutItem"});
        ((void (*)(id, SEL, id, id, id))objc_msgSend)([serviceClass new], open, entry[@"app"], options, nil);
        return YES;
    } @catch (__unused NSException *exception) { return NO; }
}

- (BOOL)layoutExternalKeyboardView:(UIView *)view
{
    CGSize screen = self.keyboardOverlay.bounds.size;
    CGSize keyboard = view.bounds.size;
    if (screen.width <= 0 || screen.height <= 0 || keyboard.height <= 0) return NO;
    CGRect previous = self.keyboardSlot.frame;
    if (screen.width > screen.height) {
        CGFloat naturalWidth = self.sourceSize.width > 0 ? MIN(keyboard.width, self.sourceSize.width) : keyboard.width;
        if (naturalWidth <= 0) return NO;
        CGFloat width = MIN(naturalWidth, screen.width);
        CGFloat height = MIN(keyboard.height, screen.height);
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.moxuan.parallelx"];
        CGFloat fraction = MIN(100, MAX(0, [defaults doubleForKey:@"externalKeyboardHorizontalPercent"])) / 100;
        CGFloat x = (screen.width - width) * fraction;
        self.keyboardSlot.transform = CGAffineTransformIdentity;
        self.keyboardSlot.frame = CGRectMake(x, screen.height - height, width, height);
        view.frame = CGRectMake(0, height - keyboard.height, width, keyboard.height);
    } else {
        CGFloat height = MIN(keyboard.height, screen.height * 0.55);
        self.keyboardSlot.transform = CGAffineTransformIdentity;
        self.keyboardSlot.frame = CGRectMake(0, screen.height - height, screen.width, height);
        view.frame = CGRectMake(0, height - keyboard.height, screen.width, keyboard.height);
    }
    return !CGRectEqualToRect(previous, self.keyboardSlot.frame);
}

- (void)relocateKeyboardView:(UIView *)view
{
    if (self.relocatingKeyboard) return;
    if (![self usesExternalKeyboard] || !PXKeyboardHasContent(view)) {
        if (view == self.keyboardHostView && self.keyboardSlot && self.keyboardOriginalParent) {
            self.relocatingKeyboard = YES;
            [self.keyboardOriginalParent addSubview:view];
            view.frame = self.keyboardOriginalFrame;
            [self.keyboardSlot removeFromSuperview];
            self.keyboardSlot = nil;
            self.relocatingKeyboard = NO;
            [NSNotificationCenter.defaultCenter postNotificationName:@"PXKeyboardStateChanged" object:self];
        }
        if (self.hostView && [view isDescendantOfView:self.hostView]) self.keyboardHostView = view;
        if (view == self.keyboardHostView) [self publishKeyboardVisibility];
        return;
    }
    if (view == self.keyboardHostView) {
        if (!view.window || view.superview != self.keyboardSlot) {
            self.keyboardSlot.userInteractionEnabled = NO;
            [self.keyboardSlot removeFromSuperview];
            self.keyboardSlot = nil;
            self.keyboardHostView = nil;
            [NSNotificationCenter.defaultCenter postNotificationName:@"PXKeyboardStateChanged" object:self];
        }
        else {
            self.relocatingKeyboard = YES;
            BOOL changed = [self layoutExternalKeyboardView:view];
            self.relocatingKeyboard = NO;
            if (changed) [NSNotificationCenter.defaultCenter postNotificationName:@"PXKeyboardStateChanged" object:self];
            [self publishKeyboardVisibility];
            return;
        }
    }
    UIView *host = self.hostView;
    UIView *overlay = self.keyboardOverlay;
    if (!host || !overlay || !view.window || ![view isDescendantOfView:host]) return;
    CGSize screen = overlay.bounds.size;
    CGFloat sourceHeight = view.bounds.size.height;
    if (screen.width <= 0 || screen.height <= 0 || sourceHeight <= 0) return;
    self.keyboardOriginalParent = view.superview;
    self.keyboardOriginalFrame = view.frame;
    self.relocatingKeyboard = YES;
    // This shared overlay is the handle window. PXPanel owns its current level,
    // including Cover Sheet depth; a keyboard must not restore an old snapshot.
    UIView *previousSlot = self.keyboardSlot;
    self.keyboardHostView = nil;
    self.keyboardSlot = nil;
    previousSlot.userInteractionEnabled = NO;
    [previousSlot removeFromSuperview];
    UIView *slot = [[PXKeyboardSlot alloc] initWithFrame:CGRectZero];
    slot.backgroundColor = UIColor.clearColor;
    slot.opaque = NO;
    slot.clipsToBounds = YES;
    [overlay insertSubview:slot atIndex:0];
    [slot addSubview:view];
    self.keyboardSlot = slot;
    self.keyboardHostView = view;
    [self layoutExternalKeyboardView:view];
    self.relocatingKeyboard = NO;
    [self publishKeyboardVisibility];
    [NSNotificationCenter.defaultCenter postNotificationName:@"PXKeyboardStateChanged" object:self];
}

- (void)relocateExistingKeyboard:(UIView *)root
{
    Class keyboard = NSClassFromString(@"_UIKeyboardLayerHostView");
    if (keyboard && [root isKindOfClass:keyboard]) {
        [self relocateKeyboardView:root];
        return;
    }
    for (UIView *child in [root.subviews copy]) [self relocateExistingKeyboard:child];
}

- (void)openApplication:(NSString *)bundleID
                inView:(UIView *)canvas
       keyboardOverlay:(UIView *)keyboardOverlay
            completion:(void (^)(BOOL))completion
{
    NSAssert(NSThread.isMainThread, @"ParallelX Scene access must be on the main thread");
    [self close];
    NSUInteger generation = self.generation;
    if (bundleID.length == 0 || !canvas) {
        completion(NO);
        return;
    }
    BOOL coldStart = ![self sceneForBundleID:bundleID];
    if (coldStart && ![self launchSuspended:bundleID]) {
        completion(NO);
        return;
    }
    self.canvas = canvas;
    self.keyboardOverlay = keyboardOverlay;
    self.bundleID = bundleID;
    [self publishHostedCamera:YES];
    __weak typeof(self) weakSelf = self;
    __block NSUInteger attempts = 0;
    __block id preparedScene = nil;
    __block void (^retry)(void) = nil;
    retry = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.generation != generation || !strongSelf.canvas) {
            retry = nil;
            return;
        }
        @try {
            id scene = [strongSelf sceneForBundleID:bundleID];
            if (scene && scene != preparedScene &&
                [strongSelf foregroundScene:scene])
                preparedScene = scene;
            [strongSelf keepHostedProcessAlive];
            if (scene && scene == preparedScene) {
                [strongSelf updateAppearanceForStyle:canvas.traitCollection.userInterfaceStyle];
                NSArray *layers = [strongSelf mainLayersForScene:scene];
                id manager = PXCall(scene, @"hostManager");
                SEL enable = NSSelectorFromString(@"enableHostingForRequester:orderFront:");
                SEL acquire = NSSelectorFromString(@"hostViewForRequester:enableAndOrderFront:");
                if (!strongSelf.hostView && [manager respondsToSelector:enable] &&
                    [manager respondsToSelector:acquire]) {
                    NSString *requester = @"com.moxuan.parallelx";
                    ((void (*)(id, SEL, id, BOOL))objc_msgSend)(manager, enable, requester, YES);
                    id view = ((id (*)(id, SEL, id, BOOL))objc_msgSend)(manager, acquire, requester, YES);
                    if ([view isKindOfClass:UIView.class]) {
                        strongSelf.hostManager = manager;
                        strongSelf.hostView = view;
                        strongSelf.hostView.userInteractionEnabled = !strongSelf.suppressSelection;
                        [strongSelf.canvas addSubview:view];
                        [strongSelf layoutHost];
                    }
                }
                Class hostClass = NSClassFromString(@"_UISceneLayerHostContainerView");
                Class contextClass = NSClassFromString(@"UIScenePresentationContext");
                SEL initializer = NSSelectorFromString(@"initWithScene:debugDescription:");
                SEL contextInitializer = NSSelectorFromString(@"_initWithDefaultValues");
                SEL bindContext = NSSelectorFromString(@"_setPresentationContext:");
                if (!strongSelf.hostView &&
                    [hostClass instancesRespondToSelector:initializer] &&
                    [hostClass instancesRespondToSelector:bindContext] &&
                    [contextClass instancesRespondToSelector:contextInitializer]) {
                    id context = ((id (*)(id, SEL))objc_msgSend)([contextClass alloc],
                                                                   contextInitializer);
                    if (context) {
                        id view = ((id (*)(id, SEL, id, id))objc_msgSend)([hostClass alloc],
                            initializer, scene, @"ParallelX");
                        if ([view isKindOfClass:UIView.class]) {
                            UIView *host = view;
                            host.userInteractionEnabled = !strongSelf.suppressSelection;
                            strongSelf.presentationContext = context;
                            [strongSelf updateAppearanceForStyle:canvas.traitCollection.userInterfaceStyle];
                            ((void (*)(id, SEL, id))objc_msgSend)(host, bindContext, context);
                            strongSelf.hostView = host;
                            [strongSelf.canvas addSubview:host];
                            [strongSelf layoutHost];
                        }
                    }
                }
                if (layers.count && strongSelf.hostView) {
                    [strongSelf.hostView layoutIfNeeded];
                    [strongSelf relocateExistingKeyboard:strongSelf.hostView];
                    completion(YES);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (strongSelf.generation == generation)
                            [strongSelf registerSceneInSwitcher:scene bundleID:bundleID];
                    });
                    retry = nil;
                    return;
                }
            }
        } @catch (__unused NSException *exception) {
            // Private interfaces vary; fail closed instead of crashing SpringBoard.
        }
        if (++attempts >= 40) {
            [strongSelf close];
            completion(NO);
            retry = nil;
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (attempts < 10 ? 50 : 125) * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), retry);
    };
    // Already on the main thread. Mount warm scenes in this transaction,
    // rather than exposing an empty window for a run-loop before the handoff.
    retry();
}

- (void)closeForFullscreen
{
    self.fullscreenHandoff = YES;
    [self close];
}

- (void)close
{
    NSAssert(NSThread.isMainThread, @"ParallelX Scene access must be on the main thread");
    [self publishHostedCamera:NO];
    self.generation += 1;
    self.latestSwitcherBundleID = nil;
    self.keyboardHostView = nil;
    self.keyboardSlot.userInteractionEnabled = NO;
    [self.keyboardSlot removeFromSuperview];
    self.keyboardSlot = nil;
    self.keyboardOriginalParent = nil;
    self.keyboardWasVisible = NO;
    self.keyboardOverlay = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:@"PXKeyboardStateChanged" object:self];
    UIView *host = self.hostView;
    self.hostView = nil;
    id hostManager = self.hostManager;
    self.hostManager = nil;
    id scene = self.scene;
    SEL removeObserver = NSSelectorFromString(@"removeObserver:");
    if ([scene respondsToSelector:removeObserver])
        ((void (*)(id, SEL, id))objc_msgSend)(scene, removeObserver, self);
    NSString *bundleID = self.bundleID;
    BOOL fullscreenHandoff = self.fullscreenHandoff;
    if ([PXHomeHandoffBundleID isEqualToString:bundleID]) PXHomeHandoffBundleID = nil;
    self.fullscreenHandoff = NO;
    self.scene = nil;
    self.bundleID = nil;
    self.canvas = nil;
    self.sourceSize = CGSizeZero;
    // Remove our hosted mapping before handing the scene back to SpringBoard.
    // Preserve its current interface orientation and other activation settings.
    id settings = PXCall(scene, @"settings");
    id mutable = [settings respondsToSelector:@selector(mutableCopy)] ? [settings mutableCopy] : nil;
    SEL resolver = NSSelectorFromString(@"setInterfaceOrientationMapResolver:");
    SEL mode = NSSelectorFromString(@"setInterfaceOrientationMode:");
    if (mutable && [mutable respondsToSelector:resolver]) {
        ((void (*)(id, SEL, id))objc_msgSend)(mutable, resolver, self.originalOrientationMapResolver);
        if (self.originalOrientationMode && [mutable respondsToSelector:mode])
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(mutable, mode, self.originalOrientationMode.integerValue);
        PXUpdateScene(scene, mutable);
    }
    self.originalOrientationMapResolver = nil;
    self.originalOrientationMode = nil;
    SEL invalidate = NSSelectorFromString(@"invalidate");
    if (hostManager) {
        SEL disable = NSSelectorFromString(@"disableHostingForRequester:");
        if ([hostManager respondsToSelector:disable])
            ((void (*)(id, SEL, id))objc_msgSend)(hostManager, disable, @"com.moxuan.parallelx");
    } else {
        for (UIView *child in [host.subviews copy]) {
            if ([child respondsToSelector:invalidate])
                ((void (*)(id, SEL))objc_msgSend)(child, invalidate);
        }
        if ([host respondsToSelector:invalidate])
            ((void (*)(id, SEL))objc_msgSend)(host, invalidate);
    }
    [host removeFromSuperview];
    self.presentationContext = nil;
    self.appearanceStyle = UIUserInterfaceStyleUnspecified;
    id assertion = self.processAssertion;
    self.processAssertion = nil;
    @try {
        if ([assertion respondsToSelector:NSSelectorFromString(@"invalidate")])
            ((void (*)(id, SEL))objc_msgSend)(assertion, NSSelectorFromString(@"invalidate"));
    } @catch (__unused NSException *exception) { }
    if (scene && !fullscreenHandoff && ![[self frontmostBundleID] isEqualToString:bundleID]) {
        id settings = PXCall(scene, @"settings");
        id mutable = [settings respondsToSelector:@selector(mutableCopy)] ? [settings mutableCopy] : nil;
        if (mutable && PXSetBool(mutable, @"setBackgrounded:", YES)) {
            PXSetBool(mutable, @"setForeground:", NO);
            PXUpdateScene(scene, mutable);
        }
    }
}

@end
