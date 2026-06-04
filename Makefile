SCHEME    := iUp
DEST      := platform=macOS
CONFIG    := Debug
BUILD_DIR := $(CURDIR)/build
APP       := $(BUILD_DIR)/$(SCHEME).app

# Developer team for signing, derived from the installed Apple Development cert (its
# subject OU) so no team ID is hardcoded here. With a valid cert, builds are signed
# with this stable identity so the Accessibility grant survives rebuilds (TCC keys on
# the signing identity, not the cdhash). Without one, fall back to ad-hoc — builds
# still work, but the grant resets each rebuild. `make signing-status` shows the mode.
TEAM      := $(shell security find-certificate -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | grep -oE 'OU=[A-Z0-9]+' | head -1 | cut -d= -f2)
# Count installed valid codesigning identities. Each identity line carries the cert
# name in quotes; the empty "0 valid identities found" summary has none. (Avoid a
# literal ')' here — it would close Make's $(shell ...) early.)
HAVE_ID   := $(shell security find-identity -v -p codesigning 2>/dev/null | grep -c '"')
ifeq ($(HAVE_ID),0)
SIGN      :=
else
SIGN      := -allowProvisioningUpdates DEVELOPMENT_TEAM=$(TEAM) CODE_SIGN_STYLE=Automatic
endif

.PHONY: build run stop test reveal accessibility path clean signing-status

## Build the app to a STABLE path ($(BUILD_DIR)) so Accessibility grants persist.
build:
	xcodebuild build -scheme $(SCHEME) -destination '$(DEST)' -configuration $(CONFIG) \
		$(SIGN) CONFIGURATION_BUILD_DIR='$(BUILD_DIR)'

## Rebuild and launch a fresh instance.
run: build stop
	open '$(APP)'

## Quit any running instance.
stop:
	-pkill -x $(SCHEME) 2>/dev/null || true

## Run the unit test suite.
test:
	xcodebuild test -scheme $(SCHEME) -destination '$(DEST)' $(SIGN) -only-testing:iUpTests

## Show whether builds will use the dev signature or fall back to ad-hoc.
signing-status:
	@if [ "$(HAVE_ID)" = "0" ]; then \
		echo "AD-HOC signing — Accessibility grant resets every rebuild."; \
		echo "Fix: Xcode > Settings > Accounts > re-sign in your Apple ID,"; \
		echo "     then Manage Certificates > + > Apple Development. Re-run this."; \
	else \
		echo "DEV signature active (team $(TEAM)) — Accessibility grant persists:"; \
		security find-identity -v -p codesigning | grep '\"'; \
	fi

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
