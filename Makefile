APP_NAME = Internet Status
EXECUTABLE = InternetStatus
SOURCES = $(wildcard Sources/*.swift)
BUILD_DIR = build
SWIFT_FLAGS = -O -whole-module-optimization
VERSION = 1.0.1
# Use a stamp file for make dependency tracking (spaces in app path break make)
STAMP = $(BUILD_DIR)/.build-stamp

.PHONY: all build clean run release

all: build

build: $(STAMP)

$(STAMP): $(SOURCES) Resources/Info.plist
	@mkdir -p "$(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS"
	@mkdir -p "$(BUILD_DIR)/$(APP_NAME).app/Contents/Resources"
	swiftc $(SWIFT_FLAGS) -target arm64-apple-macos13 -o "$(BUILD_DIR)/$(EXECUTABLE)-arm64" $(SOURCES)
	swiftc $(SWIFT_FLAGS) -target x86_64-apple-macos13 -o "$(BUILD_DIR)/$(EXECUTABLE)-x86_64" $(SOURCES)
	lipo -create -output "$(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS/$(EXECUTABLE)" \
		"$(BUILD_DIR)/$(EXECUTABLE)-arm64" "$(BUILD_DIR)/$(EXECUTABLE)-x86_64"
	@rm -f "$(BUILD_DIR)/$(EXECUTABLE)-arm64" "$(BUILD_DIR)/$(EXECUTABLE)-x86_64"
	@cp Resources/Info.plist "$(BUILD_DIR)/$(APP_NAME).app/Contents/"
	@touch $(STAMP)

run: build
	@pkill -x $(EXECUTABLE) 2>/dev/null; sleep 0.5; true
	@open "$(BUILD_DIR)/$(APP_NAME).app"

release: clean build
	cd $(BUILD_DIR) && zip -r "InternetStatus-$(VERSION).zip" "$(APP_NAME).app"
	@echo "Release zip: $(BUILD_DIR)/InternetStatus-$(VERSION).zip"

clean:
	rm -rf $(BUILD_DIR)
