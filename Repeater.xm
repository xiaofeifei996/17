// Repeater.xm — "+1 按钮"版
//
// 相对原双击手势版的改动：
//   * 移除 UITapGestureRecognizer 与 QQRepeaterGestureTarget，不再双击触发
//   * 每条消息的气泡旁显示一个 "+1" 小按钮，点击即复读该消息
//   * 复读本体（转发消息、0.65s 防抖、消息记录查找、设置项）与原版完全一致
//
// 依赖项目内其他文件的公共设施（与原版 Repeater.xm 相同）：
//   extern BOOL QQCKEnabled(NSString *key);
//   extern NSString * const QQCKRepeaterKey;                  // @"QQCK.repeater"
//   extern NSString * const QQCKSettingsChangedNotification;  // @"QQCK.settingsChanged"
//   链接 MSHookMessageEx（theos 自带）

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#include <string.h>
#include <stdlib.h>

// Substitute / ElleKit 运行时提供该符号（与原 dylib 一致的未定义导入）
extern "C" void MSHookMessageEx(Class _class, SEL _selector, IMP _imp, IMP *_out);

extern BOOL QQCKEnabled(NSString *key);
extern NSString * const QQCKRepeaterKey;
extern NSString * const QQCKSettingsChangedNotification;

#pragma mark - 全局状态（与原版同名/同义）

static char kQQRPRecordKey;  // cell 缓存的 OCMsgRecord（关联对象 key）
static char kQQRPModelKey;   // cell 缓存的 cellViewModel
static char kQQRPButtonKey;  // cell 上的 "+1" 按钮

static double gLastRepeatTime = 0;
static NSString *gLastRepeatIdentity = nil;
static double gLastChatScan = 0;
static int gLastRuntimeClassCount = -1;
static NSMutableSet *gInstalledHooks = nil;
static __weak id gKernelMsgService = nil;

static BOOL QQRPEnabled(void) { return QQCKEnabled(QQCKRepeaterKey) ? YES : NO; }

// 诊断日志：设备日志中过滤 "QQCK+1" 即可查看（Console.app / idevicesyslog）
#define QQRP_LOG(fmt, ...) NSLog(@"[QQCK+1] " fmt, ##__VA_ARGS__)
static int gQQRPDebugCount = 0;
static inline void QQRPDebugOnce(NSString *fmt, ...) {
    if (gQQRPDebugCount >= 150) return;
    gQQRPDebugCount++;
    va_list args; va_start(args, fmt);
    NSLog(@"[QQCK+1][%d] %@", gQQRPDebugCount, [[NSString alloc] initWithFormat:fmt arguments:args]);
    va_end(args);
}

#pragma mark - 消息记录判定与查找

static BOOL QQRPLooksLikeRecord(id obj) {
    if (!obj) return NO;
    return [obj respondsToSelector:@selector(msgId)] &&
           [obj respondsToSelector:@selector(msgSeq)] &&
           [obj respondsToSelector:@selector(peerUid)] &&
           [obj respondsToSelector:@selector(elements)];
}

static BOOL QQRPRecordIsSelf(id record) {
    Class c = NSClassFromString(@"AIODefine.MsgSendTypeUtil");
    SEL sel = NSSelectorFromString(@"shoudldSelfSendMsgWithRecord:");
    if (c && [c respondsToSelector:sel])
        return ((BOOL (*)(id, SEL, id))objc_msgSend)(c, sel, record) ? YES : NO;
    return NO;
}

static id QQRPObjectIvar(id obj, NSString *name) {
    if (!obj || name.length == 0) return nil;
    Class cls = object_getClass(obj);
    unsigned count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    id result = nil;
    for (unsigned i = 0; i < count; i++) {
        const char *n = ivar_getName(ivars[i]);
        if (n && [name isEqualToString:@(n)]) {
            id v = object_getIvar(obj, ivars[i]);
            if ([v isKindOfClass:[NSObject class]]) result = v;
            break;
        }
    }
    free(ivars);
    return result;
}

// 与原版一致：KVC valueForKey: + @try，失败回落同名 ivar
static id QQRPValueForKey(id obj, NSString *name) {
    if (!obj || name.length == 0) return nil;
    @try {
        id v = [obj valueForKey:name];
        if (v == nil || [v isKindOfClass:[NSObject class]] || [v isKindOfClass:[NSURL class]])
            return v;
    } @catch (NSException *e) { }
    return QQRPObjectIvar(obj, name);
}

// 限深、防环地遍历对象图找消息记录
static id QQRPFindRecordDeep(id obj, unsigned depth, NSMutableSet<NSValue *> *visited) {
    if (!obj || depth == 0) return nil;
    NSValue *key = [NSValue valueWithPointer:(__bridge void *)obj];
    if ([visited containsObject:key]) return nil;
    [visited addObject:key];

    if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]] ||
        [obj isKindOfClass:[NSValue class]] || [obj isKindOfClass:[NSDate class]] ||
        [obj isKindOfClass:[NSData class]] || [obj isKindOfClass:[NSURL class]] ||
        [obj isKindOfClass:[UIColor class]] || [obj isKindOfClass:[UIImage class]] ||
        [obj isKindOfClass:[UIView class]])
        return nil;

    if (QQRPLooksLikeRecord(obj)) return obj;

    static NSArray *knownNames = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        knownNames = @[@"record", @"msgRecord", @"_record", @"msg", @"message", @"msgData",
                       @"messageModel", @"contentVM", @"contentViewModel", @"cellViewModel",
                       @"cellModel", @"dataModel", @"model"];
    });
    for (NSString *name in knownNames) {
        id found = QQRPFindRecordDeep(QQRPValueForKey(obj, name), depth - 1, visited);
        if (found) return found;
    }

    // 部分内核对象通过 readData 暴露底层数据（与原版一致）
    if ([obj respondsToSelector:@selector(readData)]) {
        id v = ((id (*)(id, SEL))objc_msgSend)(obj, @selector(readData));
        id found = QQRPFindRecordDeep(v, depth - 1, visited);
        if (found) return found;
    }

    Class cls = object_getClass(obj);
    unsigned count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    for (unsigned i = 0; i < count; i++) {
        const char *type = ivar_getTypeEncoding(ivars[i]);
        if (!type || type[0] != '@') continue;
        id v = object_getIvar(obj, ivars[i]);
        id found = QQRPFindRecordDeep(v, depth - 1, visited);
        if (found) { free(ivars); return found; }
    }
    free(ivars);
    return nil;
}

static id QQRPFindRecord(id obj) {
    if (!obj) return nil;
    if (QQRPLooksLikeRecord(obj)) return obj;
    static NSArray *chain = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        chain = @[@"viewModel", @"cellViewModel", @"contentViewModel", @"contentVM",
                  @"cellModel", @"dataModel", @"model", @"messageModel",
                  @"record", @"msgRecord", @"_record", @"msg", @"message", @"msgData"];
    });
    for (NSString *name in chain) {
        id v = QQRPValueForKey(obj, name);
        if (QQRPLooksLikeRecord(v)) return v;
    }
    return QQRPFindRecordDeep(obj, 6, [NSMutableSet set]);
}

// 浅层查找：只走直接属性链。用于判断"这个 ViewModel 是不是消息级"，
// 避免外层容器（聊天区）的 ViewModel 因深度搜索偶然命中记录而错误创建按钮
static id QQRPShallowRecord(id obj) {
    if (!obj) return nil;
    if (QQRPLooksLikeRecord(obj)) return obj;
    static NSArray *chain = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        chain = @[@"record", @"msgRecord", @"_record", @"msg", @"message", @"msgData",
                  @"messageModel", @"viewModel", @"cellViewModel", @"contentViewModel",
                  @"contentVM", @"cellModel", @"dataModel", @"model"];
    });
    for (NSString *name in chain) {
        id v = QQRPValueForKey(obj, name);
        if (QQRPLooksLikeRecord(v)) return v;
    }
    return nil;
}

static id QQRPDirectRecordFromCell(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        id rec = objc_getAssociatedObject(v, &kQQRPRecordKey);
        if (QQRPLooksLikeRecord(rec)) return rec;
        id found = QQRPFindRecord(objc_getAssociatedObject(v, &kQQRPModelKey));
        if (QQRPLooksLikeRecord(found)) return found;
    }
    return nil;
}

static id QQRPRecordForCell(UIView *view) {
    if (!QQRPEnabled() || !view) return nil;
    id rec = objc_getAssociatedObject(view, &kQQRPRecordKey);
    if (QQRPLooksLikeRecord(rec)) return rec;
    rec = QQRPFindRecord(objc_getAssociatedObject(view, &kQQRPModelKey));
    if (!QQRPLooksLikeRecord(rec)) rec = QQRPDirectRecordFromCell(view);
    if (QQRPLooksLikeRecord(rec))
        objc_setAssociatedObject(view, &kQQRPRecordKey, rec, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return rec;
}

static void QQRPBindCell(UIView *cell, id viewModel) {
    if (!QQRPEnabled() || !cell) return;
    objc_setAssociatedObject(cell, &kQQRPModelKey, viewModel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id rec = QQRPShallowRecord(viewModel);
    if (!QQRPLooksLikeRecord(rec) &&
        [NSStringFromClass([viewModel class]) containsString:@"MessageCellViewModel"])
        rec = QQRPFindRecord(viewModel); // 消息级 VM 才允许深度搜索兜底
    if (QQRPLooksLikeRecord(rec))
        objc_setAssociatedObject(cell, &kQQRPRecordKey, rec, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    QQRPDebugOnce(@"绑定 %@ vm=%@ rec=%@",
                  NSStringFromClass([cell class]),
                  viewModel ? NSStringFromClass([viewModel class]) : @"(nil)",
                  QQRPLooksLikeRecord(rec) ? NSStringFromClass([rec class]) : @"未找到");
}

static void QQRPClearCell(UIView *cell) {
    if (!cell) return;
    objc_setAssociatedObject(cell, &kQQRPRecordKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, &kQQRPModelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIButton *btn = objc_getAssociatedObject(cell, &kQQRPButtonKey);
    btn.hidden = YES;
}

#pragma mark - 复读执行（与原版一致）

static void QQRPRepeatRecord(id record) {
    if (!QQRPEnabled()) return;
    if (!QQRPLooksLikeRecord(record) || QQRPRecordIsSelf(record)) return;

    long long msgId = ((long long (*)(id, SEL))objc_msgSend)(record, @selector(msgId));
    if (msgId <= 0) return;

    id peerUid = ((id (*)(id, SEL))objc_msgSend)(record, @selector(peerUid));
    NSString *identity = [NSString stringWithFormat:@"%@/%lld/%lld", peerUid,
        ((long long (*)(id, SEL))objc_msgSend)(record, @selector(msgSeq)), msgId];

    double now = [NSDate timeIntervalSinceReferenceDate];
    @synchronized([NSDate class]) {
        if (gLastRepeatIdentity && [gLastRepeatIdentity isEqualToString:identity] &&
            now - gLastRepeatTime < 0.65)
            return; // 0.65 秒内同一条消息只复读一次（原版防抖参数）
        gLastRepeatIdentity = [identity copy];
        gLastRepeatTime = now;
    }

    id kernel = gKernelMsgService;
    if (!kernel) {
        Class qsl = NSClassFromString(@"QSLManager");
        SEL gi = NSSelectorFromString(@"getInstance");
        id inst = (qsl && [qsl respondsToSelector:gi]) ? ((id (*)(id, SEL))objc_msgSend)(qsl, gi) : nil;
        SEL ms = NSSelectorFromString(@"msgService");
        kernel = (inst && [inst respondsToSelector:ms]) ? ((id (*)(id, SEL))objc_msgSend)(inst, ms) : nil;
    }
    if (!kernel) return;

    id contact = QQRPValueForKey(record, @"contact");
    if (!contact) {
        Class occ = NSClassFromString(@"OCContact");
        SEL mk = NSSelectorFromString(@"ContactWithChatType:peerUid:guildId:");
        if (occ && [occ respondsToSelector:mk])
            contact = ((id (*)(id, SEL, id, id, id))objc_msgSend)(occ, mk,
                QQRPValueForKey(record, @"chatType"),
                QQRPValueForKey(record, @"peerUid"),
                QQRPValueForKey(record, @"guildId"));
    }
    if (!contact) return;

    SEL fwd = NSSelectorFromString(@"forwardMsg:srcContact:dstContacts:msgAttributeInfos:cb:");
    if (![kernel respondsToSelector:fwd]) return;

    id msgIdNum = [NSNumber numberWithLongLong:msgId];
    NSArray *msgIds = [NSArray arrayWithObjects:&msgIdNum count:1];
    NSArray *dsts = [NSArray arrayWithObjects:&contact count:1];
    ((void (*)(id, SEL, id, id, id, id, id))objc_msgSend)(kernel, fwd, msgIds, contact, dsts, nil, nil);
}

#pragma mark - "+1" 按钮

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

// 气泡定位：content 属性 -> BubbleView
static UIView *QQRPContentAnchor(UIView *view) {
    if (!view) return nil;
    id content = QQRPValueForKey(view, @"content");
    if ([content isKindOfClass:[UIView class]])
        return QQRPFindSubviewNamed(content, @"BubbleView", 3);
    return QQRPFindSubviewNamed(view, @"BubbleView", 3);
}

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
    if (!cell) cell = sender.superview;
    id rec = QQRPRecordForCell(cell);
    QQRP_LOG(@"+1 点击 rec=%@ cell=%@", rec ? NSStringFromClass([rec class]) : @"(未找到)", NSStringFromClass([cell class]));
    QQRPRepeatRecord(rec);
}
@end

// 祖先视图已有按钮则不再创建（仅按绑定的记录判断是否创建，见 EsureButton）
static BOOL QQRPCellHasNearbyButton(UIView *cell) {
    for (UIView *v = cell.superview; v; v = v.superview)
        if (objc_getAssociatedObject(v, &kQQRPButtonKey)) return YES;
    return NO;
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

// 确保 cell 上存在按钮，并按当前记录刷新显示
static void QQRPEsureButton(UIView *cell) {
    if (!QQRPEnabled() || !cell) return;
    UIButton *btn = objc_getAssociatedObject(cell, &kQQRPButtonKey);
    if (!btn) {
        // 创建门禁：本 cell 必须已直接绑定消息记录（消息 cell 才有）
        if (!QQRPLooksLikeRecord(objc_getAssociatedObject(cell, &kQQRPRecordKey))) return;
        if (QQRPCellHasNearbyButton(cell)) return;
        btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.translatesAutoresizingMaskIntoConstraints = YES;
        [btn setTitle:@"+1" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        BOOL dark = NO;
        if (@available(iOS 12.0, *))
            dark = cell.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        [btn setTitleColor:(dark ? [UIColor colorWithRed:0.45 green:0.70 blue:1.0 alpha:1.0]
                                 : [UIColor colorWithRed:0.05 green:0.45 blue:0.90 alpha:1.0])
                  forState:UIControlStateNormal];
        btn.backgroundColor = dark ? [UIColor colorWithWhite:1.0 alpha:0.10]
                                   : [UIColor colorWithWhite:0.0 alpha:0.05];
        btn.layer.cornerRadius = 15.0;
        btn.layer.masksToBounds = YES;
        [btn addTarget:[QQRepeaterButtonTarget shared]
                action:@selector(plusOneTapped:)
      forControlEvents:UIControlEventTouchUpInside];
        [cell addSubview:btn];
        objc_setAssociatedObject(btn, &kQQRPButtonKey, cell, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, &kQQRPButtonKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        QQRP_LOG(@"按钮已创建 cell=%@ rec=%@", NSStringFromClass([cell class]),
                 NSStringFromClass([objc_getAssociatedObject(cell, &kQQRPRecordKey) class]));
    }
    // 只有本 cell 直接绑定了消息记录（即真正的消息 cell）才创建按钮；
    // 外层容器即使被深度搜索命中记录也不会在此处关联（BindCell 浅层失败即不落 key）
    id rec = objc_getAssociatedObject(cell, &kQQRPRecordKey);
    if (!QQRPLooksLikeRecord(rec)) { btn.hidden = YES; return; }
    QQRPUpdateButtonFrame(cell);
}

#pragma mark - Cell 钩子安装（扫描策略与原版一致）

static BOOL QQRPClassIsDescendant(Class cls, Class base) {
    for (Class c = cls; c; c = class_getSuperclass(c))
        if (c == base) return YES;
    return NO;
}

static void QQRPAddLayoutHook(Class cls, SEL sel, int kind) {
    if (!cls || !sel) return;
    // 只挂类自己实现的方法（不碰父类实现）
    unsigned count = 0;
    Method *list = class_copyMethodList(cls, &count);
    BOOL owned = NO;
    for (unsigned j = 0; j < count; j++)
        if (method_getName(list[j]) == sel) { owned = YES; break; }
    free(list);
    if (!owned) return;

    // 安全检查：只挂返回 void 的方法（block IMP 签名须匹配）
    char *retType = method_copyReturnType(class_getInstanceMethod(cls, sel));
    BOOL voidRet = retType && retType[0] == 'v';
    free(retType);
    if (!voidRet) return;

    NSString *key = [NSString stringWithFormat:@"%p/%@", cls, NSStringFromSelector(sel)];
    if ([gInstalledHooks containsObject:key]) return;
    [gInstalledHooks addObject:key];
    QQRP_LOG(@"hook %@/%@ kind=%d", NSStringFromClass(cls), NSStringFromSelector(sel), kind);

    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP orig = method_getImplementation(m);

    if (kind == 0) { // layoutViewWithViewModel: —— 绑定 ViewModel 并刷新按钮
        id blk = ^(id self, id vm) {
            ((void (*)(id, SEL, id))orig)(self, sel, vm);
            if (QQRPEnabled()) { QQRPBindCell(self, vm); QQRPEsureButton(self); }
        };
        method_setImplementation(m, imp_implementationWithBlock(blk));
    } else if (kind == 1) { // layoutSubviews —— 确保按钮存在并定位
        id blk = ^(id self) {
            ((void (*)(id, SEL))orig)(self, sel);
            if (QQRPEnabled()) QQRPEsureButton(self);
        };
        method_setImplementation(m, imp_implementationWithBlock(blk));
    } else { // unbindViewModel —— 清理
        id blk = ^(id self) {
            ((void (*)(id, SEL))orig)(self, sel);
            QQRPClearCell(self);
        };
        method_setImplementation(m, imp_implementationWithBlock(blk));
    }
}

static void QQRPInstallOwnHooks(Class cls) {
    if (!cls) return;
    QQRPAddLayoutHook(cls, @selector(layoutViewWithViewModel:), 0);
    QQRPAddLayoutHook(cls, @selector(layoutSubviews), 1);
    QQRPAddLayoutHook(cls, @selector(unbindViewModel), 2);
}

static void QQRPInstallInheritedLayout(const char *name);

static void QQRPScanUI(int unused) {
    if (!QQRPEnabled()) return;
    QQRPInstallInheritedLayout("NTAIOCellView"); // 与原版相同的两层扫描

    int classCount = (int)objc_getClassList(NULL, 0);
    if (classCount == gLastRuntimeClassCount) return;
    gLastRuntimeClassCount = classCount;

    Class base = NSClassFromString(@"NTBaseAIO.NTAIOBaseCellView");
    QQRP_LOG(@"扫描开始 base=%@ 类总数=%d 已装钩子=%lu",
             base ? NSStringFromClass(base) : @"(未找到)", classCount,
             (unsigned long)gInstalledHooks.count);
    Class *classes = (Class *)malloc(sizeof(Class) * classCount);
    int n = objc_getClassList(classes, classCount);
    for (int i = 0; i < n; i++) {
        if (base && QQRPClassIsDescendant(classes[i], base))
            QQRPInstallOwnHooks(classes[i]);
        else if (!base && [NSStringFromClass(classes[i]) containsString:@"NTAIOCellView"])
            QQRPInstallOwnHooks(classes[i]);
    }
    free(classes);
    QQRP_LOG(@"扫描完成 已装钩子=%lu", (unsigned long)gInstalledHooks.count);
}

static void QQRPInstallInheritedLayout(const char *name) {
    Class base = objc_getClass(name);
    if (!base) return;
    int classCount = (int)objc_getClassList(NULL, 0);
    if (classCount <= 0) return;
    Class *classes = (Class *)malloc(sizeof(Class) * classCount);
    int n = objc_getClassList(classes, classCount);
    for (int i = 0; i < n; i++)
        if (QQRPClassIsDescendant(classes[i], base)) QQRPInstallOwnHooks(classes[i]);
    free(classes);
}

#pragma mark - Kernel 服务钩子（仅缓存实例，与原版一致）

static id (*orig_initWithCpp)(id, SEL, const void *);
static id hook_initWithCpp(id self, SEL _cmd, const void *cpp) {
    id r = orig_initWithCpp(self, _cmd, cpp);
    if (r) gKernelMsgService = r;
    return r;
}

static void (*orig_forwardMsg)(id, SEL, id, id, id, id, id);
static void hook_forwardMsg(id self, SEL _cmd, id msgs, id src, id dsts, id attrs, id cb) {
    gKernelMsgService = self; // 复读触发的转发也会经过这里，仅更新缓存后透传
    orig_forwardMsg(self, _cmd, msgs, src, dsts, attrs, cb);
}

static void (*orig_viewDidAppear)(id, SEL, BOOL);
static void hook_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    orig_viewDidAppear(self, _cmd, animated);
    NSString *name = NSStringFromClass([self class]);
    if (!QQRPEnabled()) return;
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

        Class kernel = objc_getClass("OCIKernelMsgService");
        if (kernel) {
            MSHookMessageEx(kernel, @selector(initWithCpp:), (IMP)hook_initWithCpp, (IMP *)&orig_initWithCpp);
            MSHookMessageEx(kernel, NSSelectorFromString(@"forwardMsg:srcContact:dstContacts:msgAttributeInfos:cb:"),
                            (IMP)hook_forwardMsg, (IMP *)&orig_forwardMsg);
        }
        MSHookMessageEx(objc_getClass("UIViewController"), @selector(viewDidAppear:),
                        (IMP)hook_viewDidAppear, (IMP *)&orig_viewDidAppear);
        QQRP_LOG(@"构造完成 kernel=%d", kernel != nil);

        [[NSNotificationCenter defaultCenter]
            addObserverForName:QQCKSettingsChangedNotification object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        if (QQRPEnabled()) {
                            gLastRuntimeClassCount = -1;
                            QQRPScanUI(0);
                        }
                    }];
    }
}
