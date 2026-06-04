SCHEME    := iUp
DEST      := platform=macOS
CONFIG    := Debug
BUILD_DIR := $(CURDIR)/build
APP       := $(BUILD_DIR)/$(SCHEME).app

.PHONY: build run stop test reveal accessibility path clean

## Build the app to a STABLE path ($(BUILD_DIR)) so Accessibility grants persist.
build:
	xcodebuild build -scheme $(SCHEME) -destination '$(DEST)' -configuration $(CONFIG) \
		CONFIGURATION_BUILD_DIR='$(BUILD_DIR)'

## Rebuild and launch a fresh instance.
run: build stop
	open '$(APP)'

## Quit any running instance.
stop:
	-pkill -x $(SCHEME) 2>/dev/null || true

## Run the unit test suite.
test:
	xcodebuild test -scheme $(SCHEME) -destination '$(DEST)' -only-testing:iUpTests

## Reveal the built app in Finder (drag into the Accessibility list if needed).
reveal: build
	open -R '$(APP)'

## Open the Accessibility settings pane.
accessibility:
	open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'

## Print the built app path.
path:
	@echo '$(APP)'

## Remove build artifacts.
clean:
	rm -rf '$(BUILD_DIR)'
	xcodebuild clean -scheme $(SCHEME) -destination '$(DEST)' >/dev/null 2>&1 || true
