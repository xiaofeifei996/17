ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ParallelXPrefs
ParallelXPrefs_FILES = PXRootListController.m PXAppPickerController.swift PXActionPickerController.swift PXExternalBlacklistController.swift PXCornerRadiusController.swift PXDockController.swift PXGestureAreaController.swift PXLauncherController.swift PXBackupController.swift PXSettingsStyle.swift ../PXAppCatalog.m
ParallelXPrefs_FRAMEWORKS = UIKit
ParallelXPrefs_LIBRARIES = sqlite3
ParallelXPrefs_INSTALL_PATH = /Library/PreferenceBundles
ParallelXPrefs_CFLAGS = -fobjc-arc
ParallelXPrefs_SWIFTFLAGS = -swift-version 5
ParallelXPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk
