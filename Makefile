APP_NAME = Internet Status
BUNDLE_NAME = Internet\ Status.app
EXECUTABLE = InternetStatus
SOURCES = $(wildcard Sources/*.swift)
BUILD_DIR = build
SWIFT_FLAGS = -O -whole-module-optimization

.PHONY: all clean run

all: $(BUILD_DIR)/$(BUNDLE_NAME)

$(BUILD_DIR)/$(BUNDLE_NAME): $(SOURCES) Resources/Info.plist
	@mkdir -p "$(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS"
	@mkdir -p "$(BUILD_DIR)/$(APP_NAME).app/Contents/Resources"
	swiftc $(SWIFT_FLAGS) -o "$(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS/$(EXECUTABLE)" $(SOURCES)
	@cp Resources/Info.plist "$(BUILD_DIR)/$(APP_NAME).app/Contents/"

run: all
	@open "$(BUILD_DIR)/$(APP_NAME).app"

clean:
	rm -rf $(BUILD_DIR)
