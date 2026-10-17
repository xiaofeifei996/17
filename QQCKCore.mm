// QQCKCore.mm — 公共符号桩（独立编译版）
// 原工程里这些符号定义在 QQ净化 Core 公共文件中；
// 为了让复读模块可以独立编译成 dylib，这里提供与原版语义一致的实现：
// 开关直接读取宿主（QQ）的 NSUserDefaults，键为 "QQCK.repeater"，默认开启。

#import <Foundation/Foundation.h>

NSString * const QQCKRepeaterKey = @"QQCK.repeater";
NSString * const QQCKSettingsChangedNotification = @"QQCK.settingsChanged";

BOOL QQCKEnabled(NSString *key) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:key]) return YES; // 未配置时默认开启
    return [defaults boolForKey:key];
}
