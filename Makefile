.PHONY: setup check smoke debug build test probe app app-release dmg

setup:
	./scripts/setup.sh

check:
	./scripts/check.sh

smoke:
	./scripts/smoke.sh

.build/debug-smoke: tools/debug-smoke.c
	mkdir -p .build
	xcrun clang -g -O0 -o $@ $<

debug: .build/debug-smoke
	xcrun lldb -- .build/debug-smoke

build:
	swift build

test:
	swift test

probe:
	swift run macpocket-probe system

app:
	./scripts/build-app.sh

app-release:
	./scripts/build-app.sh release

dmg: app-release
	./scripts/build-dmg.sh
