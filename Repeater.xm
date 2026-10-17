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

#pragma mark - 撤回消息过滤

// 读取标签文本（text / attributedText.string）
static NSString *QQRPLabelText(UIView *v) {
    if (!v) return nil;
    @try {
        id t = [v valueForKey:@"text"];
        if ([t isKindOfClass:[NSString class]]) return t;
        id at = [v valueForKey:@"attributedText"];
        if ([at isKindOfClass:[NSAttributedString class]]) return [at string];
    } @catch (NSException *e) { }
    return nil;
}

// 深度扫描子视图文本里是否包含关键词（如"撤回"）
static BOOL QQRPUITextContains(UIView *view, NSString *keyword, unsigned depth) {
    if (!view || depth == 0) return NO;
    NSString *t = QQRPLabelText(view);
    if ([t containsString:keyword]) return YES;
    for (UIView *sub in view.subviews)
        if (QQRPUITextContains(sub, keyword, depth - 1)) return YES;
    return NO;
}

// 判断该 cell 是否为撤回相关（防撤回恢复的消息 / 撤回提示行）——不显示按钮
static BOOL QQRPCellIsRecallRelated(UIView *cell) {
    NSString *cn = NSStringFromClass([cell class]);
    for (NSString *kw in @[@"Tip", @"Recall", @"Revok", @"Gray", @"Time", @"Notice"])
        if ([cn rangeOfString:kw options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    // 文本探测：提示行或防撤回内容通常带"撤回"字样
    return QQRPUITextContains(cell, @"撤回", 4);
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

// BFS 查找头像视图（类名含 avatar/headicon/headimage，尺寸 20~70pt）——与 QQPlusOneUI 相同
static UIView *QQRPFindAvatar(UIView *start) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:start];
    int scanned = 0;
    while (queue.count && scanned < 200) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        scanned++;
        if ([v isKindOfClass:[UIButton class]]) continue;
        if (v.isHidden || v.alpha < 0.01) continue;
        NSString *cn = NSStringFromClass(v.class).lowercaseString;
        BOOL isAvatar = [cn containsString:@"avatar"] ||
                        [cn containsString:@"headicon"] ||
                        [cn containsString:@"headimage"];
        if (isAvatar) {
            CGFloat w = v.bounds.size.width, h = v.bounds.size.height;
            if (w >= 20 && w <= 70 && h >= 20 && h <= 70) return v;
        }
        [queue addObjectsFromArray:v.subviews];
    }
    return nil;
}

static void QQRPUpdateButtonFrame(UIView *cell);

// 确保 cell 上存在按钮（仅当原版双击手势存在时创建），并做全部过滤
static void QQRPEsureButton(UIView *cell) {
    if (!cell) return;
    UIButton *btn = objc_getAssociatedObject(cell, &kQQRPButtonKey);
    if (!btn) {
        if (!QQRPViewHasOriginalGesture(cell)) return; // 原版手势在的才是消息 cell
        id target = QQRPOriginalTarget();
        if (!target) return;                           // 原版复读模块未加载
        if (QQRPCellIsRecallRelated(cell)) return;     // 撤回相关消息不显示
        NSString *cellCls = NSStringFromClass([cell class]);
        if ([cellCls rangeOfString:@"Time" options:NSCaseInsensitiveSearch].location != NSNotFound) return;
        // 自己的消息（头像在右）不创建
        UIView *av0 = QQRPFindAvatar(cell);
        CGFloat cw0 = cell.bounds.size.width;
        if (av0 && cw0 > 50 &&
            CGRectGetMidX([cell convertRect:av0.bounds fromView:av0]) > cw0 * 0.5) return;

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
        btn.backgroundColor = [UIColor clearColor]; // 透明背景
        btn.layer.cornerRadius = 14.0;
        btn.layer.borderWidth = 1.0;
        btn.layer.borderColor = blue.CGColor;
        btn.layer.masksToBounds = YES;
        [btn addTarget:[QQRepeaterButtonTarget shared]
                action:@selector(plusOneTapped:)
      forControlEvents:UIControlEventTouchUpInside];
        [cell addSubview:btn];
        objc_setAssociatedObject(btn, &kQQRPButtonKey, cell, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, &kQQRPButtonKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        QQRP_LOG(@"按钮已创建 cell=%@", NSStringFromClass([cell class]));
    }
    QQRPUpdateButtonFrame(cell);
}

// 定位 v18：头像定左右 + 气泡右上角定位（对齐参考效果）
// 气泡查找：优先命名视图（Bubble/文本视图/ImageView），兜底取头像右侧面积最大的内容视图
static void QQRPUpdateButtonFrame(UIView *cell) {
    UIButton *btn = objc_getAssociatedObject(cell, &kQQRPButtonKey);
    if (!btn) return;
    UIView *avatar = QQRPFindAvatar(cell);
    if (!avatar) { btn.hidden = YES; return; }
    CGFloat w = cell.bounds.size.width;
    CGRect af = [cell convertRect:avatar.bounds fromView:avatar];

    // 自己发的消息（头像在右）不显示按钮
    if (w > 50 && CGRectGetMidX(af) > w * 0.5) { btn.hidden = YES; return; }

    CGFloat avatarRight = CGRectGetMaxX(af);

    // 1) 命名候选：取头像右侧、面积最大的气泡类视图
    CGRect bubble = CGRectZero;
    CGFloat bestArea = 0;
    NSArray *names = @[@"BubbleView", @"Bubble", @"TextContentView",
                       @"TextContent", @"YYLabel", @"TTextLabel", @"ImageView"];
    for (NSString *name in names) {
        UIView *v = QQRPFindSubviewNamed(cell, name, 6);
        if (!v) continue;
        CGRect f = [cell convertRect:v.bounds fromView:v];
        if (f.size.width < 30 || f.size.height < 30) continue;
        if (CGRectGetMinX(f) < avatarRight - 12) continue;          // 必须在头像右侧
        if (CGRectGetMaxX(f) > w * 0.98) continue;                  // 排除满宽容器
        CGFloat a = f.size.width * f.size.height;
        if (a > bestArea) { bestArea = a; bubble = f; }
    }
    // 2) 几何兜底：头像右侧面积最大的可见内容视图（图片/表情等）
    if (bestArea <= 0) {
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:cell];
        while (queue.count) {
            UIView *v = queue.firstObject;
            [queue removeObjectAtIndex:0];
            for (UIView *sub in v.subviews) {
                if (sub.isHidden || sub.alpha < 0.01) continue;
                if ([sub isKindOfClass:[UIButton class]]) continue;
                CGRect f = [cell convertRect:sub.bounds fromView:sub];
                CGFloat a = f.size.width * f.size.height;
                if (f.size.width > 30 && f.size.height > 30 &&
                    CGRectGetMinX(f) >= avatarRight - 12 &&
                    CGRectGetMaxX(f) < w * 0.98 && a > bestArea) {
                    bestArea = a; bubble = f;
                }
                [queue addObject:sub];
            }
        }
    }
    if (bestArea <= 0) { btn.hidden = YES; return; }

    // 按钮放气泡右上角外侧：略高于气泡顶边、贴右缘
    CGFloat size = 28.0;
    CGFloat x = CGRectGetMaxX(bubble) + 6.0;
    CGFloat y = CGRectGetMinY(bubble) - size / 2.0 - 2.0;
    x = MIN(MAX(x, 2.0), w - size - 2.0);
    y = MAX(y, 2.0);
    btn.frame = CGRectMake(x, y, size, size);
    btn.hidden = NO;
    if (cell.superview) [cell.superview bringSubviewToFront:btn];
    [cell bringSubviewToFront:btn];
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
        // 原版手势可能由外层钩子在本调用返回之后才挂上：
        // 先同步尝试一次，再在下一轮主循环复查（此时手势必定已存在）
        QQRPEsureButton(self);
        dispatch_async(dispatch_get_main_queue(), ^{ QQRPEsureButton(self); });
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
