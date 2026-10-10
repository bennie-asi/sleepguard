GO ?= go
VERSION ?= $(shell cat VERSION)
BUILD_NUMBER ?= $(shell python3 -c 'v=tuple(map(int,"$(VERSION)".split("."))); print(v[0]*1000000+v[1]*1000+v[2])')

.PHONY: build app dmg run-app test check check-ui check-native
build:
	mkdir -p bin
	CGO_ENABLED=1 $(GO) build -trimpath -ldflags="-X main.appVersion=$(VERSION) -X main.appBuild=$(BUILD_NUMBER)" -o bin/sleepguard ./cmd/sleepguard

app:
	GO="$(GO)" scripts/build-app.sh
dmg: app
	scripts/build-dmg.sh

run-app:
	open dist/SleepGuard.app --args --show-window

test:
	$(GO) test -race ./...

check:
	$(GO) vet ./...

check-ui:
	bash scripts/check-ui.sh
check-native: app
	python3 scripts/check-native.py
