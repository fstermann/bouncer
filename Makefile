export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

PROJECT := Bouncer.xcodeproj
SCHEME := Bouncer
CONFIG ?= Debug
BUILD_DIR := .build/xcode
RELEASE_DIR := .build/release
RELEASE_APP := $(BUILD_DIR)/Build/Products/Release/Bouncer.app
# Debug builds are a separate app ("Bouncer Dev", com.bouncer.app.dev — see project.yml), so
# `make run` must not reach for an installed Bouncer when it restarts the one it just built.
APP_NAME := $(if $(filter Release,$(CONFIG)),Bouncer,Bouncer Dev)

# Ad-hoc by default, so a checkout builds with no developer account. Ad-hoc signatures
# have no stable identity, so macOS treats every rebuild as a different app and forgets
# the permissions the standalone bar needs. Set SIGN_IDENTITY to a real identity —
# `security find-identity -v -p codesigning` — to keep those grants across rebuilds.
# A local .signing.mk may name a real identity; it is not checked in.
-include .signing.mk
SIGN_IDENTITY ?= -
SIGN_FLAGS := CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)"

# Releases are signed with a certificate of their own, so the one private key that must never
# be lost — losing it costs every user their permissions — is only ever used to cut a release.
# Name it in .signing.mk to build one locally; the release workflow passes it in instead.
RELEASE_SIGN_IDENTITY ?=

# Repository the feed is served from, baked into SUFeedURL. Empty here so a local build keeps
# the default in project.yml; the release workflow passes the repository it is building.
SU_FEED_URL ?=

.PHONY: all generate build run release test lint format clean

all: build

## Regenerate Bouncer.xcodeproj from project.yml
generate:
	xcodegen generate

## Build the app bundle
build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR) $(SIGN_FLAGS) build

## Build and launch
run: build
	@pkill -x "$(APP_NAME)" || true
	@while pgrep -x "$(APP_NAME)" >/dev/null; do sleep 0.1; done
	open "$(BUILD_DIR)/Build/Products/$(CONFIG)/$(APP_NAME).app"

## Build the two artifacts a release is made of: the disk image a person downloads, and
## the archive Sparkle downloads. The release workflow runs this same target.
#
# `-destination generic/platform=macOS` is what makes the build universal: with no destination
# xcodebuild resolves one for the machine it is on and narrows ARCHS to that architecture, so
# the release would quietly be Apple Silicon only.
release: generate
	@if [ -z "$(RELEASE_SIGN_IDENTITY)" ] || [ "$(RELEASE_SIGN_IDENTITY)" = "-" ]; then \
		echo "release needs the release signing identity — set RELEASE_SIGN_IDENTITY in"; \
		echo ".signing.mk. It must not be the ad-hoc \"-\" or the dev certificate: an ad-hoc"; \
		echo "signature has no stable identity, so macOS forgets the permissions the standalone"; \
		echo "bar was granted and Sparkle refuses an update it cannot match to the installed app."; \
		exit 1; \
	fi
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=macOS' \
		-derivedDataPath $(BUILD_DIR) CODE_SIGN_IDENTITY="$(RELEASE_SIGN_IDENTITY)" \
		$(if $(SU_FEED_URL),SU_FEED_URL="$(SU_FEED_URL)") build
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)/stage $(RELEASE_DIR)/sparkle
	@set -e; \
	version=$$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
		"$(RELEASE_APP)/Contents/Info.plist"); \
	ditto "$(RELEASE_APP)" "$(RELEASE_DIR)/stage/Bouncer.app"; \
	ln -s /Applications $(RELEASE_DIR)/stage/Applications; \
	hdiutil create -volname Bouncer -srcfolder $(RELEASE_DIR)/stage -fs APFS -format ULFO \
		-ov -quiet "$(RELEASE_DIR)/Bouncer-$$version.dmg"; \
	rm -rf $(RELEASE_DIR)/stage; \
	ditto -c -k --sequesterRsrc --keepParent "$(RELEASE_APP)" \
		"$(RELEASE_DIR)/sparkle/Bouncer-$$version.zip"; \
	echo "Release $$version:"; \
	ls -lh $(RELEASE_DIR)/*.dmg $(RELEASE_DIR)/sparkle/*.zip

## Run the module tests (no Xcode project needed — fast)
test:
	swift test --package-path Modules

lint:
	swiftlint lint --quiet

format:
	swiftlint lint --fix --quiet

clean:
	rm -rf $(BUILD_DIR) $(RELEASE_DIR) Modules/.build $(PROJECT)
