#import "PXAppCatalog.h"
#import <objc/message.h>
#import <string.h>
#import <sqlite3.h>
#import <dlfcn.h>

static id PXRead(id object, NSString *name)
{
    SEL selector = NSSelectorFromString(name);
    return [object respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

// Read-only: Shortcuts owns this database; an unknown schema returns an empty list.
NSArray<NSDictionary<NSString *, NSString *> *> *PXAvailableWorkflows(void)
{
    sqlite3 *db = NULL;
    if (sqlite3_open_v2("/var/mobile/Library/Shortcuts/Shortcuts.sqlite", &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
        if (db) sqlite3_close(db);
        return @[];
    }
    sqlite3_busy_timeout(db, 250);
    sqlite3_stmt *stmt = NULL;
    NSMutableArray *items = [NSMutableArray array];
    const char *query = "SELECT s.ZWORKFLOWID, s.ZNAME FROM ZSHORTCUT s WHERE s.ZNAME IS NOT NULL "
        "AND NOT EXISTS (SELECT 1 FROM ZTRIGGER t WHERE t.ZSHORTCUT = s.Z_PK) ORDER BY s.ZNAME COLLATE NOCASE";
    if (sqlite3_prepare_v2(db, query, -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *uid = (const char *)sqlite3_column_text(stmt, 0);
            const char *name = (const char *)sqlite3_column_text(stmt, 1);
            if (!uid || !name) continue;
            NSString *identifier = [NSString stringWithUTF8String:uid];
            NSString *title = [NSString stringWithUTF8String:name];
            if ([[NSUUID alloc] initWithUUIDString:identifier] && title.length)
                [items addObject:@{@"kind":@"workflow", @"workflow":identifier, @"title":title}];
        }
    }
    if (stmt) sqlite3_finalize(stmt);
    sqlite3_close(db);
    return items;
}

static NSArray *PXActionArray(id value)
{
    id composed = PXRead(value, @"composedApplicationShortcutItems");
    if (composed) value = composed;
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

static id PXActionService(void)
{
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
    return PXRead(NSClassFromString(@"SBIconView"), @"applicationShortcutService")
        ?: PXRead(UIApplication.sharedApplication, @"shortcutService")
        ?: [NSClassFromString(@"SBSApplicationShortcutService") new];
}

static NSBundle *PXApplicationBundle(NSString *bundleID)
{
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL proxySelector = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (![proxyClass respondsToSelector:proxySelector]) return nil;
    id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, proxySelector, bundleID);
    NSURL *url = PXRead(proxy, @"bundleURL");
    return [url isKindOfClass:NSURL.class] ? [NSBundle bundleWithURL:url] : nil;
}

static NSArray *PXStaticActions(NSString *bundleID)
{
    NSArray *entries = PXApplicationBundle(bundleID).infoDictionary[@"UIApplicationShortcutItems"];
    Class itemClass = NSClassFromString(@"SBSApplicationShortcutItem");
    SEL convert = NSSelectorFromString(@"_staticApplicationShortcutItemsFromInfoPlistEntry:");
    if (![entries isKindOfClass:NSArray.class] || ![itemClass respondsToSelector:convert]) return @[];
    return PXActionArray(((id (*)(id, SEL, id))objc_msgSend)(itemClass, convert, entries));
}

BOOL PXApplicationHasActions(NSString *bundleID)
{
    if (PXStaticActions(bundleID).count) return YES;
    @try {
        id service = PXActionService();
        SEL fetch = NSSelectorFromString(@"applicationShortcutItemsOfTypes:forBundleIdentifier:");
        return [service respondsToSelector:fetch] &&
            PXActionArray(((id (*)(id, SEL, NSUInteger, id))objc_msgSend)(service, fetch, 3, bundleID)).count > 0;
    } @catch (__unused NSException *exception) { return NO; }
}

void PXFetchApplicationActions(NSString *bundleID, void (^completion)(NSArray<NSDictionary *> *))
{
    NSCAssert(NSThread.isMainThread, @"Fetch application actions on the main thread");
    NSBundle *bundle = PXApplicationBundle(bundleID);
    __block BOOL finished = NO;
    NSMutableArray *base = [NSMutableArray array];
    void (^finish)(NSArray *) = ^(NSArray *raw) {
        if (finished) return;
        finished = YES;
        NSMutableArray *result = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (id item in [raw arrayByAddingObjectsFromArray:base]) {
            NSString *type = PXRead(item, @"type");
            NSString *title = PXRead(item, @"localizedTitle");
            if (![type isKindOfClass:NSString.class] || !type.length ||
                ![title isKindOfClass:NSString.class] || !title.length || [seen containsObject:type]) continue;
            [seen addObject:type];
            NSString *localized = [bundle localizedStringForKey:title value:title table:@"InfoPlist"] ?: title;
            NSMutableDictionary *entry = [@{@"kind":@"quick", @"app":bundleID, @"type":type, @"title":localized} mutableCopy];
            id info = PXRead(item, @"userInfo");
            if ([info isKindOfClass:NSDictionary.class] &&
                [NSPropertyListSerialization propertyList:info isValidForFormat:NSPropertyListBinaryFormat_v1_0])
                entry[@"userInfo"] = info;
            [result addObject:entry];
        }
        completion(result);
    };
    @try {
        id service = PXActionService();
        [base addObjectsFromArray:PXStaticActions(bundleID)];
        SEL fetch = NSSelectorFromString(@"fetchApplicationShortcutItemsOfTypes:forBundleIdentifier:withCompletionHandler:");
        if (![service respondsToSelector:fetch]) { finish(@[]); return; }
        ((void (*)(id, SEL, NSUInteger, id, id))objc_msgSend)(service, fetch, 3, bundleID, ^(id result) {
            dispatch_async(dispatch_get_main_queue(), ^{ finish(PXActionArray(result)); });
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ finish(@[]); });
    } @catch (__unused NSException *exception) { finish(@[]); }
}

id PXApplicationActionItem(NSDictionary *entry)
{
    NSString *bundleID = entry[@"app"], *type = entry[@"type"];
    if (![bundleID isKindOfClass:NSString.class] || !bundleID.length ||
        ![type isKindOfClass:NSString.class] || !type.length) return nil;
    @try {
        SEL fetch = NSSelectorFromString(@"applicationShortcutItemsOfTypes:forBundleIdentifier:");
        id service = PXActionService();
        NSArray *items = [service respondsToSelector:fetch]
            ? PXActionArray(((id (*)(id, SEL, NSUInteger, id))objc_msgSend)(service, fetch, 3, bundleID)) : @[];
        for (id item in [items arrayByAddingObjectsFromArray:PXStaticActions(bundleID)])
            if ([PXRead(item, @"type") isEqualToString:type]) return item;
        Class itemClass = NSClassFromString(@"SBSApplicationShortcutItem");
        id item = [itemClass new];
        SEL setType = NSSelectorFromString(@"setType:"), setTitle = NSSelectorFromString(@"setLocalizedTitle:");
        if (![item respondsToSelector:setType] || ![item respondsToSelector:setTitle]) return nil;
        ((void (*)(id, SEL, id))objc_msgSend)(item, setType, type);
        ((void (*)(id, SEL, id))objc_msgSend)(item, setTitle, entry[@"title"] ?: @"");
        SEL setInfo = NSSelectorFromString(@"setUserInfo:");
        if ([entry[@"userInfo"] isKindOfClass:NSDictionary.class] && [item respondsToSelector:setInfo])
            ((void (*)(id, SEL, id))objc_msgSend)(item, setInfo, entry[@"userInfo"]);
        return item;
    } @catch (__unused NSException *exception) { return nil; }
}

NSArray<NSDictionary<NSString *, NSString *> *> *PXInstalledApplications(void)
{
    id workspace = PXRead(NSClassFromString(@"LSApplicationWorkspace"), @"defaultWorkspace");
    id raw = PXRead(workspace, @"allInstalledApplications");
    if (![raw conformsToProtocol:@protocol(NSFastEnumeration)]) return @[];
    NSMutableArray *apps = [NSMutableArray array];
    for (id proxy in raw) {
        NSString *bundleID = PXRead(proxy, @"bundleIdentifier");
        if (![bundleID isKindOfClass:NSString.class] || bundleID.length == 0 ||
            [bundleID isEqualToString:@"com.apple.springboard"]) continue;
        SEL hiddenSelector = NSSelectorFromString(@"isHidden");
        NSMethodSignature *hiddenSignature = [proxy methodSignatureForSelector:hiddenSelector];
        if (hiddenSignature && hiddenSignature.numberOfArguments == 2 &&
            strcmp(hiddenSignature.methodReturnType, @encode(BOOL)) == 0 &&
            ((BOOL (*)(id, SEL))objc_msgSend)(proxy, hiddenSelector)) continue;
        NSString *name = PXRead(proxy, @"localizedName");
        if (![name isKindOfClass:NSString.class] || name.length == 0)
            name = PXRead(proxy, @"itemName");
        if (![name isKindOfClass:NSString.class] || name.length == 0) name = bundleID;
        [apps addObject:@{ @"id": bundleID, @"name": name }];
    }
    [apps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return apps;
}

@interface UIImage (PXPrivateIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleID
                                              format:(NSInteger)format
                                               scale:(CGFloat)scale;
@end

NSString *PXApplicationDisplayName(NSString *bundleID)
{
    @try {
        Class cls = NSClassFromString(@"LSApplicationProxy");
        SEL selector = NSSelectorFromString(@"applicationProxyForIdentifier:");
        id proxy = [cls respondsToSelector:selector]
            ? ((id (*)(id, SEL, id))objc_msgSend)(cls, selector, bundleID) : nil;
        NSString *name = PXRead(proxy, @"localizedName");
        if (![name isKindOfClass:NSString.class] || !name.length) name = PXRead(proxy, @"itemName");
        return [name isKindOfClass:NSString.class] && name.length ? name : bundleID;
    } @catch (__unused NSException *exception) { return bundleID; }
}

UIImage *PXApplicationIcon(NSString *bundleID)
{
    if (bundleID.length == 0) return nil;
    @try {
        return [UIImage _applicationIconImageForBundleIdentifier:bundleID
                                                         format:2
                                                          scale:UIScreen.mainScreen.scale];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

UIImage *PXApplicationIconLarge(NSString *bundleID)
{
    if (bundleID.length == 0) return nil;
    @try {
        return [UIImage _applicationIconImageForBundleIdentifier:bundleID
                                                         format:10
                                                          scale:UIScreen.mainScreen.scale]
            ?: PXApplicationIcon(bundleID);
    } @catch (__unused NSException *exception) {
        return PXApplicationIcon(bundleID);
    }
}
