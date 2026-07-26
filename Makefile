export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

PROJECT := Bouncer.xcodeproj
SCHEME := Bouncer
CONFIG ?= Debug
BUILD_DIR := .build/xcode

.PHONY: all generate build run test lint format clean

all: build

## Regenerate Bouncer.xcodeproj from project.yml
generate:
	xcodegen generate

## Build the app bundle
build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR) build

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
