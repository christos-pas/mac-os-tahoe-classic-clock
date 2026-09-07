# Lock Clock — local build / install helpers.
# These targets never use sudo, never touch other apps, and never reset
# the system login-item database.

include Version.xcconfig

APP_NAME      := LockClock
BUNDLE_ID     := app.lockclock.LockClock
PROJECT       := LockClock.xcodeproj
SCHEME        := LockClock
CONFIGURATION := Release
DERIVED_DATA  := $(CURDIR)/build.noindex
BUILT_APP     := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app
DIST_DIR      := $(CURDIR)/dist
VERSION_FILE  := $(CURDIR)/Version.xcconfig
PREFIX        ?= /Applications
DEST_APP      := $(PREFIX)/$(APP_NAME).app

# Shared Bourne-shell helpers. Kept inline so no target needs $(MAKE),
# which would make `make -n` execute destructive recipes.
define SHELL_LIB
safe_prefix() { \
	case "$(PREFIX)" in \
		""|"/"|"/System"|"/System/"*|"/usr"|"/usr/"*|"/bin"|"/sbin"|"/etc"|"/var"|"/private"|"/private/"*) \
			echo "error: refusing to use PREFIX=$(PREFIX)"; \
			return 1 ;; \
	esac; \
	case "$(DEST_APP)" in \
		*/$(APP_NAME).app) ;; \
		*) echo "error: destination must be a $(APP_NAME).app bundle"; return 1 ;; \
	esac; \
}
is_our_app() { \
	_app="$$1"; \
	if [ ! -d "$$_app" ]; then \
		echo "error: not a bundle: $$_app"; \
		return 1; \
	fi; \
	_id=$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$$_app/Contents/Info.plist" 2>/dev/null || true); \
	if [ "$$_id" != "$(BUNDLE_ID)" ]; then \
		echo "error: $$_app is not $(BUNDLE_ID) (found '$$_id'). Refusing to modify it."; \
		return 1; \
	fi; \
}
quit_ours() { \
	_pids=$$(pgrep -f '/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)' || true); \
	if [ -n "$$_pids" ]; then \
		kill -TERM $$_pids 2>/dev/null || true; \
		sleep 1; \
		_pids=$$(pgrep -f '/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)' || true); \
		if [ -n "$$_pids" ]; then kill -KILL $$_pids 2>/dev/null || true; fi; \
	fi; \
}
unregister_ours() { \
	_app="$$1"; \
	if [ -x "$$_app/Contents/MacOS/$(APP_NAME)" ]; then \
		"$$_app/Contents/MacOS/$(APP_NAME)" --unregister-login-item || true; \
	fi; \
}
endef

export SHELL_LIB

.DEFAULT_GOAL := help

.PHONY: help build diagnostics settings install uninstall dist release screenshots calibrate icon logo

help:
	@echo "Lock Clock $(MAJOR).$(MINOR).$(BUILD)"
	@echo
	@echo "  make build         Build $(APP_NAME).app (Release)"
	@echo "  make dist          Bump build number and write an unsigned zip to dist/"
	@echo "  make screenshots   Render Settings / lock-screen / menu PNGs"
	@echo "  make calibrate     Render + measure against a reference lock-screen PNG"
	@echo "  make icon          Render the app icon into Assets.xcassets and rebuild"
	@echo "  make logo          Alias for make icon"
	@echo "  make release       Dist + publish a GitHub release"
	@echo "  make diagnostics   Launch the built app with the debug window"
	@echo "  make settings      Launch the built app and open Settings"
	@echo "  make install       Copy the built app to $(DEST_APP)"
	@echo "  make uninstall     Remove this app, its login item, and its defaults"
	@echo
	@echo "Release notes (make cannot take a --notes flag):"
	@echo "  make release NOTES=\"What changed\""
	@echo "  ./scripts/release.sh --notes \"What changed\""
	@echo
	@echo "Install location can be overridden:"
	@echo "  make install PREFIX=\"$$HOME/Applications\""
	@echo
	@echo "No target uses sudo or modifies other software."

build:
	@test -d "$(PROJECT)" || { echo "error: run this from the Lock Clock repo root"; exit 1; }
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		MARKETING_VERSION="$(MAJOR).$(MINOR).$(BUILD)" \
		CURRENT_PROJECT_VERSION="$(BUILD)" \
		build
	@mkdir -p "$(DERIVED_DATA)"
	@touch "$(DERIVED_DATA)/.metadata_never_index"
	@echo "Built $(BUILT_APP) ($(MAJOR).$(MINOR).$(BUILD))"

dist:
	@test -d "$(PROJECT)" || { echo "error: run this from the Lock Clock repo root"; exit 1; }
	@eval "$$SHELL_LIB"; \
	next=$$(($(BUILD) + 1)); \
	version="$(MAJOR).$(MINOR).$$next"; \
	{ \
		echo "MAJOR = $(MAJOR)"; \
		echo "MINOR = $(MINOR)"; \
		echo "BUILD = $$next"; \
		echo 'MARKETING_VERSION = $$(MAJOR).$$(MINOR).$$(BUILD)'; \
		echo 'CURRENT_PROJECT_VERSION = $$(BUILD)'; \
	} > "$(VERSION_FILE)"; \
	echo "Version $(MAJOR).$(MINOR).$(BUILD) → $$version"; \
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		MARKETING_VERSION="$$version" \
		CURRENT_PROJECT_VERSION="$$next" \
		build || exit 1; \
	mkdir -p "$(DERIVED_DATA)"; \
	touch "$(DERIVED_DATA)/.metadata_never_index"; \
	is_our_app "$(BUILT_APP)" || exit 1; \
	xattr -cr "$(BUILT_APP)" 2>/dev/null || true; \
	codesign --force --deep --sign - "$(BUILT_APP)"; \
	mkdir -p "$(DIST_DIR)"; \
	zip_path="$(DIST_DIR)/$(APP_NAME)-$$version.zip"; \
	rm -f -- "$$zip_path"; \
	ditto -c -k --keepParent --sequesterRsrc "$(BUILT_APP)" "$$zip_path"; \
	echo "Wrote $$zip_path"; \
	echo "This zip is ad-hoc signed and not notarized. macOS Gatekeeper will warn people who download it."

screenshots: build
	@mkdir -p "$(CURDIR)/docs/screenshots"
	"$(BUILT_APP)/Contents/MacOS/$(APP_NAME)" --export-screenshots "$(CURDIR)/docs/screenshots"

CALIBRATION_REF ?= $(HOME)/Desktop/system_clock.png

calibrate: build
	@mkdir -p "$(CURDIR)/docs/calibration"
	"$(BUILT_APP)/Contents/MacOS/$(APP_NAME)" --calibrate-clock "$(CALIBRATION_REF)" "$(CURDIR)/docs/calibration"

icon: build
	"$(BUILT_APP)/Contents/MacOS/$(APP_NAME)" --export-icon "$(CURDIR)/LockClock/Assets.xcassets/AppIcon.appiconset"
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		MARKETING_VERSION="$(MAJOR).$(MINOR).$(BUILD)" \
		CURRENT_PROJECT_VERSION="$(BUILD)" \
		build
	@echo "Icon baked into $(BUILT_APP)"

logo: icon

release:
	@NOTES="$(NOTES)" "$(CURDIR)/scripts/release.sh"

diagnostics: build
	@eval "$$SHELL_LIB"; quit_ours
	"$(BUILT_APP)/Contents/MacOS/$(APP_NAME)" --debug --force-clock

settings: build
	@eval "$$SHELL_LIB"; quit_ours
	"$(BUILT_APP)/Contents/MacOS/$(APP_NAME)" --settings

install: build
	@eval "$$SHELL_LIB"; \
	safe_prefix || exit 1; \
	is_our_app "$(BUILT_APP)" || exit 1; \
	if [ -e "$(DEST_APP)" ]; then is_our_app "$(DEST_APP)" || exit 1; fi; \
	quit_ours; \
	mkdir -p "$(PREFIX)"; \
	ditto -- "$(BUILT_APP)" "$(DEST_APP)"; \
	is_our_app "$(DEST_APP)" || exit 1; \
	touch "$(DEST_APP)"; \
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted "$(DEST_APP)" >/dev/null 2>&1 || true; \
	echo "Installed $(DEST_APP)"; \
	echo "Launch it from $(PREFIX) when you want it to run. First normal launch may register Launch at Login for this app only."

uninstall:
	@eval "$$SHELL_LIB"; \
	safe_prefix || exit 1; \
	quit_ours; \
	if [ -d "$(DEST_APP)" ]; then \
		is_our_app "$(DEST_APP)" || exit 1; \
		unregister_ours "$(DEST_APP)"; \
		rm -rf -- "$(DEST_APP)"; \
		echo "Removed $(DEST_APP)"; \
	elif [ -d "$(BUILT_APP)" ]; then \
		if is_our_app "$(BUILT_APP)"; then unregister_ours "$(BUILT_APP)"; fi; \
		echo "No installed app at $(DEST_APP)"; \
	else \
		echo "Nothing to remove at $(DEST_APP)"; \
	fi; \
	if defaults read "$(BUNDLE_ID)" >/dev/null 2>&1; then \
		defaults delete "$(BUNDLE_ID)"; \
		echo "Removed defaults for $(BUNDLE_ID)"; \
	fi; \
	echo "Uninstall finished. Other apps and login items were not changed."
