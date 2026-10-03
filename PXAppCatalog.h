#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSArray<NSDictionary<NSString *, NSString *> *> *PXInstalledApplications(void);
FOUNDATION_EXPORT NSString *PXApplicationDisplayName(NSString *bundleID);
FOUNDATION_EXPORT BOOL PXApplicationHasActions(NSString *bundleID);
FOUNDATION_EXPORT UIImage * _Nullable PXApplicationIcon(NSString *bundleID);
FOUNDATION_EXPORT UIImage * _Nullable PXApplicationIconLarge(NSString *bundleID);
FOUNDATION_EXPORT NSArray<NSDictionary<NSString *, NSString *> *> *PXAvailableWorkflows(void);
FOUNDATION_EXPORT void PXFetchApplicationActions(NSString *bundleID, void (^completion)(NSArray<NSDictionary *> *items));
FOUNDATION_EXPORT id _Nullable PXApplicationActionItem(NSDictionary *entry);
NS_ASSUME_NONNULL_END
