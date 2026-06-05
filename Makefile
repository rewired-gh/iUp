SCHEME    := iUp
DEST      := platform=macOS
# Default config is Debug; `make release`/`make run-release` override to Release.
# Build dir is per-config so debug and release artifacts never clobber each other.
CONFIG    := Debug
BUILD_DIR := $(CURDIR)/build/$(CONFIG)
APP       := $(BUILD_DIR)/$(SCHEME).app

# Release optimization flags. Xcode's Release config already gives -O + whole-module;
# these push further: cross-module link-time optimization, dead-code stripping, symbol
# stripping, and disabled runtime assertions for a lean, fast shipping binary.
RELEASE_OPT := \
	SWIFT_OPTIMIZATION_LEVEL=-O \
	SWIFT_COMPILATION_MODE=wholemodule \
	GCC_OPTIMIZATION_LEVEL=s \
	LLVM_LTO=YES_THIN \
	DEAD_CODE_STRIPPING=YES \
	DEPLOYMENT_POSTPROCESSING=YES \
	STRIP_INSTALLED_PRODUCT=YES \
	COPY_PHASE_STRIP=YES \
	ENABLE_NS_ASSERTIONS=NO \
	SWIFT_DISABLE_SAFETY_CHECKS=NO \
	VALIDATE_PRODUCT=YES \
	OTHER_SWIFT_FLAGS=-cross-module-optimization \
	OTHER_LDFLAGS='-Wl,-dead_strip -Wl,-x'

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

# Apply Release opt flags only when building the Release config. Computed (not passed
# via recursive make) so the embedded quotes/spaces survive into one xcodebuild arg.
ifeq ($(CONFIG),Release)
EXTRA     := $(RELEASE_OPT)
else
EXTRA     :=
endif

.PHONY: build release run run-release stop test reveal accessibility path clean signing-status

## Build the (Debug) app to a STABLE path ($(BUILD_DIR)) so Accessibility grants persist.
## EXTRA carries extra xcodebuild settings (empty for Debug; Release opt flags via `release`).
build:
	xcodebuild build -scheme $(SCHEME) -destination '$(DEST)' -configuration $(CONFIG) \
		$(SIGN) $(EXTRA) CONFIGURATION_BUILD_DIR='$(BUILD_DIR)'

## Build a highly-optimized Release artifact (LTO, stripped, no assertions).
release:
	$(MAKE) build CONFIG=Release
	@echo "Release built: $(CURDIR)/build/Release/$(SCHEME).app"

## Rebuild and launch a fresh Debug instance.
run: build stop
	open '$(APP)'

## Rebuild Release and launch a fresh instance.
run-release: stop release
	open '$(CURDIR)/build/Release/$(SCHEME).app'

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
	rm -rf '$(CURDIR)/build'
	xcodebuild clean -scheme $(SCHEME) -destination '$(DEST)' >/dev/null 2>&1 || true
