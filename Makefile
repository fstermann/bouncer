export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

PROJECT := Bouncer.xcodeproj
SCHEME := Bouncer
CONFIG ?= Debug
BUILD_DIR := .build/xcode
RELEASE_DIR := .build/release
RELEASE_APP := $(BUILD_DIR)/Build/Products/Release/Bouncer.app
# The Debug configuration builds a separate app ("Bouncer Dev", com.bouncer.app.dev — see project.yml), so
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

.PHONY: all generate build run ctl bench bench-vm bench-vm-setup bench-tools vm-up vm-ctl vm-items vm-down release test lint format clean

all: build

## Regenerate Bouncer.xcodeproj from project.yml
generate:
	xcodegen generate

## Build the app bundle
build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR) $(SIGN_FLAGS) build

BARCTL := .build/tools/barctl

$(BARCTL): Tools/barctl.swift
	@mkdir -p $(@D)
	@xcrun swiftc -O $< -o $@

## Build and launch; a Debug build returns once its harness answers, so `make ctl` can follow at once
run: build $(BARCTL)
	@pkill -x "$(APP_NAME)" || true
	@while pgrep -x "$(APP_NAME)" >/dev/null; do sleep 0.1; done
	open "$(BUILD_DIR)/Build/Products/$(CONFIG)/$(APP_NAME).app"
	@$(if $(filter Debug,$(CONFIG)),$(BARCTL) ready >/dev/null,true)

## Drive a running Bouncer Dev: make ctl CMD="shoot /tmp/bar.png" (see Tools/barctl.swift)
ctl: $(BARCTL)
	@$(BARCTL) $(CMD)

## Time a running Bouncer Dev: make bench ARGS="--scenario bar-open --runs 3" (see Tools/bench.swift)
bench: bench-tools
	@.bench/bench $(ARGS)

## The same inside a Tart VM, off this Mac's screen: make bench-vm ARGS="--runs 3" (see docs/PERFORMANCE.md)
bench-vm: bench-tools
	@sh Tools/bench-vm.sh run $(ARGS)

## Make the VM bench-vm runs in, once per Mac
bench-vm-setup: bench-tools
	@sh Tools/bench-vm.sh setup

bench-tools:
	@mkdir -p .bench
	@xcrun swiftc -O Tools/bench.swift -o .bench/bench
	@xcrun swiftc -O Tools/bench-items.swift -o .bench/bench-items
	@xcrun swiftc -O Tools/barctl.swift -o .bench/barctl

## A lasting VM to try Bouncer Dev in, off this Mac's screen; run it again after a build to reload
vm-up: bench-tools
	@sh Tools/bench-vm.sh up

## make ctl, in the VM: make vm-ctl CMD="shoot /path/bar.png" copies the picture back
vm-ctl:
	@sh Tools/bench-vm.sh ctl $(CMD)

## The fixture that fills the hidden section, in the VM: make vm-items ON=off to stop it
vm-items:
	@sh Tools/bench-vm.sh items $(or $(ON),on)

vm-down:
	@sh Tools/bench-vm.sh down

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
