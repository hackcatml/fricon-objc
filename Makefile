FINALPACKAGE = 1
TARGET := iphone:clang:latest:12.4
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = fricon

$(TOOL_NAME)_FILES = $(wildcard *.m)
$(TOOL_NAME)_CFLAGS = -fobjc-arc -Wno-unused-function
#$(TOOL_NAME)_CODESIGN_FLAGS = -Sentitlements.plist
$(TOOL_NAME)_INSTALL_PATH = /usr/local/bin

before-package::
	ldid -S $(THEOS_STAGING_DIR)/usr/local/bin/$(TOOL_NAME);

include $(THEOS_MAKE_PATH)/tool.mk
