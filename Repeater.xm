// Repeater.xm — "+1 按钮"最终版（模拟双击）
//
// 设计（应要求"点一下 +1 = 模拟双击"）：
//   * 完全复用原版 QQ净化 的复读实现，不自建任何消息查找/转发逻辑
//   * 原版给消息 cell 挂了"双击手势"（target = QQRepeaterGestureTarget，
//     action = doubleTap:，numberOfTapsRequired=2，delegate 也是它）
//   * 本插件在同样的 cell 上加一个 "+1" 小按钮；点击时构造一个
//     "state=Ended、view=该cell" 的模拟手势对象，直接调用原版
//     [[QQRepeaterGestureTarget shared] doubleTap:] —— 与真实双击走完全相同的代码路径
//
// 前提：保留原版「QQ 净化」dylib 并开启其"复读"开关（原版负责找消息和转发）。
// 本插件只在检测到原版双击手势的 cell 上显示按钮；未检测到原版时不显示（避免死按钮）。

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

extern "C" void MSHookMessageEx(Class _class, SEL _selector, IMP _imp, IMP *_out);

#define QQRP_LOG(fmt, ...) NSLog(@"[QQCK+1] " fmt, ##__VA_ARGS__)

static NSMutableSet *gInstalledHooks = nil;
static int gLastRuntimeClassCount = -1;
static char kQQRPButtonKey;   // cell 关联的按钮

#pragma mark - 原版复读目标

// 原版 QQRepeaterGestureTarget.shared（复用其 doubleTap: 实现）
static id QQRPOriginalTarget(void) {
    Class c = objc_getClass("QQRepeaterGestureTarget");
    if (!c) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(c, @selector(shared));
}

// 检测 cell 上是否挂着原版的"双击复读"手势
// （UITapGesture 识别器 + 双击 + delegate 类名 QQRepeaterGestureTarget）
static BOOL QQRPViewHasOriginalGesture(UIView *view) {
    if (!view) return NO;
    for (UIGestureRecognizer *g in view.gestureRecognizers) {
        if (![g isKindOfClass:[UITapGestureRecognizer class]]) continue;
        if (((NSInteger (*)(id, SEL))objc_msgSend)(g, @selector(numberOfTapsRequired)) != 2) continue;
        id d = g.delegate;
        if (d && [NSStringFromClass([d class]) containsString:@"QQRepeaterGestureTarget"]) return YES;
    }
    return NO;
}

// 模拟双击所需的最小"手势"对象：原版 doubleTap: 只读 state（须为 Ended=3）和 view
@interface QQRPFakeTapGesture : NSObject
@property (nonatomic, assign) NSInteger state;
@property (nonatomic, strong) UIView *view;
@end
@implementation QQRPFakeTapGesture
@end

#pragma mark - 自己消息的转发支持

// 原版复读会跳过自己发的消息（shoudldSelfSendMsgWithRecord: 为真时直接返回）。
// 这里挂一个"透传"钩子：行为完全不变，仅借原版查找记录的过程捕获消息记录，
// 点击自己消息的 "+1" 时由本插件直接执行转发（复刻原版 forwardMsg 调用）。

static id gLastCapturedRecord = nil;
static double gLastForwardTime = 0; // 最近一次 +1 转发成功的时间（用于抑制复读副本的按钮）
static BOOL gSelfCheckHooked = NO;
static BOOL (*orig_shouldSelfSend)(id, SEL, id);
static BOOL hook_shouldSelfSend(id self, SEL _cmd, id record);

static void QQRPInstallSelfCheckHook(void) {
    if (gSelfCheckHooked) return;
    Class c = objc_getClass("AIODefine.MsgSendTypeUtil");
    SEL sel = NSSelectorFromString(@"shoudldSelfSendMsgWithRecord:");
    if (!c || ![c respondsToSelector:sel]) return;
    MSHookMessageEx(c, sel, (IMP)hook_shouldSelfSend, (IMP *)&orig_shouldSelfSend);
    gSelfCheckHooked = YES;
    QQRP_LOG(@"已挂捕获钩子 MsgSendTypeUtil");
}

static BOOL hook_shouldSelfSend(id self, SEL _cmd, id record) {
    gLastCapturedRecord = record;
    return orig_shouldSelfSend(self, _cmd, record);
}

static BOOL QQRPIsSelfRecord(id record) {
    Class c = objc_getClass("AIODefine.MsgSendTypeUtil");
    SEL sel = NSSelectorFromString(@"shoudldSelfSendMsgWithRecord:");
    if (c && [c respondsToSelector:sel])
        return ((BOOL (*)(id, SEL, id))objc_msgSend)(c, sel, record) ? YES : NO;
    return NO;
}

static BOOL QQRPLooksLikeRecord2(id obj);

// 复刻原版 QQRPRepeatRecord 的转发部分（消息 ID 装数组 -> forwardMsg 回当前会话）
static void QQRPForwardRecord(id record) {
    if (!QQRPLooksLikeRecord2(record)) return;
    long long msgId = ((long long (*)(id, SEL))objc_msgSend)(record, @selector(msgId));
    if (msgId <= 0) return;

    // 与原版一致的 0.65s 防抖
    static NSString *lastIdentity = nil;
    static double lastTime = 0;
    id peerUid = ((id (*)(id, SEL))objc_msgSend)(record, @selector(peerUid));
    NSString *identity = [NSString stringWithFormat:@"%@/%lld/%lld", peerUid,
        ((long long (*)(id, SEL))objc_msgSend)(record, @selector(msgSeq)), msgId];
    double now = [NSDate timeIntervalSinceReferenceDate];
    @synchronized([NSDate class]) {
        if (lastIdentity && [lastIdentity isEqualToString:identity] && now - lastTime < 0.65) return;
        lastIdentity = [identity copy];
        lastTime = now;
    }

    id kernel = nil;
    Class qsl = objc_getClass("QSLManager");
    SEL gi = NSSelectorFromString(@"getInstance");
    id inst = (qsl && [qsl respondsToSelector:gi]) ? ((id (*)(id, SEL))objc_msgSend)(qsl, gi) : nil;
    SEL ms = NSSelectorFromString(@"msgService");
    kernel = (inst && [inst respondsToSelector:ms]) ? ((id (*)(id, SEL))objc_msgSend)(inst, ms) : nil;
    if (!kernel) { QQRP_LOG(@"转发失败：未取得消息服务"); return; }

    id contact = nil;
    SEL ct = @selector(contact);
    if ([record respondsToSelector:ct]) contact = ((id (*)(id, SEL))objc_msgSend)(record, ct);
    if (!contact) {
        Class occ = objc_getClass("OCContact");
        SEL mk = NSSelectorFromString(@"ContactWithChatType:peerUid:guildId:");
        if (occ && [occ respondsToSelector:mk])
            contact = ((id (*)(id, SEL, id, id, id))objc_msgSend)(occ, mk,
                ((id (*)(id, SEL))objc_msgSend)(record, @selector(chatType)),
                ((id (*)(id, SEL))objc_msgSend)(record, @selector(peerUid)),
                ((id (*)(id, SEL))objc_msgSend)(record, @selector(guildId)));
    }
    if (!contact) { QQRP_LOG(@"转发失败：未取得会话"); return; }

    SEL fwd = NSSelectorFromString(@"forwardMsg:srcContact:dstContacts:msgAttributeInfos:cb:");
    if (![kernel respondsToSelector:fwd]) { QQRP_LOG(@"转发失败：接口不存在"); return; }
    id num = [NSNumber numberWithLongLong:msgId];
    NSArray *ids = [NSArray arrayWithObjects:&num count:1];
    NSArray *dsts = [NSArray arrayWithObjects:&contact count:1];
    ((void (*)(id, SEL, id, id, id, id, id))objc_msgSend)(kernel, fwd, ids, contact, dsts, nil, nil);
    gLastForwardTime = [NSDate timeIntervalSinceReferenceDate];
    QQRP_LOG(@"已转发自己的消息 msgId=%lld", msgId);
}

// 轻量记录判定（原版同款四件套）
static BOOL QQRPLooksLikeRecord2(id obj) {
    return obj && [obj respondsToSelector:@selector(msgId)] &&
           [obj respondsToSelector:@selector(msgSeq)] &&
           [obj respondsToSelector:@selector(peerUid)];
}

#pragma mark - 按钮

@interface QQRepeaterButtonTarget : NSObject
+ (instancetype)shared;
- (void)plusOneTapped:(UIButton *)sender;
@end

@implementation QQRepeaterButtonTarget
+ (instancetype)shared {
    static id obj = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ obj = [[self alloc] init]; });
    return obj;
}

- (void)plusOneTapped:(UIButton *)sender {
    UIView *cell = objc_getAssociatedObject(sender, &kQQRPButtonKey);
    id target = QQRPOriginalTarget();
    if (!target || !cell) {
        QQRP_LOG(@"+1 点击放弃：原版复读模块未加载");
        return;
    }
    QQRPInstallSelfCheckHook();
    // 构造模拟手势并直接调用原版 doubleTap: —— 等效于双击该消息；
    // 调用过程中原版会查询 shoudldSelfSendMsgWithRecord:，透传钩子顺带捕获消息记录
    gLastCapturedRecord = nil;
    QQRPFakeTapGesture *fake = [[QQRPFakeTapGesture alloc] init];
    fake.state = 3; // UIGestureRecognizerStateEnded（原版只处理该状态）
    fake.view = cell;
    ((void (*)(id, SEL, id))objc_msgSend)(target, @selector(doubleTap:), fake);

    id rec = gLastCapturedRecord;
    if (rec && QQRPIsSelfRecord(rec)) {
        // 原版会跳过自己发的消息，这里由插件直接转发（等效双击效果）
        QQRPForwardRecord(rec);
    } else {
        QQRP_LOG(@"已模拟双击 cell=%@ rec=%@", NSStringFromClass([cell class]),
                 rec ? NSStringFromClass([rec class]) : @"(未捕获)");
    }
}
@end

// 按名字找可用子视图（可见、非透明、有尺寸），限深防环
static UIView *QQRPFindSubviewNamed(UIView *view, NSString *name, unsigned depth) {
    if (!view || depth == 0) return nil;
    if ([NSStringFromClass(view.class) containsString:name] &&
        !view.isHidden && view.alpha > 0.01 &&
        view.bounds.size.width > 1 && view.bounds.size.height > 1)
        return view;
    for (UIView *sub in view.subviews) {
        UIView *found = QQRPFindSubviewNamed(sub, name, depth - 1);
        if (found) return found;
    }
    return nil;
}

// 气泡定位：先找气泡类视图（Bubble*），找不到再找气泡内文本视图（TextContent/YYLabel/TTextLabel）
static UIView *QQRPFindSubviewNamed(UIView *view, NSString *name, unsigned depth);

static UIView *QQRPContentAnchor(UIView *view) {
    if (!view) return nil;
    // 两轮搜索：优先气泡本体，其次气泡内的文本视图（可据此推算气泡边缘）
    NSArray *passes = @[@[@"BubbleView", @"Bubble"],
                        @[@"TextContentView", @"TextContent", @"YYLabel", @"TTextLabel"]];
    for (NSArray *names in passes) {
        for (NSString *name in names) {
            UIView *found = QQRPFindSubviewNamed(view, name, 6);
            if (found) return found;
        }
    }
    return nil;
}

// 依据气泡位置把按钮放到消息旁
static void QQRPUpdateButtonFrame(UIView *cell) {
    UIButton *btn = objc_getAssociatedObject(cell, &kQQRPButtonKey);
    if (!btn) return;
    CGFloat w = cell.bounds.size.width, h = cell.bounds.size.height;
    if (w < 50 || h < 30) { btn.hidden = YES; return; }

    CGRect anchorFrame = CGRectZero;
    BOOL haveAnchor = NO;
    UIView *anchor = QQRPContentAnchor(cell);
    if (anchor) {
        anchorFrame = [cell convertRect:anchor.bounds fromView:anchor];
        // 锚点可能是气泡内的文本视图：向四周外扩近似气泡真实边缘
        anchorFrame = CGRectInset(anchorFrame, -10.0, -4.0);
        if (anchorFrame.size.width > 1 && anchorFrame.size.height > 1) haveAnchor = YES;
    }

    CGFloat size = 30.0;
    CGFloat x, y;
    if (haveAnchor) {
        BOOL selfSide = CGRectGetMidX(anchorFrame) > w * 0.5; // 自己的消息气泡靠右
        x = selfSide ? (CGRectGetMinX(anchorFrame) - size - 5.0)
                     : (CGRectGetMaxX(anchorFrame) + 5.0);
        y = CGRectGetMidY(anchorFrame) - size / 2.0;
    } else {
        x = w - size - 8.0;
        y = h / 2.0 - size / 2.0;
    }
    x = MIN(MAX(x, 2.0), w - size - 2.0);
    y = MIN(MAX(y, 2.0), h - size - 2.0);
    btn.frame = CGRectMake(x, y, size, size);
    btn.hidden = NO;
    if (cell.superview) [cell.superview bringSubviewToFront:btn];
    [cell bringSubviewToFront:btn];
}

// 确保 cell 上存在按钮（仅当原版双击手势存在时创建），并定位
static void QQRPEsureButton(UIView *cell) {
    if (!cell) return;
    // 复读抑制（每次布局都评估，覆盖 cell 复用场景）：
    // 刚 +1 转发后的短暂时间窗内，右侧（自己发的）消息一律不显示按钮
    CGFloat cw0 = cell.bounds.size.width;
    BOOL suppressNow = NO;
    if (gLastForwardTime > 0 && cw0 > 50) {
        UIView *probe0 = QQRPContentAnchor(cell);
        if (probe0) {
            CGRect pf0 = [cell convertRect:probe0.bounds fromView:probe0];
            if (CGRectGetMidX(pf0) > cw0 * 0.5 &&
                [NSDate timeIntervalSinceReferenceDate] - gLastForwardTime < 5.0)
                suppressNow = YES;
        }
    }
    UIButton *btn = objc_getAssociatedObject(cell, &kQQRPButtonKey);
    if (btn && suppressNow) { btn.hidden = YES; return; }
    if (!btn) {
        if (!QQRPViewHasOriginalGesture(cell)) return; // 原版手势在的才是消息 cell
        id target = QQRPOriginalTarget();
        if (!target) {
            QQRP_LOG(@"未检测到原版复读模块（QQRepeaterGestureTarget），不显示按钮");
            return;
        }
        // 过滤 1：时间行（如 17:00 / 19:50 的分隔 cell），不是聊天消息
        NSString *cellCls = NSStringFromClass([cell class]);
        if ([cellCls rangeOfString:@"Time" options:NSCaseInsensitiveSearch].location != NSNotFound) return;
        // 过滤 2：刚通过 +1 转发的消息不再显示按钮（suppressNow 见上）
        CGFloat cw = cw0;
        UIView *probe = QQRPContentAnchor(cell);
        if (suppressNow) return;
        btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.translatesAutoresizingMaskIntoConstraints = YES;
        [btn setTitle:@"+1" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        BOOL dark = NO;
        if (@available(iOS 12.0, *))
            dark = cell.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        UIColor *blue = dark ? [UIColor colorWithRed:0.40 green:0.65 blue:1.0 alpha:1.0]
                             : [UIColor colorWithRed:0.10 green:0.50 blue:0.95 alpha:1.0];
        [btn setTitleColor:blue forState:UIControlStateNormal];
        btn.backgroundColor = dark ? [UIColor colorWithWhite:0.16 alpha:1.0]
                                   : [UIColor whiteColor];
        btn.layer.cornerRadius = 15.0;
        btn.layer.borderWidth = 1.0;
        btn.layer.borderColor = blue.CGColor;
        btn.layer.masksToBounds = YES;
        [btn addTarget:[QQRepeaterButtonTarget shared]
                action:@selector(plusOneTapped:)
      forControlEvents:UIControlEventTouchUpInside];
        // 过滤 3：锚点是居中的纯文本小视图（时间戳样式）
        if (probe) {
            CGRect pf = [cell convertRect:probe.bounds fromView:probe];
            BOOL isTextLabel = [NSStringFromClass([probe class]) containsString:@"Label"];
            if (isTextLabel && cw > 50 && fabs(CGRectGetMidX(pf) - cw * 0.5) < 12.0) {
                [btn removeFromSuperview];
                return;
            }
        }
        [cell addSubview:btn];
        objc_setAssociatedObject(btn, &kQQRPButtonKey, cell, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, &kQQRPButtonKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        QQRP_LOG(@"按钮已创建 cell=%@", NSStringFromClass([cell class]));
    }
    QQRPUpdateButtonFrame(cell);
}

#pragma mark - cell 钩子（与原版相同的类扫描）

static BOOL QQRPClassIsDescendant(Class cls, Class base) {
    for (Class c = cls; c; c = class_getSuperclass(c))
        if (c == base) return YES;
    return NO;
}

static void QQRPAddLayoutHook(Class cls) {
    if (!cls) return;
    SEL sel = @selector(layoutSubviews);
    unsigned count = 0;
    Method *list = class_copyMethodList(cls, &count);
    BOOL owned = NO;
    for (unsigned j = 0; j < count; j++)
        if (method_getName(list[j]) == sel) { owned = YES; break; }
    free(list);
    if (!owned) return;

    NSString *key = [NSString stringWithFormat:@"%p/%@", cls, NSStringFromSelector(sel)];
    if ([gInstalledHooks containsObject:key]) return;
    [gInstalledHooks addObject:key];

    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP orig = method_getImplementation(m);
    id blk = ^(id self) {
        ((void (*)(id, SEL))orig)(self, sel);
        // 原版在 layoutViewWithViewModel:/layoutSubviews 钩子里挂手势；
        // 本调用位于原实现之后，若原版钩子链在外层，此时手势已存在
        QQRPEsureButton(self);
    };
    method_setImplementation(m, imp_implementationWithBlock(blk));
}

static void QQRPScanUI(int unused) {
    int classCount = (int)objc_getClassList(NULL, 0);
    if (classCount == gLastRuntimeClassCount) return;
    gLastRuntimeClassCount = classCount;
    if (!objc_getClass("QQRepeaterGestureTarget")) return; // 原版未加载
    QQRPInstallSelfCheckHook();

    Class bases[2] = { objc_getClass("NTBaseAIO.NTAIOBaseCellView"), objc_getClass("NTAIOCellView") };
    QQRP_LOG(@"扫描开始 base1=%@ base2=%@",
             bases[0] ? NSStringFromClass(bases[0]) : @"(nil)",
             bases[1] ? NSStringFromClass(bases[1]) : @"(nil)");

    Class *classes = (Class *)malloc(sizeof(Class) * classCount);
    int n = objc_getClassList(classes, classCount);
    for (int i = 0; i < n; i++) {
        for (int b = 0; b < 2; b++) {
            if (bases[b] && QQRPClassIsDescendant(classes[i], bases[b])) {
                QQRPAddLayoutHook(classes[i]);
                break;
            }
        }
    }
    free(classes);
    QQRP_LOG(@"扫描完成 已装钩子=%lu", (unsigned long)gInstalledHooks.count);
}

#pragma mark - 触发扫描

static void (*orig_viewDidAppear)(id, SEL, BOOL);
static void hook_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    orig_viewDidAppear(self, _cmd, animated);
    static double gLastChatScan = 0;
    NSString *name = NSStringFromClass([self class]);
    if (![name containsString:@"AIOChat"] && ![name containsString:@"NTAIOChatTable"]) return;
    double now = [NSDate timeIntervalSinceReferenceDate];
    if (now - gLastChatScan < 1.5) return;
    gLastChatScan = now;
    QQRP_LOG(@"聊天页 %@，0.2s 后扫描", name);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ QQRPScanUI(0); });
}

#pragma mark - 安装入口

__attribute__((constructor))
static void QQRepeaterInit(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.tencent.mqq"]) return;
        gInstalledHooks = [NSMutableSet new];
        MSHookMessageEx(objc_getClass("UIViewController"), @selector(viewDidAppear:),
                        (IMP)hook_viewDidAppear, (IMP *)&orig_viewDidAppear);
        QQRP_LOG(@"构造完成 原版复读模块=%d", objc_getClass("QQRepeaterGestureTarget") != nil);
    }
}
