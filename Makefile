APP_NAME := TouchBarTokenUsage
DIST := dist
VERSION ?= 0.4.0

.PHONY: all build test app zip install uninstall clean

all: app

build:
	swift build

test:
	swift test

app:
	VERSION=$(VERSION) ./scripts/make-bundle.sh

zip: app
	cd $(DIST) && ditto -c -k --keepParent $(APP_NAME).app $(APP_NAME).zip
	@echo "==> $(DIST)/$(APP_NAME).zip"

install: app
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(DIST)/$(APP_NAME).app /Applications/
	@echo "==> installed to /Applications/$(APP_NAME).app — right-click > Open on first launch"

uninstall:
	rm -rf /Applications/$(APP_NAME).app

clean:
	rm -rf .build $(DIST)
