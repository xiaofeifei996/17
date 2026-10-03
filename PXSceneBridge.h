#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface PXSceneBridge : NSObject
+ (BOOL)consumeHomeHandoffForBundleID:(NSString *)bundleID;
+ (BOOL)consumeHomeHandoffForCurrentApplication;
+ (void)noteSystemOrientation:(UIInterfaceOrientation)orientation;
+ (UIInterfaceOrientation)systemOrientation;
+ (instancetype)sharedBridge;
+ (nullable id)protectedSettings:(id)settings forAnyScene:(id)scene;
+ (void)relocateAnyKeyboardView:(UIView *)view;
+ (void)setCaptureHidden:(BOOL)hidden forView:(UIView *)view NS_SWIFT_NAME(setCaptureHidden(_:for:));
+ (void)keepTransparentGestureViewHittable:(UIView *)view NS_SWIFT_NAME(keepTransparentGestureViewHittable(_:));
- (void)openApplication:(NSString *)bundleID
                inView:(UIView *)canvas
       keyboardOverlay:(UIView *)keyboardOverlay
            completion:(void (^)(BOOL success))completion;
- (void)relocateKeyboardView:(UIView *)view;
- (void)layoutHost;
- (void)updateAppearanceForStyle:(UIUserInterfaceStyle)style NS_SWIFT_NAME(updateAppearance(for:));
- (void)setHostedInteractionEnabled:(BOOL)enabled;
- (CGSize)hostedSourceSize;
- (BOOL)hasHostedSurface;
- (void)refreshHostedOrientationMap;
- (BOOL)isKeyboardRelocated;
- (BOOL)isHostedKeyboardVisible;
- (BOOL)usesExternalKeyboard;
- (void)refreshKeyboardPlacement;
- (CGRect)relocatedKeyboardFrame;
- (BOOL)hasSceneForApplication:(NSString *)bundleID;
- (nullable UIImage *)launchImageForApplication:(NSString *)bundleID size:(CGSize)size;
- (nullable NSString *)frontmostBundleID;
- (void)prepareWindowForBundleID:(NSString *)bundleID
            wasFullscreen:(BOOL)wasFullscreen
                      completion:(void (^)(BOOL success))completion
    NS_SWIFT_NAME(prepareWindow(for:wasFullscreen:completion:));
- (nullable id)protectedSettings:(id)settings forScene:(id)scene;
- (BOOL)openFullscreenApplication:(NSString *)bundleID;
- (BOOL)restartApplication:(NSString *)bundleID
                 suspended:(BOOL)suspended
                completion:(void (^)(BOOL success))completion;
- (BOOL)performShortcut:(NSString *)identifier;
- (BOOL)performConfiguredAction:(NSDictionary *)entry;
- (BOOL)setBrightnessLevel:(float)level;
- (BOOL)shortcutIsActive:(NSString *)identifier;
- (nullable NSString *)recentApplicationSkipping:(NSArray<NSString *> *)excluded rank:(NSInteger)rank;
- (void)close;
- (void)closeForFullscreen;
@end
@interface PXOverlayWindow : UIWindow
- (void)applySystemOrientation;
@end
NS_ASSUME_NONNULL_END
