APP_NAME = Internet Status
BUNDLE_NAME = Internet\ Status.app
EXECUTABLE = InternetStatus
SOURCES = $(wildcard Sources/*.swift)
BUILD_DIR = build
SWIFT_FLAGS = -O -whole-module-optimization
VERSION = 1.0.0

.PHONY: all clean run release

all: $(BUILD_DIR)/$(BUNDLE_NAME)

$(BUILD_DIR)/$(BUNDLE_NAME): $(SOURCES) Resources/Info.plist
	@mkdir -p "$(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS"
	@mkdir -p "$(BUILD_DIR)/$(APP_NAME).app/Contents/Resources"
	swiftc $(SWIFT_FLAGS) -target arm64-apple-macos13 -o "$(BUILD_DIR)/$(EXECUTABLE)-arm64" $(SOURCES)
	swiftc $(SWIFT_FLAGS) -target x86_64-apple-macos13 -o "$(BUILD_DIR)/$(EXECUTABLE)-x86_64" $(SOURCES)
	lipo -create -output "$(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS/$(EXECUTABLE)" \
		"$(BUILD_DIR)/$(EXECUTABLE)-arm64" "$(BUILD_DIR)/$(EXECUTABLE)-x86_64"
	@rm -f "$(BUILD_DIR)/$(EXECUTABLE)-arm64" "$(BUILD_DIR)/$(EXECUTABLE)-x86_64"
	@cp Resources/Info.plist "$(BUILD_DIR)/$(APP_NAME).app/Contents/"

run: all
	@open "$(BUILD_DIR)/$(APP_NAME).app"

release: clean all
	cd $(BUILD_DIR) && zip -r "InternetStatus-$(VERSION).zip" "$(APP_NAME).app"
	@echo "Release zip: $(BUILD_DIR)/InternetStatus-$(VERSION).zip"

clean:
	rm -rf $(BUILD_DIR)
