#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <notify.h>
#import <string.h>

// RegionShot CameraSupport demonstrates this iOS 15 media-service hook.
// Restrict it to opted-in hosted clients, never to all camera clients.
static uint64_t PXCameraState(NSString *name)
{
    int token;
    uint64_t state = 0;
    if (notify_register_check(name.UTF8String, &token) == NOTIFY_STATUS_OK) {
        notify_get_state(token, &state);
        notify_cancel(token);
    }
    return state;
}

static void (*PXOriginalCameraState)(id, SEL, void *, id);
static void PXCameraStateChanged(id client, SEL selector, void *condition, id value)
{
    BOOL hosted = NO;
    @try {
        SEL identifier = NSSelectorFromString(@"applicationID");
        id bundleID = [client respondsToSelector:identifier]
            ? ((id (*)(id, SEL))objc_msgSend)(client, identifier) : nil;
        if ([bundleID isKindOfClass:NSString.class] && [bundleID length] > 0) {
            uint64_t epoch = PXCameraState(@"com.moxuan.parallelx.camera-session");
            hosted = epoch > 1 &&
                PXCameraState([@"com.moxuan.parallelx.camera-client." stringByAppendingString:bundleID]) == epoch;
        }
    } @catch (__unused NSException *exception) { }
    if (!hosted && PXOriginalCameraState)
        PXOriginalCameraState(client, selector, condition, value);
}

__attribute__((constructor)) static void PXInstallCameraSupport(void)
{
    @autoreleasepool {
        Class cls = objc_getClass("FigCaptureClientSessionMonitor");
        SEL selector = NSSelectorFromString(@"_updateClientStateCondition:newValue:");
        Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
        if (method && strcmp(method_getTypeEncoding(method), "v32@0:8^v16@24") == 0)
            MSHookMessageEx(cls, selector, (IMP)PXCameraStateChanged, (IMP *)&PXOriginalCameraState);
    }
}
