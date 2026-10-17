TARGET := iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = QQCKRepeaterPlusOne
QQCKRepeaterPlusOne_FILES = Repeater.xm
QQCKRepeaterPlusOne_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
QQCKRepeaterPlusOne_FRAMEWORKS = UIKit Foundation
QQCKRepeaterPlusOne_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
