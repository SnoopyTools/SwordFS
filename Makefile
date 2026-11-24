# Builds SwordFS.ipa. Requires: macOS with Xcode, xcodegen, ldid (and dpkg-deb optional).
#   brew install xcodegen ldid

APP_NAME = SwordFS
SCHEME   = SwordFS

all: ipa

project:
	xcodegen -spec project.yml

build: project
	xcodebuild -project $(APP_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination 'generic/platform=iOS' \
		clean build \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		CODE_SIGN_ENTITLEMENTS=""

app: build
	@rm -rf build/$(APP_NAME).app
	cp -r build/Build/Products/Release-iphoneos/$(APP_NAME).app build/$(APP_NAME).app
	ldid -S$(APP_NAME)/SwordFS.entitlements build/$(APP_NAME).app/$(APP_NAME)

ipa: app
	@rm -rf build/Payload build/$(APP_NAME).ipa
	mkdir -p build/Payload
	cp -r build/$(APP_NAME).app build/Payload/
	cd build && zip -qry $(APP_NAME).ipa Payload
	@echo "==> build/$(APP_NAME).ipa"

clean:
	rm -rf build $(APP_NAME).xcodeproj

.PHONY: all project build app ipa clean
