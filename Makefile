GO ?= go

.PHONY: build app dmg run-app test check check-ui check-native
build:
	mkdir -p bin
	CGO_ENABLED=1 $(GO) build -trimpath -o bin/sleepguard ./cmd/sleepguard

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
