export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

PROJECT := Bouncer.xcodeproj
SCHEME := Bouncer
CONFIG ?= Debug
BUILD_DIR := .build/xcode

# Ad-hoc by default, so a checkout builds with no developer account. Ad-hoc signatures
# have no stable identity, so macOS treats every rebuild as a different app and forgets
# the permissions the standalone bar needs. Set SIGN_IDENTITY to a real identity —
# `security find-identity -v -p codesigning` — to keep those grants across rebuilds.
# A local .signing.mk may name a real identity; it is not checked in.
-include .signing.mk
SIGN_IDENTITY ?= -
SIGN_FLAGS := CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)"

.PHONY: all generate build run test lint format clean

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
	@pkill -x Bouncer || true
	open $(BUILD_DIR)/Build/Products/$(CONFIG)/Bouncer.app

## Run the module tests (no Xcode project needed — fast)
test:
	swift test --package-path Modules

lint:
	swiftlint lint --quiet

format:
	swiftlint lint --fix --quiet

clean:
	rm -rf $(BUILD_DIR) Modules/.build $(PROJECT)
