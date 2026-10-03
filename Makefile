ARCHS = arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = roothide
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ParallelX
ParallelX_FILES = Tweak.m PXPanel.swift PXAppIndex.swift PXSceneBridge.m PXAppCatalog.m
ParallelX_FRAMEWORKS = UIKit Foundation QuartzCore
ParallelX_LIBRARIES = substrate sqlite3
ParallelX_CFLAGS = -fobjc-arc -Wall -Wextra
ParallelX_SWIFTFLAGS = -swift-version 5

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
